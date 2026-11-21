import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/product_variant_kind.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/owner_clothing_dashboard_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OwnerClothingDashboardRepository', () {
    late DatabaseHelper dbHelper;
    late OwnerClothingDashboardRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = OwnerClothingDashboardRepository(db: dbHelper);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<int> seedClothingVariant({
      required int tenantId,
      required String productName,
      required String colorName,
      required String size,
      required int quantity,
      double lowStockThreshold = 0,
    }) async {
      final db = await dbHelper.database;
      final now = DateTime(2026, 5, 20, 12).toIso8601String();
      final productId = await db.insert('products', {
        'tenantId': tenantId,
        'name': productName,
        'qty': 0,
        'lowStockThreshold': lowStockThreshold,
        'isActive': 1,
        'trackInventory': 1,
        'isService': 0,
        'variantKind': ProductVariantKind.clothing,
        'buyPrice': 10000,
        'createdAt': now,
      });
      final colorId = await db.insert('product_colors', {
        'tenantId': tenantId,
        'productId': productId,
        'name': colorName,
        'createdAt': now,
        'updatedAt': now,
      });
      return db.insert('product_variants', {
        'tenantId': tenantId,
        'productId': productId,
        'colorId': colorId,
        'size': size,
        'quantity': quantity,
        'createdAt': now,
        'updatedAt': now,
      });
    }

    test('loadVariantShortages counts SKU-level shortages not parent product', () async {
      await seedClothingVariant(
        tenantId: 1,
        productName: 'قميص',
        colorName: 'أبيض',
        size: 'M',
        quantity: 0,
      );
      await seedClothingVariant(
        tenantId: 1,
        productName: 'قميص',
        colorName: 'أبيض',
        size: 'L',
        quantity: 5,
      );
      await seedClothingVariant(
        tenantId: 2,
        productName: 'بنطلون',
        colorName: 'أسود',
        size: '32',
        quantity: 0,
      );

      final kpi = await repo.loadVariantShortages(tenantId: 1);
      expect(kpi.shortageCount, 1);
    });

    test('loadVariantShortageRows returns color and size labels', () async {
      await seedClothingVariant(
        tenantId: 1,
        productName: 'فستان',
        colorName: 'أحمر',
        size: 'S',
        quantity: 0,
      );

      final rows = await repo.loadVariantShortageRows(tenantId: 1);
      expect(rows, hasLength(1));
      expect(rows.first.displayLabel, 'فستان — أحمر — S');
    });

    test('loadSlowMovers finds in-stock variants without recent sales', () async {
      final db = await dbHelper.database;
      final variantId = await seedClothingVariant(
        tenantId: 1,
        productName: 'جاكيت',
        colorName: 'كحلي',
        size: 'XL',
        quantity: 3,
      );
      await seedClothingVariant(
        tenantId: 1,
        productName: 'جاكيت',
        colorName: 'كحلي',
        size: 'L',
        quantity: 2,
      );

      final oldDate = DateTime(2026, 3, 1, 10).toIso8601String();
      final invId = await db.insert('invoices', {
        'tenantId': 1,
        'date': oldDate,
        'total': 50000,
        'deleted_at': null,
        'isReturned': 0,
      });
      await db.insert('invoice_items', {
        'invoiceId': invId,
        'productVariantId': variantId,
        'productName': 'جاكيت',
        'quantity': 1,
        'baseQty': 1,
        'total': 50000,
        'totalFils': 50000000,
        'deleted_at': null,
      });

      final kpi = await repo.loadSlowMovers(tenantId: 1);
      expect(kpi.slowCount, greaterThanOrEqualTo(2));
      expect(kpi.daysThreshold, OwnerClothingDashboardRepository.slowMoversDaysThreshold);
    });

    test('loadSlowMovers ignores other tenant sales', () async {
      final db = await dbHelper.database;
      final variantId = await seedClothingVariant(
        tenantId: 1,
        productName: 'حذاء',
        colorName: 'بيج',
        size: '42',
        quantity: 4,
      );

      final recent = DateTime(2026, 5, 27, 10).toIso8601String();
      final invId = await db.insert('invoices', {
        'tenantId': 2,
        'date': recent,
        'total': 80000,
        'deleted_at': null,
        'isReturned': 0,
      });
      await db.insert('invoice_items', {
        'invoiceId': invId,
        'productVariantId': variantId,
        'productName': 'حذاء',
        'quantity': 1,
        'baseQty': 1,
        'total': 80000,
        'totalFils': 80000000,
        'deleted_at': null,
      });

      final kpi = await repo.loadSlowMovers(tenantId: 1);
      expect(kpi.slowCount, 1);
    });
  });
}
