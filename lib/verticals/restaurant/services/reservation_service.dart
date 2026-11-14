import 'package:sqflite/sqflite.dart';

import '../models/restaurant_models.dart';

/// حجز مكوّنات حرجة بذرية داخل transaction واحد (spec §8).
///
/// تعارض موثّق: يستخدم `products.qty` REAL عبر [RestaurantStockMicro]
/// لأن Core لا يملك `on_hand_qty_micro`.
class ReservationService {
  const ReservationService();

  /// يفحص المتاح لكل مكوّن حرج ثم يُدرج الحجوزات — أو يرمي [IngredientShortageException].
  Future<void> reserveCritical({
    required DatabaseExecutor txn,
    required int tenantId,
    required int orderId,
    required int sessionId,
    required List<IngredientNeed> criticalNeeds,
  }) async {
    if (criticalNeeds.isEmpty) return;

    for (final need in criticalNeeds) {
      final available = await availableQtyMicro(
        txn: txn,
        tenantId: tenantId,
        productId: need.productId,
      );
      if (available < need.qtyMicroNeeded) {
        throw IngredientShortageException(
          productId: need.productId,
          availableMicro: available,
          requestedMicro: need.qtyMicroNeeded,
          nameAr: need.nameAr,
        );
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final need in criticalNeeds) {
      await txn.insert('restaurant_ingredient_reservations', {
        'tenant_id': tenantId,
        'order_id': orderId,
        'session_id': sessionId,
        'product_id': need.productId,
        'qty_micro_reserved': need.qtyMicroNeeded,
        'state': 'reserved',
        'reserved_at': now,
      });
    }
  }

  Future<int> availableQtyMicro({
    required DatabaseExecutor txn,
    required int tenantId,
    required int productId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        CAST(ROUND(COALESCE(p.qty, 0) * 1000) AS INTEGER)
          - COALESCE((
              SELECT SUM(r.qty_micro_reserved)
              FROM restaurant_ingredient_reservations r
              WHERE r.product_id = p.id
                AND r.tenant_id = p.tenantId
                AND r.state = 'reserved'
            ), 0) AS available
      FROM products p
      WHERE p.id = ? AND p.tenantId = ?
      ''',
      [productId, tenantId],
    );
    if (rows.isEmpty) return 0;
    final v = rows.first['available'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// تحويل reserved → consumed + خصم products.qty + snapshot تكلفة.
  Future<void> consumeReservationsForOrder({
    required DatabaseExecutor txn,
    required int tenantId,
    required int orderId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final reservations = await txn.query(
      'restaurant_ingredient_reservations',
      where: 'tenant_id = ? AND order_id = ? AND state = ?',
      whereArgs: [tenantId, orderId, 'reserved'],
    );

    // ربط بسطور الطلب النشطة لنفس المكوّن (تقريبي: أول سطر نشط للطلب).
    final activeLines = await txn.query(
      'restaurant_order_lines',
      where: "order_id = ? AND line_state = 'active' AND deleted_at IS NULL",
      whereArgs: [orderId],
    );
    final fallbackLineId =
        activeLines.isEmpty ? null : activeLines.first['id'] as int;

    for (final r in reservations) {
      final productId = r['product_id'] as int;
      final qtyMicro = r['qty_micro_reserved'] as int;
      final reservationId = r['id'] as int;

      final productRows = await txn.query(
        'products',
        columns: ['buyPrice', 'qty'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [productId, tenantId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw StateError('منتج $productId غير موجود عند الاستهلاك');
      }
      final buyPrice = (productRows.first['buyPrice'] as num?)?.toDouble() ?? 0;
      final unitCostFils = (buyPrice * 1000).round();
      // total = qty_micro/1000 × unit_cost بحساب int
      final totalCostFils = (qtyMicro * unitCostFils) ~/ 1000;

      final lineId = fallbackLineId;
      if (lineId != null) {
        await txn.insert('restaurant_order_line_costs', {
          'order_line_id': lineId,
          'product_id': productId,
          'base_unit': 'g',
          'qty_micro': qtyMicro,
          'unit_cost_fils_at_sale': unitCostFils,
          'total_cost_fils_at_sale': totalCostFils,
          'consumed_at': now,
        });
      }

      final deltaQty = RestaurantStockMicro.toQty(qtyMicro);
      await txn.rawUpdate(
        'UPDATE products SET qty = qty - ? WHERE id = ? AND tenantId = ?',
        [deltaQty, productId, tenantId],
      );

      await txn.update(
        'restaurant_ingredient_reservations',
        {'state': 'consumed', 'resolved_at': now},
        where: 'id = ?',
        whereArgs: [reservationId],
      );
    }
  }

  Future<void> releaseReservationsForOrder({
    required DatabaseExecutor txn,
    required int tenantId,
    required int orderId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await txn.update(
      'restaurant_ingredient_reservations',
      {'state': 'released', 'resolved_at': now},
      where: 'tenant_id = ? AND order_id = ? AND state = ?',
      whereArgs: [tenantId, orderId, 'reserved'],
    );
  }

  Future<void> releaseReservationsForLineNeeds({
    required DatabaseExecutor txn,
    required int tenantId,
    required int orderId,
    required List<IngredientNeed> needs,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final need in needs) {
      final rows = await txn.query(
        'restaurant_ingredient_reservations',
        where:
            'tenant_id = ? AND order_id = ? AND product_id = ? AND state = ?',
        whereArgs: [tenantId, orderId, need.productId, 'reserved'],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (rows.isEmpty) continue;
      await txn.update(
        'restaurant_ingredient_reservations',
        {'state': 'released', 'resolved_at': now},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }
}
