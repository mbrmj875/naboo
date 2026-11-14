import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_reports_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;
  final today = DateTime.now();
  final expiringSoon = today.add(const Duration(days: 15));
  final validExpiry = today.add(const Duration(days: 180));

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyReportsRepository', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository catalog;
    late PharmacyReportsRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      catalog = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await catalog.ensureSchema();
      repo = PharmacyReportsRepository(db: dbHelper);
      await repo.ensureSchema();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<int> insertProduct(int tid, String name) async {
      final db = await dbHelper.database;
      return db.insert('products', {
        'tenantId': tid,
        'name': name,
        'buyPrice': 10,
        'sellPrice': 15,
        'minSellPrice': 12,
        'qty': 0,
        'lowStockThreshold': 5,
        'status': 'instock',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'trackInventory': 1,
        'isActive': 1,
      });
    }

    Future<int> seedPharmacyProduct({
      required int tid,
      required String name,
      required int refId,
      required DateTime expiry,
      double batchQty = 20,
      int costFils = 10000,
    }) async {
      final productId = await insertProduct(tid, name);
      await catalog.insertProductProfile(
        tenantId: tid,
        productId: productId,
        drugReferenceId: refId,
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
      );
      await catalog.insertBatch(
        tenantId: tid,
        productId: productId,
        batchNo: 'B-$productId',
        expiryDate: expiry,
        qty: batchQty,
        costFils: costFils,
      );
      return productId;
    }

    Future<void> insertSale({
      required int tid,
      required int productId,
      required String productName,
      required DateTime date,
      required int totalFils,
      required int unitCostFils,
      required double qty,
    }) async {
      final db = await dbHelper.database;
      final invoiceId = await db.insert('invoices', {
        'tenantId': tid,
        'customerName': 'عميل',
        'date': date.toIso8601String(),
        'type': 0,
        'total': totalFils / 1000.0,
        'totalFils': totalFils,
        'discount': 0,
        'discountFils': 0,
        'tax': 0,
        'taxFils': 0,
        'advancePayment': 0,
        'advancePaymentFils': 0,
        'isReturned': 0,
        'deleted_at': null,
      });
      await db.insert('invoice_items', {
        'invoiceId': invoiceId,
        'productName': productName,
        'quantity': qty,
        'enteredQty': qty,
        'price': totalFils / qty / 1000.0,
        'priceFils': (totalFils / qty).round(),
        'total': totalFils / 1000.0,
        'totalFils': totalFils,
        'unitCostFils': unitCostFils,
        'productId': productId,
        'deleted_at': null,
      });
    }

    test('counts expiring batches within 30 days', () async {
      final ref = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
      );
      await seedPharmacyProduct(
        tid: tenantId,
        name: 'Panadol',
        refId: ref,
        expiry: expiringSoon,
      );
      await seedPharmacyProduct(
        tid: tenantId,
        name: 'Vitamin C',
        refId: ref,
        expiry: validExpiry,
      );

      final dash = await repo.loadOwnerDashboard(tenantId: tenantId);
      expect(dash.expiringSoonCount, 1);
    });

    test('loads sales KPIs for pharmacy products', () async {
      final ref = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'إيبوبروفين',
        nameEn: 'Ibuprofen',
      );
      final productId = await seedPharmacyProduct(
        tid: tenantId,
        name: 'Brufen 400mg',
        refId: ref,
        expiry: validExpiry,
      );
      await insertSale(
        tid: tenantId,
        productId: productId,
        productName: 'Brufen 400mg',
        date: today,
        totalFils: 30000,
        unitCostFils: 10000,
        qty: 2,
      );

      final dash = await repo.loadOwnerDashboard(tenantId: tenantId);
      expect(dash.topDrugs, isNotEmpty);
      expect(dash.topDrugs.first.productName, 'Brufen 400mg');
      expect(dash.monthlyProfitFils, greaterThanOrEqualTo(0));
    });

    test('tenant isolation for expiry counts', () async {
      final ref = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'دواء',
        nameEn: 'Drug',
      );
      await seedPharmacyProduct(
        tid: tenantId,
        name: 'T1 Drug',
        refId: ref,
        expiry: expiringSoon,
      );

      final ref2 = await catalog.insertDrugReference(
        tenantId: otherTenantId,
        nameAr: 'دواء 2',
        nameEn: 'Drug 2',
      );
      await seedPharmacyProduct(
        tid: otherTenantId,
        name: 'T2 Drug',
        refId: ref2,
        expiry: validExpiry,
      );

      final t1 = await repo.loadOwnerDashboard(tenantId: tenantId);
      final t2 = await repo.loadOwnerDashboard(tenantId: otherTenantId);
      expect(t1.expiringSoonCount, 1);
      expect(t2.expiringSoonCount, 0);
    });

    test('loadReportsBundle includes inventory and sales sections', () async {
      final ref = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'دواء',
        nameEn: 'Drug',
      );
      await seedPharmacyProduct(
        tid: tenantId,
        name: 'Drug A',
        refId: ref,
        expiry: expiringSoon,
        batchQty: 0,
      );

      final bundle = await repo.loadReportsBundle(tenantId: tenantId);
      expect(bundle.inventory.outOfStock, isNotEmpty);
      expect(bundle.sales.dailySalesFils, 0);
      expect(bundle.finance.receivableFils, isA<int>());
      expect(bundle.suppliers.bestPriceMatches, isA<List<dynamic>>());
    });
  });
}
