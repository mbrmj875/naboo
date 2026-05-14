import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';

/// Pure SQL operations for service orders + their items.
///
/// All reads must include:
/// `tenantId = ? AND deletedAt IS NULL`
///
/// Production callers should go through [ServiceOrdersRepository], which gates
/// calls using [TenantContextService.requireActiveTenantId] قبل SQLite.
class ServiceOrdersSqlOps {
  ServiceOrdersSqlOps._();

  // ───────────────────────── service_orders ─────────────────────────

  static bool _rowNotSoftDeleted(Map<String, dynamic> r) {
    final v = r['deletedAt'] ?? r['deleted_at'];
    if (v == null) return true;
    return v.toString().trim().isEmpty;
  }

  /// يدعم مخططات قديمة قد تستخدم `tenant_id` بدل `tenantId`.
  static int? _tenantIdFromRow(Map<String, dynamic> r) {
    final a = r['tenantId'] ?? r['tenant_id'];
    if (a == null) return null;
    if (a is int) return a;
    if (a is num) return a.toInt();
    return int.tryParse(a.toString());
  }

  static Future<List<Map<String, dynamic>>> listServiceOrders(
    DatabaseExecutor db,
    int tenantId, {
    String? status,
    int limit = 200,
  }) async {
    final statusClause = (status != null && status.trim().isNotEmpty)
        ? 'AND so.status = ?'
        : '';
    final args = <Object?>[tenantId, if (status != null && status.trim().isNotEmpty) status.trim(), limit];

    final sql = '''
      SELECT
        so.*,
        inv.type            AS invType,
        inv.totalFils       AS invTotalFils,
        inv.advancePaymentFils AS invAdvanceFils,
        inv.isReturned      AS invIsReturned
      FROM service_orders AS so
      LEFT JOIN invoices AS inv ON so.invoiceId = inv.id
      WHERE so.tenantId = ? AND so.deletedAt IS NULL $statusClause
      ORDER BY so.id DESC
      LIMIT ?
    ''';

    try {
      return await db.rawQuery(sql, args);
    } on Object catch (e, st) {
      AppLogger.error(
        'service_orders_sql',
        'listServiceOrders JOIN path failed; falling back to simple query',
        e,
        st,
      );
      // الاحتياط: الاستعلام البسيط بدون JOIN
      final where = StringBuffer('tenantId = ? AND deletedAt IS NULL');
      final simpleArgs = <Object?>[tenantId];
      if (status != null && status.trim().isNotEmpty) {
        where.write(' AND status = ?');
        simpleArgs.add(status.trim());
      }
      try {
        return await db.query(
          'service_orders',
          where: where.toString(),
          whereArgs: simpleArgs,
          orderBy: 'id DESC',
          limit: limit,
        );
      } on Object catch (e2, st2) {
        AppLogger.error(
          'service_orders_sql',
          'listServiceOrders simple query failed; using SELECT * + in-memory filter',
          e2,
          st2,
        );
        final cap = limit < 1000 ? 1000 : limit;
        final stKey = status?.trim();
        try {
          final raw = await db.rawQuery(
            'SELECT * FROM service_orders WHERE tenantId = ? ORDER BY id DESC LIMIT ?',
            [tenantId, cap],
          );
          return _filterServiceOrderRows(raw, tenantId, stKey, limit);
        } on Object catch (e3, st3) {
          AppLogger.error(
            'service_orders_sql',
            'listServiceOrders exhausted; returning empty',
            e3,
            st3,
          );
          return const [];
        }
      }
    }
  }

  static List<Map<String, dynamic>> _filterServiceOrderRows(
    List<Map<String, dynamic>> raw,
    int tenantId,
    String? statusKey,
    int limit,
  ) {
    Iterable<Map<String, dynamic>> out = raw.where((r) {
      final tid = _tenantIdFromRow(r);
      return tid == tenantId;
    }).where(_rowNotSoftDeleted);
    final sk = statusKey?.trim();
    if (sk != null && sk.isNotEmpty) {
      out = out.where((r) => (r['status'] ?? '').toString() == sk);
    }
    return out.take(limit).toList(growable: false);
  }

  static Future<Map<String, dynamic>?> getServiceOrderByGlobalId(
    DatabaseExecutor db,
    int tenantId,
    String globalId,
  ) async {
    final rows = await db.query(
      'service_orders',
      where: 'tenantId = ? AND deletedAt IS NULL AND global_id = ?',
      whereArgs: [tenantId, globalId.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> insertServiceOrder(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('service_orders', stamped);
  }

  static Future<int> updateServiceOrderById(
    DatabaseExecutor txn,
    int tenantId, {
    required int id,
    required Map<String, dynamic> values,
  }) {
    final patched = Map<String, dynamic>.from(values);
    return txn.update(
      'service_orders',
      patched,
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
  }

  static Future<int> softDeleteServiceOrderById(
    DatabaseExecutor txn,
    int tenantId, {
    required int id,
    required String nowIso,
  }) {
    return txn.update(
      'service_orders',
      {'deletedAt': nowIso, 'updatedAt': nowIso},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
  }

  // ─────────────────────── service_order_items ───────────────────────

  static Future<List<Map<String, dynamic>>> listItemsForOrderGlobalId(
    DatabaseExecutor db,
    int tenantId, {
    required String orderGlobalId,
  }) async {
    final og = orderGlobalId.trim();
    try {
      return await db.query(
        'service_order_items',
        where: 'tenantId = ? AND deletedAt IS NULL AND orderGlobalId = ?',
        whereArgs: [tenantId, og],
        orderBy: 'id ASC',
      );
    } on Object catch (e, st) {
      AppLogger.error(
        'service_orders_sql',
        'listItemsForOrderGlobalId SQL path failed; using SELECT * + filter',
        e,
        st,
      );
      final raw = await db.rawQuery(
        'SELECT * FROM service_order_items WHERE tenantId = ? AND orderGlobalId = ? ORDER BY id ASC',
        [tenantId, og],
      );
      return raw.where(_rowNotSoftDeleted).toList(growable: false);
    }
  }

  static Future<int> insertServiceOrderItem(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('service_order_items', stamped);
  }

  static Future<int> updateServiceOrderItemById(
    DatabaseExecutor txn,
    int tenantId, {
    required int id,
    required Map<String, dynamic> values,
  }) {
    final patched = Map<String, dynamic>.from(values);
    return txn.update(
      'service_order_items',
      patched,
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
  }

  static Future<int> softDeleteServiceOrderItemById(
    DatabaseExecutor txn,
    int tenantId, {
    required int id,
    required String nowIso,
  }) {
    return txn.update(
      'service_order_items',
      {'deletedAt': nowIso, 'updatedAt': nowIso},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tenantId],
    );
  }
}

