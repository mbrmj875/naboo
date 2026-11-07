import 'package:sqflite/sqflite.dart';

import '../../../../models/product_variant_kind.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/reports_repository.dart';
import '../../../../services/service_order_kinds.dart';
import '../../../../services/tenant_context_service.dart';
import '../../../../utils/stock_quantity_kind.dart';
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

class ProductsReportSnapshot {
  const ProductsReportSnapshot({
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

  int get revenueFils => revenueByChannelFils.values.fold(0, (a, b) => a + b);
  int get profitFils => products.fold(0, (a, p) => a + p.profitFils);
  int get stockCostFils => products.fold(0, (a, p) => a + p.stockCostFils);
  int get shortageCount => products.where((p) => p.isShort).length;

  /// في المخزون ولم يخرج منه شيء طوال الفترة.
  List<ProductReportRow> get idle =>
      products.where((p) => p.qty > 0 && p.soldQty <= 0).toList()
        ..sort((a, b) => b.stockCostFils.compareTo(a.stockCostFils));

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
      SELECT id, name, qty, lowStockThreshold, buyPrice, sellPrice,
             IFNULL(stockBaseKind, 0) AS stockBaseKind
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
    for (final (pid, liters) in await _cardFluids(db, tid, range)) {
      final m = qtyBy[pid] ??= {};
      m[OilShopChannel.oilCard] = (m[OilShopChannel.oilCard] ?? 0) + liters;
    }

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
        ),
    ]..sort((a, b) => b.revenueFils.compareTo(a.revenueFils));

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
  Future<List<(int, double)>> _cardFluids(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) async {
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
      ''',
      [tenantId, fromUtc, toUtc],
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
      SELECT ii.productId, ii.quantity, inv.date,
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
