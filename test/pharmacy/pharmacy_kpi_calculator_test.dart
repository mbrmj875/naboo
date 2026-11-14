import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_kpi_calculator.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_reports_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  final today = DateTime.now();
  final validExpiry = today.add(const Duration(days: 180));

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyKpiCalculator', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository catalog;
    late PharmacyReportsRepository reportsRepo;
    late PharmacyKpiCalculator calculator;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      catalog = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await catalog.ensureSchema();
      reportsRepo = PharmacyReportsRepository(db: dbHelper);
      await reportsRepo.ensureSchema();
      calculator = PharmacyKpiCalculator(reportsRepo: reportsRepo);
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
      required String name,
      required int refId,
      required double batchQty,
      required int costFils,
    }) async {
      final productId = await insertProduct(name);
      await catalog.insertProductProfile(
        tenantId: tenantId,
        productId: productId,
        drugReferenceId: refId,
        strengthText: '500 mg',
        rxSchedule: PharmacyRxSchedule.otc,
      );
      await catalog.insertBatch(
        tenantId: tenantId,
        productId: productId,
        batchNo: 'B-$productId',
        expiryDate: validExpiry,
        qty: batchQty,
        costFils: costFils,
      );
      return productId;
    }

    Future<void> insertInvoice({
      required int totalFils,
      int? productId,
      String productName = 'Drug',
      int unitCostFils = 5000,
      double qty = 1,
    }) async {
      final db = await dbHelper.database;
      final invoiceId = await db.insert('invoices', {
        'tenantId': tenantId,
        'customerName': 'عميل',
        'date': today.toIso8601String(),
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
      if (productId != null) {
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
    }

    test('calculates average ticket from monthly invoices', () async {
      await insertInvoice(totalFils: 10000);
      await insertInvoice(totalFils: 30000);

      final dash = await calculator.calculateDashboard(tenantId: tenantId);
      expect(dash.avgTicketFils, 20000);
    });

    test('calculates inventory turnover from COGS and inventory value', () async {
      final ref = await catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'دواء',
        nameEn: 'Drug',
      );
      final productId = await seedPharmacyProduct(
        name: 'Turnover Drug',
        refId: ref,
        batchQty: 10,
        costFils: 10000,
      );
      await insertInvoice(
        totalFils: 30000,
        productId: productId,
        productName: 'Turnover Drug',
        unitCostFils: 10000,
        qty: 5,
      );

      final dash = await calculator.calculateDashboard(tenantId: tenantId);
      expect(dash.inventoryValueFils, 100000);
      expect(dash.inventoryTurnover, closeTo(0.5, 0.01));
    });

    test('sums receivable and payable into total debt exposure', () async {
      final db = await dbHelper.database;
      final supplierId = await db.insert('suppliers', {
        'tenantId': tenantId,
        'name': 'مورد',
        'phone': '',
        'isActive': 1,
        'createdAt': today.toUtc().toIso8601String(),
        'updatedAt': today.toUtc().toIso8601String(),
      });
      await db.insert('supplier_bills', {
        'tenantId': tenantId,
        'supplierId': supplierId,
        'amount': 50,
        'createdAt': today.toUtc().toIso8601String(),
        'note': '',
      });

      final dash = await calculator.calculateDashboard(tenantId: tenantId);
      expect(dash.totalPayableFils, greaterThan(0));
      expect(
        dash.totalDebtExposureFils,
        dash.totalReceivableFils + dash.totalPayableFils,
      );
    });
  });
}
