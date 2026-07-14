import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';
import '../verticals/oil_change/utils/oil_change_lookup_normalize.dart';
import '../verticals/oil_change/utils/oil_change_order_status.dart';
import 'service_order_kinds.dart';

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
    final sql = '''
      SELECT
        so.*,
        inv.type            AS invType,
        inv.totalFils       AS invTotalFils,
        inv.advancePaymentFils AS invAdvanceFils,
        inv.isReturned      AS invIsReturned
      FROM service_orders AS so
      LEFT JOIN invoices AS inv ON so.invoiceId = inv.id
      WHERE so.tenantId = ? AND so.deletedAt IS NULL
        AND (so.orderKind IS NULL OR so.orderKind = ?) $statusClause
      ORDER BY so.id DESC
      LIMIT ?
    ''';

    final repairArgs = <Object?>[
      tenantId,
      ServiceOrderKinds.repair,
      if (status != null && status.trim().isNotEmpty) status.trim(),
      limit,
    ];

    try {
      return await db.rawQuery(sql, repairArgs);
    } on Object catch (e, st) {
      AppLogger.error(
        'service_orders_sql',
        'listServiceOrders JOIN path failed; falling back to simple query',
        e,
        st,
      );
      // الاحتياط: الاستعلام البسيط بدون JOIN
      final where = StringBuffer(
        "tenantId = ? AND deletedAt IS NULL AND (orderKind IS NULL OR orderKind = ?)",
      );
      final simpleArgs = <Object?>[tenantId, ServiceOrderKinds.repair];
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
    out = out.where(ServiceOrderKinds.isRepairTicket);
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

  static Future<Map<String, dynamic>?> getServiceOrderById(
    DatabaseExecutor db,
    int tenantId,
    int id,
  ) async {
    final rows = await db.query(
      'service_orders',
      where: 'tenantId = ? AND deletedAt IS NULL AND id = ?',
      whereArgs: [tenantId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// آخر بطاقة غيار زيت لنفس رقم اللوحة (لتعبئة بيانات السيارة تلقائياً).
  static Future<Map<String, dynamic>?> getLatestOilChangeByPlate(
    DatabaseExecutor db,
    int tenantId, {
    required String deviceSerial,
    int? excludeOrderId,
  }) async {
    final plate = deviceSerial.trim();
    if (plate.isEmpty) return null;
    final plateKey = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (plateKey.isEmpty) return null;

    final variants = <String>{plate, plate.toLowerCase(), plateKey};
    for (final variant in variants) {
      if (variant.isEmpty) continue;
      final row = await _queryLatestOilChangeWhere(
        db,
        tenantId,
        excludeOrderId: excludeOrderId,
        extraWhere: 'deviceSerial = ?',
        extraArgs: [variant],
      );
      if (row != null) return row;
    }

    return _scanRecentOilChangeByPlateKey(
      db,
      tenantId,
      plateKey: plateKey,
      excludeOrderId: excludeOrderId,
    );
  }

  static Future<Map<String, dynamic>?> _queryLatestOilChangeWhere(
    DatabaseExecutor db,
    int tenantId, {
    required String extraWhere,
    required List<Object?> extraArgs,
    int? excludeOrderId,
  }) async {
    final where = StringBuffer(
      'tenantId = ? AND deletedAt IS NULL AND orderKind = ? AND $extraWhere',
    );
    final args = <Object?>[tenantId, ServiceOrderKinds.oilChange, ...extraArgs];
    if (excludeOrderId != null && excludeOrderId > 0) {
      where.write(' AND id != ?');
      args.add(excludeOrderId);
    }
    final rows = await db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> _scanRecentOilChangeByPlateKey(
    DatabaseExecutor db,
    int tenantId, {
    required String plateKey,
    int? excludeOrderId,
  }) async {
    final where = StringBuffer(
      'tenantId = ? AND deletedAt IS NULL AND orderKind = ? '
      "AND deviceSerial IS NOT NULL AND trim(deviceSerial) != ''",
    );
    final args = <Object?>[tenantId, ServiceOrderKinds.oilChange];
    if (excludeOrderId != null && excludeOrderId > 0) {
      where.write(' AND id != ?');
      args.add(excludeOrderId);
    }
    final rows = await db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 160,
    );
    for (final row in rows) {
      final stored = (row['deviceSerial'] ?? '').toString();
      if (OilChangeLookupNormalize.normalizePlateKey(stored) == plateKey) {
        return row;
      }
    }
    return null;
  }

  /// آخر بطاقة غيار زيت لنفس العميل (عند عدم وجود لوحة).
  static Future<Map<String, dynamic>?> getLatestOilChangeByCustomerId(
    DatabaseExecutor db,
    int tenantId, {
    required int customerId,
    int? excludeOrderId,
  }) async {
    if (customerId <= 0) return null;
    final where = StringBuffer(
      'tenantId = ? AND deletedAt IS NULL AND orderKind = ? AND customerId = ?',
    );
    final args = <Object?>[tenantId, ServiceOrderKinds.oilChange, customerId];
    if (excludeOrderId != null && excludeOrderId > 0) {
      where.write(' AND id != ?');
      args.add(excludeOrderId);
    }
    final rows = await db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// آخر بطاقة غيار زيت لنفس اسم العميل (للعملاء غير المربوطين بـ customerId).
  static Future<Map<String, dynamic>?> getLatestOilChangeByCustomerName(
    DatabaseExecutor db,
    int tenantId, {
    required String customerName,
    int? excludeOrderId,
  }) async {
    final name = customerName.trim();
    if (name.isEmpty) return null;
    final nameKey = OilChangeLookupNormalize.normalizeNameKey(name);
    if (nameKey.isEmpty) return null;

    final row = await _queryLatestOilChangeWhere(
      db,
      tenantId,
      excludeOrderId: excludeOrderId,
      extraWhere: 'LOWER(TRIM(customerNameSnapshot)) = ?',
      extraArgs: [nameKey],
    );
    if (row != null) return row;

    return _scanRecentOilChangeByCustomerNameKey(
      db,
      tenantId,
      nameKey: nameKey,
      excludeOrderId: excludeOrderId,
    );
  }

  static Future<Map<String, dynamic>?> _scanRecentOilChangeByCustomerNameKey(
    DatabaseExecutor db,
    int tenantId, {
    required String nameKey,
    int? excludeOrderId,
  }) async {
    final where = StringBuffer(
      'tenantId = ? AND deletedAt IS NULL AND orderKind = ? '
      "AND customerNameSnapshot IS NOT NULL AND trim(customerNameSnapshot) != ''",
    );
    final args = <Object?>[tenantId, ServiceOrderKinds.oilChange];
    if (excludeOrderId != null && excludeOrderId > 0) {
      where.write(' AND id != ?');
      args.add(excludeOrderId);
    }
    final rows = await db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 160,
    );
    for (final row in rows) {
      final stored = (row['customerNameSnapshot'] ?? '').toString();
      if (OilChangeLookupNormalize.normalizeNameKey(stored) == nameKey) {
        return row;
      }
    }
    return null;
  }

  static Future<bool> _tableHasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in info) {
      if ((r['name'] ?? '').toString() == column) return true;
    }
    return false;
  }

  static bool _rowNotDeleted(Map<String, dynamic> r) => _rowNotSoftDeleted(r);

  static bool _matchesOilLogSearch(Map<String, dynamic> r, String q) {
    final needle = q.toLowerCase();
    bool hit(String? v) => (v ?? '').toString().toLowerCase().contains(needle);
    return hit(r['customerNameSnapshot']?.toString()) ||
        hit(r['customerPhone']?.toString()) ||
        hit(r['deviceName']?.toString()) ||
        hit(r['deviceSerial']?.toString()) ||
        hit(r['carModel']?.toString());
  }

  static List<Map<String, dynamic>> _filterOilLogRows(
    List<Map<String, dynamic>> rows, {
    String? searchQuery,
    int? afterId,
    required int limit,
    OilChangeLogStatusFilter? statusFilter,
  }) {
    final cap = limit < 1 ? 40 : (limit > 120 ? 120 : limit);
    final q = searchQuery?.trim();
    final hasSearch = q != null && q.isNotEmpty;

    var out = rows
        .where(_rowNotDeleted)
        .where(ServiceOrderKinds.isOilChangeLogRow)
        .toList();

    if (statusFilter == OilChangeLogStatusFilter.suspended) {
      out = out.where(OilChangeOrderStatus.isSuspended).toList();
    } else if (statusFilter == OilChangeLogStatusFilter.active) {
      out = out.where(OilChangeOrderStatus.isActiveLogRow).toList();
    }

    if (hasSearch) {
      out = out.where((r) => _matchesOilLogSearch(r, q)).toList();
    }

    out.sort((a, b) {
      final ai = (a['id'] as num?)?.toInt() ?? 0;
      final bi = (b['id'] as num?)?.toInt() ?? 0;
      return bi.compareTo(ai);
    });

    if (afterId != null && afterId > 0) {
      out = out.where((r) => ((r['id'] as num?)?.toInt() ?? 0) < afterId).toList();
    }

    if (out.length > cap) {
      out = out.sublist(0, cap);
    }
    return out;
  }

  /// سجل بطاقات غيار الزيت — ترقيم بمؤشر [afterId] (بدون OFFSET).
  ///
  /// يدعم قواعد قديمة بلا [orderKind] أو ببطاقات مُوسومة repair مع بيانات زيت.
  static Future<List<Map<String, dynamic>>> listOilChangeLogPage(
    DatabaseExecutor db,
    int tenantId, {
    String? searchQuery,
    int? afterId,
    int limit = 40,
    OilChangeLogStatusFilter? statusFilter,
  }) async {
    final cap = limit < 1 ? 40 : (limit > 120 ? 120 : limit);
    final q = searchQuery?.trim();
    final hasSearch = q != null && q.isNotEmpty;
    final like = hasSearch ? '%$q%' : null;

    final hasOrderKind =
        await _tableHasColumn(db, 'service_orders', 'orderKind');
    final hasCustomerPhone =
        await _tableHasColumn(db, 'service_orders', 'customerPhone');

    try {
      final where = StringBuffer(
        "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '')",
      );
      final args = <Object?>[
        tenantId,
      ];

      if (hasOrderKind) {
        where.write(
          " AND (orderKind = ? OR ("
          "(orderKind IS NULL OR orderKind = ?) AND ("
          "(oilType IS NOT NULL AND TRIM(oilType) != '') OR "
          "(odometerCurrent IS NOT NULL AND TRIM(odometerCurrent) != '')"
          ")))",
        );
        args.addAll([
          ServiceOrderKinds.oilChange,
          ServiceOrderKinds.repair,
        ]);
      }

      if (afterId != null && afterId > 0) {
        where.write(' AND id < ?');
        args.add(afterId);
      }
      if (hasSearch) {
        if (hasCustomerPhone) {
          where.write(
            ' AND (customerNameSnapshot LIKE ? OR customerPhone LIKE ? '
            'OR deviceName LIKE ? OR deviceSerial LIKE ? OR carModel LIKE ?)',
          );
          args.addAll([like, like, like, like, like]);
        } else {
          where.write(
            ' AND (customerNameSnapshot LIKE ? OR deviceName LIKE ? '
            'OR deviceSerial LIKE ? OR carModel LIKE ?)',
          );
          args.addAll([like, like, like, like]);
        }
      }

      if (statusFilter == OilChangeLogStatusFilter.suspended) {
        where.write(' AND status = ?');
        args.add(OilChangeOrderStatus.suspended);
      } else if (statusFilter == OilChangeLogStatusFilter.active) {
        where.write(
          " AND (status IS NULL OR TRIM(COALESCE(status,'')) = '' OR status != ?)",
        );
        args.add(OilChangeOrderStatus.suspended);
      }

      final rows = await db.query(
        'service_orders',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'id DESC',
        limit: cap,
      );

      if (!hasOrderKind) {
        return _filterOilLogRows(
          rows,
          searchQuery: searchQuery,
          afterId: afterId,
          limit: cap,
          statusFilter: statusFilter,
        );
      }
      return rows;
    } on Object catch (e) {
      AppLogger.warn(
        'service_orders_sql',
        'listOilChangeLogPage strict query failed; using in-memory filter: $e',
      );
      final raw = await db.query(
        'service_orders',
        where: 'tenantId = ?',
        whereArgs: [tenantId],
        orderBy: 'id DESC',
        limit: 800,
      );
      return _filterOilLogRows(
        raw,
        searchQuery: searchQuery,
        afterId: afterId,
        limit: cap,
        statusFilter: statusFilter,
      );
    }
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

