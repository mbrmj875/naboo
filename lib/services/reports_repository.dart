import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// نطاق زمني للتقارير (مقارنة نصية ISO مع عمود `invoices.date`).
class ReportDateRange {
  const ReportDateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  String get fromIso =>
      DateTime(from.year, from.month, from.day).toIso8601String();
  String get toIso {
    final e = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    return e.toIso8601String();
  }
}

/// لقطة بيانات تقارير — تُحمَّل دفعة واحدة للفترة المحددة.
class ReportsSnapshot {
  const ReportsSnapshot({
    required this.range,
    required this.salesNet,
    required this.returnsTotal,
    required this.expensesTotal,
    required this.invoiceCount,
    required this.returnCount,
    required this.salesByType,
    required this.dailySales,
    required this.dailyExpenses,
    required this.dailySalesByType,
    required this.dailySalesByStaff,
    required this.dailyMargin,
    required this.productMargins,
    required this.topCustomers,
    required this.topProducts,
    required this.debtors,
    required this.installmentPlansInRange,
    required this.installmentTotals,
    required this.staffSales,
    required this.estimatedGrossMargin,
    required this.marginStats,
    required this.loyaltyRedeemedInRange,
    required this.loyaltyEarnedInRange,
  });

  final ReportDateRange range;
  final double salesNet;
  final double returnsTotal;
  final double expensesTotal;
  final int invoiceCount;
  final int returnCount;
  final Map<int, double> salesByType; // InvoiceType.index -> sum total
  final List<DailySalesPoint> dailySales;
  final List<DailyAmountPoint> dailyExpenses;
  final List<DailyByTypePoint> dailySalesByType;
  final List<DailyByLabelPoint> dailySalesByStaff;
  final List<DailyMarginPoint> dailyMargin;
  final List<ProductMarginRow> productMargins;
  final List<NamedAmountRow> topCustomers;
  final List<ProductSalesRow> topProducts;
  final List<DebtorRow> debtors;
  final List<InstallmentPlanRow> installmentPlansInRange;
  final InstallmentTotals installmentTotals;
  final List<StaffSalesRow> staffSales;
  final double? estimatedGrossMargin;
  final MarginStats marginStats;
  final double loyaltyRedeemedInRange;
  final double loyaltyEarnedInRange;
}

class DailySalesPoint {
  const DailySalesPoint({required this.dayLabel, required this.amount});
  final String dayLabel;
  final double amount;
}

class DailyAmountPoint {
  const DailyAmountPoint({required this.dayLabel, required this.amount});
  final String dayLabel;
  final double amount;
}

class DailyByTypePoint {
  const DailyByTypePoint({
    required this.dayLabel,
    required this.typeIdx,
    required this.amount,
  });
  final String dayLabel;
  final int typeIdx;
  final double amount;
}

class DailyByLabelPoint {
  const DailyByLabelPoint({
    required this.dayLabel,
    required this.label,
    required this.amount,
  });
  final String dayLabel;
  final String label;
  final double amount;
}

/// نقطة يومية للهامش — تعطينا إيراد وتكلفة وهامش في اليوم الواحد.
class DailyMarginPoint {
  const DailyMarginPoint({
    required this.dayLabel,
    required this.revenue,
    required this.cost,
  });
  final String dayLabel;
  final double revenue;
  final double cost;
  double get margin => revenue - cost;
}

/// صف هامش لمنتج — يُستخدم في قوائم Top/Bottom.
class ProductMarginRow {
  const ProductMarginRow({
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
    required this.cost,
  });
  final int? productId;
  final String name;
  final double qty;
  final double revenue;
  final double cost;
  double get margin => revenue - cost;
  double? get marginPct =>
      revenue > 0 ? (margin / revenue) * 100.0 : null;
}

class NamedAmountRow {
  const NamedAmountRow({required this.name, required this.amount, this.count});
  final String name;
  final double amount;
  final int? count;
}

class ProductSalesRow {
  const ProductSalesRow({
    required this.name,
    required this.qty,
    required this.revenue,
  });
  final String name;
  final double qty;
  final double revenue;
}

class DebtorRow {
  const DebtorRow({
    required this.customerId,
    required this.name,
    required this.balance,
  });
  final int customerId;
  final String name;
  final double balance;
}

class InstallmentPlanRow {
  const InstallmentPlanRow({
    required this.planId,
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.remaining,
    required this.invoiceId,
  });
  final int planId;
  final String customerName;
  final double totalAmount;
  final double paidAmount;
  final double remaining;
  final int? invoiceId;
}

