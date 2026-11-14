import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/iqd_money.dart';
import '../models/pharmacy_owner_dashboard.dart';
import '../models/pharmacy_report_models.dart';
import 'pharmacy_db_schema.dart';

class _CacheEntry<T> {
  _CacheEntry(this.value, this.at);
  final T value;
  final DateTime at;
}

/// استعلامات تقارير/KPIs الصيدلية — TTL 5 دقائق.
class PharmacyReportsRepository {
  PharmacyReportsRepository({
    DatabaseHelper? db,
  }) : _dbHelper = db ?? DatabaseHelper() {
    _instances.add(this);
  }

  final DatabaseHelper _dbHelper;
  static const _cacheTtl = Duration(minutes: 5);
  static final Set<PharmacyReportsRepository> _instances = {};
  final Map<String, _CacheEntry<Object>> _cache = {};

  static const _pharmacyOwnerDashboardKey = 'pharmacy_owner_dashboard';
  static const _reportsBundleKey = 'pharmacy_reports_bundle';

  static void invalidateCache() {
    for (final repo in _instances) {
      repo._cache.clear();
    }
  }

  Future<Database> get _db async => _dbHelper.database;

  Future<void> ensureSchema() async {
    final db = await _db;
    await ensurePharmacyCatalogTables(db);
  }

  Future<int> resolveTenantId({int? tenantId}) async {
    if (tenantId != null) return tenantId;
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  T? _readCache<T>(String key) {
    final hit = _cache[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return hit.value as T?;
  }

  void _writeCache<T>(String key, T value) {
    _cache[key] = _CacheEntry(value as Object, DateTime.now());
  }

  Future<PharmacyOwnerDashboard> loadOwnerDashboard({
    int? tenantId,
  }) async {
    final tid = await resolveTenantId(tenantId: tenantId);
    final cached = _readCache<PharmacyOwnerDashboard>(
      '${_pharmacyOwnerDashboardKey}_$tid',
    );
    if (cached != null) return cached;

    await ensureSchema();
    final db = await _db;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = monthStart.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, monthStart.month + 1, 1);

    final expiringSoon = await _countExpiringBatches(
      db,
      tenantId: tid,
      withinDays: 30,
    );
    final outOfStock = await _countOutOfStockPharmacyProducts(db, tenantId: tid);
    final topDrugs = await _loadTopDrugs(
      db,
      tenantId: tid,
      start: todayStart.subtract(const Duration(days: 30)),
      endExclusive: todayStart.add(const Duration(days: 1)),
      limit: 3,
    );
    final originGeneric = await _loadOriginGenericQty(
      db,
      tenantId: tid,
      start: monthStart,
      endExclusive: nextMonth,
    );
    final inventoryValue = await _sumInventoryValueFils(db, tenantId: tid);
    final dailyProfit = await _sumProfitFils(
      db,
      tenantId: tid,
      start: todayStart,
      endExclusive: todayStart.add(const Duration(days: 1)),
    );
    final monthlyProfit = await _sumProfitFils(
      db,
      tenantId: tid,
      start: monthStart,
      endExclusive: nextMonth,
    );
    final topCustomers = await _loadTopCustomers(
      db,
      tenantId: tid,
      start: monthStart,
      endExclusive: nextMonth,
      limit: 3,
    );
    final bestSuppliers = await _countBestSupplierMatches(db, tenantId: tid);
    final cogs = await _sumCogsFils(
      db,
      tenantId: tid,
      start: monthStart,
      endExclusive: nextMonth,
    );
    final turnover = inventoryValue <= 0 ? 0.0 : cogs / inventoryValue;
    final avgTicket = await _avgTicketFils(
      db,
      tenantId: tid,
      start: monthStart,
      endExclusive: nextMonth,
    );
    final receivable = await _sumReceivableFils(db, tenantId: tid);
    final payable = await _sumPayableFils(db, tenantId: tid);

    final dashboard = PharmacyOwnerDashboard(
      expiringSoonCount: expiringSoon,
      outOfStockCount: outOfStock,
      topDrugs: topDrugs,
      originatorQty: originGeneric.$1,
      genericQty: originGeneric.$2,
      inventoryValueFils: inventoryValue,
      dailyProfitFils: dailyProfit,
      monthlyProfitFils: monthlyProfit,
      topCustomers: topCustomers,
      bestSupplierMatches: bestSuppliers,
      inventoryTurnover: turnover,
      avgTicketFils: avgTicket,
      totalReceivableFils: receivable,
      totalPayableFils: payable,
      calculatedAt: now,
    );
    _writeCache('${_pharmacyOwnerDashboardKey}_$tid', dashboard);
    return dashboard;
  }

  Future<PharmacyReportsBundle> loadReportsBundle({int? tenantId}) async {
    final tid = await resolveTenantId(tenantId: tenantId);
    final cached = _readCache<PharmacyReportsBundle>(
      '${_reportsBundleKey}_$tid',
    );
    if (cached != null) return cached;

    await ensureSchema();
    final db = await _db;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = monthStart.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, monthStart.month + 1, 1);
    final prevMonthStart = monthStart.month == 1
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, monthStart.month - 1, 1);

