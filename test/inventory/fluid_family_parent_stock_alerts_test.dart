import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/product_variant_kind.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper dbHelper;

  setUp(() async {
    dbHelper = DatabaseHelper();
    await dbHelper.closeAndDeleteDatabaseFile();
  });

  tearDown(() async {
    await dbHelper.closeAndDeleteDatabaseFile();
  });

  test('أب الزيت/الهيدروليك لا يدخل تنبيه نفاذ المخزون', () async {
    final db = await dbHelper.database;
    final now = DateTime(2026, 8, 17).toIso8601String();

    final parentId = await db.insert('products', {
      'tenantId': 1,
      'name': 'ديفلون',
      'qty': 0,
      'lowStockThreshold': 0,
      'isActive': 1,
      'trackInventory': 1,
      'isService': 0,
      'stockBaseKind': 3,
      'variantKind': ProductVariantKind.oilFamily,
      'buyPrice': 0,
      'sellPrice': 0,
      'createdAt': now,
    });
    await db.insert('products', {
      'tenantId': 1,
      'name': 'ديفلون — 0W8',
      'qty': 30,
      'lowStockThreshold': 1,
      'isActive': 1,
      'trackInventory': 1,
      'isService': 0,
      'stockBaseKind': 3,
      'variantKind': ProductVariantKind.none,
      'parentProductId': parentId,
      'buyPrice': 4000,
      'sellPrice': 5000,
      'createdAt': now,
    });
    await db.insert('products', {
      'tenantId': 1,
      'name': 'ديفلون — 15W40',
      'qty': 20,
      'lowStockThreshold': 1,
      'isActive': 1,
      'trackInventory': 1,
      'isService': 0,
      'stockBaseKind': 3,
      'variantKind': ProductVariantKind.none,
      'parentProductId': parentId,
      'buyPrice': 6000,
      'sellPrice': 8000,
      'createdAt': now,
    });

    final low = await dbHelper.getProductsForLowStockNotifications(
      tenantId: 1,
    );
    final count = await dbHelper.countProductsForLowStockNotifications(
      tenantId: 1,
    );

    expect(low.map((r) => r['name']), isNot(contains('ديفلون')));
    expect(count, 0);
  });
}
