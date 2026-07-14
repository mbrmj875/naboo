import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/_contract/vertical_manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_drug_reference.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_manufacturer.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_pos_drug_panel_data.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_substitute_candidate.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_pos_drug_panel.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/fefo_picker_service.dart';
import 'package:naboo/verticals/pharmacy/services/substitute_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  final validExpiry = DateTime(2027, 7, 15);
  final laterExpiry = DateTime(2028, 1, 1);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FefoPickerService', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository repo;
    late FefoPickerService fefo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await repo.ensureSchema();
      fefo = FefoPickerService(catalog: repo);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('picks nearest expiry batch with stock', () async {
      final db = await dbHelper.database;
      final productId = await db.insert('products', {
        'tenantId': tenantId,
        'name': 'Panadol',
        'buyPrice': 10,
        'sellPrice': 15,
        'minSellPrice': 12,
        'qty': 50,
        'lowStockThreshold': 5,
        'status': 'instock',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'trackInventory': 1,
        'isActive': 1,
      });
      await repo.insertBatch(
        tenantId: tenantId,
        productId: productId,
        batchNo: 'B2402',
        expiryDate: laterExpiry,
        qty: 20,
        costFils: 10000,
      );
      await repo.insertBatch(
        tenantId: tenantId,
        productId: productId,
        batchNo: 'B2401',
        expiryDate: validExpiry,
        qty: 10,
        costFils: 9000,
      );

      final picked = await fefo.pickDefault(
        tenantId: tenantId,
        productId: productId,
      );

      expect(picked?.batchNo, 'B2401');
    });
  });

  group('SubstituteResolver', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository repo;
    late SubstituteResolver resolver;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await repo.ensureSchema();
      resolver = SubstituteResolver(catalog: repo);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('lists substitutes with same INN strength and form', () async {
      final refId = await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
      );
      final mfgA = await repo.insertManufacturer(
        tenantId: tenantId,
        name: 'GSK',
        qualityTier: 'A',
      );
      final mfgB = await repo.insertManufacturer(
        tenantId: tenantId,
        name: 'Local',
        qualityTier: 'B',
      );
      final formId = await repo.insertDosageForm(
        tenantId: tenantId,
        nameAr: 'أقراص',
        nameEn: 'Tablets',
        code: 'tab',
      );

      final db = await dbHelper.database;
      Future<int> insertProduct(String name, double sell) async {
        return db.insert('products', {
          'tenantId': tenantId,
          'name': name,
          'buyPrice': 10,
          'sellPrice': sell,
          'minSellPrice': sell,
          'qty': 30,
          'lowStockThreshold': 5,
          'status': 'instock',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'trackInventory': 1,
          'isActive': 1,
        });
      }

      final mainId = await insertProduct('Panadol 500mg', 15);
      final altId = await insertProduct('Propain 500mg', 12);

      await repo.insertProductProfile(
        tenantId: tenantId,
        productId: mainId,
        drugReferenceId: refId,
        manufacturerId: mfgA,
        dosageFormId: formId,
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
      );
      await repo.insertProductProfile(
        tenantId: tenantId,
        productId: altId,
        drugReferenceId: refId,
        manufacturerId: mfgB,
        dosageFormId: formId,
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
      );

      final mainProfile = (await repo.getProductProfileByProductId(
        tenantId: tenantId,
        productId: mainId,
      ))!;

      final subs = await resolver.resolve(
        tenantId: tenantId,
        profile: mainProfile,
      );

      expect(subs, hasLength(1));
      expect(subs.single.productName, 'Propain 500mg');
      expect(subs.single.qualityTier, 'B');
    });
  });

  group('PharmacyPosDrugPanel widget', () {
    testWidgets('shows drug info FEFO substitutes and Rx badge', (tester) async {
      final reference = PharmacyDrugReference(
        id: 1,
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
        indications: const ['حمى', 'ألم', 'صداع'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final data = PharmacyPosDrugPanelData(
        productName: 'Panadol 500mg',
        drugReference: reference,
        manufacturer: PharmacyManufacturer(
          id: 1,
          tenantId: tenantId,
          name: 'GSK',
          type: 'generic',
          qualityTier: 'A',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
        selectedBatch: null,
        substitutes: const [
          PharmacySubstituteCandidate(
            productId: 2,
            productName: 'Propain 500mg',
            sellPrice: 12,
            qualityTier: 'B',
          ),
        ],
        available: true,
        latestExpiry: validExpiry,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PharmacyPosDrugPanel(data: data),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Panadol 500mg'), findsOneWidget);
      expect(find.textContaining('INN: Paracetamol'), findsOneWidget);
      expect(find.textContaining('ATC: N02BE01'), findsOneWidget);
      expect(find.textContaining('دواعي:'), findsOneWidget);
      expect(find.textContaining('بدائل نفس المادة'), findsOneWidget);
      expect(find.textContaining('Propain 500mg'), findsOneWidget);
      expect(find.textContaining('Rx/OTC: OTC'), findsOneWidget);
    });
  });

  group('VerticalRegistry POS drug panel hook', () {
    test('oil manifest returns null panel', () {
      const oil = OilChangeVerticalManifest();
      expect(
        oil.buildPosDrugPanel(
          _FakeBuildContext(),
          const PosDrugPanelArgs(productId: 1),
        ),
        isNull,
      );
    });

    test('pharmacy manifest returns host widget', () {
      const pharmacy = PharmacyVerticalManifest();
      final panel = pharmacy.buildPosDrugPanel(
        _FakeBuildContext(),
        const PosDrugPanelArgs(productId: 1),
      );
      expect(panel, isA<PharmacyPosDrugPanelHost>());
    });
  });
}

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
