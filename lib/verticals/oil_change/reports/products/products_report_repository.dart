import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../models/product_variant_kind.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/reports_repository.dart';
import '../../../../services/stock/stock_engine.dart';
import '../../../../services/stock/stock_metrics.dart';
import '../../../../services/stock_ledger.dart';
import '../../../../services/service_order_kinds.dart';
import '../../../../services/tenant_context_service.dart';
import '../../../../utils/stock_quantity_kind.dart';
import '../../utils/oil_change_filter_format.dart';
import '../kit/oil_shop_report_sql.dart';
import '../kit/report_math.dart';

/// منتج واحد: مخزونه الآن، وما خرج منه في الفترة من كل قناة.
class ProductReportRow {
  const ProductReportRow({
    required this.id,
    required this.name,
    required this.isLiter,
    required this.qty,
    required this.threshold,
    required this.buyPrice,
    required this.sellPrice,
    required this.soldQtyByChannel,
    required this.revenueFils,
    required this.costFils,
    this.cardCostFils = 0,
    this.lastExit,
  });

  final int id;
  final String name;
  final bool isLiter;
  final double qty;
  final double threshold;
  final double buyPrice;
  final double sellPrice;

  /// الكمية الصافية (بعد المرتجع) لكل [OilShopChannel].
  final Map<OilShopChannel, double> soldQtyByChannel;
  final int revenueFils;
  final int costFils;

  /// كلفة ما صُرف على بطاقات الغيار في الفترة (بتاريخ الصرف). إيرادها في سعر
  /// البطاقة بتقرير غيار الزيت، فلا تُطرح هنا من ربح الصنف (ع-14).
  final int cardCostFils;

  /// آخر خروج للصنف (بيع أو بطاقة) من حركات المخزون، أياً كانت الفترة.
  final DateTime? lastExit;

  double get soldQty => soldQtyByChannel.values.fold(0, (a, b) => a + b);
  int get profitFils => revenueFils - costFils;
  int get stockCostFils => ReportMath.toFils(qty > 0 ? qty * buyPrice : 0);

  bool get hasBuyPrice => buyPrice > 0;

  bool get isShort => qty <= 0 || (threshold > 0 && qty <= threshold);

  /// متوسط الاستهلاك اليومي في الفترة.
  double avgDaily(int rangeDays) =>
      rangeDays <= 0 || soldQty <= 0 ? 0 : soldQty / rangeDays;

  /// الكمية التي تكفي [days] يوماً بمعدل الفترة، بعد طرح المخزون الحالي.
  double reorderQty(int rangeDays, {int days = 14}) {
    final need = avgDaily(rangeDays) * days - (qty > 0 ? qty : 0);
    if (need <= 0) return 0;
    // اللتر يُقرّب لنصف لتر، والقطعة لعدد صحيح.
    return isLiter ? (need * 2).ceil() / 2 : need.ceilToDouble();
  }

  /// كم يوماً يكفي المخزون بمعدل استهلاك الفترة؛ `null` إن لم يُستهلك.
  double? daysOfCover(int rangeDays) {
    if (soldQty <= 0 || rangeDays <= 0) return null;
    if (qty <= 0) return 0;
    return qty / (soldQty / rangeDays);
  }
}

/// مرة سمح فيها المالك (برمزه) ببيع بطاقة رغم نقص الرصيد.
class StockOverrideEvent {
  const StockOverrideEvent({
    required this.at,
    required this.username,
    required this.orderId,
    required this.lines,
  });

  final DateTime at;
  final String username;
  final String orderId;

  /// نص كل نقص: «الزيت — صنف: متوفر 2 لتر، المطلوب 4 لتر».
  final List<String> lines;
}

class ProductsReportSnapshot {
  const ProductsReportSnapshot({
    this.overrides = const [],
    required this.range,
    required this.rangeDays,
    required this.products,
    required this.revenueByChannelFils,
    required this.previousRevenueFils,
    required this.previousProfitFils,
    required this.days,
    required this.costCoverage,
  });

  final ReportDateRange range;
  final int rangeDays;
  final List<ProductReportRow> products;
  final Map<OilShopChannel, int> revenueByChannelFils;
  final int previousRevenueFils;
  final int previousProfitFils;

  /// إيراد المنتجات يومياً من كل القنوات.
  final List<ReportDayPoint> days;
  final ReportCostCoverage costCoverage;

