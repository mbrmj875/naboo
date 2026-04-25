part of 'database_helper.dart';

// ── التقارير ولوحة التحكم ─────────────────────────────────────────────────

extension DbReports on DatabaseHelper {
  /// سلسلة أيام حديثة للوحة الرئيسية (المبيعات / الإيرادات / المصروفات).
  Future<Map<String, dynamic>> getDashboardSalesExpenseSeries({
    int days = 7,
  }) async {
    final db = await database;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final startDay = today.subtract(Duration(days: days - 1));
    final start = startDay.toIso8601String();
    final end = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();

    final salesRows = await db.rawQuery(
      '''
      SELECT substr(date, 1, 10) AS d, IFNULL(SUM(total), 0) AS v
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND datetime(date) >= datetime(?)
        AND datetime(date) <= datetime(?)
      GROUP BY substr(date, 1, 10)
      ORDER BY d ASC
      ''',
      [start, end],
    );
    final expenseRows = await db.rawQuery(
      '''
      SELECT substr(createdAt, 1, 10) AS d, IFNULL(SUM(ABS(amount)), 0) AS v
      FROM cash_ledger
      WHERE amount < 0
        AND datetime(createdAt) >= datetime(?)
        AND datetime(createdAt) <= datetime(?)
      GROUP BY substr(createdAt, 1, 10)
      ORDER BY d ASC
      ''',
      [start, end],
    );

    final salesByDay = <String, double>{
      for (final r in salesRows)
        (r['d']?.toString() ?? ''): (r['v'] as num?)?.toDouble() ?? 0,
    };
    final expenseByDay = <String, double>{
      for (final r in expenseRows)
        (r['d']?.toString() ?? ''): (r['v'] as num?)?.toDouble() ?? 0,
    };

    final dayKeys = <String>[];
    final sales = <double>[];
    final income = <double>[];
    final expense = <double>[];
    for (var i = 0; i < days; i++) {
      final d = startDay.add(Duration(days: i));
      final key = d.toIso8601String().substring(0, 10);
      final s = salesByDay[key] ?? 0;
      final e = expenseByDay[key] ?? 0;
      dayKeys.add(key);
      sales.add(s);
      income.add(s);
      expense.add(e);
    }

    return {
      'dayKeys': dayKeys,
      'sales': sales,
      'income': income,
      'expense': expense,
      'totalSales': sales.fold<double>(0, (a, b) => a + b),
      'totalExpense': expense.fold<double>(0, (a, b) => a + b),
    };
  }

