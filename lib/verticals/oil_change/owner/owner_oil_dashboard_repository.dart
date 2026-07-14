import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/service_order_kinds.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/stock_quantity_kind.dart';
import '../../../owner/models/owner_date_range.dart';
import '../../../owner/models/owner_kpi_models.dart';

/// استعلامات v3 لورشة غيار الزيت — [tenantId] إلزامي (لا TenantContext داخلياً).
class OwnerOilDashboardRepository {
  OwnerOilDashboardRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  static const garageStaleHoursThreshold = 2;

  Future<OilActiveCarsKpi> loadActiveCars({
    required int tenantId,
    int garageStaleHours = garageStaleHoursThreshold,
  }) async {
    final db = await _db.database;
    final count = await _countActiveOilGarage(db, tenantId);
    final stale = await _countStaleGarageOrders(
      db,
      tenantId,
      hoursThreshold: garageStaleHours,
    );
    return OilActiveCarsKpi(activeCount: count, staleWaitingCount: stale);
  }

  Future<OilChangesKpi> loadOilChangesInRange({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    final db = await _db.database;
    final stats = await _aggregateOilOrdersInRange(
      db,
      tenantId: tenantId,
      startIso: range.startLocal.toIso8601String(),
      endExclusiveIso: range.endExclusiveLocal.toIso8601String(),
      staffName: staffName,
    );
    return OilChangesKpi(
      changeCount: stats.count,
      revenueFils: stats.revenueFils,
      range: range,
    );
  }

  Future<OilAvgTicketKpi> loadAvgTicket({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    final stats = await loadOilChangesInRange(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
    final avg = stats.changeCount <= 0
        ? 0
        : stats.revenueFils ~/ stats.changeCount;
    return OilAvgTicketKpi(
      avgTicketFils: avg,
      changeCount: stats.changeCount,
      range: range,
    );
  }

  Future<InventoryAlert> loadOilFluidShortages({required int tenantId}) async {
    try {
      final count = await _db.countProductsForLowStockNotifications(
        tenantId: tenantId,
        stockBaseKind: StockBaseKind.volumeLiter,
      );
      return InventoryAlert(shortageCount: count);
    } catch (e, st) {
      AppLogger.error(
        'OwnerOilDashboardRepo',
        'تعذر تحميل نواقص سوائل الزيت',
        e,
        st,
      );
      return const InventoryAlert(shortageCount: 0);
    }
  }

  Future<HybridRevenueKpi> loadHybridRevenueSplit({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    final db = await _db.database;
    final start = range.startLocal.toIso8601String();
    final end = range.endExclusiveLocal.toIso8601String();

    final totalFils = await _sumInvoiceSalesFils(
      db,
      tenantId: tenantId,
      startIso: start,
      endExclusiveIso: end,
      staffName: staffName,
    );
    final serviceFils = await _sumOilInvoicedRevenueFils(
      db,
      tenantId: tenantId,
      startIso: start,
      endExclusiveIso: end,
      staffName: staffName,
    );
    final posFils = totalFils > serviceFils ? totalFils - serviceFils : 0;
    return HybridRevenueKpi(
      serviceFils: serviceFils,
      posRetailFils: posFils,
      range: range,
    );
  }

  /// إيراد يومي (آخر 7 أيام) من بطاقات غيار الزيت — للمخطط في لوحة المالك.
  Future<List<int>> loadDailyRevenueSparklineFils({
    required int tenantId,
    String? staffName,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final seriesStart = todayStart.subtract(const Duration(days: 6));
    final endExclusive = todayStart.add(const Duration(days: 1));

    final rows = await _queryDailyOilRevenue(
      db,
      tenantId: tenantId,
      startIso: seriesStart.toIso8601String(),
      endExclusiveIso: endExclusive.toIso8601String(),
      staffName: staffName,
    );

    final byDay = <String, int>{};
    for (final row in rows) {
      final day = (row['day'] as String?) ?? '';
      final invSum = (row['invSum'] as num?)?.toDouble() ?? 0;
      final cardSum = (row['cardSum'] as num?)?.toInt() ?? 0;
      byDay[day] = IqdMoney.toFils(invSum) + cardSum;
    }

    return _buildSevenDaySeries(byDay, seriesStart);
  }

  static Future<int> _countActiveOilGarage(Database db, int tenantId) async {
    final hasOrderKind = await _tableHasColumn(db, 'service_orders', 'orderKind');
    final where = StringBuffer(
      "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '') "
      "AND status IN ('pending', 'in_progress')",
    );
    final args = <Object?>[tenantId];
    _appendOilOrderKindFilter(where, args, hasOrderKind: hasOrderKind);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM service_orders WHERE ${where.toString()}',
      args,
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  static Future<int> _countStaleGarageOrders(
    Database db,
    int tenantId, {
    required int hoursThreshold,
  }) async {
    final hasOrderKind = await _tableHasColumn(db, 'service_orders', 'orderKind');
    final hasCreatedAt = await _tableHasColumn(db, 'service_orders', 'createdAt');
    if (!hasCreatedAt) return 0;
    final where = StringBuffer(
      "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '') "
      "AND status IN ('pending', 'in_progress') "
      "AND datetime(createdAt) <= datetime('now', 'localtime', '-$hoursThreshold hours')",
    );
    final args = <Object?>[tenantId];
    _appendOilOrderKindFilter(where, args, hasOrderKind: hasOrderKind);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM service_orders WHERE ${where.toString()}',
      args,
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  static Future<_OilRangeStats> _aggregateOilOrdersInRange(
    Database db, {
    required int tenantId,
    required String startIso,
    required String endExclusiveIso,
    String? staffName,
  }) async {
    final hasOrderKind = await _tableHasColumn(db, 'service_orders', 'orderKind');
    final hasInvoice = await _tableHasColumn(db, 'service_orders', 'invoiceId');
    final hasTech = await _tableHasColumn(db, 'service_orders', 'technicianName');

    final where = StringBuffer(
      "so.tenantId = ? AND (so.deletedAt IS NULL OR TRIM(COALESCE(so.deletedAt,'')) = '') "
      "AND so.status NOT IN ('cancelled') "
      "AND so.createdAt >= ? AND so.createdAt < ?",
    );
    final args = <Object?>[tenantId, startIso, endExclusiveIso];
    _appendOilOrderKindFilter(where, args, hasOrderKind: hasOrderKind, alias: 'so');
    if (staffName != null && staffName.isNotEmpty && hasTech) {
      where.write(' AND so.technicianName = ?');
      args.add(staffName);
    }

    final invoiceJoin = hasInvoice
        ? 'LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId '
            'AND i.deleted_at IS NULL AND IFNULL(i.isReturned, 0) = 0'
        : '';
    final invoiceSum = hasInvoice
        ? 'COALESCE(SUM(CASE WHEN so.invoiceId IS NOT NULL AND so.invoiceId > 0 '
            'THEN i.total ELSE 0 END), 0)'
        : '0';
    const cardSum =
        'COALESCE(SUM(CASE WHEN so.invoiceId IS NULL OR so.invoiceId <= 0 '
        'THEN COALESCE(so.agreedPriceFils, so.estimatedPriceFils, 0) ELSE 0 END), 0)';

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c,
             $invoiceSum AS invSum,
             $cardSum AS cardSum
      FROM service_orders so
      $invoiceJoin
      WHERE ${where.toString()}
      ''',
      args,
    );
    final row = rows.first;
    final count = (row['c'] as num?)?.toInt() ?? 0;
    final invSum = (row['invSum'] as num?)?.toDouble() ?? 0;
    final cardSumVal = (row['cardSum'] as num?)?.toInt() ?? 0;
    return _OilRangeStats(
      count: count,
      revenueFils: IqdMoney.toFils(invSum) + cardSumVal,
    );
  }

  static Future<int> _sumInvoiceSalesFils(
    Database db, {
    required int tenantId,
    required String startIso,
    required String endExclusiveIso,
    String? staffName,
  }) async {
    var sql = '''
      SELECT COALESCE(SUM(total), 0) AS s
      FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND IFNULL(isReturned, 0) = 0
        AND date >= ?
        AND date < ?
    ''';
    final args = <Object?>[tenantId, startIso, endExclusiveIso];
    if (staffName != null && staffName.isNotEmpty) {
      sql += ' AND createdByUserName = ?';
      args.add(staffName);
    }
    final rows = await db.rawQuery(sql, args);
    return IqdMoney.toFils((rows.first['s'] as num?)?.toDouble() ?? 0);
  }

  static Future<int> _sumOilInvoicedRevenueFils(
    Database db, {
    required int tenantId,
    required String startIso,
    required String endExclusiveIso,
    String? staffName,
  }) async {
    final hasOrderKind = await _tableHasColumn(db, 'service_orders', 'orderKind');
    final where = StringBuffer(
      "i.tenantId = ? AND i.deleted_at IS NULL AND IFNULL(i.isReturned, 0) = 0 "
      "AND i.date >= ? AND i.date < ? "
      "AND so.id IS NOT NULL",
    );
    final args = <Object?>[tenantId, startIso, endExclusiveIso];
    _appendOilOrderKindFilter(where, args, hasOrderKind: hasOrderKind, alias: 'so');
    if (staffName != null && staffName.isNotEmpty) {
      where.write(' AND i.createdByUserName = ?');
      args.add(staffName);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(i.total), 0) AS s
      FROM invoices i
      INNER JOIN service_orders so
        ON so.invoiceId = i.id AND so.tenantId = i.tenantId
        AND (so.deletedAt IS NULL OR TRIM(COALESCE(so.deletedAt,'')) = '')
      WHERE ${where.toString()}
      ''',
      args,
    );
    return IqdMoney.toFils((rows.first['s'] as num?)?.toDouble() ?? 0);
  }

  static void _appendOilOrderKindFilter(
    StringBuffer where,
    List<Object?> args, {
    required bool hasOrderKind,
    String alias = '',
  }) {
    if (!hasOrderKind) return;
    final p = alias.isEmpty ? '' : '$alias.';
    where.write(
      " AND (${p}orderKind = ? OR ("
      "(${p}orderKind IS NULL OR ${p}orderKind = ?) AND ("
      "(${p}oilType IS NOT NULL AND TRIM(${p}oilType) != '') OR "
      "(${p}odometerCurrent IS NOT NULL AND TRIM(${p}odometerCurrent) != '')"
      ")))",
    );
    args.addAll([ServiceOrderKinds.oilChange, ServiceOrderKinds.repair]);
  }

  static Future<bool> _tableHasColumn(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in rows) {
      if ((r['name'] as String?) == column) return true;
    }
    return false;
  }

  static List<int> _buildSevenDaySeries(
    Map<String, int> byDay,
    DateTime seriesStart,
  ) {
    final out = <int>[];
    for (var i = 0; i < 7; i++) {
      final d = seriesStart.add(Duration(days: i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      out.add(byDay[key] ?? 0);
    }
    return out;
  }

  static Future<List<Map<String, Object?>>> _queryDailyOilRevenue(
    Database db, {
    required int tenantId,
    required String startIso,
    required String endExclusiveIso,
    String? staffName,
  }) async {
    try {
      final hasOrderKind = await _tableHasColumn(db, 'service_orders', 'orderKind');
      final hasInvoice = await _tableHasColumn(db, 'service_orders', 'invoiceId');
      final hasTech = await _tableHasColumn(db, 'service_orders', 'technicianName');

      final where = StringBuffer(
        "so.tenantId = ? AND (so.deletedAt IS NULL OR TRIM(COALESCE(so.deletedAt,'')) = '') "
        "AND so.status NOT IN ('cancelled') "
        "AND so.createdAt >= ? AND so.createdAt < ?",
      );
      final args = <Object?>[tenantId, startIso, endExclusiveIso];
      _appendOilOrderKindFilter(where, args, hasOrderKind: hasOrderKind, alias: 'so');
      if (staffName != null && staffName.isNotEmpty && hasTech) {
        where.write(' AND so.technicianName = ?');
        args.add(staffName);
      }

      final invoiceJoin = hasInvoice
          ? 'LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId '
              'AND i.deleted_at IS NULL AND IFNULL(i.isReturned, 0) = 0'
          : '';
      final invoiceSum = hasInvoice
          ? 'COALESCE(SUM(CASE WHEN so.invoiceId IS NOT NULL AND so.invoiceId > 0 '
              'THEN i.total ELSE 0 END), 0)'
          : '0';
      const cardSum =
          'COALESCE(SUM(CASE WHEN so.invoiceId IS NULL OR so.invoiceId <= 0 '
          'THEN COALESCE(so.agreedPriceFils, so.estimatedPriceFils, 0) ELSE 0 END), 0)';

      final rows = await db.rawQuery(
        '''
        SELECT substr(so.createdAt, 1, 10) AS day,
               $invoiceSum AS invSum,
               $cardSum AS cardSum
        FROM service_orders so
        $invoiceJoin
        WHERE ${where.toString()}
        GROUP BY substr(so.createdAt, 1, 10)
        ORDER BY day ASC
        ''',
        args,
      );
      return rows.map((e) => Map<String, Object?>.from(e)).toList();
    } catch (e, st) {
      AppLogger.error(
        'OwnerOilDashboardRepo',
        'تعذر تحميل إيراد الغيارات اليومي',
        e,
        st,
      );
      return const [];
    }
  }
}

class _OilRangeStats {
  const _OilRangeStats({required this.count, required this.revenueFils});

  final int count;
  final int revenueFils;
}
