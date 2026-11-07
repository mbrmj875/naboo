import 'package:sqflite/sqflite.dart';

import '../../../../services/database_helper.dart';
import '../../../../services/reports_repository.dart';
import '../../../../services/tenant_context_service.dart';
import '../../services/oil_change_direct_sale_service.dart';
import '../kit/oil_shop_report_sql.dart';
import '../kit/report_math.dart';

/// أرقام فترة واحدة للبيع المباشر.
class DirectSaleTotals {
  const DirectSaleTotals({
    required this.invoices,
    required this.salesFils,
    required this.returnsFils,
    required this.costFils,
  });

  static const empty = DirectSaleTotals(
    invoices: 0,
    salesFils: 0,
    returnsFils: 0,
    costFils: 0,
  );

  final int invoices;
  final int salesFils;
  final int returnsFils;

  /// تكلفة البضاعة بعد طرح تكلفة المرتجع.
  final int costFils;

  int get netFils => salesFils - returnsFils;
  int get profitFils => netFils - costFils;
  int get avgBasketFils => invoices == 0 ? 0 : salesFils ~/ invoices;
  double? get marginPct => netFils > 0 ? profitFils / netFils * 100 : null;
}

class DirectSaleInvoiceRow {
  const DirectSaleInvoiceRow({
    required this.id,
    required this.date,
    required this.customer,
    required this.isCredit,
    required this.totalFils,
    required this.paidFils,
    required this.itemCount,
    required this.actor,
  });

  final int id;
  final DateTime? date;
  final String customer;
  final bool isCredit;
  final int totalFils;
  final int paidFils;
  final int itemCount;
  final String actor;
}

class DirectSaleReportSnapshot {
  const DirectSaleReportSnapshot({
    required this.range,
    required this.current,
    required this.previous,
    required this.days,
    required this.cashFils,
    required this.creditFils,
    required this.creditOutstandingFils,
    required this.returnCount,
    required this.products,
    required this.heatmap,
    required this.invoices,
    required this.costCoverage,
  });

  final ReportDateRange range;
  final DirectSaleTotals current;
  final DirectSaleTotals previous;
  final List<ReportDayPoint> days;
  final int cashFils;
  final int creditFils;

  /// المتبقي على العملاء من فواتير الآجل في الفترة (لحظة البيع).
  final int creditOutstandingFils;
  final int returnCount;

  /// المنتجات مرتبة بصافي الإيراد.
  final List<ReportRankRow> products;
  final List<List<int>> heatmap;
  final List<DirectSaleInvoiceRow> invoices;
  final ReportCostCoverage costCoverage;
}

/// تقرير البيع المباشر: فواتير المنتجات بلا بطاقة غيار.
class DirectSaleReportRepository {
  DirectSaleReportRepository._();
  static final DirectSaleReportRepository instance =
      DirectSaleReportRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const _tag = OilChangeDirectSaleService.sourceTag;

