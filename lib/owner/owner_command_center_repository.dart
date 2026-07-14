import 'package:sqflite/sqflite.dart';

import '../services/database_helper.dart';
import '../services/tenant_context_service.dart';
import '../utils/app_logger.dart';
import '../utils/iqd_money.dart';
import '../utils/stock_quantity_kind.dart';
import 'owner_finance_repository.dart';
import 'owner_inventory_repository.dart';
import '../verticals/oil_change/owner/owner_oil_dashboard_repository.dart';
import 'owner_supermarket_dashboard_repository.dart';
import 'owner_clothing_dashboard_repository.dart';
import 'owner_trend_repository.dart';
import 'models/owner_date_range.dart';
import 'models/owner_kpi_models.dart';
import 'models/owner_kpi_trend.dart';

/// قراءة SQLite لأقسام لوحة المالك — بدون UI state.
class OwnerCommandCenterRepository {
  OwnerCommandCenterRepository({
    DatabaseHelper? db,
    OwnerTrendRepository? trends,
    OwnerFinanceRepository? finance,
    OwnerInventoryRepository? inventory,
    OwnerOilDashboardRepository? oilDashboard,
    OwnerSupermarketDashboardRepository? supermarketDashboard,
    OwnerClothingDashboardRepository? clothingDashboard,
  })  : _db = db ?? DatabaseHelper(),
        _trends = trends ?? OwnerTrendRepository(),
        _finance = finance ?? OwnerFinanceRepository(),
        _inventory = inventory ?? OwnerInventoryRepository(),
        _oil = oilDashboard ?? OwnerOilDashboardRepository(db: db),
        _supermarket = supermarketDashboard ??
            OwnerSupermarketDashboardRepository(db: db),
        _clothing = clothingDashboard ??
            OwnerClothingDashboardRepository(db: db);

  final DatabaseHelper _db;
  final OwnerTrendRepository _trends;
  final OwnerFinanceRepository _finance;
  final OwnerInventoryRepository _inventory;
  final OwnerOilDashboardRepository _oil;
  final OwnerSupermarketDashboardRepository _supermarket;
  final OwnerClothingDashboardRepository _clothing;