  /// تجاوزات المالك للرصيد في الفترة، الأحدث أولاً.
  final List<StockOverrideEvent> overrides;

  /// أصناف رصيدها تحت الصفر الآن (بيع رغم النقص، أو جرد لم يُسجَّل).
  List<ProductReportRow> get negative =>
      products.where((p) => p.qty < -1e-9).toList()
        ..sort((a, b) => a.qty.compareTo(b.qty));

  int get revenueFils => revenueByChannelFils.values.fold(0, (a, b) => a + b);
  int get profitFils => products.fold(0, (a, p) => a + p.profitFils);
  int get stockCostFils => products.fold(0, (a, p) => a + p.stockCostFils);
  int get shortageCount => products.where((p) => p.isShort).length;

  /// أيام بلا خروج قبل أن يُعدّ الصنف راكداً.
  static const int stagnantDays = 60;

  /// راكد (ع-14): في المخزون ولم يخرج منه شيء منذ [stagnantDays] يوماً من آخر
  /// خروج، لا «في الفترة المختارة» (فلا يصير المحل كله راكداً في تقرير اليوم).
  List<ProductReportRow> get idle {
    final cut = DateTime.now().subtract(const Duration(days: stagnantDays));
    return products
        .where((p) =>
            p.qty > 0 &&
            p.soldQty <= 0 &&
            (p.lastExit == null || p.lastExit!.isBefore(cut)))
        .toList()
      ..sort((a, b) => b.stockCostFils.compareTo(a.stockCostFils));
  }

  /// كلفة ما صرفته البطاقات من المخزون في الفترة.
  int get cardCostFils => products.fold(0, (a, p) => a + p.cardCostFils);

  int get idleCostFils => idle.fold(0, (a, p) => a + p.stockCostFils);
}

/// تقرير المنتجات لمحل الزيت: كل ما خرج من المخزون عبر الفواتير، مقسوماً
/// حسب القناة (بطاقة غيار، بيع مباشر، بيع سريع).
class ProductsReportRepository {
  ProductsReportRepository._();
  static final ProductsReportRepository instance = ProductsReportRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<ProductsReportSnapshot> loadSnapshot(ReportDateRange range) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;

    final stock = await db.rawQuery(
      '''
      SELECT id, name, ${StockMetrics.total} AS qty, lowStockThreshold,
             buyPrice, sellPrice, IFNULL(stockBaseKind, 0) AS stockBaseKind
      FROM products
      WHERE tenantId = ? AND isActive = 1 AND IFNULL(isService, 0) = 0
        AND IFNULL(trackInventory, 1) = 1
        AND ${ProductVariantKind.sqlNotFluidFamilyParent}
      ''',
      [tid],
    );

    final lines = await _lines(db, tid, range);
    final prevLines = await _lines(db, tid, ReportMath.previousRange(range));

    final qtyBy = <int, Map<OilShopChannel, double>>{};
    final revenueBy = <int, int>{};
    final costBy = <int, int>{};
    final channelRevenue = {for (final c in OilShopChannel.values) c: 0};
    final dayAmounts = <String, int>{};
    final dayCounts = <String, int>{};
    var stamped = 0;
    var fallback = 0;
    var missing = 0;

    for (final l in lines) {
      final pid = (l['productId'] as num).toInt();
      final sign = ((l['isReturned'] as num?)?.toInt() ?? 0) == 1 ? -1 : 1;
      final channel = OilShopChannel.values[(l['channel'] as num).toInt()];
      final qty = sign * ((l['quantity'] as num?)?.toDouble() ?? 0);
      final fils = sign * ((l['lineFils'] as num?)?.toInt() ?? 0);
      final cost = sign * ReportMath.toFils(l['costIqd'] as num?);
      final m = qtyBy[pid] ??= {};
      m[channel] = (m[channel] ?? 0) + qty;
      revenueBy[pid] = (revenueBy[pid] ?? 0) + fils;
      costBy[pid] = (costBy[pid] ?? 0) + cost;
      channelRevenue[channel] = channelRevenue[channel]! + fils;

      final date = DateTime.tryParse((l['date'] ?? '').toString())?.toLocal();
      if (date != null) {
        final k = ReportMath.dayKey(date);
        dayAmounts[k] = (dayAmounts[k] ?? 0) + fils;
        if (sign > 0) dayCounts[k] = (dayCounts[k] ?? 0) + 1;
      }
      if (sign > 0) {
        switch ((l['costSource'] as num?)?.toInt()) {
          case 0:
            stamped++;
          case 1:
            fallback++;
          case 2:
            missing++;
        }
      }
    }

