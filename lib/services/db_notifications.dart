part of 'database_helper.dart';

// ── إشعارات لوحة التحكم (استعلامات مباشرة من القاعدة) ─────────────────
int _notifToFils(double value) => (value * 1000).round();

extension DbNotifications on DatabaseHelper {
  static const String _lowStockProductsWhere = '''
    tenantId = ? AND isActive = 1 AND IFNULL(trackInventory, 1) = 1
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
  ''';

  /// عدد الأصناف الناقصة — COUNT كامل دون حد [LIMIT].
  Future<int> countProductsForLowStockNotifications({
    required int tenantId,
    int? stockBaseKind,
  }) async {
    final db = await database;
    final args = <Object?>[tenantId];
    var extra = '';
    if (stockBaseKind != null) {
      extra = ' AND IFNULL(stockBaseKind, 0) = ?';
      args.add(stockBaseKind);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM products
      WHERE $_lowStockProductsWhere$extra
      ''',
      args,
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// منتجات نشطة بمخزون منخفض أو منفد (مع تتبع مخزون).
  Future<List<Map<String, dynamic>>> getProductsForLowStockNotifications({
    required int tenantId,
    int limit = 100,
    int? stockBaseKind,
  }) async {
    final db = await database;
    final args = <Object?>[tenantId];
    var extra = '';
    if (stockBaseKind != null) {
      extra = ' AND IFNULL(stockBaseKind, 0) = ?';
      args.add(stockBaseKind);
    }
    args.add(limit);
    return db.rawQuery(
      '''
      SELECT id, name, qty, lowStockThreshold, stockBaseKind
      FROM products
      WHERE $_lowStockProductsWhere$extra
      ORDER BY qty ASC, name COLLATE NOCASE ASC
      LIMIT ?
    ''',
      args,
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
      WHERE tenantId = ? AND ROUND(balance * 1000) > 0
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
        AND ${MoneySql.invoiceOpenRemainingFilsOf('i')} > 0
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
    final customerCapFils = _notifToFils(customerCap);
    if (customerCapFils <= 0) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT i.customerId AS customerId,
             MAX(i.customerName) AS customerName,
             SUM(${MoneySql.invoiceOpenRemainingFilsOf('i')}) AS openTotalFils
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND i.customerId IS NOT NULL
        AND ${MoneySql.invoiceOpenRemainingFilsOf('i')} > 0
      GROUP BY i.customerId
      HAVING SUM(${MoneySql.invoiceOpenRemainingFilsOf('i')}) >= ?
      ORDER BY openTotalFils DESC
      LIMIT ?
      ''',
      [tenantId, t, customerCapFils, limit],
    );
  }

  /// أطراف بدون customerId لكن بنفس الاسم — مجموع آجلها ≥ [customerCap].
  Future<List<Map<String, dynamic>>> getCreditDebtUnlinkedNameCapBreaches({
    required int tenantId,
    required double customerCap,
    int limit = 40,
  }) async {
    final customerCapFils = _notifToFils(customerCap);
    if (customerCapFils <= 0) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT LOWER(TRIM(i.customerName)) AS nameKey,
             MIN(i.customerName) AS customerName,
             SUM(${MoneySql.invoiceOpenRemainingFilsOf('i')}) AS openTotalFils
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND i.customerId IS NULL
        AND LENGTH(TRIM(IFNULL(i.customerName, ''))) > 0
        AND ${MoneySql.invoiceOpenRemainingFilsOf('i')} > 0
      GROUP BY LOWER(TRIM(i.customerName))
      HAVING SUM(${MoneySql.invoiceOpenRemainingFilsOf('i')}) >= ?
      ORDER BY openTotalFils DESC
      LIMIT ?
      ''',
      [tenantId, t, customerCapFils, limit],
    );
  }

  /// فواتير دين مفتوحة متبقياتها ≥ [perInvoiceCap] (د.ع).
  Future<List<Map<String, dynamic>>> getCreditDebtInvoiceCapBreaches({
    required int tenantId,
    required double perInvoiceCap,
    int limit = 60,
  }) async {
    final perInvoiceCapFils = _notifToFils(perInvoiceCap);
    if (perInvoiceCapFils <= 0) return [];
    final db = await database;
    final t = InvoiceType.credit.index;
    return db.rawQuery(
      '''
      SELECT i.id,
             IFNULL(i.customerName, '') AS customerName,
             i.date,
             CAST(${MoneySql.invoiceOpenRemainingFilsOf('i')} AS REAL) / 1000.0 AS remaining
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND ${MoneySql.invoiceOpenRemainingFilsOf('i')} > 0
        AND ${MoneySql.invoiceOpenRemainingFilsOf('i')} >= ?
      ORDER BY remaining DESC, i.date ASC
      LIMIT ?
      ''',
      [tenantId, t, perInvoiceCapFils, limit],
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
      SELECT COALESCE(SUM(${MoneySql.invoiceTotalFils}), 0) AS s_fils
      FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND IFNULL(isReturned, 0) = 0
        AND date >= ? AND date <= ?
      ''',
      [tenantId, start, end],
    );
    if (rows.isEmpty) return 0;
    return ((rows.first['s_fils'] as num?)?.toInt() ?? 0) / 1000.0;
  }
}
