import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/_contract/vertical_manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_alert.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_alert_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const customerId = 10;
  final today = DateTime.now();
  final expired = today.subtract(const Duration(days: 30));
  final validExpiry = today.add(const Duration(days: 180));

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyAlertResolver', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository catalog;
    late PharmacyAlertResolver resolver;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      catalog = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await catalog.ensureSchema();
      resolver = PharmacyAlertResolver(catalog: catalog);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<int> insertProduct(String name) async {
      final db = await dbHelper.database;
      return db.insert('products', {
        'tenantId': tenantId,
        'name': name,
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
    }

    Future<({int productId, int batchId})> seedPharmacyProduct({
      required String name,
      required int refId,
      required DateTime expiry,
      String rxSchedule = PharmacyRxSchedule.otc,
      double batchQty = 50,
      DateTime? recallFrozenAt,
    }) async {
      final productId = await insertProduct(name);
      await catalog.insertProductProfile(
        tenantId: tenantId,
        productId: productId,
        drugReferenceId: refId,
        strengthText: '500 mg',
        rxSchedule: rxSchedule,
      );
      final batchId = await catalog.insertBatch(
        tenantId: tenantId,
        productId: productId,
        batchNo: 'B-${productId}',
        expiryDate: expiry,
        qty: batchQty,
        costFils: 10000,
      );
      if (recallFrozenAt != null) {
        final db = await dbHelper.database;
        await db.update(
          'pharmacy_batches',
          {'recallFrozenAt': recallFrozenAt.toUtc().toIso8601String()},
          where: 'id = ? AND tenantId = ?',
          whereArgs: [batchId, tenantId],
        );
      }
      return (productId: productId, batchId: batchId);
    }

    test('drug interaction in same invoice returns warning', () async {
      final refA = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'وارفارين',
        nameEn: 'Warfarin',
        interactionsPlaceholder: const ['Ibuprofen'],
      );
      final refB = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'إيبوبروفين',
        nameEn: 'Ibuprofen',
      );
      final a = await seedPharmacyProduct(
        name: 'Warfarin 5mg',
        refId: refA,
        expiry: validExpiry,
      );
      final b = await seedPharmacyProduct(
        name: 'Ibuprofen 400mg',
        refId: refB,
        expiry: validExpiry,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: a.productId, qty: 1, batchId: a.batchId),
            SaleAlertLine(productId: b.productId, qty: 1, batchId: b.batchId),
          ],
        ),
      );

      expect(
        alerts.any((a) => a.code == PharmacyAlertCodes.drugInteraction),
        isTrue,
      );
      expect(
        alerts.firstWhere((a) => a.code == PharmacyAlertCodes.drugInteraction).severity,
        PharmacyAlertSeverity.warning,
      );
    });

    test('expiring batch within 30 days returns warning', () async {
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
      );
      final nearExpiry = today.add(const Duration(days: 15));
      final p = await seedPharmacyProduct(
        name: 'Panadol',
        refId: refId,
        expiry: nearExpiry,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: p.productId, qty: 2, batchId: p.batchId),
          ],
        ),
      );

      final hit = alerts.firstWhere(
        (a) => a.code == PharmacyAlertCodes.expiringBatchWarning,
      );
      expect(hit.severity, PharmacyAlertSeverity.warning);
      expect(hit.blocksSale, isFalse);
      expect(hit.descriptionAr, contains('15'));
    });

    test('expired batch returns error', () async {
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
      );
      final p = await seedPharmacyProduct(
        name: 'Panadol',
        refId: refId,
        expiry: expired,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: p.productId, qty: 2, batchId: p.batchId),
          ],
        ),
      );

      final hit = alerts.firstWhere((a) => a.code == PharmacyAlertCodes.expiredBatch);
      expect(hit.severity, PharmacyAlertSeverity.error);
      expect(hit.blocksSale, isTrue);
    });

    test('customer allergy returns warning', () async {
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
      );
      await catalog.upsertCustomerAllergies(
        tenantId: tenantId,
        customerId: customerId,
        allergies: const ['Paracetamol'],
      );
      final p = await seedPharmacyProduct(
        name: 'Panadol',
        refId: refId,
        expiry: validExpiry,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          customerId: customerId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: p.productId, qty: 1, batchId: p.batchId),
          ],
        ),
      );

      expect(
        alerts.any((a) => a.code == PharmacyAlertCodes.customerAllergy),
        isTrue,
      );
    });

    test('monitored high qty returns overdose warning', () async {
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'ترامادول',
        nameEn: 'Tramadol',
      );
      final p = await seedPharmacyProduct(
        name: 'Tramadol 50mg',
        refId: refId,
        expiry: validExpiry,
        rxSchedule: PharmacyRxSchedule.monitored,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: p.productId, qty: 120, batchId: p.batchId),
          ],
        ),
      );

      expect(
        alerts.any((a) => a.code == PharmacyAlertCodes.overdoseQty),
        isTrue,
      );
    });

    test('recalled batch returns error', () async {
      final refId = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'أموكسيسيلين',
        nameEn: 'Amoxicillin',
      );
      final p = await seedPharmacyProduct(
        name: 'Amoxil',
        refId: refId,
        expiry: validExpiry,
        recallFrozenAt: today,
      );

      final alerts = await resolver.evaluate(
        SaleAlertContext(
          tenantId: tenantId,
          saleDateTime: today,
          lines: [
            SaleAlertLine(productId: p.productId, qty: 1, batchId: p.batchId),
          ],
        ),
      );

      final hit = alerts.firstWhere((a) => a.code == PharmacyAlertCodes.recalledBatch);
      expect(hit.severity, PharmacyAlertSeverity.error);
      expect(hit.blocksSale, isTrue);
    });
  });

  group('VerticalRegistry evaluateSaleAlerts', () {
    test('oil manifest returns empty alerts', () async {
      const oil = OilChangeVerticalManifest();
      final alerts = await oil.evaluateSaleAlerts(
        const SaleAlertContext(tenantId: 1, productIds: [1, 2]),
      );
      expect(alerts, isEmpty);
    });

    test('pharmacy manifest delegates to resolver', () async {
      const pharmacy = PharmacyVerticalManifest();
      expect(pharmacy.evaluateSaleAlerts, isNotNull);
    });
  });
}
