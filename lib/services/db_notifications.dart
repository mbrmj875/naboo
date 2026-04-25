part of 'database_helper.dart';

// ── إشعارات لوحة التحكم (استعلامات مباشرة من القاعدة) ─────────────────

extension DbNotifications on DatabaseHelper {
  /// منتجات نشطة بمخزون منخفض أو منفد (مع تتبع مخزون).
  Future<List<Map<String, dynamic>>> getProductsForLowStockNotifications({
    required int tenantId,
    int limit = 100,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT id, name, qty, lowStockThreshold, stockBaseKind
      FROM products
      WHERE tenantId = ? AND isActive = 1 AND IFNULL(trackInventory, 1) = 1
        AND (
          qty <= 0
          OR (IFNULL(lowStockThreshold, 0) > 0 AND qty <= lowStockThreshold)
          OR (
            IFNULL(stockBaseKind, 0) = 1
            AND IFNULL(lowStockThreshold, 0) <= 0
            AND qty > 0
            AND qty < 1
          )
        )
      ORDER BY qty ASC, name COLLATE NOCASE ASC
      LIMIT ?
    ''',
      [tenantId, limit],
    );
  }

  /// منتجات لها تاريخ صلاحية مسجّل.
  Future<List<Map<String, dynamic>>> getProductsWithExpiryForNotifications({
    required int tenantId,
    int limit = 80,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT id, name, expiryDate, qty, expiryAlertDaysBefore
      FROM products
      WHERE tenantId = ?
        AND isActive = 1
        AND expiryDate IS NOT NULL
        AND TRIM(expiryDate) != ''
      ORDER BY expiryDate ASC, name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [tenantId, limit],
    );
  }

  /// أقساط غير مدفوعة تجاوزت تاريخ الاستحقاق (مقارنة تاريخية YYYY-MM-DD بالتوقيت المحلي).
  Future<List<Map<String, dynamic>>> getOverdueInstallmentsForNotifications({
    required int tenantId,
    int limit = 40,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT i.id AS instId, i.planId, i.dueDate, i.amount,
             IFNULL(p.customerName, '') AS customerName
      FROM installments i
      INNER JOIN installment_plans p ON p.id = i.planId
      LEFT JOIN invoices inv ON inv.id = p.invoiceId
      LEFT JOIN customers c ON c.id = p.customerId
      WHERE i.paid = 0
        AND IFNULL(inv.tenantId, c.tenantId) = ?
        AND substr(trim(i.dueDate), 1, 10) < date('now', 'localtime')
      ORDER BY substr(trim(i.dueDate), 1, 10) ASC, i.dueDate ASC
      LIMIT ?
    ''',
      [tenantId, limit],
    );
  }

  /// أقساط غير مدفوعة مستحقة خلال الأيام القادمة (شامِل اليوم؛ بالتوقيت المحلي).
  Future<List<Map<String, dynamic>>> getUpcomingInstallmentsForNotifications({
    required int tenantId,
    int withinDays = 14,
    int limit = 40,
  }) async {
    final db = await database;
    final d = withinDays.clamp(1, 366);
    return db.rawQuery(
      '''
      SELECT i.id AS instId, i.planId, i.dueDate, i.amount,
             IFNULL(p.customerName, '') AS customerName
      FROM installments i
      INNER JOIN installment_plans p ON p.id = i.planId
      LEFT JOIN invoices inv ON inv.id = p.invoiceId
      LEFT JOIN customers c ON c.id = p.customerId
      WHERE i.paid = 0
        AND IFNULL(inv.tenantId, c.tenantId) = ?
        AND substr(trim(i.dueDate), 1, 10) >= date('now', 'localtime')
        AND substr(trim(i.dueDate), 1, 10) <= date('now', 'localtime', '+$d days')
      ORDER BY substr(trim(i.dueDate), 1, 10) ASC, i.dueDate ASC
      LIMIT ?
    ''',
      [tenantId, limit],
    );
  }

  /// عملاء عليهم رصيد مدين (آجل) ضمن المستأجر النشط.
  Future<List<Map<String, dynamic>>> getCustomersWithDebtForNotifications({
    required int tenantId,
    int limit = 80,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT id, name, phone, balance
      FROM customers
      WHERE tenantId = ? AND balance > 1e-6
      ORDER BY balance DESC, name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [tenantId, limit],
    );
  }

