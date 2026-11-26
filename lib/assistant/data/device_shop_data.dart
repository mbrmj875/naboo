import 'package:sqflite/sqflite.dart';

import '../../models/product_variant_kind.dart';
import '../../services/product_repository.dart';
import '../../services/customer_search_index.dart';
import '../../services/database_helper.dart';
import '../../services/license_service.dart';
import '../../services/service_order_kinds.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/iqd_money.dart';
import '../../utils/stock_quantity_kind.dart';
import '../../verticals/oil_change/reports/car_wash/car_wash_report_repository.dart';
import '../../verticals/oil_change/reports/direct_sale/direct_sale_report_repository.dart';
import '../../verticals/oil_change/reports/kit/oil_shop_report_sql.dart';
import '../../verticals/oil_change/reports/kit/report_math.dart';
import '../../verticals/oil_change/reports/products/products_report_repository.dart';
import '../../verticals/oil_change/services/oil_change_ratings_repository.dart';
import '../../verticals/oil_change/services/oil_change_reports_repository.dart';
import '../../verticals/oil_change/services/oil_change_whatsapp_messages_repository.dart';
import '../../verticals/oil_change/services/oil_change_whatsapp_status_store.dart';
import '../../verticals/oil_change/services/wa_message_wallet_service.dart';
import '../../verticals/oil_change/services/wa_oil_followup_service.dart';
import '../../verticals/oil_change/models/wa_oil_followup_rule.dart';
import '../../verticals/oil_change/utils/oil_change_lookup_normalize.dart';
import 'assistant_period.dart';
import 'assistant_shop_data.dart';

/// بيانات المحل من قاعدة الجهاز، بمستودعات الشاشات نفسها (4.3).
class DeviceShopData implements AssistantShopData {
  DeviceShopData({DatabaseHelper? db, this.license}) : _helper = db ?? DatabaseHelper();

  /// حالة الترخيص من مزوّدها (تُقرأ عند الطلب).
  final LicenseState? Function()? license;

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  Future<int> _tenant() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  static int _fils(Object? iqd) => iqd is num ? (iqd * 1000).round() : 0;

  static String _unit(Object? kind) => switch ((kind as num?)?.toInt()) {
    StockBaseKind.volumeLiter => 'لتر',
    StockBaseKind.weightKg => 'كغم',
    _ => 'قطعة',
  };

  static final _hydraulicName = RegExp('هيدرو|هايدرو|hydraul|atf|دبل', caseSensitive: false);
  static final _filterName = RegExp('فلتر|فلاتر|filter', caseSensitive: false);

  /// زيت أُدخل كصنف عادي (بلا نوع «لتر» ولا درجة لزوجة): اسمه يبدأ بـ«زيت» أو فيه لزوجة مثل 5W-30.
  static final _oilName = RegExp(r'^\s*(زيت|دهن)(\s|$)|(^|[^0-9a-z])\d{1,2}\s*w\s*-?\s*\d{2}($|[^0-9])', caseSensitive: false);

  /// oil | hydraulic | filter | general: من عائلة الصنف أولاً ثم اسمه.
  static String kindOf({required String name, Object? stockBaseKind, Object? familyKind}) {
    final family = (familyKind as num?)?.toInt();
    if (family == ProductVariantKind.hydraulicFamily) return 'hydraulic';
    if (family == ProductVariantKind.oilFamily) return 'oil';
    if (_filterName.hasMatch(name)) return 'filter';
    if ((stockBaseKind as num?)?.toInt() == StockBaseKind.volumeLiter || _oilName.hasMatch(name)) {
      return _hydraulicName.hasMatch(name) ? 'hydraulic' : 'oil';
    }
    return 'general';
  }

