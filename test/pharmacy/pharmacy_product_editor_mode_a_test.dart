import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_form.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_save_service.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_validation.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_dosage_form.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_drug_reference.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_manufacturer.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;
  final today = DateTime(2026, 6, 11);
  final validExpiry = DateTime(2027, 1, 1);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyProductEditorValidation', () {
    test('valid input passes', () {
      final result = PharmacyProductEditorValidation.validate(
        reference: _reference(),
        manufacturer: _manufacturer(),
        dosageForm: _dosageForm(),
        strengthText: '500 mg',
        batchNo: 'B2401',
        expiryDate: validExpiry,
        costFils: 15000,
        qty: 20,
        today: today,
      );
      expect(result.isValid, isTrue);
    });

    test('missing reference fails', () {
      final result = PharmacyProductEditorValidation.validate(
        reference: null,
        manufacturer: _manufacturer(),
        dosageForm: _dosageForm(),
        strengthText: '500 mg',
        batchNo: 'B2401',
        expiryDate: validExpiry,
        costFils: 15000,
        qty: 20,
        today: today,
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('المادة'));
    });

    test('collectErrors returns all missing fields', () {
      final errors = PharmacyProductEditorValidation.collectErrors(
        reference: null,
        manufacturer: null,
        dosageForm: null,
        strengthText: '',
        batchNo: '',
        expiryDate: null,
        costFils: null,
        qty: null,
        today: today,
      );
      expect(errors.length, greaterThan(3));
      expect(errors.any((e) => e.contains('المادة')), isTrue);
      expect(errors.any((e) => e.contains('الشركة')), isTrue);
    });

    test('strength must be greater than zero', () {
      final result = PharmacyProductEditorValidation.validate(
        reference: _reference(),
        manufacturer: _manufacturer(),
        dosageForm: _dosageForm(),
        strengthText: 'mg',
        batchNo: 'B2401',
        expiryDate: validExpiry,
        costFils: 15000,
        qty: 20,
        today: today,
      );
      expect(result.isValid, isFalse);
    });

    test('expiry before today fails', () {
      final result = PharmacyProductEditorValidation.validate(
        reference: _reference(),
        manufacturer: _manufacturer(),
        dosageForm: _dosageForm(),
        strengthText: '500 mg',
        batchNo: 'B2401',
        expiryDate: DateTime(2026, 6, 10),
        costFils: 15000,
        qty: 20,
        today: today,
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('الصلاحية'));
    });

    test('costFils and qty must be positive', () {
      expect(
        PharmacyProductEditorValidation.validate(
          reference: _reference(),
          manufacturer: _manufacturer(),
          dosageForm: _dosageForm(),
          strengthText: '500 mg',
          batchNo: 'B2401',
          expiryDate: validExpiry,
          costFils: 0,
          qty: 20,
          today: today,
        ).isValid,
        isFalse,
      );
      expect(
        PharmacyProductEditorValidation.validate(
          reference: _reference(),
          manufacturer: _manufacturer(),
          dosageForm: _dosageForm(),
          strengthText: '500 mg',
          batchNo: 'B2401',
          expiryDate: validExpiry,
          costFils: 1000,
          qty: 0,
          today: today,
        ).isValid,
        isFalse,
      );
    });
  });

  group('PharmacyProductEditorSaveService', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository repo;
    late PharmacyProductEditorSaveService saveService;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = DrugCatalogRepository(
        db: dbHelper,
        scheduleSync: () {},
      );
      await repo.ensureSchema();
      saveService = PharmacyProductEditorSaveService(
        catalog: repo,
        createCoreProduct: ({
          required int tenantId,
          required String name,
          required double buyPriceDinars,
          required double sellPriceDinars,
          required double qty,
          required String expiryDateIso,
        }) async {
          final db = await dbHelper.database;
          return db.insert('products', {
            'tenantId': tenantId,
            'name': name,
            'buyPrice': buyPriceDinars,
            'sellPrice': sellPriceDinars,
            'minSellPrice': buyPriceDinars,
            'qty': qty,
            'lowStockThreshold': 10,
            'status': 'instock',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
            'expiryDate': expiryDateIso,
            'trackInventory': 1,
            'isActive': 1,
          });
        },
      );
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<_CatalogSeed> seedCatalog({required int tenantId}) async {
      final refId = await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
      );
      await repo.insertManufacturer(
        tenantId: tenantId,
        name: 'شركة أ',
        qualityTier: 'A',
        countryCode: 'IQ',
      );
      await repo.insertDosageForm(
        tenantId: tenantId,
        nameAr: 'أقراص',
        nameEn: 'Tablets',
        code: 'tab',
        isSplittable: true,
      );
      final reference = (await repo.getDrugReferenceById(
        tenantId: tenantId,
        id: refId,
      ))!;
      final manufacturers = await repo.listManufacturers(tenantId: tenantId);
      final forms = await repo.listDosageForms(tenantId: tenantId);
      return _CatalogSeed(
        reference: reference,
        manufacturer: manufacturers.single,
        dosageForm: forms.single,
      );
    }

    test('save inserts profile batch and stock policy', () async {
      final seed = await seedCatalog(tenantId: tenantId);

      final result = await saveService.save(
        PharmacyProductEditorSaveInput(
          tenantId: tenantId,
          reference: seed.reference,
          manufacturer: seed.manufacturer,
          dosageForm: seed.dosageForm,
          strengthText: '500 mg',
          rxSchedule: PharmacyRxSchedule.otc,
          batchNo: 'B2401',
          expiryDate: validExpiry,
          costFils: 25000,
          qty: 30,
        ),
      );

      expect(result.productId, greaterThan(0));
      expect(result.profileId, greaterThan(0));
      expect(result.batchId, greaterThan(0));
      expect(result.stockPolicyId, greaterThan(0));

      final profile = await repo.getProductProfileByProductId(
        tenantId: tenantId,
        productId: result.productId,
      );
      expect(profile, isNotNull);
      expect(profile!.strengthText, '500 mg');
      expect(profile.rxSchedule, PharmacyRxSchedule.otc);

      final batches = await repo.listBatchesForProduct(
        tenantId: tenantId,
        productId: result.productId,
      );
      expect(batches, hasLength(1));
      expect(batches.single.batchNo, 'B2401');
      expect(batches.single.costFils, 25000);

      final policy = await repo.getStockPolicy(
        tenantId: tenantId,
        productId: result.productId,
      );
      expect(policy, isNotNull);
      expect(policy!.minQty, 10);
      expect(policy.maxQty, 1000);
    });

    test('tenant isolation on saved profile', () async {
      final seed = await seedCatalog(tenantId: tenantId);
      await seedCatalog(tenantId: otherTenantId);

      final result = await saveService.save(
        PharmacyProductEditorSaveInput(
          tenantId: tenantId,
          reference: seed.reference,
          manufacturer: seed.manufacturer,
          dosageForm: seed.dosageForm,
          strengthText: '500 mg',
          rxSchedule: PharmacyRxSchedule.rx,
          batchNo: 'B2401',
          expiryDate: validExpiry,
          costFils: 10000,
          qty: 12,
        ),
      );

      expect(
        await repo.getProductProfileByProductId(
          tenantId: otherTenantId,
          productId: result.productId,
        ),
        isNull,
      );
      expect(
        await repo.listBatchesForProduct(
          tenantId: otherTenantId,
          productId: result.productId,
        ),
        isEmpty,
      );
    });

    test('save rejects invalid input before writing', () async {
      final seed = await seedCatalog(tenantId: tenantId);

      expect(
        () => saveService.save(
          PharmacyProductEditorSaveInput(
            tenantId: tenantId,
            reference: seed.reference,
            manufacturer: seed.manufacturer,
            dosageForm: seed.dosageForm,
            strengthText: '0 mg',
            rxSchedule: PharmacyRxSchedule.otc,
            batchNo: 'B2401',
            expiryDate: validExpiry,
            costFils: 1000,
            qty: 5,
          ),
        ),
        throwsStateError,
      );
    });

    test('resolveReferenceBeforeSave creates reference from free text', () async {
      final controller = PharmacyProductEditorFormController(
        tenantId: tenantId,
        catalog: repo,
        saveService: saveService,
      );
      await controller.load();
      controller.drugReferenceController.text = '23we';

      final err = await controller.resolveReferenceBeforeSave();
      expect(err, isNull);
      expect(controller.selectedReference, isNotNull);
      expect(controller.selectedReference!.nameAr, '23we');

      final listed = await repo.searchDrugReferences(
        tenantId: tenantId,
        query: '23we',
      );
      expect(listed, hasLength(1));
      controller.dispose();
    });
  });
}

PharmacyDrugReference _reference() {
  return PharmacyDrugReference(
    id: 1,
    tenantId: 1,
    nameAr: 'باراسيتامول',
    nameEn: 'Paracetamol',
    atcCode: 'N02BE01',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

PharmacyManufacturer _manufacturer() {
  return PharmacyManufacturer(
    id: 1,
    tenantId: 1,
    name: 'شركة',
    type: 'generic',
    qualityTier: 'A',
    countryCode: 'IQ',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

PharmacyDosageForm _dosageForm() {
  return PharmacyDosageForm(
    id: 1,
    tenantId: 1,
    nameAr: 'أقراص',
    nameEn: 'Tablets',
    code: 'tab',
    isSplittable: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

class _CatalogSeed {
  const _CatalogSeed({
    required this.reference,
    required this.manufacturer,
    required this.dosageForm,
  });

  final PharmacyDrugReference reference;
  final PharmacyManufacturer manufacturer;
  final PharmacyDosageForm dosageForm;
}