  /// فواتير مرتجعة حديثاً.
  Future<List<Map<String, dynamic>>> getRecentReturnInvoicesForNotifications({
    required int tenantId,
    int limit = 25,
    int withinDays = 21,
  }) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    return db.query(
      'invoices',
      columns: ['id', 'customerName', 'date', 'total', 'originalInvoiceId'],
      where: 'tenantId = ? AND IFNULL(isReturned, 0) = 1 AND date >= ?',
      whereArgs: [tenantId, cutoff],
      orderBy: 'date DESC',
      limit: limit,
    );
  }

  /// فواتير «دين / آجل» المفتوحة التي تجاوزت [warnAgeDays] يوماً تقويمياً على تاريخ الفاتورة
  /// (نفس منطق [CreditDebtInvoice.daysSinceInvoice] وإعدادات الدين).
  Future<List<Map<String, dynamic>>> getAgedOpenCreditDebtInvoicesForNotifications({
    required int tenantId,
    required int warnAgeDays,
    int limit = 60,
  }) async {
    if (warnAgeDays <= 0) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT i.id,
             IFNULL(i.customerName, '') AS customerName,
             i.date,
             CAST(
               (julianday(date('now', 'localtime')) - julianday(date(trim(i.date))))
               AS INTEGER
             ) AS ageDays
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND (i.total - IFNULL(i.advancePayment, 0)) > 0.009
        AND CAST(
          (julianday(date('now', 'localtime')) - julianday(date(trim(i.date))))
          AS INTEGER
        ) >= ?
      ORDER BY i.date ASC, i.id ASC
      LIMIT ?
      ''',
      [tenantId, t, warnAgeDays, limit],
    );
  }

  /// عملاء (بمعرّف) مجموع ديونهم الآجلة المفتوحة ≥ [customerCap] (د.ع).
  Future<List<Map<String, dynamic>>> getCreditDebtCustomerTotalCapBreaches({
    required int tenantId,
    required double customerCap,
    int limit = 40,
  }) async {
    if (customerCap <= 1e-9) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT i.customerId AS customerId,
             MAX(i.customerName) AS customerName,
             SUM(i.total - IFNULL(i.advancePayment, 0)) AS openTotal
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND i.customerId IS NOT NULL
        AND (i.total - IFNULL(i.advancePayment, 0)) > 0.009
      GROUP BY i.customerId
      HAVING SUM(i.total - IFNULL(i.advancePayment, 0)) >= ?
      ORDER BY openTotal DESC
      LIMIT ?
      ''',
      [tenantId, t, customerCap, limit],
    );
  }

  /// أطراف بدون customerId لكن بنفس الاسم — مجموع آجلها ≥ [customerCap].
  Future<List<Map<String, dynamic>>> getCreditDebtUnlinkedNameCapBreaches({
    required int tenantId,
    required double customerCap,
    int limit = 40,
  }) async {
    if (customerCap <= 1e-9) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT LOWER(TRIM(i.customerName)) AS nameKey,
             MIN(i.customerName) AS customerName,
             SUM(i.total - IFNULL(i.advancePayment, 0)) AS openTotal
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND i.customerId IS NULL
        AND LENGTH(TRIM(IFNULL(i.customerName, ''))) > 0
        AND (i.total - IFNULL(i.advancePayment, 0)) > 0.009
      GROUP BY LOWER(TRIM(i.customerName))
      HAVING SUM(i.total - IFNULL(i.advancePayment, 0)) >= ?
      ORDER BY openTotal DESC
      LIMIT ?
      ''',
      [tenantId, t, customerCap, limit],
    );
  }

  /// فواتير دين مفتوحة متبقياتها ≥ [perInvoiceCap] (د.ع).
  Future<List<Map<String, dynamic>>> getCreditDebtInvoiceCapBreaches({
    required int tenantId,
    required double perInvoiceCap,
    int limit = 60,
  }) async {
    if (perInvoiceCap <= 1e-9) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT i.id,
             IFNULL(i.customerName, '') AS customerName,
             i.date,
             (i.total - IFNULL(i.advancePayment, 0)) AS remaining
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND (i.total - IFNULL(i.advancePayment, 0)) > 0.009
        AND (i.total - IFNULL(i.advancePayment, 0)) >= ?
      ORDER BY remaining DESC, i.date ASC
      LIMIT ?
      ''',
      [tenantId, t, perInvoiceCap, limit],
    );
  }

  /// إجمالي مبيعات اليوم (فواتير بيع فعلية، بدون مرتجعات).
  Future<double> getTodaySalesTotalForNotifications({
    required int tenantId,
  }) async {
    final db = await database;
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day).toIso8601String();
    final end = DateTime(
      n.year,
      n.month,
      n.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(total), 0) AS s FROM invoices
      WHERE tenantId = ?
        AND IFNULL(isReturned, 0) = 0 AND date >= ? AND date <= ?
      ''',
      [tenantId, start, end],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }
}