    final inventoryValue = await _sumInventoryValueFils(db, tenantId: tid);
    final prevInventory = await _sumInventoryValueFilsAt(
      db,
      tenantId: tid,
      asOf: prevMonthStart,
    );

    final bundle = PharmacyReportsBundle(
      inventory: PharmacyInventoryReportSnapshot(
        expiring30: await _loadExpiringRows(db, tenantId: tid, withinDays: 30),
        expiring60: await _loadExpiringRows(db, tenantId: tid, withinDays: 60),
        expiring90: await _loadExpiringRows(db, tenantId: tid, withinDays: 90),
        outOfStock: await _loadOutOfStockRows(db, tenantId: tid),
        slowMoving30: await _loadSlowMovingRows(
          db,
          tenantId: tid,
          inactiveDays: 30,
        ),
        slowMoving60: await _loadSlowMovingRows(
          db,
          tenantId: tid,
          inactiveDays: 60,
        ),
        slowMoving90: await _loadSlowMovingRows(
          db,
          tenantId: tid,
          inactiveDays: 90,
        ),
        inventoryValueFils: inventoryValue,
        previousMonthValueFils: prevInventory,
      ),
      sales: PharmacySalesReportSnapshot(
        dailySalesFils: await _sumSalesFils(
          db,
          tenantId: tid,
          start: today,
          endExclusive: today.add(const Duration(days: 1)),
        ),
        weeklySalesFils: await _sumSalesFils(
          db,
          tenantId: tid,
          start: today.subtract(const Duration(days: 7)),
          endExclusive: today.add(const Duration(days: 1)),
        ),
        monthlySalesFils: await _sumSalesFils(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        ),
        topByQty: _mapTopDrugsToReportRows(
          await _loadTopDrugs(
            db,
            tenantId: tid,
            start: monthStart,
            endExclusive: nextMonth,
            limit: 10,
          ),
        ),
        topByValue: await _loadTopDrugsByValue(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
          limit: 10,
        ),
        topCustomers: await _loadTopCustomersReport(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
          limit: 10,
        ),
        rxQty: await _sumRxOtcQty(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
          rx: true,
        ),
        otcQty: await _sumRxOtcQty(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
          rx: false,
        ),
        originatorQty: (await _loadOriginGenericQty(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        )).$1,
        genericQty: (await _loadOriginGenericQty(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        )).$2,
        peakHours: await _loadPeakHours(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        ),
      ),
      finance: PharmacyFinanceReportSnapshot(
        topProfitDrugs: await _loadTopProfitDrugs(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
          limit: 10,
        ),
        avgMarginPct: await _avgMarginPct(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        ),
        receivableFils: await _sumReceivableFils(db, tenantId: tid),
        payableFils: await _sumPayableFils(db, tenantId: tid),
        currentMonthProfitFils: await _sumProfitFils(
          db,
          tenantId: tid,
          start: monthStart,
          endExclusive: nextMonth,
        ),
        previousMonthProfitFils: await _sumProfitFils(
          db,
          tenantId: tid,
          start: prevMonthStart,
          endExclusive: monthStart,
        ),
        inventoryCostFils: inventoryValue,
        expectedRetailFils: await _sumExpectedRetailFils(db, tenantId: tid),
      ),
      suppliers: PharmacySupplierReportSnapshot(
        bestPriceMatches: await _loadBestSupplierMatches(db, tenantId: tid),
        lastSupplyRows: await _loadLastSupplyRows(db, tenantId: tid),
        purchaseInvoices: await _loadRecentPurchaseInvoices(db, tenantId: tid),
        supplierBalances: await _loadSupplierBalances(db, tenantId: tid),
      ),
      generatedAt: now,
    );
    _writeCache('${_reportsBundleKey}_$tid', bundle);
    return bundle;
  }

  // ── KPI helpers ───────────────────────────────────────────────────────────

  Future<int> _countExpiringBatches(
    Database db, {
    required int tenantId,
    required int withinDays,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT b.id) AS c
      FROM pharmacy_batches b
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = b.productId AND pp.tenantId = b.tenantId AND pp.deletedAt IS NULL
      WHERE b.tenantId = ?
        AND b.deletedAt IS NULL
        AND b.qty > 0
        AND date(b.expiryDate) <= date('now', 'localtime', '+$withinDays day')
      ''',
      [tenantId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countOutOfStockPharmacyProducts(
    Database db, {
    required int tenantId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT p.id) AS c
      FROM products p
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = p.tenantId AND pp.deletedAt IS NULL
      WHERE p.tenantId = ?
        AND p.isActive = 1
        AND COALESCE((
          SELECT SUM(b.qty) FROM pharmacy_batches b
          WHERE b.productId = p.id AND b.tenantId = p.tenantId AND b.deletedAt IS NULL
        ), 0) <= 0
      ''',
      [tenantId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<List<PharmacyTopDrugRow>> _loadTopDrugs(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT ii.productId AS pid, p.name AS name,
        SUM(ii.quantity) AS qty, SUM(ii.totalFils) AS rev
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN products p ON p.id = ii.productId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND ii.productId IS NOT NULL
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY ii.productId
      ORDER BY qty DESC
      LIMIT ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacyTopDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            qty: (r['qty'] as num?)?.toDouble() ?? 0,
            revenueFils: (r['rev'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PharmacyReportDrugRow>> _loadTopDrugsByValue(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT ii.productId AS pid, p.name AS name, SUM(ii.totalFils) AS rev
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN products p ON p.id = ii.productId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY ii.productId
      ORDER BY rev DESC
      LIMIT ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            valueFils: (r['rev'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<(double, double)> _loadOriginGenericQty(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(m.type, 'generic') AS mtype, SUM(ii.quantity) AS qty
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = ii.productId AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      LEFT JOIN pharmacy_manufacturers m
        ON m.id = pp.manufacturerId AND m.tenantId = pp.tenantId AND m.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY mtype
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    var originator = 0.0;
    var generic = 0.0;
    for (final r in rows) {
      final type = (r['mtype'] ?? 'generic').toString().toLowerCase();
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      if (type == 'originator') {
        originator += qty;
      } else {
        generic += qty;
      }
    }
    return (originator, generic);
  }

  Future<int> _sumInventoryValueFils(
    Database db, {
    required int tenantId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(b.qty * b.costFils), 0) AS v
      FROM pharmacy_batches b
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = b.productId AND pp.tenantId = b.tenantId AND pp.deletedAt IS NULL
      WHERE b.tenantId = ? AND b.deletedAt IS NULL AND b.qty > 0
      ''',
      [tenantId],
    );
    return ((rows.first['v'] as num?)?.toDouble() ?? 0).round();
  }

  Future<int> _sumInventoryValueFilsAt(
    Database db, {
    required int tenantId,
    required DateTime asOf,
  }) async {
    // v1: نفس القيمة الحالية — لا history table بعد.
    return _sumInventoryValueFils(db, tenantId: tenantId);
  }

  Future<int> _sumProfitFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ii.totalFils - (ii.unitCostFils * ii.quantity)), 0) AS p
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = ii.productId AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return (rows.first['p'] as num?)?.toInt() ?? 0;
  }

  Future<int> _sumCogsFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ii.unitCostFils * ii.quantity), 0) AS c
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = ii.productId AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<List<PharmacyTopCustomerRow>> _loadTopCustomers(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(i.customerId, 0) AS cid,
        COALESCE(c.name, i.customerName, 'عميل') AS cname,
        COUNT(*) AS cnt, SUM(i.totalFils) AS total
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customerId
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY cid, cname
      ORDER BY cnt DESC, total DESC
      LIMIT ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacyTopCustomerRow(
            customerId: (r['cid'] as num?)?.toInt() ?? 0,
            customerName: (r['cname'] ?? '').toString(),
            invoiceCount: (r['cnt'] as num?)?.toInt() ?? 0,
            totalFils: (r['total'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<int> _countBestSupplierMatches(
    Database db, {
    required int tenantId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM (
        SELECT b.productId, MIN(b.costFils) AS minCost
        FROM pharmacy_batches b
        WHERE b.tenantId = ? AND b.deletedAt IS NULL AND b.supplierId IS NOT NULL
        GROUP BY b.productId
      )
      ''',
      [tenantId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _avgTicketFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(AVG(i.totalFils), 0) AS avg
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return (rows.first['avg'] as num?)?.toInt() ?? 0;
  }

  Future<int> _sumReceivableFils(
    Database db, {
    required int tenantId,
  }) async {
    final summary = await _dbHelper.summarizeOpenCreditDebtForDashboard(
      tenantId: tenantId,
    );
    return IqdMoney.toFils(summary.totalOpen);
  }

  Future<int> _sumPayableFils(
    Database db, {
    required int tenantId,
  }) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(COALESCE(b.tb, 0) - COALESCE(p.tp, 0)), 0) AS open
        FROM suppliers s
        LEFT JOIN (
          SELECT supplierId, SUM(amount) AS tb FROM supplier_bills
          WHERE tenantId = ? GROUP BY supplierId
        ) b ON b.supplierId = s.id
        LEFT JOIN (
          SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts
          WHERE tenantId = ? GROUP BY supplierId
        ) p ON p.supplierId = s.id
        WHERE s.tenantId = ? AND s.isActive = 1
        ''',
        [tenantId, tenantId, tenantId],
      );
      return IqdMoney.toFils((rows.first['open'] as num?)?.toDouble() ?? 0);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _sumSalesFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(i.totalFils), 0) AS s
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return (rows.first['s'] as num?)?.toInt() ?? 0;
  }

  Future<double> _sumRxOtcQty(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required bool rx,
  }) async {
    final schedule = rx ? "('rx','monitored')" : "('otc')";
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ii.quantity), 0) AS q
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = ii.productId AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND pp.rxSchedule IN $schedule
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return (rows.first['q'] as num?)?.toDouble() ?? 0;
  }

  Future<double> _avgMarginPct(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(ii.totalFils), 0) AS rev,
        COALESCE(SUM(ii.unitCostFils * ii.quantity), 0) AS cost
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = ii.productId AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    final rev = (rows.first['rev'] as num?)?.toInt() ?? 0;
    final cost = (rows.first['cost'] as num?)?.toInt() ?? 0;
    if (rev <= 0) return 0;
    return ((rev - cost) / rev * 100).clamp(0, 100);
  }

  Future<int> _sumExpectedRetailFils(
    Database db, {
    required int tenantId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(b.qty * CAST(p.sellPrice * 1000 AS INTEGER)), 0) AS v
      FROM pharmacy_batches b
      INNER JOIN products p ON p.id = b.productId AND p.tenantId = b.tenantId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = b.productId AND pp.tenantId = b.tenantId AND pp.deletedAt IS NULL
      WHERE b.tenantId = ? AND b.deletedAt IS NULL AND b.qty > 0
      ''',
      [tenantId],
    );
    return ((rows.first['v'] as num?)?.toDouble() ?? 0).round();
  }

  Future<List<PharmacyReportDrugRow>> _loadExpiringRows(
    Database db, {
    required int tenantId,
    required int withinDays,
    int limit = 50,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT b.productId AS pid, p.name AS name, b.batchNo AS batchNo,
        b.expiryDate AS expiry, b.qty AS qty
      FROM pharmacy_batches b
      INNER JOIN products p ON p.id = b.productId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = b.productId AND pp.tenantId = b.tenantId AND pp.deletedAt IS NULL
      WHERE b.tenantId = ? AND b.deletedAt IS NULL AND b.qty > 0
        AND date(b.expiryDate) <= date('now', 'localtime', '+$withinDays day')
      ORDER BY b.expiryDate ASC
      LIMIT ?
      ''',
      [tenantId, limit],
    );
    return _mapDrugRows(rows);
  }

  Future<List<PharmacyReportDrugRow>> _loadOutOfStockRows(
    Database db, {
    required int tenantId,
    int limit = 50,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, p.name AS name
      FROM products p
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = p.tenantId AND pp.deletedAt IS NULL
      WHERE p.tenantId = ? AND p.isActive = 1
        AND COALESCE((
          SELECT SUM(b.qty) FROM pharmacy_batches b
          WHERE b.productId = p.id AND b.tenantId = p.tenantId AND b.deletedAt IS NULL
        ), 0) <= 0
      ORDER BY p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, limit],
    );
    return _mapDrugRows(rows);
  }

  Future<List<PharmacyReportDrugRow>> _loadSlowMovingRows(
    Database db, {
    required int tenantId,
    required int inactiveDays,
    int limit = 50,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, p.name AS name,
        COALESCE((
          SELECT SUM(b.qty) FROM pharmacy_batches b
          WHERE b.productId = p.id AND b.tenantId = p.tenantId AND b.deletedAt IS NULL
        ), 0) AS qty
      FROM products p
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = p.tenantId AND pp.deletedAt IS NULL
      WHERE p.tenantId = ? AND p.isActive = 1
        AND NOT EXISTS (
          SELECT 1 FROM invoice_items ii
          INNER JOIN invoices i ON i.id = ii.invoiceId
          WHERE ii.productId = p.id AND i.tenantId = p.tenantId
            AND i.deleted_at IS NULL AND IFNULL(i.isReturned, 0) = 0
            AND datetime(i.date) >= datetime('now', 'localtime', '-$inactiveDays day')
        )
      ORDER BY p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, limit],
    );
    return _mapDrugRows(rows);
  }

  Future<List<PharmacyReportDrugRow>> _loadTopProfitDrugs(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT ii.productId AS pid, p.name AS name,
        SUM(ii.totalFils - (ii.unitCostFils * ii.quantity)) AS profit
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoiceId
      INNER JOIN products p ON p.id = ii.productId
      INNER JOIN pharmacy_product_profile pp
        ON pp.productId = p.id AND pp.tenantId = i.tenantId AND pp.deletedAt IS NULL
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY ii.productId
      ORDER BY profit DESC
      LIMIT ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            valueFils: (r['profit'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PharmacyReportEntityRow>> _loadTopCustomersReport(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(i.customerId, 0) AS cid,
        COALESCE(c.name, i.customerName, 'عميل') AS cname,
        COUNT(*) AS cnt, SUM(i.totalFils) AS total
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customerId
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY cid, cname
      ORDER BY cnt DESC
      LIMIT ?
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PharmacyReportEntityRow(
            id: (r['cid'] as num?)?.toInt() ?? 0,
            name: (r['cname'] ?? '').toString(),
            metricLabel: '${(r['cnt'] as num?)?.toInt() ?? 0} فاتورة',
            amountFils: (r['total'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<({int hour, int salesFils})>> _loadPeakHours(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT CAST(strftime('%H', i.date) AS INTEGER) AS hr,
        SUM(i.totalFils) AS sales
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND datetime(i.date) >= ?
        AND datetime(i.date) < ?
      GROUP BY hr
      ORDER BY sales DESC
      LIMIT 5
      ''',
      [
        tenantId,
        start.toIso8601String(),
        endExclusive.toIso8601String(),
      ],
    );
    return rows
        .map(
          (r) => (
            hour: (r['hr'] as num?)?.toInt() ?? 0,
            salesFils: (r['sales'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PharmacyReportDrugRow>> _loadBestSupplierMatches(
    Database db, {
    required int tenantId,
    int limit = 30,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, p.name AS name, MIN(b.costFils) AS minCost
      FROM pharmacy_batches b
      INNER JOIN products p ON p.id = b.productId
      WHERE b.tenantId = ? AND b.deletedAt IS NULL AND b.supplierId IS NOT NULL
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE
      LIMIT ?
      ''',
      [tenantId, limit],
    );
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            valueFils: (r['minCost'] as num?)?.toInt() ?? 0,
            extra: 'أقل تكلفة',
          ),
        )
        .toList(growable: false);
  }

  Future<List<PharmacyReportDrugRow>> _loadLastSupplyRows(
    Database db, {
    required int tenantId,
    int limit = 30,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT b.productId AS pid, p.name AS name, b.batchNo AS batchNo,
        b.createdAt AS createdAt, b.costFils AS cost
      FROM pharmacy_batches b
      INNER JOIN products p ON p.id = b.productId
      WHERE b.tenantId = ? AND b.deletedAt IS NULL
      ORDER BY datetime(b.createdAt) DESC
      LIMIT ?
      ''',
      [tenantId, limit],
    );
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            batchNo: r['batchNo']?.toString(),
            valueFils: (r['cost'] as num?)?.toInt() ?? 0,
            extra: r['createdAt']?.toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PharmacyReportEntityRow>> _loadRecentPurchaseInvoices(
    Database db, {
    required int tenantId,
    int limit = 20,
  }) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT sb.id AS id, s.name AS name, sb.amount AS amount, sb.billDate AS dt
        FROM supplier_bills sb
        INNER JOIN suppliers s ON s.id = sb.supplierId AND s.tenantId = sb.tenantId
        WHERE sb.tenantId = ?
        ORDER BY datetime(sb.billDate) DESC
        LIMIT ?
        ''',
        [tenantId, limit],
      );
      return rows
          .map(
            (r) => PharmacyReportEntityRow(
              id: (r['id'] as num?)?.toInt() ?? 0,
              name: (r['name'] ?? '').toString(),
              metricLabel: r['dt']?.toString() ?? '',
              amountFils: IqdMoney.toFils((r['amount'] as num?)?.toDouble() ?? 0),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<PharmacyReportEntityRow>> _loadSupplierBalances(
    Database db, {
    required int tenantId,
    int limit = 30,
  }) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT s.id AS id, s.name AS name,
          COALESCE(b.tb, 0) - COALESCE(p.tp, 0) AS open
        FROM suppliers s
        LEFT JOIN (
          SELECT supplierId, SUM(amount) AS tb FROM supplier_bills
          WHERE tenantId = ? GROUP BY supplierId
        ) b ON b.supplierId = s.id
        LEFT JOIN (
          SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts
          WHERE tenantId = ? GROUP BY supplierId
        ) p ON p.supplierId = s.id
        WHERE s.tenantId = ? AND s.isActive = 1
        ORDER BY open DESC
        LIMIT ?
        ''',
        [tenantId, tenantId, tenantId, limit],
      );
      return rows
          .map(
            (r) => PharmacyReportEntityRow(
              id: (r['id'] as num?)?.toInt() ?? 0,
              name: (r['name'] ?? '').toString(),
              metricLabel: 'رصيد مستحق',
              amountFils: IqdMoney.toFils((r['open'] as num?)?.toDouble() ?? 0),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<PharmacyReportDrugRow> _mapTopDrugsToReportRows(
    List<PharmacyTopDrugRow> rows,
  ) {
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: r.productId,
            productName: r.productName,
            qty: r.qty,
            valueFils: r.revenueFils,
          ),
        )
        .toList(growable: false);
  }

  List<PharmacyReportDrugRow> _mapDrugRows(List<Map<String, Object?>> rows) {
    return rows
        .map(
          (r) => PharmacyReportDrugRow(
            productId: (r['pid'] as num?)?.toInt() ?? 0,
            productName: (r['name'] ?? '').toString(),
            batchNo: r['batchNo']?.toString(),
            expiryDate: _parseDate(r['expiry']),
            qty: (r['qty'] as num?)?.toDouble() ?? 0,
            valueFils: (r['valueFils'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }
}
