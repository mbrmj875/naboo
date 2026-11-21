import 'package:sqflite/sqflite.dart';

import '../services/database_helper.dart';
import '../utils/app_logger.dart';
import '../utils/iqd_money.dart';
import 'models/owner_date_range.dart';
import 'models/owner_kpi_trend.dart';
import '../verticals/oil_change/owner/owner_oil_dashboard_repository.dart';

/// اتجاهات المبيعات — sparkline 7 أيام + مقارنات WoW.
class OwnerTrendRepository {
  OwnerTrendRepository({
    DatabaseHelper? db,
    OwnerOilDashboardRepository? oilDashboard,
  })  : _db = db ?? DatabaseHelper(),
        _oil = oilDashboard ?? OwnerOilDashboardRepository(db: db);

  final DatabaseHelper _db;
  final OwnerOilDashboardRepository _oil;

  /// مجموع مبيعات كل يوم (آخر 7 أيام، الأقدم أولاً) بالفلس.
  Future<List<int>> loadSalesSparklineFils({
    required int tenantId,
    String? staffName,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final seriesStart = todayStart.subtract(const Duration(days: 6));
    final endExclusive = todayStart.add(const Duration(days: 1));

    final rows = await _queryDailySales(
      db,
      tenantId: tenantId,
      start: seriesStart,
      endExclusive: endExclusive,
      staffName: staffName,
    );

    final byDay = <String, int>{};
    for (final row in rows) {
      final day = (row['day'] as String?) ?? '';
      byDay[day] = IqdMoney.toFils((row['total'] as num?)?.toDouble() ?? 0);
    }

    return buildSevenDaySeries(byDay, seriesStart);
  }

  /// مقارنة عدد غيارات الزيت — الفترة الحالية vs قبل 7 أيام.
  Future<OwnerKpiTrend?> compareOilChangesWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    try {
      final refRange = OwnerKpiTrend.referenceRangeWoW(range);
      final current = await _oil.loadOilChangesInRange(
        tenantId: tenantId,
        range: range,
        staffName: staffName,
      );
      final reference = await _oil.loadOilChangesInRange(
        tenantId: tenantId,
        range: refRange,
        staffName: staffName,
      );
      return OwnerKpiTrend.compute(
        current: current.changeCount,
        reference: reference.changeCount,
        range: range,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerTrendRepository',
        'تعذر حساب اتجاه تغييرات الزيت WoW',
        e,
        st,
      );
      return null;
    }
  }

  /// مقارنة مبيعات POS — WoW (supermarket v3.1).
  Future<OwnerKpiTrend?> compareRetailSalesWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    try {
      final refRange = OwnerKpiTrend.referenceRangeWoW(range);
      final db = await _db.database;
      final current = await _sumSalesFils(
        db,
        tenantId: tenantId,
        start: range.startLocal,
        endExclusive: range.endExclusiveLocal,
        staffName: staffName,
      );
      final reference = await _sumSalesFils(
        db,
        tenantId: tenantId,
        start: refRange.startLocal,
        endExclusive: refRange.endExclusiveLocal,
        staffName: staffName,
      );
      return OwnerKpiTrend.compute(
        current: current,
        reference: reference,
        range: range,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerTrendRepository',
        'تعذر حساب اتجاه مبيعات POS WoW',
        e,
        st,
      );
      return null;
    }
  }

  /// مقارنة متوسط قيمة الغيار — WoW.
  Future<OwnerKpiTrend?> compareOilAvgTicketWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    try {
      final refRange = OwnerKpiTrend.referenceRangeWoW(range);
      final current = await _oil.loadAvgTicket(
        tenantId: tenantId,
        range: range,
        staffName: staffName,
      );
      final reference = await _oil.loadAvgTicket(
        tenantId: tenantId,
        range: refRange,
        staffName: staffName,
      );
      if (current.changeCount <= 0 && reference.changeCount <= 0) return null;
      return OwnerKpiTrend.compute(
        current: current.avgTicketFils,
        reference: reference.avgTicketFils,
        range: range,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerTrendRepository',
        'تعذر حساب اتجاه متوسط الغيار WoW',
        e,
        st,
      );
      return null;
    }
  }

  /// يبني 7 نقاط (الأقدم أولاً) — قابل للاختبار بدون DB.
  static List<int> buildSevenDaySeries(
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

  static Future<List<Map<String, Object?>>> _queryDailySales(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    String? staffName,
  }) async {
    try {
      var sql = '''
        SELECT substr(date, 1, 10) AS day, COALESCE(SUM(total), 0) AS total
        FROM invoices
        WHERE tenantId = ?
          AND deleted_at IS NULL
          AND IFNULL(isReturned, 0) = 0
          AND date >= ?
          AND date < ?
      ''';
      final args = <Object?>[
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ];
      if (staffName != null && staffName.isNotEmpty) {
        sql += ' AND createdByUserName = ?';
        args.add(staffName);
      }
      sql += ' GROUP BY substr(date, 1, 10) ORDER BY day ASC';
      final rows = await db.rawQuery(sql, args);
      return rows.map((e) => Map<String, Object?>.from(e)).toList();
    } catch (e, st) {
      AppLogger.error(
        'OwnerTrendRepository',
        'تعذر تحميل السلسلة اليومية للمبيعات',
        e,
        st,
      );
      return const [];
    }
  }

  static Future<int> _sumSalesFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    String? staffName,
  }) async {
    try {
      var sql = '''
        SELECT COALESCE(SUM(total), 0) AS s
        FROM invoices
        WHERE tenantId = ?
          AND deleted_at IS NULL
          AND IFNULL(isReturned, 0) = 0
          AND date >= ?
          AND date < ?
      ''';
      final args = <Object?>[
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ];
      if (staffName != null && staffName.isNotEmpty) {
        sql += ' AND createdByUserName = ?';
        args.add(staffName);
      }
      final rows = await db.rawQuery(sql, args);
      final total = (rows.first['s'] as num?)?.toDouble() ?? 0.0;
      return IqdMoney.toFils(total);
    } catch (e, st) {
      AppLogger.error(
        'OwnerTrendRepository',
        'تعذر حساب مجموع مبيعات الفترة للفلس',
        e,
        st,
      );
      return 0;
    }
  }
}