/// إحصائيات الهامش الذكية — تشمل الإيراد والتكلفة والهامش والصافي بعد المصروفات
/// ومؤشرات جودة البيانات (Coverage) حتى يعرف المستخدم مدى دقة الرقم.
class MarginStats {
  const MarginStats({
    required this.revenueNet,
    required this.cost,
    required this.grossMargin,
    required this.expenses,
    required this.netProfit,
    required this.marginPct,
    required this.totalLines,
    required this.linesStamped,
    required this.linesFallbackBuyPrice,
    required this.linesZeroCost,
    required this.available,
  });

  /// إيراد البنود في الفترة (بعد استبعاد المرتجعات وسندات التحصيل).
  final double revenueNet;

  /// تكلفة البضاعة المباعة (Cost of Goods Sold) المحتسبة.
  final double cost;

  /// الهامش الإجمالي = revenueNet - cost
  final double grossMargin;

  /// مجموع مصروفات الفترة (يُطرح من الهامش لحساب الصافي).
  final double expenses;

  /// الصافي بعد طرح المصروفات.
  final double netProfit;

  /// نسبة الهامش الإجمالي من الإيراد ×100 (null إذا الإيراد = 0).
  final double? marginPct;

  /// عدد سطور البنود (invoice_items) الداخلة في الحساب.
  final int totalLines;

  /// سطور تكلفتها مثبّتة من البيع (unitCost موجود على السطر).
  final int linesStamped;

  /// سطور اعتمدت على products.buyPrice الحالي (Fallback).
  final int linesFallbackBuyPrice;

  /// سطور تكلفتها صفر — لا منتج مربوط ولا buyPrice → غير دقيقة.
  final int linesZeroCost;

  /// هل الحساب تم بنجاح؟ false فقط عند خطأ قاعدة بيانات.
  final bool available;

  /// نسبة جودة البيانات (0..100).
  double get coveragePct {
    if (totalLines <= 0) return 0;
    final known = linesStamped + linesFallbackBuyPrice;
    return (known / totalLines) * 100.0;
  }
}

class InstallmentTotals {
  const InstallmentTotals({
    required this.planCount,
    required this.totalDue,
    required this.totalPaid,
    required this.totalRemaining,
  });
  final int planCount;
  final double totalDue;
  final double totalPaid;
  final double totalRemaining;
}

class StaffSalesRow {
  const StaffSalesRow({
    required this.staffLabel,
    required this.invoiceCount,
    required this.salesTotal,
  });
  final String staffLabel;
  final int invoiceCount;
  final double salesTotal;
}

/// استعلامات تجميعية للتقارير — لا تُحمّل كل الجدول في الذاكرة.
class ReportsRepository {
  ReportsRepository._();
  static final ReportsRepository instance = ReportsRepository._();

  final DatabaseHelper _db = DatabaseHelper();

  /// أنواع الفواتير التي تُعتبر "مبيعات" (ولا تشمل السندات مثل التحصيل/دفع مورد).
  static const List<int> _salesInvoiceTypeIdx = <int>[0, 1, 2, 3];

  String get _salesTypeInSql => 'type IN (${_salesInvoiceTypeIdx.join(',')})';

  Future<ReportsSnapshot> loadSnapshot(ReportDateRange range) async {
    final db = await _db.database;
    final from = range.fromIso;
    final to = range.toIso;

    final salesByType = await _salesByType(db, from, to);
    final netReturns = await _returnsTotals(db, from, to);
    final expensesTotal = await _sumExpenses(db, from, to);
    final invCount = await _countInvoices(db, from, to, returned: false);
    final retCount = await _countInvoices(db, from, to, returned: true);
    final daily = await _dailySales(db, from, to);
    final dailyExpenses = await _dailyExpenses(db, from, to);
    final dailySalesByType = await _dailySalesByType(db, from, to);
    final topCust = await _topCustomers(db, from, to);
    final topProd = await _topProducts(db, from, to);
    final debtors = await _debtors(db);
    final inst = await _installmentsInRange(db, from, to);
    final staff = await _staffSales(db, from, to);
    final dailyStaff = await _dailySalesByStaff(db, from, to);
    final marginStats = await _marginStats(
      db,
      from,
      to,
      expensesTotal: expensesTotal,
    );
    final dailyMargin = await _dailyMargin(db, from, to);
    final productMargins = await _productMargins(db, from, to);
    final loyalty = await _loyaltyInvoiceTotals(db, from, to);

    final netSales = await _sumSalesNet(db, from, to);

    return ReportsSnapshot(
      range: range,
      salesNet: netSales,
      returnsTotal: netReturns,
      expensesTotal: expensesTotal,
      invoiceCount: invCount,
      returnCount: retCount,
      salesByType: salesByType,
      dailySales: daily,
      dailyExpenses: dailyExpenses,
      dailySalesByType: dailySalesByType,
      dailySalesByStaff: dailyStaff,
      dailyMargin: dailyMargin,
      productMargins: productMargins,
      topCustomers: topCust,
      topProducts: topProd,
      debtors: debtors,
      installmentPlansInRange: inst.plans,
      installmentTotals: inst.totals,
      staffSales: staff,
      estimatedGrossMargin: marginStats.available ? marginStats.grossMargin : null,
      marginStats: marginStats,
      loyaltyRedeemedInRange: loyalty.$1,
      loyaltyEarnedInRange: loyalty.$2,
    );
  }