  /// فواتير البيع المباشر الحية، ومرتجعاتها (المرتجع يُعرف من فاتورته الأصلية).
  static const _scope =
      "((IFNULL(inv.isReturned, 0) = 0 AND inv.type IN (0,1,2,3) "
      "AND inv.deliveryAddress = '$_tag') OR "
      "(IFNULL(inv.isReturned, 0) = 1 AND (inv.deliveryAddress = '$_tag' "
      "OR o.deliveryAddress = '$_tag')))";

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<DirectSaleReportSnapshot> loadSnapshot(ReportDateRange range) async {
    final tid = await _tenantId();
    final db = await _dbHelper.database;

    final heads = await _heads(db, tid, range);
    final lines = await _lines(db, tid, range);
    final prevRange = ReportMath.previousRange(range);
    final previous = _totals(
      await _heads(db, tid, prevRange),
      await _lines(db, tid, prevRange),
    );
    final current = _totals(heads, lines);

    final dayCounts = <String, int>{};
    final dayAmounts = <String, int>{};
    final heat = List.generate(7, (_) => List.filled(24, 0));
    var cash = 0;
    var credit = 0;
    var outstanding = 0;
    var returnCount = 0;
    final itemCounts = <int, int>{};
    for (final l in lines) {
      final id = (l['invoiceId'] as num).toInt();
      itemCounts[id] = (itemCounts[id] ?? 0) + 1;
    }
    final rows = <DirectSaleInvoiceRow>[];

    for (final h in heads) {
      final returned = ((h['isReturned'] as num?)?.toInt() ?? 0) == 1;
      final total = (h['totalFils'] as num?)?.toInt() ?? 0;
      final date = DateTime.tryParse((h['date'] ?? '').toString())?.toLocal();
      if (returned) {
        returnCount++;
        if (date != null) {
          final k = ReportMath.dayKey(date);
          dayAmounts[k] = (dayAmounts[k] ?? 0) - total;
        }
        continue;
      }
      final type = (h['type'] as num?)?.toInt() ?? 0;
      final isCredit = type == 1;
      final paid = (h['paidFils'] as num?)?.toInt() ?? 0;
      if (isCredit) {
        credit += total;
        outstanding += (total - paid).clamp(0, total);
      } else {
        cash += total;
      }
      if (date != null) {
        final k = ReportMath.dayKey(date);
        dayCounts[k] = (dayCounts[k] ?? 0) + 1;
        dayAmounts[k] = (dayAmounts[k] ?? 0) + total;
        heat[ReportMath.weekdayRow(date)][date.hour]++;
      }
      final id = (h['id'] as num).toInt();
      rows.add(
        DirectSaleInvoiceRow(
          id: id,
          date: date,
          customer: (h['customerName'] ?? '').toString().trim(),
          isCredit: isCredit,
          totalFils: total,
          paidFils: isCredit ? paid : total,
          itemCount: itemCounts[id] ?? 0,
          actor: (h['createdByUserName'] ?? '').toString().trim(),
        ),
      );
    }

    final byProduct = <String, ReportRankRow>{};
    var stamped = 0;
    var fallback = 0;
    var missing = 0;
    for (final l in lines) {
      final sign = ((l['isReturned'] as num?)?.toInt() ?? 0) == 1 ? -1 : 1;
      final name = (l['productName'] ?? '').toString().trim();
      final key = name.isEmpty ? 'منتج' : name;
      final old = byProduct[key];
      final amount = sign * ((l['lineFils'] as num?)?.toInt() ?? 0);
      final cost = sign * ReportMath.toFils(l['costIqd'] as num?);
      final qty = sign * ((l['quantity'] as num?)?.toDouble() ?? 0);
      byProduct[key] = ReportRankRow(
        label: key,
        count: (old?.count ?? 0) + (sign > 0 ? 1 : 0),
        amountFils: (old?.amountFils ?? 0) + amount,
        costFils: (old?.costFils ?? 0) + cost,
        quantity: (old?.quantity ?? 0) + qty,
      );
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

    return DirectSaleReportSnapshot(
      range: range,
      current: current,
      previous: previous,
      days: ReportMath.zeroFill(
        range,
        counts: dayCounts,
        amountsFils: dayAmounts,
      ),
      cashFils: cash,
      creditFils: credit,
      creditOutstandingFils: outstanding,
      returnCount: returnCount,
      products: ReportMath.rank(byProduct.values),
      heatmap: heat,
      invoices: rows,
      costCoverage: ReportCostCoverage(
        stamped: stamped,
        fallback: fallback,
        missing: missing,
      ),
    );
  }

  static DirectSaleTotals _totals(
    List<Map<String, Object?>> heads,
    List<Map<String, Object?>> lines,
  ) {
    var invoices = 0;
    var sales = 0;
    var returns = 0;
    for (final h in heads) {
      final total = (h['totalFils'] as num?)?.toInt() ?? 0;
      if (((h['isReturned'] as num?)?.toInt() ?? 0) == 1) {
        returns += total;
      } else {
        invoices++;
        sales += total;
      }
    }
    var cost = 0;
    for (final l in lines) {
      final sign = ((l['isReturned'] as num?)?.toInt() ?? 0) == 1 ? -1 : 1;
      cost += sign * ReportMath.toFils(l['costIqd'] as num?);
    }
    return DirectSaleTotals(
      invoices: invoices,
      salesFils: sales,
      returnsFils: returns,
      costFils: cost,
    );
  }

  Future<List<Map<String, Object?>>> _heads(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) {
    return db.rawQuery(
      '''
      SELECT inv.id, inv.date, inv.type, inv.customerName, inv.createdByUserName,
             IFNULL(inv.isReturned, 0) AS isReturned,
             ${OilShopReportSql.totalFils('inv')} AS totalFils,
             CAST(ROUND(CASE WHEN IFNULL(inv.advancePaymentFils, 0) > 0
               THEN inv.advancePaymentFils
               ELSE IFNULL(inv.advancePayment, 0) * 1000 END) AS INTEGER) AS paidFils
      FROM invoices inv
      LEFT JOIN invoices o ON o.id = inv.originalInvoiceId
      WHERE inv.tenantId = ? AND inv.deleted_at IS NULL
        AND inv.date >= ? AND inv.date <= ?
        AND $_scope
      ORDER BY inv.date DESC
      ''',
      [tenantId, range.fromIso, range.toIso],
    );
  }

  Future<List<Map<String, Object?>>> _lines(
    Database db,
    int tenantId,
    ReportDateRange range,
  ) {
    return db.rawQuery(
      '''
      SELECT ii.invoiceId, ii.productId, ii.productName, ii.quantity,
             IFNULL(inv.isReturned, 0) AS isReturned,
             CAST(ROUND(CASE WHEN IFNULL(ii.totalFils, 0) > 0 THEN ii.totalFils
               ELSE IFNULL(ii.total, 0) * 1000 END) AS INTEGER) AS lineFils,
             ${OilShopReportSql.lineCostIqd('ii', 'p')} AS costIqd,
             ${OilShopReportSql.lineCostSource('ii', 'p')} AS costSource
      FROM invoice_items ii
      INNER JOIN invoices inv ON inv.id = ii.invoiceId
      LEFT JOIN invoices o ON o.id = inv.originalInvoiceId
      LEFT JOIN products p ON p.id = ii.productId
      WHERE inv.tenantId = ? AND inv.deleted_at IS NULL AND ii.deleted_at IS NULL
        AND inv.date >= ? AND inv.date <= ?
        AND $_scope
      ''',
      [tenantId, range.fromIso, range.toIso],
    );
  }
}