    // الزيت والهيدروليك المصروفان على بطاقات الغيار يخرجان من المخزون عند
    // الصرف، وسطر فاتورتهما بلا منتج؛ فيُضافان هنا للكمية دون الإيراد
    // (إيرادهما ضمن سعر البطاقة في تقرير غيار الزيت).
    // وكذلك فلاتر المخزون على البطاقة: سطرها في الفاتورة بلا منتج لأن سند
    // البطاقة هو الذي صرفها.
    //
    // منذ المرحلة 2 يكتب كل صرف بطاقة حركة باسمه وكلفته وتاريخ الصرف (ع-14)،
    // فتُقرأ الحركات. البطاقات قبل ذلك (بلا حركة مسمّاة) تُقرأ من البطاقة.
    final cardCostBy = <int, int>{};
    final namedSince = await _namedMovesSince(db);
    for (final (pid, qty, costFils) in await _cardMoves(db, tid, range)) {
      final m = qtyBy[pid] ??= {};
      m[OilShopChannel.oilCard] = (m[OilShopChannel.oilCard] ?? 0) + qty;
      cardCostBy[pid] = (cardCostBy[pid] ?? 0) + costFils;
    }
    for (final (pid, qty) in [
      ...await _cardFluids(db, tid, range, before: namedSince),
      ...await _cardFilters(db, tid, range, before: namedSince),
    ]) {
      final m = qtyBy[pid] ??= {};
      m[OilShopChannel.oilCard] = (m[OilShopChannel.oilCard] ?? 0) + qty;
    }
    final lastExit = await StockMetrics.lastExitByProduct(db, tid);

    final products = <ProductReportRow>[
      for (final s in stock)
        ProductReportRow(
          id: (s['id'] as num).toInt(),
          name: (s['name'] ?? '').toString().trim(),
          isLiter:
              (s['stockBaseKind'] as num?)?.toInt() ==
              StockBaseKind.volumeLiter,
          qty: (s['qty'] as num?)?.toDouble() ?? 0,
          threshold: (s['lowStockThreshold'] as num?)?.toDouble() ?? 0,
          buyPrice: (s['buyPrice'] as num?)?.toDouble() ?? 0,
          sellPrice: (s['sellPrice'] as num?)?.toDouble() ?? 0,
          soldQtyByChannel: qtyBy[(s['id'] as num).toInt()] ?? const {},
          revenueFils: revenueBy[(s['id'] as num).toInt()] ?? 0,
          costFils: costBy[(s['id'] as num).toInt()] ?? 0,
          cardCostFils: cardCostBy[(s['id'] as num).toInt()] ?? 0,
          lastExit: lastExit[(s['id'] as num).toInt()],
        ),
    ]..sort((a, b) {
        // الترتيب بالكمية الخارجة أولاً ثم الإيراد (ع-14): الزيت المصروف على
        // البطاقات أكثر ما يتحرك ولا إيراد له هنا.
        final q = b.soldQty.compareTo(a.soldQty);
        return q != 0 ? q : b.revenueFils.compareTo(a.revenueFils);
      });

    var prevRevenue = 0;
    var prevCost = 0;
    for (final l in prevLines) {
      final sign = ((l['isReturned'] as num?)?.toInt() ?? 0) == 1 ? -1 : 1;
      prevRevenue += sign * ((l['lineFils'] as num?)?.toInt() ?? 0);
      prevCost += sign * ReportMath.toFils(l['costIqd'] as num?);
    }

    final from = DateTime(range.from.year, range.from.month, range.from.day);
    final to = DateTime(range.to.year, range.to.month, range.to.day);

