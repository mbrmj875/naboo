import 'package:sqflite/sqflite.dart';

import '../services/database_helper.dart';
import '../services/service_order_kinds.dart';
import '../utils/app_logger.dart';
import '../utils/iqd_money.dart';
import '../utils/stock_quantity_kind.dart';

/// لقطة KPI للوحة الرئيسية (غيار زيت).
class HomeKpiSnapshot {
  const HomeKpiSnapshot({
    required this.activeCarsInGarage,
    required this.stockShortages,
    required this.todayShiftSalesFils,
    required this.todayShiftCashInFils,
    required this.hasOpenShift,
  });

  final int activeCarsInGarage;
  final int stockShortages;
  final int todayShiftSalesFils;
  /// المقبوض نقداً في الوردية الحالية (من cash_ledger).
  final int todayShiftCashInFils;
  final bool hasOpenShift;

  static const empty = HomeKpiSnapshot(
    activeCarsInGarage: 0,
    stockShortages: 0,
    todayShiftSalesFils: 0,
    todayShiftCashInFils: 0,
    hasOpenShift: false,
  );
}

/// جلب KPIs مجمّع مع cache قصير (45 ثانية).
class HomeKpiRepository {
  HomeKpiRepository._();
  static final HomeKpiRepository instance = HomeKpiRepository._();

  final DatabaseHelper _db = DatabaseHelper();
  HomeKpiSnapshot _cache = HomeKpiSnapshot.empty;
  DateTime? _cachedAt;

  HomeKpiSnapshot get cached => _cache;

  Future<HomeKpiSnapshot> load({
    int? openShiftId,
    bool force = false,
    bool includeAllProductShortages = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(seconds: 45)) {
      return _cache;
    }

    final db = await _db.database;
    final tid = await _db.resolveLocalBusinessTenantId();

    final activeCars = await _countActiveOilGarage(db, tid);
    final shortages = await _countStockShortages(
      tid,
      includeAllProducts: includeAllProductShortages,
    );
    final salesFils = openShiftId != null && openShiftId > 0
        ? await _sumShiftSalesFils(db, tid, openShiftId)
        : 0;
    final cashInFils = openShiftId != null && openShiftId > 0
        ? await _sumShiftCashInFils(db, tid, openShiftId)
        : 0;

    _cache = HomeKpiSnapshot(
      activeCarsInGarage: activeCars,
      stockShortages: shortages,
      todayShiftSalesFils: salesFils,
      todayShiftCashInFils: cashInFils,
      hasOpenShift: openShiftId != null && openShiftId > 0,
    );
    _cachedAt = now;
    return _cache;
  }

  Future<int> loadTodaySalesForTenantFils({required int tenantId, String? staffName}) async {
    final db = await _db.database;
    return _sumTodaySalesFils(db, tenantId, staffName);
  }

  void invalidate() {
    _cachedAt = null;
  }

  static Future<int> _countActiveOilGarage(Database db, int tenantId) async {
    try {
      final hasOrderKind = await _tableHasColumn(
        db,
        'service_orders',
        'orderKind',
      );
      final where = StringBuffer(
        "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt,'')) = '') "
        "AND status IN ('pending', 'in_progress')",
      );
      final args = <Object?>[tenantId];
      if (hasOrderKind) {
        where.write(
          " AND (orderKind = ? OR ("
          "(orderKind IS NULL OR orderKind = ?) AND ("
          "(oilType IS NOT NULL AND TRIM(oilType) != '') OR "
          "(odometerCurrent IS NOT NULL AND TRIM(odometerCurrent) != '')"
          ")))",
        );
        args.addAll([ServiceOrderKinds.oilChange, ServiceOrderKinds.repair]);
      }
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM service_orders WHERE ${where.toString()}',
        args,
      );
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    } catch (e, st) {
      AppLogger.error(
        'HomeKpiRepository',
        'تعذر حساب السيارات النشطة في الورشة',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<int> _countStockShortages(
    int tenantId, {
    required bool includeAllProducts,
  }) async {
    try {
      final low = await DatabaseHelper().getProductsForLowStockNotifications(
        tenantId: tenantId,
        limit: 500,
      );
      if (includeAllProducts) return low.length;
      var n = 0;
      for (final p in low) {
        final kind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
        if (kind == StockBaseKind.volumeLiter) n++;
      }
      return n;
    } catch (e, st) {
      AppLogger.error(
        'HomeKpiRepository',
        'تعذر حساب نواقص المخزون للرئيسية',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<int> _sumShiftSalesFils(
    Database db,
    int tenantId,
    int shiftId,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(total), 0) AS s
        FROM invoices
        WHERE tenantId = ?
          AND deleted_at IS NULL
          AND workShiftId = ?
          AND IFNULL(isReturned, 0) = 0
        ''',
        [tenantId, shiftId],
      );
      final total = (rows.first['s'] as num?)?.toDouble() ?? 0.0;
      return IqdMoney.toFils(total);
    } catch (e, st) {
      AppLogger.error(
        'HomeKpiRepository',
        'تعذر حساب مبيعات الوردية',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<int> _sumShiftCashInFils(
    Database db,
    int tenantId,
    int shiftId,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(
          CASE
            WHEN cl.amountFils > 0 THEN cl.amountFils
            WHEN cl.amount > 0 THEN ROUND(cl.amount * 1000)
            ELSE 0
          END
        ), 0) AS s
        FROM cash_ledger cl
        WHERE cl.tenantId = ?
          AND cl.deleted_at IS NULL
          AND (
            cl.workShiftId = ?
            OR (
              cl.invoiceId IS NOT NULL
              AND cl.invoiceId > 0
              AND EXISTS (
                SELECT 1 FROM invoices i
                WHERE i.id = cl.invoiceId
                  AND i.tenantId = ?
                  AND i.deleted_at IS NULL
                  AND i.workShiftId = ?
              )
            )
          )
        ''',
        [tenantId, shiftId, tenantId, shiftId],
      );
      return (rows.first['s'] as num?)?.toInt() ?? 0;
    } catch (e, st) {
      AppLogger.error(
        'HomeKpiRepository',
        'تعذر حساب المقبوض النقدي للوردية',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<int> _sumTodaySalesFils(Database db, int tenantId, String? staffName) async {
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final nextDay = dayStart.add(const Duration(days: 1));
      
      String sql = '''
        SELECT COALESCE(SUM(total), 0) AS s
        FROM invoices
        WHERE tenantId = ?
          AND deleted_at IS NULL
          AND IFNULL(isReturned, 0) = 0
          AND date >= ?
          AND date < ?
        ''';
      List<Object?> args = [tenantId, dayStart.toIso8601String(), nextDay.toIso8601String()];

      if (staffName != null && staffName.isNotEmpty) {
        sql += ' AND createdByUserName = ?';
        args.add(staffName);
      }

      final rows = await db.rawQuery(sql, args);
      final total = (rows.first['s'] as num?)?.toDouble() ?? 0.0;
      return IqdMoney.toFils(total);
    } catch (e, st) {
      AppLogger.error(
        'HomeKpiRepository',
        'تعذر حساب مبيعات اليوم',
        e,
        st,
      );
      return 0;
    }
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
}