  Future<StaffUsersData> loadStaffUsers() async {
    final db = await _db.database;
    final rows = await db.query(
      'users',
      columns: const ['id', 'displayName', 'username'],
      where:
          "LOWER(TRIM(COALESCE(role, ''))) NOT IN ('owner', 'admin') AND isActive = 1",
      orderBy: 'displayName COLLATE NOCASE ASC, username COLLATE NOCASE ASC',
    );
    final users = <StaffUserRow>[];
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      final displayName = (row['displayName'] as String?)?.trim() ?? '';
      final username = (row['username'] as String?)?.trim() ?? '';
      if (displayName.isEmpty && username.isEmpty) continue;
      users.add(
        StaffUserRow(
          id: id,
          displayName: displayName,
          username: username,
        ),
      );
    }
    return StaffUsersData(users: users);
  }

  Future<SalesKpi> loadSales({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    final db = await _db.database;
    final fils = await _sumSalesFils(
      db,
      tenantId: tenantId,
      start: range.startLocal,
      endExclusive: range.endExclusiveLocal,
      staffName: staffName,
    );
    return SalesKpi(salesFils: fils, range: range);
  }

  Future<OpenShiftsKpi> loadOpenShifts({required int tenantId}) async {
    final db = await _db.database;
    // إصلاح ورديات قديمة أُدخلت بـ tenantId = userId (local-2 → 2) بدل المستأجر الفعلي.
    await db.rawUpdate(
      '''
      UPDATE work_shifts
      SET tenantId = ?
      WHERE (closedAt IS NULL OR TRIM(IFNULL(closedAt, '')) = '')
        AND deleted_at IS NULL
        AND tenantId != ?
        AND NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = work_shifts.tenantId)
      ''',
      [tenantId, tenantId],
    );
    await _db.repairDuplicateOpenShifts();
    // الاستبعاد بالاسم/المعرّف — مع دمج الاسم من جدول users لتجنب «1ali» من مزامنة قديمة.
    final rows = await db.rawQuery(
      '''
      SELECT ws.id, ws.shiftStaffUserId, ws.openedAt,
        CASE
          WHEN TRIM(COALESCE(u.displayName, '')) != '' THEN TRIM(u.displayName)
          WHEN TRIM(COALESCE(u.username, '')) != '' THEN TRIM(u.username)
          ELSE TRIM(ws.shiftStaffName)
        END AS staffName
      FROM work_shifts ws
      LEFT JOIN users u ON u.id = ws.shiftStaffUserId
      WHERE (ws.closedAt IS NULL OR TRIM(IFNULL(ws.closedAt, '')) = '')
        AND ws.deleted_at IS NULL
        AND (
          ws.tenantId = ?
          OR NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = ws.tenantId)
        )
        AND NOT EXISTS (
          SELECT 1 FROM users ou
          WHERE LOWER(TRIM(COALESCE(ou.role, ''))) IN ('owner', 'admin')
            AND (
              LOWER(TRIM(ws.shiftStaffName)) = LOWER(TRIM(COALESCE(ou.displayName, '')))
              OR LOWER(TRIM(ws.shiftStaffName)) = LOWER(TRIM(COALESCE(ou.username, '')))
              OR (ws.shiftStaffUserId IS NOT NULL AND ws.shiftStaffUserId = ou.id)
            )
        )
      ORDER BY datetime(ws.openedAt) DESC, ws.id DESC
      ''',
      [tenantId],
    );
    final deduped = <String, OpenShiftRow>{};
    final seenNormNames = <String>{};
    for (final row in rows) {
      final staffId = (row['shiftStaffUserId'] as num?)?.toInt() ?? 0;
      final name = (row['staffName'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final norm = _normalizeStaffPresenceKey(name);
      if (norm.isNotEmpty && seenNormNames.contains(norm)) continue;
      final key = staffId > 0 ? 'id:$staffId' : 'name:$norm';
      if (deduped.containsKey(key)) continue;
      if (norm.isNotEmpty) seenNormNames.add(norm);
      deduped[key] = OpenShiftRow(
        id: (row['id'] as num?)?.toInt() ?? 0,
        staffName: name,
        openedAt: (row['openedAt'] as String?)?.trim() ?? '',
      );
    }
    final items = deduped.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return OpenShiftsKpi(items: items);
  }

  Future<DebtSummary> loadDebtSummary({
    required int tenantId,
    String? staffName,
  }) async {
    final summary = await _db.summarizeOpenCreditDebtForDashboard(
      tenantId: tenantId,
      staffName: staffName,
    );
    return DebtSummary(
      totalReceivableFils: IqdMoney.toFils(summary.totalOpen),
      indebtedCustomerCount: summary.debtorCount,
    );
  }

  Future<InstallmentAlert> loadInstallmentAlert({required int tenantId}) async {
    final db = await _db.database;
    final hasTable = await _tableExists(db, 'installments');
    if (!hasTable) {
      return const InstallmentAlert(overdueCount: 0, dueTodayCount: 0);
    }
    try {
      final overdueRows = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c
        FROM installments i
        INNER JOIN installment_plans p ON p.id = i.planId
        LEFT JOIN invoices inv ON inv.id = p.invoiceId
        LEFT JOIN customers c ON c.id = p.customerId
        WHERE i.paid = 0
          AND IFNULL(inv.tenantId, c.tenantId) = ?
          AND substr(trim(i.dueDate), 1, 10) < date('now', 'localtime')
        ''',
        [tenantId],
      );
      final dueTodayRows = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c
        FROM installments i
        INNER JOIN installment_plans p ON p.id = i.planId
        LEFT JOIN invoices inv ON inv.id = p.invoiceId
        LEFT JOIN customers c ON c.id = p.customerId
        WHERE i.paid = 0
          AND IFNULL(inv.tenantId, c.tenantId) = ?
          AND substr(trim(i.dueDate), 1, 10) = date('now', 'localtime')
        ''',
        [tenantId],
      );
      return InstallmentAlert(
        overdueCount: (overdueRows.first['c'] as num?)?.toInt() ?? 0,
        dueTodayCount: (dueTodayRows.first['c'] as num?)?.toInt() ?? 0,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterRepo',
        'تعذر تحميل تنبيه الأقساط',
        e,
        st,
      );
      return const InstallmentAlert(overdueCount: 0, dueTodayCount: 0);
    }
  }

  Future<InventoryAlert> loadInventoryShortages({required int tenantId}) async {
    try {
      final count = await _db.countProductsForLowStockNotifications(
        tenantId: tenantId,
        stockBaseKind: StockBaseKind.volumeLiter,
      );
      return InventoryAlert(shortageCount: count);
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterRepo',
        'تعذر تحميل تنبيهات نواقص المخزون',
        e,
        st,
      );
      return const InventoryAlert(shortageCount: 0);
    }
  }

  Future<List<int>> loadSalesSparkline({
    required int tenantId,
    String? staffName,
  }) {
    return _trends.loadSalesSparklineFils(
      tenantId: tenantId,
      staffName: staffName,
    );
  }

  Future<List<int>> loadOilDailyRevenueSparkline({
    required int tenantId,
    String? staffName,
  }) {
    return _oil.loadDailyRevenueSparklineFils(
      tenantId: tenantId,
      staffName: staffName,
    );
  }

  Future<CashSummary> loadCashSummary({
    required int tenantId,
    String? staffName,
  }) {
    return _finance.loadCashSummary(tenantId: tenantId, staffName: staffName);
  }

  Future<InventoryValueKpi> loadInventoryValue({required int tenantId}) {
    return _inventory.loadInventoryValue(tenantId: tenantId);
  }

  Future<OilActiveCarsKpi> loadOilActiveCars({
    required int tenantId,
    int garageStaleHours = OwnerOilDashboardRepository.garageStaleHoursThreshold,
  }) {
    return _oil.loadActiveCars(
      tenantId: tenantId,
      garageStaleHours: garageStaleHours,
    );
  }

  Future<OilChangesKpi> loadOilChangesCount({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _oil.loadOilChangesInRange(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<OilAvgTicketKpi> loadOilAvgTicket({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _oil.loadAvgTicket(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<InventoryAlert> loadOilStockShortages({required int tenantId}) {
    return _oil.loadOilFluidShortages(tenantId: tenantId);
  }

  Future<HybridRevenueKpi> loadHybridRevenueSplit({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _oil.loadHybridRevenueSplit(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<InventoryAlert> loadRetailStockShortages({required int tenantId}) {
    return _supermarket.loadRetailStockShortages(tenantId: tenantId);
  }

  Future<RetailTopSellersKpi> loadRetailTopSellers({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _supermarket.loadTopSellers(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<List<ShortageProductRow>> loadRetailShortageProducts({
    required int tenantId,
    int limit = 100,
  }) {
    return _supermarket.loadRetailShortageProducts(
      tenantId: tenantId,
      limit: limit,
    );
  }

  Future<ClothingVariantShortagesKpi> loadClothingVariantShortages({
    required int tenantId,
  }) {
    return _clothing.loadVariantShortages(tenantId: tenantId);
  }

  Future<ClothingSlowMoversKpi> loadClothingSlowMovers({
    required int tenantId,
    int daysThreshold = OwnerClothingDashboardRepository.slowMoversDaysThreshold,
  }) {
    return _clothing.loadSlowMovers(
      tenantId: tenantId,
      daysThreshold: daysThreshold,
    );
  }

  Future<List<ClothingVariantShortageRow>> loadClothingVariantShortageRows({
    required int tenantId,
    int limit = 100,
  }) {
    return _clothing.loadVariantShortageRows(tenantId: tenantId, limit: limit);
  }

  Future<OwnerKpiTrend?> loadRetailSalesTrendWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _trends.compareRetailSalesWoW(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<OwnerKpiTrend?> loadOilChangesTrendWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _trends.compareOilChangesWoW(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<OwnerKpiTrend?> loadOilAvgTicketTrendWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) {
    return _trends.compareOilAvgTicketWoW(
      tenantId: tenantId,
      range: range,
      staffName: staffName,
    );
  }

  Future<List<ShortageProductRow>> loadShortageProducts({
    required int tenantId,
    int limit = 100,
  }) async {
    try {
      final low = await _db.getProductsForLowStockNotifications(
        tenantId: tenantId,
        limit: limit,
      );
      final out = <ShortageProductRow>[];
      for (final p in low) {
        final kind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
        if (kind != StockBaseKind.volumeLiter) continue;
        out.add(
          ShortageProductRow(
            id: (p['id'] as num?)?.toInt() ?? 0,
            name: (p['name'] as String?)?.trim() ?? '',
            qty: (p['qty'] as num?)?.toDouble() ?? 0,
            lowStockThreshold:
                (p['lowStockThreshold'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
      return out;
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterRepo',
        'تعذر تحميل قائمة النواقص',
        e,
        st,
      );
      return const [];
    }
  }

  Future<List<DebtorRow>> loadTopDebtors({
    required int tenantId,
    int limit = 10,
  }) async {
    final db = await _db.database;
    try {
      final rows = await db.rawQuery(
        '''
        SELECT id, name, phone, balance
        FROM customers
        WHERE tenantId = ? AND balance > 0.01
        ORDER BY balance DESC, name COLLATE NOCASE ASC
        LIMIT ?
        ''',
        [tenantId, limit],
      );
      return rows.map((row) {
        final balance = (row['balance'] as num?)?.toDouble() ?? 0;
        return DebtorRow(
          id: (row['id'] as num?)?.toInt() ?? 0,
          name: (row['name'] as String?)?.trim() ?? '',
          phone: (row['phone'] as String?)?.trim(),
          balanceFils: IqdMoney.toFils(balance),
        );
      }).toList();
    } catch (e, st) {
      AppLogger.error(
        'OwnerCommandCenterRepo',
        'تعذر تحميل أعلى العملاء مديونية',
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
        'OwnerCommandCenterRepo',
        'تعذر حساب مبيعات الفترة',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  /// للاختبارات — يتحقق من tenant context.
  Future<int> requireTenantId() async {
    final tenant = TenantContextService.instance;
    if (!tenant.loaded) await tenant.load();
    return tenant.activeTenantId;
  }
}

/// يُزيل أرقاماً بادئة من أسماء مزامنة خاطئة (مثل «1ali» → «ali»).
String _normalizeStaffPresenceKey(String name) {
  final s = name.trim().toLowerCase();
  if (s.isEmpty) return s;
  return s.replaceFirst(RegExp(r'^\d+'), '');
}