    return ProductsReportSnapshot(
      overrides: await _overrides(db, tid, range),
      range: range,
      rangeDays: to.difference(from).inDays + 1,
      products: products,
      revenueByChannelFils: channelRevenue,
      previousRevenueFils: prevRevenue,
      previousProfitFils: prevRevenue - prevCost,
      days: ReportMath.zeroFill(
        range,
        counts: dayCounts,
        amountsFils: dayAmounts,
      ),
      costCoverage: ReportCostCoverage(
        stamped: stamped,
        fallback: fallback,
        missing: missing,
      ),
    );
  }

  /// (المنتج، اللترات) لكل سائل صُرف من المحل على بطاقة غيار في الفترة.
  Future<List<StockOverrideEvent>> _overrides(
    Database db,
    int tid,
    ReportDateRange range,
  ) async {
    final rows = await db.query(
      'business_audit_events',
      columns: ['username', 'entity_id', 'new_value_json', 'created_at'],
      where:
          "tenant_id = ? AND event_type = 'oil_change_stock_override' "
          'AND created_at >= ? AND created_at <= ?',
      whereArgs: [tid, range.fromIso, range.toIso],
      orderBy: 'created_at DESC, id DESC',
    );
    return [
      for (final r in rows)
        StockOverrideEvent(
          at:
              DateTime.tryParse((r['created_at'] ?? '').toString()) ??
              range.from,
          username: (r['username'] ?? '').toString().trim(),
          orderId: (r['entity_id'] ?? '').toString(),
          lines: _overrideLines(r['new_value_json']),
        ),
    ];
  }

  static List<String> _overrideLines(Object? raw) {
    try {
      final m = jsonDecode((raw ?? '').toString()) as Map<String, dynamic>;
      String n(Object? v) {
        final d = (v as num?)?.toDouble() ?? 0;
        return d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(1);
      }

      return [
        for (final s in (m['shortages'] as List? ?? const []))
          if (s is Map)
            '${(s['labels'] as List? ?? const []).join('، ')} — ${s['product']}: '
                    'متوفر ${n(s['available'])}، المطلوب ${n(s['needed'])} ${s['unit'] ?? ''}'
                .trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<(int, double)>> _cardFluids(
    Database db,
    int tenantId,
    ReportDateRange range, {
    String? before,
  }) async {
    final cols = {
      for (final r in await db.rawQuery('PRAGMA table_info(service_orders)'))
        (r['name'] ?? '').toString(),
    };
    final prefixes = [
      for (final p in const ['oil', 'hydraulic', 'powerHydraulic'])
        if (cols.contains('${p}ProductId') && cols.contains('${p}LitersUsed'))
          p,
    ];
    if (prefixes.isEmpty) return const [];
    String provided(String p) => cols.contains('${p}CustomerProvided')
        ? 'IFNULL(so.${p}CustomerProvided, 0)'
        : '0';
    final kind = cols.contains('orderKind')
        ? "AND IFNULL(so.orderKind, '') != '${ServiceOrderKinds.carWash}'"
        : '';
    final (fromUtc, toUtc) = ReportMath.utcBounds(range);
    final rows = await db.rawQuery(
      '''
      SELECT ${[for (final p in prefixes) 'so.${p}ProductId AS ${p}P, so.${p}LitersUsed AS ${p}L, ${provided(p)} AS ${p}C'].join(', ')}
      FROM service_orders so
      WHERE so.tenantId = ? AND ${OilShopReportSql.aliveOrder('so')}
        AND so.createdAt >= ? AND so.createdAt < ? $kind
        ${before == null ? '' : 'AND so.createdAt < ?'}
      ''',
      [tenantId, fromUtc, toUtc, if (before != null) before],
    );
    final out = <(int, double)>[];
    for (final r in rows) {
      for (final p in prefixes) {
        final pid = (r['${p}P'] as num?)?.toInt();
        final liters = (r['${p}L'] as num?)?.toDouble() ?? 0;
        final customer = ((r['${p}C'] as num?)?.toInt() ?? 0) != 0;
        if (pid != null && pid > 0 && liters > 1e-9 && !customer) {
          out.add((pid, liters));
        }
      }
    }
    return out;
  }

  /// قطع الفلاتر المصروفة من المخزون على بطاقات الفترة (لا ما أحضره العميل).
  Future<List<(int, double)>> _cardFilters(
    Database db,
    int tenantId,
    ReportDateRange range, {
    String? before,
  }) async {
    final cols = {
      for (final r in await db.rawQuery('PRAGMA table_info(service_orders)'))
        (r['name'] ?? '').toString(),
    };
    if (!cols.contains('oilFiltersJson')) return const [];
    final kind = cols.contains('orderKind')
        ? "AND IFNULL(so.orderKind, '') != '${ServiceOrderKinds.carWash}'"
        : '';
    final (fromUtc, toUtc) = ReportMath.utcBounds(range);
    final rows = await db.rawQuery(
      '''
      SELECT so.oilFiltersJson AS j
      FROM service_orders so
      WHERE so.tenantId = ? AND ${OilShopReportSql.aliveOrder('so')}
        AND so.createdAt >= ? AND so.createdAt < ? $kind
        AND IFNULL(so.oilFiltersJson, '') != ''
        ${before == null ? '' : 'AND so.createdAt < ?'}
      ''',
      [tenantId, fromUtc, toUtc, if (before != null) before],
    );
    return [
      for (final r in rows)
        for (final line in parseOilFiltersJson(r['j']?.toString()))
          if (line.issuesStock) (line.productId!, line.qty.toDouble()),
    ];
  }

  /// أول حركة مسمّاة في دفتر المخزون: قبلها تُقرأ البطاقات من سجلها.
  Future<String?> _namedMovesSince(Database db) async {
    try {
      final r = await db.rawQuery(
        'SELECT MIN(created_at) AS m FROM ${StockLedger.table} '
        'WHERE kind IS NOT NULL',
      );
      final m = r.first['m']?.toString();
      return (m == null || m.isEmpty) ? null : m;
    } catch (_) {
      return null;
    }
  }

  /// (المنتج، الكمية الصافية، الكلفة بالفلس) لصرف البطاقات في الفترة بتاريخ
  /// الصرف، بعد طرح ما أعادته البطاقات الملغاة.
  Future<List<(int, double, int)>> _cardMoves(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) async {
    final (fromUtc, toUtc) = ReportMath.utcBounds(range);
    final rows = await db.rawQuery(
      '''
      SELECT p.id AS pid, SUM(-l.delta) AS q,
             SUM(-l.delta * COALESCE(l.unit_cost_fils,
                 CAST(ROUND(IFNULL(p.buyPrice, 0) * 1000) AS INTEGER))) AS c
      FROM ${StockLedger.table} l
      JOIN products p ON p.global_id = l.product_global_id
      WHERE p.tenantId = ? AND l.kind IN (?, ?)
        AND l.created_at >= ? AND l.created_at < ?
      GROUP BY p.id
      ''',
      [tenantId, StockMoveKind.card, StockMoveKind.cardReturn, fromUtc, toUtc],
    );
    return [
      for (final r in rows)
        (
          (r['pid'] as num).toInt(),
          (r['q'] as num?)?.toDouble() ?? 0,
          ((r['c'] as num?) ?? 0).round(),
        ),
    ];
  }

  /// سطور المنتجات في فواتير البيع ومرتجعاتها، مع قناة كل فاتورة.
  Future<List<Map<String, Object?>>> _lines(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) {
    // المرتجع يُنسب لقناة فاتورته الأصلية.
    final channel = OilShopReportSql.channelOf(
      invoiceId: 'IFNULL(o.id, inv.id)',
      tenant: 'inv.tenantId',
      deliveryAddress: 'IFNULL(o.deliveryAddress, inv.deliveryAddress)',
    );
    return db.rawQuery(
      '''
      SELECT ii.productId,
             COALESCE(NULLIF(ii.baseQty, 0), ii.quantity) AS quantity, inv.date,
             IFNULL(inv.isReturned, 0) AS isReturned,
             CAST(ROUND(CASE WHEN IFNULL(ii.totalFils, 0) > 0 THEN ii.totalFils
               ELSE IFNULL(ii.total, 0) * 1000 END) AS INTEGER) AS lineFils,
             ${OilShopReportSql.lineCostIqd('ii', 'p')} AS costIqd,
             ${OilShopReportSql.lineCostSource('ii', 'p')} AS costSource,
             $channel AS channel
      FROM invoice_items ii
      INNER JOIN invoices inv ON inv.id = ii.invoiceId
      LEFT JOIN invoices o ON o.id = inv.originalInvoiceId
        AND IFNULL(inv.isReturned, 0) = 1
      INNER JOIN products p ON p.id = ii.productId
      WHERE inv.tenantId = ? AND inv.deleted_at IS NULL AND ii.deleted_at IS NULL
        AND IFNULL(p.isService, 0) = 0
        AND (${OilShopReportSql.aliveSale('inv')} OR ${OilShopReportSql.aliveReturn('inv')})
        AND inv.date >= ? AND inv.date <= ?
      ''',
      [tenantId, range.fromIso, range.toIso],
    );
  }
}