  /// عدد قوائم البيع المنجزة ضمن الوردية الحالية/الأخيرة.
  Future<Map<String, dynamic>> getShiftCompletedSalesInvoicesStat() async {
    final db = await database;
    final shiftRows = await db.rawQuery('''
      SELECT id, openedAt, closedAt
      FROM work_shifts
      ORDER BY datetime(COALESCE(closedAt, openedAt)) DESC
      LIMIT 2
      ''');
    if (shiftRows.isEmpty) {
      return {
        'hasShift': false,
        'shiftId': null,
        'salesInvoicesCount': 0,
        'currentShiftSalesTotal': 0.0,
        'previousShiftSalesTotal': 0.0,
        'diffPercent': 0.0,
        'isPositive': true,
        'openedAt': null,
        'closedAt': null,
      };
    }
    final currentShift = shiftRows.first;
    final shiftId = currentShift['id'] as int;
    final openedAt = currentShift['openedAt']?.toString();
    final closedAt = currentShift['closedAt']?.toString();
    final previousShiftId = shiftRows.length > 1
        ? (shiftRows[1]['id'] as int?)
        : null;

    final countRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM invoices
      WHERE IFNULL(isReturned, 0) = 0
        AND type IN (0, 1, 2, 3)
        AND workShiftId = ?
      ''',
      [shiftId],
    );
    final c = (countRows.first['c'] as num?)?.toInt() ?? 0;

    Future<double> sumShiftSalesTotal(int sid) async {
      final rows = await db.rawQuery(
        '''
        SELECT IFNULL(SUM(total), 0) AS s
        FROM invoices
        WHERE IFNULL(isReturned, 0) = 0
          AND type IN (0, 1, 2, 3)
          AND workShiftId = ?
        ''',
        [sid],
      );
      return (rows.first['s'] as num?)?.toDouble() ?? 0;
    }

    final currentTotal = await sumShiftSalesTotal(shiftId);
    final previousTotal = previousShiftId == null
        ? 0.0
        : await sumShiftSalesTotal(previousShiftId);
    final diff = currentTotal - previousTotal;
    final isPositive = diff >= 0;
    final pct = previousTotal == 0
        ? (currentTotal > 0 ? 100.0 : 0.0)
        : (diff / previousTotal) * 100.0;

    return {
      'hasShift': true,
      'shiftId': shiftId,
      'salesInvoicesCount': c,
      'currentShiftSalesTotal': currentTotal,
      'previousShiftSalesTotal': previousTotal,
      'diffPercent': pct,
      'isPositive': isPositive,
      'openedAt': openedAt,
      'closedAt': closedAt,
    };
  }

  /// دمج أنشطة حديثة من عدة جداول — مرتّب زمنياً للوحة التحكم.
  Future<List<RecentActivityEntry>> getRecentActivityFeed({
    int perSource = 120,
    int maxTotal = 280,
  }) async {
    final db = await database;
    final futures = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      db.rawQuery(
        '''
      SELECT id, customerName, total, type, date, isReturned, createdByUserName
      FROM invoices
      ORDER BY datetime(date) DESC
      LIMIT ?
      ''',
        [perSource],
      ),
      db.rawQuery(
        '''
      SELECT id, transactionType, amount, description, invoiceId, createdAt
      FROM cash_ledger
      WHERE NOT (
        invoiceId IS NOT NULL AND transactionType IN (
          'sale_cash', 'sale_advance', 'sale_other',
          'installment_payment', 'sale_return'
        )
      )
      ORDER BY datetime(createdAt) DESC
      LIMIT ?
      ''',
        [perSource],
      ),
      db.rawQuery(
        '''
      SELECT id, title, updatedAt, createdAt
      FROM parked_sales
      ORDER BY datetime(updatedAt) DESC
      LIMIT ?
      ''',
        [perSource],
      ),
      db.rawQuery(
        '''
      SELECT l.id, l.customerId, l.invoiceId, l.kind, l.points, l.balanceAfter,
             l.note, l.createdAt, c.name AS customerName
      FROM loyalty_ledger l
      LEFT JOIN customers c ON c.id = l.customerId
      ORDER BY datetime(l.createdAt) DESC
      LIMIT ?
      ''',
        [perSource],
      ),
      db.rawQuery(
        '''
      SELECT id, voucherNo, voucherType, voucherDate, notes, createdAt
      FROM stock_vouchers
      ORDER BY datetime(createdAt) DESC
      LIMIT ?
      ''',
        [80],
      ),
      db.rawQuery(
        '''
      SELECT id, name, createdAt
      FROM customers
      ORDER BY datetime(createdAt) DESC
      LIMIT ?
      ''',
        [60],
      ),
      db.rawQuery(
        '''
      SELECT id, name, createdAt
      FROM products
      ORDER BY datetime(createdAt) DESC
      LIMIT ?
      ''',
        [60],
      ),
      db.rawQuery(
        '''
      SELECT id, shiftStaffName, openedAt, closedAt
      FROM work_shifts
      ORDER BY datetime(COALESCE(closedAt, openedAt)) DESC
      LIMIT ?
      ''',
        [50],
      ),
    ]);
    final invRows = futures[0];
    final cashRows = futures[1];
    final parkedRows = futures[2];
    final loyaltyRows = futures[3];
    final voucherRows = futures[4];
    final customerRows = futures[5];
    final productRows = futures[6];
    final shiftRows = futures[7];

    final out = <RecentActivityEntry>[
      for (final r in invRows) RecentActivityEntry.fromInvoiceRow(r),
      for (final r in cashRows) RecentActivityEntry.fromCashRow(r),
      for (final r in parkedRows) RecentActivityEntry.fromParkedRow(r),
      for (final r in loyaltyRows) RecentActivityEntry.fromLoyaltyRow(r),
      for (final r in voucherRows) RecentActivityEntry.fromStockVoucherRow(r),
      for (final r in customerRows)
        RecentActivityEntry.fromCustomerCreatedRow(r),
      for (final r in productRows)
        RecentActivityEntry.fromProductCreatedRow(r),
    ];

    for (final r in shiftRows) {
      final open = r['openedAt']?.toString();
      final close = r['closedAt']?.toString();
      if (open != null && open.isNotEmpty) {
        out.add(RecentActivityEntry.fromWorkShiftRow(r, isClose: false));
      }
      if (close != null && close.isNotEmpty) {
        out.add(RecentActivityEntry.fromWorkShiftRow(r, isClose: true));
      }
    }

    out.sort((a, b) => b.at.compareTo(a.at));
    if (out.length <= maxTotal) return out;
    return out.sublist(0, maxTotal);
  }
}
