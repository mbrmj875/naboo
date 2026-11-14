import '../models/pharmacy_pos_drug_panel_data.dart';
import 'drug_catalog_repository.dart';
import 'fefo_picker_service.dart';
import 'substitute_resolver.dart';

/// تحميل بيانات لوحة الدواء في POS.
class PharmacyPosDrugPanelService {
  PharmacyPosDrugPanelService({
    DrugCatalogRepository? catalog,
    FefoPickerService? fefoPicker,
    SubstituteResolver? substituteResolver,
  })  : _catalog = catalog ?? DrugCatalogRepository(),
        _fefoPicker = fefoPicker ?? FefoPickerService(catalog: catalog),
        _substitutes =
            substituteResolver ?? SubstituteResolver(catalog: catalog);

  final DrugCatalogRepository _catalog;
  final FefoPickerService _fefoPicker;
  final SubstituteResolver _substitutes;

  Future<PharmacyPosDrugPanelData?> load({
    required int tenantId,
    required int productId,
    int? selectedBatchId,
    int? branchId,
    String? productNameOverride,
  }) async {
    final profile = await _catalog.getProductProfileByProductId(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
    );
    if (profile == null) return null;

    final reference = await _catalog.getDrugReferenceById(
      tenantId: tenantId,
      id: profile.drugReferenceId,
    );
    if (reference == null) return null;

    final manufacturer = profile.manufacturerId == null
        ? null
        : await _catalog.getManufacturerById(
            tenantId: tenantId,
            id: profile.manufacturerId!,
          );

    final productName = productNameOverride?.trim().isNotEmpty == true
        ? productNameOverride!.trim()
        : (reference.nameAr.isNotEmpty
            ? reference.nameAr
            : reference.nameEn);

    final batch = await _fefoPicker.resolveSelectedBatch(
      tenantId: tenantId,
      productId: productId,
      selectedBatchId: selectedBatchId,
      branchId: branchId,
    );

    final substituteRows = await _substitutes.resolve(
      tenantId: tenantId,
      profile: profile,
    );

    final batches = await _fefoPicker.listSelectableBatches(
      tenantId: tenantId,
      productId: productId,
      branchId: branchId,
    );
    DateTime? latestExpiry;
    for (final b in batches) {
      if (b.qty <= 0) continue;
      if (latestExpiry == null || b.expiryDate.isBefore(latestExpiry)) {
        latestExpiry = b.expiryDate;
      }
    }

    return PharmacyPosDrugPanelData(
      productName: productName,
      drugReference: reference,
      manufacturer: manufacturer,
      strengthText: profile.strengthText,
      rxSchedule: profile.rxSchedule,
      selectedBatch: batch,
      substitutes: substituteRows,
      available: batch != null && batch.qty > 0,
      latestExpiry: latestExpiry ?? batch?.expiryDate,
    );
  }
}
