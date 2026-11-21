import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_stock_service.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  test('بيع 5.5 لتر ينقص رصيد المنتج حتى لو رصيد المستودع صفر', () async {
    final harness = OilChangeTestHarness.instance;
    await harness.reset();
    final db = await harness.database;
    final tid = await harness.tenantId();
    final now = DateTime.now().toUtc().toIso8601String();
    final productId = await db.insert('products', {
      'tenantId': tid,
      'name': 'اويل — 0W8',
      'qty': 50,
      'isActive': 1,
      'trackInventory': 1,
      'buyPrice': 0,
      'sellPrice': 20000,
      'createdAt': now,
    });
    final warehouseId = await db.insert('warehouses', {
      'tenantId': tid,
      'name': 'المحل',
      'isDefault': 1,
      'isActive': 1,
      'createdAt': now,
    });
    await db.insert('product_warehouse_stock', {
      'tenantId': tid,
      'productId': productId,
      'warehouseId': warehouseId,
      'qty': 0,
      'updatedAt': now,
    });

    await OilChangeStockService.instance.issueForOilChangeOrder(
      orderId: 12,
      productId: productId,
      liters: 5.5,
      warehouseId: warehouseId,
    );

    final product = await db.query(
      'products',
      columns: ['qty'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [productId, tid],
      limit: 1,
    );
    expect((product.first['qty'] as num).toDouble(), 44.5);

    final shelf = await db.query(
      'product_warehouse_stock',
      columns: ['qty'],
      where: 'tenantId = ? AND productId = ? AND warehouseId = ?',
      whereArgs: [tid, productId, warehouseId],
      limit: 1,
    );
    expect((shelf.first['qty'] as num).toDouble(), 44.5);

    final shown = await OilChangeStockService.instance.availableLiters(
      productId: productId,
      warehouseId: warehouseId,
    );
    expect(shown, 44.5);
  });
}