  Future<double> _sumExpenses(Database db, String from, String to) async {
    // Ensure tables exist even on older DBs.
    await ensureExpensesSchema(db);
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE tenantId = 1
        AND occurredAt >= ? AND occurredAt <= ?
      ''',
      [from, to],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> _sumSalesNet(Database db, String from, String to) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) AS s FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      ''',
      [from, to],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<Map<int, double>> _salesByType(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT type, COALESCE(SUM(total), 0) AS s FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      GROUP BY type
      ''',
      [from, to],
    );
    final m = <int, double>{};
    for (final r in rows) {
      m[(r['type'] as num).toInt()] = (r['s'] as num).toDouble();
    }
    return m;
  }

  Future<double> _returnsTotals(Database db, String from, String to) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) AS s FROM invoices
      WHERE IFNULL(isReturned, 0) = 1
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      ''',
      [from, to],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<int> _countInvoices(
    Database db,
    String from,
    String to, {
    required bool returned,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE IFNULL(isReturned, 0) = ?
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      ''',
      [returned ? 1 : 0, from, to],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<List<DailyAmountPoint>> _dailyExpenses(
    Database db,
    String from,
    String to,
  ) async {
    await ensureExpensesSchema(db);
    final rows = await db.rawQuery(
      '''
      SELECT substr(occurredAt, 1, 10) AS d, COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE tenantId = 1
        AND occurredAt >= ? AND occurredAt <= ?
      GROUP BY substr(occurredAt, 1, 10)
      ORDER BY d ASC
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => DailyAmountPoint(
            dayLabel: r['d']?.toString() ?? '',
            amount: (r['s'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  Future<List<DailyByTypePoint>> _dailySalesByType(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT substr(date, 1, 10) AS d,
             type AS t,
             COALESCE(SUM(total), 0) AS s
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      GROUP BY substr(date, 1, 10), type
      ORDER BY d ASC
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => DailyByTypePoint(
            dayLabel: r['d']?.toString() ?? '',
            typeIdx: (r['t'] as num?)?.toInt() ?? -1,
            amount: (r['s'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  Future<List<DailyByLabelPoint>> _dailySalesByStaff(
    Database db,
    String from,
    String to,
  ) async {
    // نقيّد السلاسل إلى أعلى 5 موظفين لتفادي ازدحام الرسم/الاستعلام.
    final rows = await db.rawQuery(
      '''
      WITH top_staff AS (
        SELECT IFNULL(NULLIF(TRIM(createdByUserName), ''), '(غير معروف)') AS u,
               COALESCE(SUM(total), 0) AS s
        FROM invoices
        WHERE IFNULL(isReturned, 0) = 0
          AND $_salesTypeInSql
          AND date >= ? AND date <= ?
        GROUP BY 1
        ORDER BY s DESC
        LIMIT 5
      )
      SELECT substr(date, 1, 10) AS d,
             IFNULL(NULLIF(TRIM(createdByUserName), ''), '(غير معروف)') AS u,
             COALESCE(SUM(total), 0) AS s
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
        AND IFNULL(NULLIF(TRIM(createdByUserName), ''), '(غير معروف)') IN (SELECT u FROM top_staff)
      GROUP BY substr(date, 1, 10), u
      ORDER BY d ASC
      ''',
      [from, to, from, to],
    );
    return rows
        .map(
          (r) => DailyByLabelPoint(
            dayLabel: r['d']?.toString() ?? '',
            label: r['u']?.toString() ?? '',
            amount: (r['s'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  Future<List<DailySalesPoint>> _dailySales(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT substr(date, 1, 10) AS d, COALESCE(SUM(total), 0) AS s
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      GROUP BY substr(date, 1, 10)
      ORDER BY d ASC
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => DailySalesPoint(
            dayLabel: r['d']?.toString() ?? '',
            amount: (r['s'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<List<NamedAmountRow>> _topCustomers(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT TRIM(customerName) AS n, COALESCE(SUM(total), 0) AS s, COUNT(*) AS c
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
        AND IFNULL(customerName, '') != ''
      GROUP BY TRIM(customerName)
      ORDER BY s DESC
      LIMIT 20
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => NamedAmountRow(
            name: r['n']?.toString() ?? '',
            amount: (r['s'] as num?)?.toDouble() ?? 0,
            count: (r['c'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  Future<List<ProductSalesRow>> _topProducts(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT ii.productName AS n,
             COALESCE(SUM(ii.quantity), 0) AS q,
             COALESCE(SUM(ii.total), 0) AS t
      FROM invoice_items ii
      INNER JOIN invoices inv ON inv.id = ii.invoiceId
      WHERE IFNULL(inv.isReturned, 0) = 0
        AND inv.$_salesTypeInSql
        AND inv.date >= ? AND inv.date <= ?
      GROUP BY ii.productName
      ORDER BY t DESC
      LIMIT 20
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => ProductSalesRow(
            name: r['n']?.toString() ?? '',
            qty: (r['q'] as num?)?.toDouble() ?? 0,
            revenue: (r['t'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<List<DebtorRow>> _debtors(Database db) async {
    final rows = await db.query(
      'customers',
      columns: ['id', 'name', 'balance'],
      where: 'balance > ?',
      whereArgs: [0.01],
      orderBy: 'balance DESC',
      limit: 100,
    );
    return rows
        .map(
          (r) => DebtorRow(
            customerId: r['id'] as int,
            name: r['name']?.toString() ?? '',
            balance: (r['balance'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<({List<InstallmentPlanRow> plans, InstallmentTotals totals})>
  _installmentsInRange(Database db, String from, String to) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        '''
      SELECT p.id AS pid,
             p.customerName AS cn,
             p.totalAmount AS ta,
             p.paidAmount AS pa,
             p.invoiceId AS iid
      FROM installment_plans p
      INNER JOIN invoices i ON i.id = p.invoiceId
      WHERE i.date >= ? AND i.date <= ?
      ORDER BY (p.totalAmount - p.paidAmount) DESC
      ''',
        [from, to],
      );
    } catch (_) {
      rows = const [];
    }
    double sumDue = 0, sumPaid = 0, sumRem = 0;
    final plans = <InstallmentPlanRow>[];
    for (final r in rows) {
      final ta = (r['ta'] as num?)?.toDouble() ?? 0;
      final pa = (r['pa'] as num?)?.toDouble() ?? 0;
      final rem = ta - pa;
      sumDue += ta;
      sumPaid += pa;
      sumRem += rem;
      plans.add(
        InstallmentPlanRow(
          planId: (r['pid'] as num).toInt(),
          customerName: r['cn']?.toString() ?? '',
          totalAmount: ta,
          paidAmount: pa,
          remaining: rem,
          invoiceId: r['iid'] as int?,
        ),
      );
    }
    final totals = InstallmentTotals(
      planCount: plans.length,
      totalDue: sumDue,
      totalPaid: sumPaid,
      totalRemaining: sumRem,
    );
    return (plans: plans, totals: totals);
  }

  Future<List<StaffSalesRow>> _staffSales(
    Database db,
    String from,
    String to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT IFNULL(NULLIF(TRIM(createdByUserName), ''), '(غير معروف)') AS u,
             COUNT(*) AS c,
             COALESCE(SUM(total), 0) AS s
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND $_salesTypeInSql
        AND date >= ? AND date <= ?
      GROUP BY 1
      ORDER BY s DESC
      ''',
      [from, to],
    );
    return rows
        .map(
          (r) => StaffSalesRow(
            staffLabel: r['u']?.toString() ?? '',
            invoiceCount: (r['c'] as num?)?.toInt() ?? 0,
            salesTotal: (r['s'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  /// حساب الهامش الإجمالي والصافي مع مؤشرات جودة البيانات.
  ///
  /// التسلسل الهرمي للتكلفة (من الأدق للأقل):
  ///   1) `invoice_items.unitCost` — تكلفة مثبّتة لحظة البيع.
  ///   2) `products.buyPrice` — آخر سعر شراء حالي (Fallback).
  ///   3) 0 — يُعدّ كسطر بدون تكلفة ويُعلَّم في الإحصائيات.
  ///
  /// معالجات متقدمة:
  ///   - توزيع الخصم على الفاتورة (discount + loyaltyDiscount) نسبياً على كل سطر.
  ///   - المرتجعات: تُطرح إيراداتها وتكلفتها من الصافي (sign = -1).
  ///
  /// التغطية: نحسب كم سطر مثبّت vs. Fallback vs. بدون تكلفة حتى يظهر للمستخدم
  /// مدى موثوقية الرقم.
  Future<MarginStats> _marginStats(
    Database db,
    String from,
    String to, {
    required double expensesTotal,
  }) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            (
              ii.total -
              CASE WHEN IFNULL(t.gross, 0) > 0
                   THEN ii.total * (IFNULL(inv.discount, 0) + IFNULL(inv.loyaltyDiscount, 0)) / t.gross
                   ELSE 0
              END
            )
          ), 0) AS revenue,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            CASE
              WHEN ii.unitCost IS NOT NULL THEN ii.unitCost * ii.quantity
              WHEN p.buyPrice IS NOT NULL   THEN p.buyPrice * ii.quantity
              ELSE 0
            END
          ), 0) AS cost,
          SUM(CASE WHEN IFNULL(inv.isReturned,0) = 0 THEN 1 ELSE 0 END) AS totalLines,
          SUM(CASE WHEN IFNULL(inv.isReturned,0) = 0 AND ii.unitCost IS NOT NULL THEN 1 ELSE 0 END) AS stamped,
          SUM(CASE WHEN IFNULL(inv.isReturned,0) = 0 AND ii.unitCost IS NULL AND p.buyPrice IS NOT NULL THEN 1 ELSE 0 END) AS fallback,
          SUM(CASE WHEN IFNULL(inv.isReturned,0) = 0 AND ii.unitCost IS NULL AND p.buyPrice IS NULL THEN 1 ELSE 0 END) AS zeroCost
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        LEFT JOIN products p ON p.id = ii.productId
        LEFT JOIN (
          SELECT invoiceId, SUM(total) AS gross
          FROM invoice_items
          GROUP BY invoiceId
        ) t ON t.invoiceId = inv.id
        WHERE inv.$_salesTypeInSql
          AND inv.date >= ? AND inv.date <= ?
        ''',
        [from, to],
      );
      if (rows.isEmpty) {
        return MarginStats(
          revenueNet: 0,
          cost: 0,
          grossMargin: 0,
          expenses: expensesTotal,
          netProfit: -expensesTotal,
          marginPct: null,
          totalLines: 0,
          linesStamped: 0,
          linesFallbackBuyPrice: 0,
          linesZeroCost: 0,
          available: true,
        );
      }
      final r = rows.first;
      final revenue = (r['revenue'] as num?)?.toDouble() ?? 0.0;
      final cost = (r['cost'] as num?)?.toDouble() ?? 0.0;
      final total = (r['totalLines'] as num?)?.toInt() ?? 0;
      final stamped = (r['stamped'] as num?)?.toInt() ?? 0;
      final fb = (r['fallback'] as num?)?.toInt() ?? 0;
      final zc = (r['zeroCost'] as num?)?.toInt() ?? 0;
      final gross = revenue - cost;
      return MarginStats(
        revenueNet: revenue,
        cost: cost,
        grossMargin: gross,
        expenses: expensesTotal,
        netProfit: gross - expensesTotal,
        marginPct: revenue > 0 ? (gross / revenue) * 100.0 : null,
        totalLines: total,
        linesStamped: stamped,
        linesFallbackBuyPrice: fb,
        linesZeroCost: zc,
        available: true,
      );
    } catch (_) {
      return MarginStats(
        revenueNet: 0,
        cost: 0,
        grossMargin: 0,
        expenses: expensesTotal,
        netProfit: -expensesTotal,
        marginPct: null,
        totalLines: 0,
        linesStamped: 0,
        linesFallbackBuyPrice: 0,
        linesZeroCost: 0,
        available: false,
      );
    }
  }

  /// سلسلة يومية للهامش (إيراد، تكلفة) — تستخدم نفس منطق _marginStats
  /// (توزيع الخصم + معالجة المرتجعات + سلسلة Fallback للتكلفة).
  Future<List<DailyMarginPoint>> _dailyMargin(
    Database db,
    String from,
    String to,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          substr(inv.date, 1, 10) AS d,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            (
              ii.total -
              CASE WHEN IFNULL(t.gross, 0) > 0
                   THEN ii.total * (IFNULL(inv.discount, 0) + IFNULL(inv.loyaltyDiscount, 0)) / t.gross
                   ELSE 0
              END
            )
          ), 0) AS revenue,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            CASE
              WHEN ii.unitCost IS NOT NULL THEN ii.unitCost * ii.quantity
              WHEN p.buyPrice IS NOT NULL   THEN p.buyPrice * ii.quantity
              ELSE 0
            END
          ), 0) AS cost
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        LEFT JOIN products p ON p.id = ii.productId
        LEFT JOIN (
          SELECT invoiceId, SUM(total) AS gross
          FROM invoice_items
          GROUP BY invoiceId
        ) t ON t.invoiceId = inv.id
        WHERE inv.$_salesTypeInSql
          AND inv.date >= ? AND inv.date <= ?
        GROUP BY substr(inv.date, 1, 10)
        ORDER BY d ASC
        ''',
        [from, to],
      );
      return rows
          .map(
            (r) => DailyMarginPoint(
              dayLabel: r['d']?.toString() ?? '',
              revenue: (r['revenue'] as num?)?.toDouble() ?? 0.0,
              cost: (r['cost'] as num?)?.toDouble() ?? 0.0,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// أعلى/أدنى المنتجات هامشاً — نعيد كل المنتجات في الفترة ويُرتّب في الـ UI.
  Future<List<ProductMarginRow>> _productMargins(
    Database db,
    String from,
    String to,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          ii.productId AS pid,
          COALESCE(NULLIF(TRIM(ii.productName), ''), p.name, '(بدون اسم)') AS name,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) * ii.quantity
          ), 0) AS qty,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            (
              ii.total -
              CASE WHEN IFNULL(t.gross, 0) > 0
                   THEN ii.total * (IFNULL(inv.discount, 0) + IFNULL(inv.loyaltyDiscount, 0)) / t.gross
                   ELSE 0
              END
            )
          ), 0) AS revenue,
          COALESCE(SUM(
            (CASE WHEN IFNULL(inv.isReturned, 0) = 0 THEN 1 ELSE -1 END) *
            CASE
              WHEN ii.unitCost IS NOT NULL THEN ii.unitCost * ii.quantity
              WHEN p.buyPrice IS NOT NULL   THEN p.buyPrice * ii.quantity
              ELSE 0
            END
          ), 0) AS cost
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        LEFT JOIN products p ON p.id = ii.productId
        LEFT JOIN (
          SELECT invoiceId, SUM(total) AS gross
          FROM invoice_items
          GROUP BY invoiceId
        ) t ON t.invoiceId = inv.id
        WHERE inv.$_salesTypeInSql
          AND inv.date >= ? AND inv.date <= ?
        GROUP BY ii.productId, name
        HAVING ABS(revenue) > 0.0001 OR ABS(cost) > 0.0001
        ORDER BY (revenue - cost) DESC
        LIMIT 200
        ''',
        [from, to],
      );
      return rows
          .map(
            (r) => ProductMarginRow(
              productId: (r['pid'] as num?)?.toInt(),
              name: r['name']?.toString() ?? '',
              qty: (r['qty'] as num?)?.toDouble() ?? 0.0,
              revenue: (r['revenue'] as num?)?.toDouble() ?? 0.0,
              cost: (r['cost'] as num?)?.toDouble() ?? 0.0,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<(double redeemed, double earned)> _loyaltyInvoiceTotals(
    Database db,
    String from,
    String to,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(loyaltyDiscount), 0) AS r,
               COALESCE(SUM(loyaltyPointsEarned), 0) AS e
        FROM invoices
        WHERE IFNULL(isReturned, 0) = 0
          AND $_salesTypeInSql
          AND date >= ? AND date <= ?
        ''',
        [from, to],
      );
      if (rows.isEmpty) return (0.0, 0.0);
      final r = (rows.first['r'] as num?)?.toDouble() ?? 0;
      final e = (rows.first['e'] as num?)?.toDouble() ?? 0;
      return (r, e);
    } catch (_) {
      return (0.0, 0.0);
    }
  }
}