  @override
  Future<List<Map<String, Object?>>> stockItems() async {
    final tid = await _tenant();
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT p.id, p.name, p.qty, p.sellPrice, p.buyPrice, p.lowStockThreshold, p.barcode,
             IFNULL(p.stockBaseKind, 0) AS stockBaseKind, b.name AS brand,
             g.viscosity AS viscosity, pp.variantKind AS familyKind
      FROM products p
      LEFT JOIN brands b ON b.id = p.brandId
      LEFT JOIN product_oil_grades g
        ON g.linkedProductId = p.id AND g.deleted_at IS NULL AND g.tenantId = p.tenantId
      LEFT JOIN products pp ON pp.id = g.parentProductId
      WHERE p.tenantId = ? AND p.isActive = 1
        AND ${ProductVariantKind.sqlNotFluidFamilyParentOf('p.variantKind')}
        AND IFNULL(p.isService, 0) = 0
      ORDER BY p.name COLLATE NOCASE
      LIMIT 3000
      ''',
      [tid],
    );
    return [for (final r in rows) _item(r)];
  }

  Map<String, Object?> _item(Map<String, Object?> r) {
    final name = '${r['name'] ?? ''}'.trim();
    return {
      'id': r['id'],
      'name': name,
      'brand': ?r['brand'],
      'viscosity': ?r['viscosity'],
      'kind': kindOf(name: name, stockBaseKind: r['stockBaseKind'], familyKind: r['familyKind']),
      'qty': r['qty'] ?? 0,
      'unit': _unit(r['stockBaseKind']),
      'sell_price_fils': _fils(r['sellPrice']),
      'buy_price_fils': _fils(r['buyPrice']),
      'threshold': r['lowStockThreshold'] ?? 0,
      'barcode': ?r['barcode'],
    };
  }

  @override
  Future<List<Map<String, Object?>>> lowStock() async {
    final tid = await _tenant();
    final rows = await _helper.getProductsForLowStockNotifications(tenantId: tid);
    return [
      for (final r in rows)
        {
          'id': r['id'],
          'name': '${r['name'] ?? ''}'.trim(),
          'qty': r['qty'] ?? 0,
          'unit': _unit(r['stockBaseKind']),
          'threshold': r['lowStockThreshold'] ?? 0,
          'kind': kindOf(name: '${r['name'] ?? ''}', stockBaseKind: r['stockBaseKind']),
          'alert': ((r['qty'] as num?) ?? 0) <= 0 ? 'out' : 'low',
        },
    ];
  }

  @override
  Future<int?> productIdByBarcode(String code) => ProductRepository().findConflictingProductIdForBarcode(code);

  @override
  Future<Map<String, Object?>?> productDetail(int id) async {
    final items = (await stockItems()).where((x) => x['id'] == id).toList();
    if (items.isEmpty) return null;
    final db = await _db;
    final wh = await db.rawQuery(
      '''
      SELECT w.name AS warehouse, s.qty AS qty
      FROM product_warehouse_stock s JOIN warehouses w ON w.id = s.warehouseId
      WHERE s.productId = ? AND IFNULL(w.isActive, 1) = 1
      ORDER BY w.isDefault DESC, w.name
      ''',
      [id],
    );
    return {
      ...items.first,
      'warehouses': [
        for (final w in wh) {'warehouse': w['warehouse'], 'qty': w['qty']},
      ],
    };
  }

  /// بطاقات الزيت فقط، كما في تقرير الغيار.
  static String _oilKindWhere(String so) =>
      "($so.orderKind = '${ServiceOrderKinds.oilChange}' OR (($so.orderKind IS NULL OR $so.orderKind = "
      "'${ServiceOrderKinds.repair}') AND (($so.oilType IS NOT NULL AND TRIM($so.oilType) != '') OR "
      "($so.odometerCurrent IS NOT NULL AND TRIM($so.odometerCurrent) != ''))))";

  Map<String, Object?> _card(Map<String, Object?> r) {
    final status = '${r['status'] ?? ''}';
    final invoiced = r['invoiceId'] != null;
    final price = (r['agreedPriceFils'] as num?)?.toInt() ?? (r['estimatedPriceFils'] as num?)?.toInt();
    return {
      'id': r['id'],
      'no': r['id'],
      'plate': '${r['deviceSerial'] ?? ''}'.trim(),
      'car': '${r['deviceName'] ?? ''}'.trim(),
      'customer': '${r['customerNameSnapshot'] ?? ''}'.trim(),
      'oil': '${r['oilType'] ?? ''}'.trim(),
      'liters': ?r['oilLitersUsed'],
      'odometer': ?_int(r['odometerCurrent']),
      'next_odometer': ?_int(r['odometerNext']),
      'total_fils': ?price,
      'technician': '${r['technicianName'] ?? ''}'.trim(),
      'status': invoiced ? 'invoiced' : (status == 'pending' || status == 'in_progress' ? 'pending' : status),
      'date': _localDate(r['createdAt']),
    };
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    final d = OilChangeLookupNormalize.toWesternDigits('${v ?? ''}');
    return d.isEmpty ? null : int.tryParse(d);
  }

  static String _localDate(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, Object?>>> _orders({
    int? id,
    String? plate,
    int? customerId,
    String? customer,
    AssistantPeriod? period,
    String status = 'any',
    required int limit,
  }) async {
    final tid = await _tenant();
    final db = await _db;
    await _helper.ensureServiceOrdersReadRepair();
    final where = StringBuffer('so.tenantId = ? AND ${OilShopReportSql.aliveOrder('so')} AND ${_oilKindWhere('so')}');
    final args = <Object?>[tid];
    if (id != null) {
      where.write(' AND so.id = ?');
      args.add(id);
    }
    if (customerId != null) {
      where.write(' AND so.customerId = ?');
      args.add(customerId);
    }
    if (customer != null && customer.trim().isNotEmpty) {
      where.write(' AND so.customerNameSnapshot LIKE ? COLLATE NOCASE');
      args.add('%${customer.trim().replaceAll('%', '')}%');
    }
    if (period != null) {
      final (from, to) = ReportMath.utcBounds(period.range);
      where.write(' AND so.createdAt >= ? AND so.createdAt < ?');
      args.addAll([from, to]);
    }
    if (status == 'pending') where.write(" AND so.invoiceId IS NULL AND so.status IN ('pending', 'in_progress')");
    if (status == 'invoiced') where.write(' AND so.invoiceId IS NOT NULL');
    final plateKey = plate == null ? '' : OilChangeLookupNormalize.normalizePlateKey(plate);
    final rows = await db.rawQuery(
      'SELECT so.* FROM service_orders so WHERE $where ORDER BY so.createdAt DESC LIMIT ?',
      // اللوحة تُقارن بعد التوحيد، فيُجلب أكثر ثم يُصفّى.
      [...args, plateKey.isEmpty ? limit : 2000],
    );
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      if (plateKey.isNotEmpty &&
          !OilChangeLookupNormalize.normalizePlateKey('${r['deviceSerial'] ?? ''}').contains(plateKey)) {
        continue;
      }
      out.add(_card(r));
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<List<Map<String, Object?>>> oilCards({
    int? id,
    String? plate,
    String? customer,
    AssistantPeriod? period,
    String status = 'any',
    int limit = 20,
  }) => _orders(id: id, plate: plate, customer: customer, period: period, status: status, limit: limit);

  @override
  Future<List<Map<String, Object?>>> carVisits({String? plate, int? customerId, int limit = 5}) =>
      _orders(plate: plate, customerId: customerId, limit: limit);

  @override
  Future<Map<String, Object?>> sales(AssistantPeriod period, String channel) async {
    switch (channel) {
      case 'oil':
        final s = await OilChangeReportsRepository.instance.loadSnapshot(period.range);
        return {'count': s.current.visits, 'total_fils': s.current.revenueFils, 'cost_fils': s.current.costFils};
      case 'direct':
        final s = await DirectSaleReportRepository.instance.loadSnapshot(period.range);
        return {
          'count': s.current.invoices,
          'total_fils': s.current.salesFils,
          'returns': s.returnCount,
          'returns_fils': s.current.returnsFils,
        };
      default:
        final s = await CarWashReportRepository.instance.loadSnapshot(period.range);
        return {'count': s.current.washes, 'total_fils': s.current.revenueFils};
    }
  }

  @override
  Future<List<Map<String, Object?>>> productSales(AssistantPeriod period) async {
    final s = await ProductsReportRepository.instance.loadSnapshot(period.range);
    return [
      for (final p in s.products)
        {
          'id': p.id,
          'name': p.name,
          'sold_qty': p.soldQty,
          'amount_fils': p.revenueFils,
          if (p.hasBuyPrice) 'profit_fils': p.profitFils,
          'qty': p.qty,
          'unit': p.isLiter ? 'لتر' : 'قطعة',
          'is_liter': p.isLiter,
          'threshold': p.threshold,
          'days_of_cover': ?p.daysOfCover(s.rangeDays),
          'reorder_qty': p.reorderQty(s.rangeDays, days: 30),
        },
    ];
  }

  @override
  Future<Map<String, Object?>> debtTotals() async {
    final t = await _helper.summarizeOpenCreditDebtForDashboard();
    return {'open_total_fils': IqdMoney.toFils(t.totalOpen), 'debtors': t.debtorCount};
  }

  @override
  Future<List<Map<String, Object?>>> debtors() async {
    final list = await _helper.getCustomerDebtSummaries();
    return [
      for (final d in list)
        {
          'customer': d.displayName,
          'customer_id': ?d.customerId,
          'amount_fils': IqdMoney.toFils(d.openRemaining),
          'invoices': d.invoiceCount,
          if (d.oldestInvoiceDate != null) 'oldest': _localDate(d.oldestInvoiceDate!.toIso8601String()),
        },
    ];
  }

  @override
  Future<Map<String, Object?>> cash(AssistantPeriod period) async {
    final all = await _helper.getCashSummary();
    final tid = await _tenant();
    final db = await _db;
    const amount = 'CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END';
    final r = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(CASE WHEN $amount > 0 THEN $amount ELSE 0 END), 0) AS inF,
             COALESCE(SUM(CASE WHEN $amount < 0 THEN -($amount) ELSE 0 END), 0) AS outF
      FROM cash_ledger
      WHERE tenantId = ? AND deleted_at IS NULL AND createdAt >= ? AND createdAt <= ?
      ''',
      [tid, period.range.fromIso, period.range.toIso],
    );
    final expenses = await _helper.sumExpensesFiltered(from: period.range.from, to: period.range.to, tenantId: tid);
    return {
      'balance_fils': IqdMoney.toFils(all['balance'] ?? 0),
      'in_fils': (r.first['inF'] as num?)?.round() ?? 0,
      'out_fils': (r.first['outF'] as num?)?.round() ?? 0,
      'expenses_fils': IqdMoney.toFils(expenses),
    };
  }

  @override
  Future<Map<String, Object?>> shift() async {
    final open = await _helper.getOpenWorkShift();
    if (open == null) return {'open_shift': false};
    final counts = await _helper.getWorkShiftInvoiceCounts((open['id'] as num).toInt());
    return {
      'open_shift': true,
      'staff': ['${open['shiftStaffName'] ?? ''}'.trim()],
      'invoices': counts['sales'] ?? 0,
      'returns': counts['returns'] ?? 0,
      'opened_at': _localDate(open['openedAt']),
    };
  }

  @override
  Future<List<Map<String, Object?>>> ratingsByEmployee() async {
    final list = await OilChangeRatingsRepository.instance.loadEmployeeSummary();
    return [
      for (final e in list)
        {
          'employee': e.employeeName,
          'count': e.ratingsCount,
          'avg': e.averageScore,
          'notes': e.notesCount,
          if (e.lastRatingAt != null) 'last_at': _localDate(e.lastRatingAt!.toIso8601String()),
        },
    ];
  }

  @override
  Future<Map<String, Object?>> whatsapp(AssistantPeriod period) async {
    final status = await OilChangeWhatsappStatusStore.instance.readStatus(refreshFromServer: false);
    final out = <String, Object?>{
      'connected': status == OilChangeWhatsappGatewayStatus.connected,
      'status': status.name,
    };
    try {
      final (fromUtc, _) = ReportMath.utcBounds(period.range);
      final from = DateTime.parse(fromUtc).toLocal();
      final to = DateTime(period.range.to.year, period.range.to.month, period.range.to.day + 1);
      final s = await OilChangeWhatsappMessagesRepository.instance.countStats(fromInclusive: from, toExclusive: to);
      out.addAll({'total': s.total, 'sent': s.sent, 'delivered': s.deliveredOrRead, 'failed': s.failed});
    } catch (_) {
      out['counts_unavailable'] = true;
    }
    return out;
  }

  @override
  Future<List<Map<String, Object?>>> customers(String query, {int limit = 8}) async {
    final index = CustomerSearchIndex.instance;
    await index.ensureFresh();
    final hits = index.search(query, limit: limit);
    if (hits.isEmpty) return const [];
    final tid = await _tenant();
    final db = await _db;
    final out = <Map<String, Object?>>[];
    for (final h in hits) {
      final id = h.entry.id;
      final last = await db.rawQuery(
        "SELECT MAX(createdAt) AS d FROM service_orders WHERE tenantId = ? AND customerId = ? "
        "AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt, '')) = '')",
        [tid, id],
      );
      final debt = await _helper.sumOpenCreditDebtForCustomer(id);
      out.add({
        'id': id,
        'name': h.entry.name,
        if (last.first['d'] != null) 'last_visit': _localDate(last.first['d']),
        'open_debt_fils': IqdMoney.toFils(debt),
      });
    }
    return out;
  }

  @override
  Future<List<Map<String, Object?>>> latestVisitPerCar() async {
    final tid = await _tenant();
    final db = await _db;
    await _helper.ensureServiceOrdersReadRepair();
    final rows = await db.rawQuery(
      'SELECT so.* FROM service_orders so WHERE so.tenantId = ? AND ${OilShopReportSql.aliveOrder('so')} '
      'AND ${_oilKindWhere('so')} AND so.createdAt >= ? ORDER BY so.createdAt DESC LIMIT 5000',
      [tid, DateTime.now().subtract(const Duration(days: 400)).toUtc().toIso8601String()],
    );
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final key = OilChangeLookupNormalize.normalizePlateKey('${r['deviceSerial'] ?? ''}');
      if (key.isEmpty || !seen.add(key)) continue;
      final c = _card(r);
      out.add({
        'plate': c['plate'],
        'car': c['car'],
        'customer': c['customer'],
        'customer_id': ?r['customerId'],
        'date': c['date'],
        'odometer': ?c['odometer'],
        'next_odometer': ?c['next_odometer'],
      });
    }
    return out;
  }

  @override
  Future<int> followupDelayDays() async {
    try {
      final s = await WaOilFollowupService.instance.loadSummary();
      return switch (s.delayUnit) {
        WaOilFollowupDelayUnit.hour => 1,
        WaOilFollowupDelayUnit.day => s.delayValue,
        WaOilFollowupDelayUnit.week => s.delayValue * 7,
        WaOilFollowupDelayUnit.month => s.delayValue * 30,
        WaOilFollowupDelayUnit.year => s.delayValue * 365,
      };
    } catch (_) {
      return 90;
    }
  }

  @override
  Future<List<Map<String, Object?>>> technicians(AssistantPeriod period) async {
    final s = await OilChangeReportsRepository.instance.loadSnapshot(period.range);
    return [
      for (final t in s.topTechnicians) {'name': t.name, 'count': t.count, 'amount_fils': IqdMoney.toFils(t.amountIqd)},
    ];
  }

  @override
  Future<List<Map<String, Object?>>> purchases(int productId, {int limit = 10}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      """
      SELECT v.voucherNo, v.voucherDate, v.supplierName, i.qty, i.unitPrice
      FROM stock_voucher_items i JOIN stock_vouchers v ON v.id = i.voucherId
      WHERE i.productId = ? AND v.voucherType = 'in'
      ORDER BY v.voucherDate DESC, v.id DESC
      LIMIT ?
      """,
      [productId, limit],
    );
    return [
      for (final r in rows)
        {
          'date': '${r['voucherDate'] ?? ''}'.split('T').first,
          'supplier': '${r['supplierName'] ?? ''}'.trim(),
          'qty': r['qty'],
          'unit_price_fils': _fils(r['unitPrice']),
          'voucher_no': r['voucherNo'],
        },
    ];
  }

  @override
  Future<Map<String, Object?>> nabooAccount() async {
    final l = license?.call();
    final out = <String, Object?>{
      if (l != null) 'status': l.status.name,
      if (l?.expiresAt != null) 'expires': _localDate(l!.expiresAt!.toIso8601String()),
      'days_left': ?l?.daysLeft,
      if (l?.plan != null) 'plan': l!.plan!.nameAr,
    };
    try {
      final w = await WaMessageWalletService.instance.load();
      out['wa_balance'] = w.balance;
    } catch (_) {
      out['wa_balance_unavailable'] = true;
    }
    return out;
  }
}
