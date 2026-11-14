import '../../../services/product_repository.dart';
import '../../../utils/iqd_money.dart';
import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import '../services/drug_catalog_repository.dart';
import 'pharmacy_product_editor_validation.dart';

/// مدخلات حفظ دواء جديد (Mode A).
class PharmacyProductEditorSaveInput {
  const PharmacyProductEditorSaveInput({
    required this.tenantId,
    required this.reference,
    required this.manufacturer,
    required this.dosageForm,
    required this.strengthText,
    required this.rxSchedule,
    required this.batchNo,
    required this.expiryDate,
    required this.costFils,
    required this.qty,
  });

  final int tenantId;
  final PharmacyDrugReference reference;
  final PharmacyManufacturer manufacturer;
  final PharmacyDosageForm dosageForm;
  final String strengthText;
  final String rxSchedule;
  final String batchNo;
  final DateTime expiryDate;
  final int costFils;
  final double qty;
}

/// نتيجة حفظ ناجحة.
class PharmacyProductEditorSaveResult {
  const PharmacyProductEditorSaveResult({
    required this.productId,
    required this.profileId,
    required this.batchId,
    required this.stockPolicyId,
  });

  final int productId;
  final int profileId;
  final int batchId;
  final int stockPolicyId;
}

typedef PharmacyCoreProductCreator = Future<int> Function({
  required int tenantId,
  required String name,
  required double buyPriceDinars,
  required double sellPriceDinars,
  required double qty,
  required String expiryDateIso,
});

/// ينشئ منتج Core + profile + batch + stock policy.
class PharmacyProductEditorSaveService {
  PharmacyProductEditorSaveService({
    DrugCatalogRepository? catalog,
    ProductRepository? products,
    PharmacyCoreProductCreator? createCoreProduct,
  })  : _catalog = catalog ?? DrugCatalogRepository(),
        _createCoreProduct = createCoreProduct ??
            (({
              required int tenantId,
              required String name,
              required double buyPriceDinars,
              required double sellPriceDinars,
              required double qty,
              required String expiryDateIso,
            }) {
              final repo = products ?? ProductRepository();
              return repo.insertProduct(
                tenantId: tenantId,
                name: name,
                buyPrice: buyPriceDinars,
                sellPrice: sellPriceDinars,
                qty: qty,
                lowStockThreshold: 10,
                expiryDate: expiryDateIso,
                trackInventory: 1,
              );
            });

  final DrugCatalogRepository _catalog;
  final PharmacyCoreProductCreator _createCoreProduct;

  Future<PharmacyProductEditorSaveResult> save(
    PharmacyProductEditorSaveInput input,
  ) async {
    final validation = PharmacyProductEditorValidation.validate(
      reference: input.reference,
      manufacturer: input.manufacturer,
      dosageForm: input.dosageForm,
      strengthText: input.strengthText,
      batchNo: input.batchNo,
      expiryDate: input.expiryDate,
      costFils: input.costFils,
      qty: input.qty,
    );
    if (!validation.isValid) {
      throw StateError(validation.errorMessage ?? 'invalid_input');
    }

    final productName = buildProductName(input);
    final buyDinars = IqdMoney.fromFils(input.costFils);
    final expiryIso = DateTime(
      input.expiryDate.year,
      input.expiryDate.month,
      input.expiryDate.day,
    ).toIso8601String();

    final productId = await _createCoreProduct(
      tenantId: input.tenantId,
      name: productName,
      buyPriceDinars: buyDinars,
      sellPriceDinars: buyDinars,
      qty: input.qty,
      expiryDateIso: expiryIso,
    );

    final profileId = await _catalog.insertProductProfile(
      tenantId: input.tenantId,
      productId: productId,
      drugReferenceId: input.reference.id,
      manufacturerId: input.manufacturer.id,
      dosageFormId: input.dosageForm.id,
      strengthText: input.strengthText.trim(),
      rxSchedule: input.rxSchedule,
    );

    final batchId = await _catalog.insertBatch(
      tenantId: input.tenantId,
      productId: productId,
      batchNo: input.batchNo.trim(),
      expiryDate: input.expiryDate,
      qty: input.qty,
      costFils: input.costFils,
    );

    final stockPolicyId = await _catalog.upsertStockPolicy(
      tenantId: input.tenantId,
      productId: productId,
      minQty: 10,
      maxQty: 1000,
      reorderQty: 10,
    );

    return PharmacyProductEditorSaveResult(
      productId: productId,
      profileId: profileId,
      batchId: batchId,
      stockPolicyId: stockPolicyId,
    );
  }

  static String buildProductName(PharmacyProductEditorSaveInput input) {
    final strength = input.strengthText.trim();
    final base = input.reference.nameAr.trim().isNotEmpty
        ? input.reference.nameAr.trim()
        : input.reference.nameEn.trim();
    return '$base $strength ${input.dosageForm.nameAr} (${input.manufacturer.name})';
  }

  Future<PharmacyProductEditorSaveResult> saveForExistingProduct({
    required int productId,
    required PharmacyProductEditorSaveInput input,
  }) async {
    final validation = PharmacyProductEditorValidation.validate(
      reference: input.reference,
      manufacturer: input.manufacturer,
      dosageForm: input.dosageForm,
      strengthText: input.strengthText,
      batchNo: input.batchNo,
      expiryDate: input.expiryDate,
      costFils: input.costFils,
      qty: input.qty,
    );
    if (!validation.isValid) {
      throw StateError(validation.errorMessage ?? 'invalid_input');
    }

    final profileId = await _catalog.insertProductProfile(
      tenantId: input.tenantId,
      productId: productId,
      drugReferenceId: input.reference.id,
      manufacturerId: input.manufacturer.id,
      dosageFormId: input.dosageForm.id,
      strengthText: input.strengthText.trim(),
      rxSchedule: input.rxSchedule,
    );

    final batchId = await _catalog.insertBatch(
      tenantId: input.tenantId,
      productId: productId,
      batchNo: input.batchNo.trim(),
      expiryDate: input.expiryDate,
      qty: input.qty,
      costFils: input.costFils,
    );

    final stockPolicyId = await _catalog.upsertStockPolicy(
      tenantId: input.tenantId,
      productId: productId,
      minQty: 10,
      maxQty: 1000,
      reorderQty: 10,
    );

    return PharmacyProductEditorSaveResult(
      productId: productId,
      profileId: profileId,
      batchId: batchId,
      stockPolicyId: stockPolicyId,
    );
  }
}
