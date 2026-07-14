import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/owner_supermarket_dashboard_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OwnerSupermarketDashboardRepository', () {
    late DatabaseHelper dbHelper;
    late OwnerSupermarketDashboardRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = OwnerSupermarketDashboardRepository(db: dbHelper);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('loadTopSellers aggregates in SQL with tenant filter', () async {
      final db = await dbHelper.database;
      final now = DateTime(2026, 5, 20, 12);
      final invId = await db.insert('invoices', {
        'tenantId': 1,
        'date': now.toIso8601String(),
        'total': 10000,
        'deleted_at': null,
        'isReturned': 0,
      });
      await db.insert('invoice_items', {
        'invoiceId': invId,
        'productName': 'حليب',
        'quantity': 3,
        'baseQty': 3,
        'total': 6000,
        'totalFils': 6000000,
        'deleted_at': null,
      });
      await db.insert('invoice_items', {
        'invoiceId': invId,
        'productName': 'خبز',
        'quantity': 1,
        'baseQty': 1,
        'total': 4000,
        'totalFils': 4000000,
        'deleted_at': null,
      });

      final otherInv = await db.insert('invoices', {
        'tenantId': 2,
        'date': now.toIso8601String(),
        'total': 5000,
        'deleted_at': null,
        'isReturned': 0,
      });
      await db.insert('invoice_items', {
        'invoiceId': otherInv,
        'productName': 'tenant2',
        'quantity': 9,
        'baseQty': 9,
        'total': 5000,
        'totalFils': 5000000,
        'deleted_at': null,
      });

      final kpi = await repo.loadTopSellers(
        tenantId: 1,
        range: OwnerDateRange.custom(
          DateTime(2026, 5, 20),
          DateTime(2026, 5, 21),
        ),
      );

      expect(kpi.items, hasLength(2));
      expect(kpi.items.first.productName, 'حليب');
      expect(kpi.items.first.revenueFils, 6000000);
    });

    test('loadRetailStockShortages counts all low stock products', () async {
      final db = await dbHelper.database;
      final now = DateTime(2026, 5, 20, 12);
      await db.insert('products', {
        'tenantId': 1,
        'name': 'رز',
        'qty': 1,
        'lowStockThreshold': 5,
        'isActive': 1,
        'trackInventory': 1,
        'isService': 0,
        'buyPrice': 1000,
        'createdAt': now.toIso8601String(),
      });
      await db.insert('products', {
        'tenantId': 1,
        'name': 'زيت',
        'qty': 10,
        'lowStockThreshold': 2,
        'isActive': 1,
        'trackInventory': 1,
        'isService': 0,
        'stockBaseKind': 1,
        'buyPrice': 2000,
        'createdAt': now.toIso8601String(),
      });

      final alert = await repo.loadRetailStockShortages(tenantId: 1);
      expect(alert.shortageCount, 1);
    });

    test('loadRetailStockShortages uses full COUNT not list LIMIT', () async {
      final db = await dbHelper.database;
      final now = DateTime(2026, 5, 20, 12);
      for (var i = 0; i < 3; i++) {
        await db.insert('products', {
          'tenantId': 1,
          'name': 'ناقص $i',
          'qty': 0,
          'lowStockThreshold': 1,
          'isActive': 1,
          'trackInventory': 1,
          'isService': 0,
          'buyPrice': 1000,
          'createdAt': now.toIso8601String(),
        });
      }

      final count = await dbHelper.countProductsForLowStockNotifications(
        tenantId: 1,
      );
      final limited = await dbHelper.getProductsForLowStockNotifications(
        tenantId: 1,
        limit: 2,
      );
      final alert = await repo.loadRetailStockShortages(tenantId: 1);

      expect(count, 3);
      expect(limited, hasLength(2));
      expect(alert.shortageCount, 3);
    });
  });
}
