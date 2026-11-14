part of 'database_helper.dart';

// ── الديون الآجلة وتسديد العملاء ─────────────────────────────────────────
//
// Step 5 (tenant isolation):
// Every read/write goes through [TenantContext.requireTenantId] before
// touching SQLite, and every SQL statement carries `tenantId = ?` so the
// active session can never observe rows belonging to another tenant on the
// same device. The pure SQL is extracted into [DbDebtsSqlOps] so unit tests
// can drive it against an in-memory FFI database without instantiating the
// production [DatabaseHelper] singleton.

CreditDebtInvoice _creditDebtInvoiceFromRow(Map<String, dynamic> r) {
  return CreditDebtInvoice(
    invoiceId: r['id'] as int,
    customerName: (r['customerName'] as String?)?.trim() ?? '',
    customerId: r['customerId'] as int?,
    date: DateTime.parse(r['date'] as String),
    total: (r['total'] as num).toDouble(),
    advancePayment: (r['advancePayment'] as num?)?.toDouble() ?? 0,
    totalFils: (r['totalFils'] as num?)?.toInt(),
    advancePaymentFils: (r['advancePaymentFils'] as num?)?.toInt(),
  );
}

double _openRemainingForCreditDebtRow(Map<String, dynamic> r) {
  final totalFils = (r['totalFils'] as num?)?.toInt();
  final advFils = (r['advancePaymentFils'] as num?)?.toInt();
  if (totalFils != null || advFils != null) {
    final remFils = max(0, (totalFils ?? 0) - (advFils ?? 0));
    return remFils / 1000.0;
  }
  final tot = (r['total'] as num).toDouble();
  final adv = (r['advancePayment'] as num?)?.toDouble() ?? 0;
  return max(0.0, tot - adv);
}

int _toFils(num amount) => (amount.toDouble() * 1000).round();
double _fromFils(int fils) => fils / 1000.0;

/// Pure SQL operations for the credit-debt domain, parameterised over
/// `tenantId` so they can be covered by unit tests with the in-memory schema
/// in `test/helpers/in_memory_db.dart`. Production callers must always go
/// through the [DbDebts] extension on [DatabaseHelper], which gates each call
/// on [TenantContext.requireTenantId] before invoking these helpers.
@visibleForTesting
class DbDebtsSqlOps {
  DbDebtsSqlOps._();

  static Future<List<CreditDebtInvoice>> getNonReturnedCreditInvoices(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date,
             total, advancePayment, totalFils, advancePaymentFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
      ORDER BY date DESC
      ''',
      [tenantId, t],
    );
    return rows.map(_creditDebtInvoiceFromRow).toList();
  }

  static Future<List<CreditDebtInvoice>> getOpenCreditDebtInvoices(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date,
             total, advancePayment, totalFils, advancePaymentFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
      ORDER BY date DESC
      ''',
      [tenantId, t],
    );
    return rows.map(_creditDebtInvoiceFromRow).toList();
  }

  static Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForCustomerId(
    DatabaseExecutor db,
    int tenantId,
    int customerId,
  ) async {
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date,
             total, advancePayment, totalFils, advancePaymentFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId = ?
      ORDER BY date DESC
      ''',
      [tenantId, t, customerId],
    );
    return rows.map(_creditDebtInvoiceFromRow).toList();
  }

  static Future<double> sumOpenCreditDebtForCustomer(
    DatabaseExecutor db,
    int tenantId,
    int customerId,
  ) async {
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(
        ${MoneySql.invoiceOpenRemainingFils}
      ), 0) AS sFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId = ?
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
      ''',
      [tenantId, t, customerId],
    );
    final sFils = (rows.first['sFils'] as num?)?.toInt() ?? 0;
    return sFils / 1000.0;
  }

  static Future<double> sumOpenCreditDebtForUnlinkedCustomerName(
    DatabaseExecutor db,
    int tenantId,
    String rawName,
  ) async {
    final n = rawName.trim().toLowerCase();
    if (n.isEmpty) return 0;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(
        ${MoneySql.invoiceOpenRemainingFils}
      ), 0) AS sFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
      ''',
      [tenantId, t, n],
    );
    final sFils = (rows.first['sFils'] as num?)?.toInt() ?? 0;
    return sFils / 1000.0;
  }

  /// ملخص الديون المفتوحة — نفس مصدر [DebtsScreen] (فواتير آجل − المقدّم).
  static Future<({double totalOpen, int debtorCount})> summarizeOpenCreditDebt(
    DatabaseExecutor db,
    int tenantId, {
    String? staffName,
  }) async {
    final t = InvoiceType.credit.index;
    var sql = '''
      SELECT
        COALESCE(SUM(
          ${MoneySql.invoiceOpenRemainingFils}
        ), 0) AS totalOpenFils,
        COUNT(DISTINCT COALESCE(
          CASE WHEN customerId IS NOT NULL AND customerId > 0
            THEN 'id:' || customerId
            ELSE 'name:' || LOWER(TRIM(customerName))
          END,
          'unknown'
        )) AS debtorCount
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
    ''';
    final args = <Object?>[tenantId, t];
    if (staffName != null && staffName.trim().isNotEmpty) {
      sql += ' AND TRIM(COALESCE(createdByUserName, "")) = ?';
      args.add(staffName.trim());
    }
    final rows = await db.rawQuery(sql, args);
    final row = rows.first;
    final totalOpenFils = (row['totalOpenFils'] as num?)?.toInt() ?? 0;
    return (
      totalOpen: totalOpenFils / 1000.0,
      debtorCount: (row['debtorCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<Map<String, dynamic>>>
      queryOpenCreditInvoiceMapsForParty(
    DatabaseExecutor ex,
    int tenantId,
    CustomerDebtParty party,
  ) async {
    final t = InvoiceType.credit.index;
    if (party.customerId != null) {
      return ex.rawQuery(
        '''
        SELECT id, customerName, total, advancePayment,
               totalFils, advancePaymentFils, date
        FROM invoices
        WHERE tenantId = ?
          AND type = ?
          AND IFNULL(isReturned, 0) = 0
          AND deleted_at IS NULL
          AND customerId = ?
          AND (
            ${MoneySql.invoiceOpenRemainingFils}
          ) > 0
        ORDER BY date ASC, id ASC
        ''',
        [tenantId, t, party.customerId],
      );
    }
    return ex.rawQuery(
      '''
      SELECT id, customerName, total, advancePayment,
             totalFils, advancePaymentFils, date
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
      ORDER BY date ASC, id ASC
      ''',
      [tenantId, t, party.normalizedName],
    );
  }

  static Future<List<CustomerDebtLineItem>> getCustomerDebtLineItems(
    DatabaseExecutor db,
    int tenantId,
    CustomerDebtParty party,
  ) async {
    final t = InvoiceType.credit.index;
    final List<Map<String, dynamic>> rows;
    if (party.customerId != null) {
      rows = await db.rawQuery(
        '''
        SELECT ii.productName, ii.quantity, ii.price, ii.total AS lineTotal,
               i.id AS invoiceId, i.date AS invDate, i.createdByUserName
        FROM invoice_items ii
        INNER JOIN invoices i ON i.id = ii.invoiceId
        WHERE i.tenantId = ?
          AND i.type = ?
          AND IFNULL(i.isReturned, 0) = 0
          AND i.deleted_at IS NULL
          AND ii.deleted_at IS NULL
          AND i.customerId = ?
        ORDER BY i.date DESC, ii.id ASC
        ''',
        [tenantId, t, party.customerId],
      );
    } else {
      rows = await db.rawQuery(
        '''
        SELECT ii.productName, ii.quantity, ii.price, ii.total AS lineTotal,
               i.id AS invoiceId, i.date AS invDate, i.createdByUserName
        FROM invoice_items ii
        INNER JOIN invoices i ON i.id = ii.invoiceId
        WHERE i.tenantId = ?
          AND i.type = ?
          AND IFNULL(i.isReturned, 0) = 0
          AND i.deleted_at IS NULL
          AND ii.deleted_at IS NULL
          AND i.customerId IS NULL
          AND LOWER(TRIM(i.customerName)) = ?
        ORDER BY i.date DESC, ii.id ASC
        ''',
        [tenantId, t, party.normalizedName],
      );
    }
    return rows
        .map(
          (r) => CustomerDebtLineItem(
            invoiceId: r['invoiceId'] as int,
            invoiceDate: DateTime.parse(r['invDate'] as String),
            productName: (r['productName'] as String?)?.trim() ?? '',
            quantity: (r['quantity'] as num?)?.toInt() ?? 0,
            unitPrice: (r['price'] as num?)?.toDouble() ?? 0,
            lineTotal: (r['lineTotal'] as num?)?.toDouble() ?? 0,
            sellerName: r['createdByUserName'] as String?,
          ),
        )
        .toList();
  }

  static Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForParty(
    DatabaseExecutor db,
    int tenantId,
    CustomerDebtParty party,
  ) async {
    final t = InvoiceType.credit.index;
    final List<Map<String, dynamic>> rows;
    if (party.customerId != null) {
      rows = await db.rawQuery(
        '''
        SELECT id, customerName, customerId, date,
               total, advancePayment, totalFils, advancePaymentFils
        FROM invoices
        WHERE tenantId = ?
          AND type = ?
          AND IFNULL(isReturned, 0) = 0
          AND deleted_at IS NULL
          AND customerId = ?
        ORDER BY date DESC
        ''',
        [tenantId, t, party.customerId],
      );
    } else {
      rows = await db.rawQuery(
        '''
        SELECT id, customerName, customerId, date,
               total, advancePayment, totalFils, advancePaymentFils
        FROM invoices
        WHERE tenantId = ?
          AND type = ?
          AND IFNULL(isReturned, 0) = 0
          AND deleted_at IS NULL
          AND customerId IS NULL
          AND LOWER(TRIM(customerName)) = ?
        ORDER BY date DESC
        ''',
        [tenantId, t, party.normalizedName],
      );
    }
    return rows.map(_creditDebtInvoiceFromRow).toList();
  }

  /// Applies a payment to a single invoice. The `tenantId = ?` predicate is
  /// what enforces cross-tenant safety: an attempt to update an invoice that
  /// belongs to a different tenant returns 0 rows affected. Soft-deleted
  /// invoices are also blocked — paying onto a tombstoned row would silently
  /// resurrect it from the user's perspective.
  static Future<int> applyPaymentToInvoice(
    DatabaseExecutor txn,
    int tenantId,
    int invoiceId,
    int newAdvancePaymentFils,
  ) {
    final newAdvancePayment = _fromFils(newAdvancePaymentFils);
    return txn.update(
      'invoices',
      {
        'advancePayment': newAdvancePayment,
        'advancePaymentFils': newAdvancePaymentFils,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [invoiceId, tenantId],
    );
  }

  /// Inserts a debt-payment row, stamping `tenantId` from the active session
  /// regardless of whatever the caller provided.
  static Future<int> insertCustomerDebtPayment(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('customer_debt_payments', stamped);
  }
}

extension DbDebts on DatabaseHelper {
  Future<int> _activeTenantIdForDebts(Database db, String sessionTenant) async {
    return _resolveActiveTenantIdForLocalDb(db);
  }

  /// ترحيل آمن للبيانات التاريخية:
  /// يربط فواتير الدين غير المربوطة (`customerId IS NULL`) بالعميل عندما يكون
  /// الاسم مطابقاً بشكل فريد داخل نفس المستأجر.
  Future<void> _backfillLegacyCreditInvoiceCustomerIds(
    DatabaseExecutor ex,
    int tenantId, {
    String? normalizedName,
  }) async {
    final t = InvoiceType.credit.index;
    final uniqueNameToId = <String, int>{};
    final rows = await ex.rawQuery(
      '''
      SELECT LOWER(TRIM(name)) AS nk, MIN(id) AS cid, COUNT(*) AS c
      FROM customers
      WHERE tenantId = ?
        AND TRIM(name) != ''
      GROUP BY LOWER(TRIM(name))
      ''',
      [tenantId],
    );
    for (final r in rows) {
      final c = (r['c'] as num?)?.toInt() ?? 0;
      if (c != 1) continue;
      final nk = (r['nk'] ?? '').toString().trim();
      final cid = (r['cid'] as num?)?.toInt() ?? 0;
      if (nk.isEmpty || cid <= 0) continue;
      uniqueNameToId[nk] = cid;
    }
    if (uniqueNameToId.isEmpty) return;

    final args = <Object?>[tenantId, t];
    final sql = StringBuffer('''
      SELECT id, LOWER(TRIM(customerName)) AS nk
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND TRIM(customerName) != ''
    ''');
    if (normalizedName != null && normalizedName.trim().isNotEmpty) {
      sql.write(' AND LOWER(TRIM(customerName)) = ?');
      args.add(normalizedName.trim());
    }
    final invRows = await ex.rawQuery(sql.toString(), args);
    if (invRows.isEmpty) return;

    for (final r in invRows) {
      final invoiceId = (r['id'] as num?)?.toInt() ?? 0;
      final nk = (r['nk'] ?? '').toString().trim();
      final customerId = uniqueNameToId[nk];
      if (invoiceId <= 0 || customerId == null || customerId <= 0) continue;
      await ex.update(
        'invoices',
        {
          'customerId': customerId,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND tenantId = ? AND customerId IS NULL',
        whereArgs: [invoiceId, tenantId],
      );
    }
  }

  /// كل فواتير «دين / آجل» غير المرتجعة.
  Future<List<CreditDebtInvoice>> getAllNonReturnedCreditInvoices() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.getNonReturnedCreditInvoices(db, tid);
  }

  /// فواتير «دين / آجل» ذات متبقٍ > 0 (غير مرتجعة).
  Future<List<CreditDebtInvoice>> getOpenCreditDebtInvoices() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.getOpenCreditDebtInvoices(db, tid);
  }

  /// ملخص الديون المفتوحة للوحة المالك — نفس منطق [DebtsScreen].
  ///
  /// [tenantId] يُمرَّر من لوحة المالك (مصدره [TenantContextService]) لتجنّب
  /// الاعتماد على [TenantContext.requireTenantId] الذي قد يكون فارغاً بعد
  /// `lockSession()` رغم بقاء المستأجر النشط محلياً.
  Future<({double totalOpen, int debtorCount})>
      summarizeOpenCreditDebtForDashboard({
    String? staffName,
    int? tenantId,
  }) async {
    final db = await database;
    final tid = (tenantId != null && tenantId > 0)
        ? tenantId
        : await _activeTenantIdForDebts(
            db,
            TenantContext.instance.hasTenant
                ? TenantContext.instance.requireTenantId()
                : '',
          );
    return DbDebtsSqlOps.summarizeOpenCreditDebt(
      db,
      tid,
      staffName: staffName,
    );
  }

  /// كل فواتير «آجل» غير المرتجعة لعميل مسجّل (للعرض والربط بإيصال البيع).
  Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForCustomerId(
    int customerId,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.getCreditDebtInvoicesForCustomerId(
      db,
      tid,
      customerId,
    );
  }

  Future<double> sumOpenCreditDebtForCustomer(int customerId) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.sumOpenCreditDebtForCustomer(db, tid, customerId);
  }

  Future<double> sumOpenCreditDebtForUnlinkedCustomerName(
    String rawName,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.sumOpenCreditDebtForUnlinkedCustomerName(
      db,
      tid,
      rawName,
    );
  }

  /// تجميع ديون «آجل» حسب العميل (مسجّل أو باسم فقط).
  Future<List<CustomerDebtSummary>> getCustomerDebtSummaries() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _backfillLegacyCreditInvoiceCustomerIds(db, tid);
    final rows = await getAllNonReturnedCreditInvoices();
    final byId = <int, List<CreditDebtInvoice>>{};
    final byName = <String, List<CreditDebtInvoice>>{};
    for (final r in rows) {
      if (r.customerId != null) {
        byId.putIfAbsent(r.customerId!, () => []).add(r);
      } else {
        final k = r.customerName.trim().toLowerCase();
        final key = k.isEmpty ? '\u0000unnamed' : k;
        byName.putIfAbsent(key, () => []).add(r);
      }
    }
    final out = <CustomerDebtSummary>[];
    for (final e in byId.entries) {
      final list = e.value;
      final openFils = list.fold<int>(0, (s, x) => s + x.remainingFils);
      if (openFils <= 0) continue;
      DateTime? oldest;
      for (final x in list) {
        if (x.remainingFils <= 0) continue;
        oldest = oldest == null || x.date.isBefore(oldest) ? x.date : oldest;
      }
      final names = list
          .map((x) => x.customerName.trim())
          .where((s) => s.isNotEmpty);
      final display = names.isNotEmpty ? names.first : 'عميل #${e.key}';
      out.add(
        CustomerDebtSummary(
          customerId: e.key,
          displayName: display,
          openRemaining: openFils / 1000.0,
          invoiceCount: list.where((x) => x.remainingFils > 0).length,
          oldestInvoiceDate: oldest,
        ),
      );
    }
    for (final e in byName.entries) {
      final list = e.value;
      final openFils = list.fold<int>(0, (s, x) => s + x.remainingFils);
      if (openFils <= 0) continue;
      DateTime? oldest;
      for (final x in list) {
        if (x.remainingFils <= 0) continue;
        oldest = oldest == null || x.date.isBefore(oldest) ? x.date : oldest;
      }
      final display = list.first.customerName.trim().isEmpty
          ? 'عميل'
          : list.first.customerName.trim();
      out.add(
        CustomerDebtSummary(
          customerId: null,
          displayName: display,
          openRemaining: openFils / 1000.0,
          invoiceCount: list.where((x) => x.remainingFils > 0).length,
          oldestInvoiceDate: oldest,
        ),
      );
    }
    out.sort((a, b) => b.openRemaining.compareTo(a.openRemaining));
    return out;
  }

  Future<double> sumOpenCreditDebtForParty(CustomerDebtParty party) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _backfillLegacyCreditInvoiceCustomerIds(
      db,
      tid,
      normalizedName: party.customerId == null ? party.normalizedName : null,
    );
    final rows = await DbDebtsSqlOps.queryOpenCreditInvoiceMapsForParty(
      db,
      tid,
      party,
    );
    var s = 0.0;
    for (final r in rows) {
      s += _openRemainingForCreditDebtRow(r);
    }
    return s;
  }

  Future<List<CustomerDebtLineItem>> getCustomerDebtLineItems(
    CustomerDebtParty party,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _backfillLegacyCreditInvoiceCustomerIds(
      db,
      tid,
      normalizedName: party.customerId == null ? party.normalizedName : null,
    );
    return DbDebtsSqlOps.getCustomerDebtLineItems(db, tid, party);
  }

  Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForParty(
    CustomerDebtParty party,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _backfillLegacyCreditInvoiceCustomerIds(
      db,
      tid,
      normalizedName: party.customerId == null ? party.normalizedName : null,
    );
    return DbDebtsSqlOps.getCreditDebtInvoicesForParty(db, tid, party);
  }

  /// تسديد دفعة على ديون آجل: تخصيم FIFO على [advancePayment].
  Future<CustomerDebtPaymentResult?> recordCustomerDebtPayment({
    required CustomerDebtParty party,
    required double amount,
    required String recordedByUserName,
    String? note,
  }) async {
    final customerId = party.customerId;
    if (customerId == null || customerId <= 0) {
      throw StateError(
        'لا يمكن تسجيل تسديد دين بدون ربط العميل ببطاقته (customerId). '
        'اختر عميلاً مسجلاً أولاً ثم أعد المحاولة.',
      );
    }
    final requestedFils = _toFils(amount);
    if (requestedFils <= 0) return null;
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _ensureCustomerDebtPaymentsTable(db);
    final result = await db.transaction<CustomerDebtPaymentResult?>((txn) async {
      final openMaps = await DbDebtsSqlOps.queryOpenCreditInvoiceMapsForParty(
        txn,
        tid,
        party,
      );
      var debtBeforeFils = 0;
      for (final r in openMaps) {
        final remFils = _toFils(_openRemainingForCreditDebtRow(r));
        if (remFils > 0) debtBeforeFils += remFils;
      }
      if (debtBeforeFils <= 0) return null;
      final toApplyFils = requestedFils > debtBeforeFils
          ? debtBeforeFils
          : requestedFils;
      var leftFils = toApplyFils;
      for (final r in openMaps) {
        if (leftFils <= 0) break;
        final id = r['id'] as int;
        final advFils = _toFils((r['advancePayment'] as num?)?.toDouble() ?? 0);
        final totFils = _toFils((r['total'] as num).toDouble());
        final remFils = max(0, totFils - advFils);
        if (remFils <= 0) continue;
        final addFils = leftFils > remFils ? remFils : leftFils;
        final newAdvFils = advFils + addFils;
        await DbDebtsSqlOps.applyPaymentToInvoice(txn, tid, id, newAdvFils);
        leftFils -= addFils;
      }
      final unappliedFils = leftFils > 0 ? leftFils : 0;
      final appliedFils = toApplyFils - unappliedFils;
      if (appliedFils <= 0) return null;
      final applied = _fromFils(appliedFils);

      var debtAfterFils = 0;
      final afterMaps = await DbDebtsSqlOps.queryOpenCreditInvoiceMapsForParty(
        txn,
        tid,
        party,
      );
      for (final r in afterMaps) {
        final remFils = _toFils(_openRemainingForCreditDebtRow(r));
        if (remFils > 0) debtAfterFils += remFils;
      }
      final debtBefore = _fromFils(debtBeforeFils);
      final debtAfter = _fromFils(debtAfterFils);

      final trimmedUser = recordedByUserName.trim();
      final paymentGlobalId = const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      String? customerGlobalId;
      final r = await txn.query(
        'customers',
        columns: ['global_id'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [customerId, tid],
        limit: 1,
      );
      if (r.isNotEmpty) customerGlobalId = r.first['global_id'] as String?;

      final pid = await DbDebtsSqlOps.insertCustomerDebtPayment(txn, tid, {
        'global_id': paymentGlobalId,
        'customer_global_id': customerGlobalId,
        'customerId': customerId,
        'customerNameSnapshot': party.displayName,
        'amount': applied,
        'debtBefore': debtBefore,
        'debtAfter': debtAfter,
        'createdAt': nowIso,
        'updatedAt': nowIso,
        'createdByUserName': trimmedUser.isEmpty ? null : trimmedUser,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
      });

      final loyaltySettings = await _readLoyaltySettings(txn);
      var meta =
          'دين قبل التسديد: ${debtBefore.toStringAsFixed(0)} د.ع — متبقي بعد: ${debtAfter.toStringAsFixed(0)} د.ع';
      final n = note?.trim();
      if (n != null && n.isNotEmpty) meta = '$meta — ملاحظة: $n';
      if (meta.length > 900) meta = meta.substring(0, 900);

      final receiptInv = Invoice(
        customerName: party.displayName,
        date: DateTime.now(),
        type: InvoiceType.debtCollection,
        items: [
          InvoiceItem(
            productName: 'تحصيل دين آجل',
            quantity: 1,
            price: applied,
            total: applied,
            productId: null,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: applied,
        isReturned: false,
        createdByUserName: trimmedUser.isEmpty ? null : trimmedUser,
        customerId: customerId,
        deliveryAddress: meta,
      );
      final receiptId = await _insertInvoiceInTransaction(
        txn,
        receiptInv,
        loyaltySettings,
        enforceStockNonZero: false,
      );

      return CustomerDebtPaymentResult(
        amountApplied: applied,
        debtBefore: debtBefore,
        debtAfter: debtAfter,
        paymentRowId: pid,
        receiptInvoiceId: receiptId,
      );
    });
    if (result != null) {
      await BusinessAuditLogService.instance.record(
        eventType: 'debt_payment_received',
        entityType: 'customer',
        entityId: customerId.toString(),
        oldValueJson: jsonEncode({'debtBefore': result.debtBefore}),
        newValueJson: jsonEncode({
          'debtAfter': result.debtAfter,
          'amountApplied': result.amountApplied,
        }),
        tenantId: tid,
      );
      OwnerCommandCenterRefreshBridge.instance.invalidateSections([
        OwnerSectionIds.debts,
        OwnerSectionIds.cash,
      ]);
    }
    return result;
  }

  /// فواتير دين آجل مفتوحة ما زالت بلا `customerId` بعد محاولة الترحيل التلقائي.
  Future<List<UnlinkedCreditDebtInvoice>> getUnlinkedOpenCreditDebtInvoices() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _backfillLegacyCreditInvoiceCustomerIds(db, tid);

    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, date, total, advancePayment, totalFils, advancePaymentFils
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND TRIM(customerName) != ''
        AND (
          ${MoneySql.invoiceOpenRemainingFils}
        ) > 0
      ORDER BY date ASC, id ASC
      ''',
      [tid, t],
    );
    return rows
        .map((r) {
          final rem = _openRemainingForCreditDebtRow(r);
          final name = (r['customerName'] as String?)?.trim() ?? '';
          return UnlinkedCreditDebtInvoice(
            invoiceId: r['id'] as int,
            customerName: name,
            remaining: rem,
            date: DateTime.parse(r['date'] as String),
            normalizedName: name.toLowerCase(),
          );
        })
        .toList();
  }

  /// أسماء عملاء مكررة في جدول العملاء — تمنع الربط التلقائي الآمن.
  Future<List<AmbiguousDebtCustomerName>> getAmbiguousDebtCustomerNames() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    final t = InvoiceType.credit.index;

    final rows = await db.rawQuery(
      '''
      SELECT
        LOWER(TRIM(i.customerName)) AS nk,
        MIN(TRIM(i.customerName)) AS sampleName,
        COUNT(DISTINCT i.id) AS openInvoiceCount,
        (
          SELECT COUNT(*)
          FROM customers c
          WHERE c.tenantId = ?
            AND LOWER(TRIM(c.name)) = LOWER(TRIM(i.customerName))
        ) AS customerMatches
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.type = ?
        AND IFNULL(i.isReturned, 0) = 0
        AND i.deleted_at IS NULL
        AND i.customerId IS NULL
        AND TRIM(i.customerName) != ''
        AND (
          ${MoneySql.invoiceOpenRemainingFilsOf('i')}
        ) > 0
      GROUP BY LOWER(TRIM(i.customerName))
      HAVING customerMatches > 1
      ORDER BY openInvoiceCount DESC, nk ASC
      ''',
      [tid, tid, t],
    );

    final out = <AmbiguousDebtCustomerName>[];
    for (final r in rows) {
      final nk = (r['nk'] ?? '').toString();
      final sampleName = (r['sampleName'] ?? '').toString();
      final matchRows = await db.rawQuery(
        '''
        SELECT c.id, c.name
        FROM customers c
        WHERE c.tenantId = ?
          AND LOWER(TRIM(c.name)) = ?
        ORDER BY c.name ASC, c.id ASC
        ''',
        [tid, nk],
      );
      out.add(
        AmbiguousDebtCustomerName(
          normalizedName: nk,
          sampleName: sampleName,
          matchingCustomerCount: (r['customerMatches'] as num?)?.toInt() ?? 0,
          openInvoiceCount: (r['openInvoiceCount'] as num?)?.toInt() ?? 0,
          matchingCustomers: matchRows
              .map(
                (c) => AmbiguousDebtCustomerMatch(
                  customerId: c['id'] as int,
                  name: (c['name'] ?? '').toString(),
                ),
              )
              .toList(),
        ),
      );
    }
    return out;
  }

  /// ربط يدوي لفاتورة دين آجل بعميل مسجّل (بعد فشل/تعذّر الربط التلقائي).
  Future<void> linkOpenCreditInvoiceToCustomer({
    required int invoiceId,
    required int customerId,
  }) async {
    if (invoiceId <= 0 || customerId <= 0) {
      throw StateError('معرّف الفاتورة أو العميل غير صالح.');
    }
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    final t = InvoiceType.credit.index;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final invRows = await txn.query(
        'invoices',
        columns: ['id', 'type', 'customerId', 'customerName'],
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [invoiceId, tid],
        limit: 1,
      );
      if (invRows.isEmpty) {
        throw StateError('الفاتورة غير موجودة أو محذوفة.');
      }
      final inv = invRows.first;
      if ((inv['type'] as num?)?.toInt() != t) {
        throw StateError('يمكن ربط فواتير «دين / آجل» فقط.');
      }
      final existingCid = (inv['customerId'] as num?)?.toInt();
      if (existingCid != null && existingCid > 0) {
        throw StateError('الفاتورة مربوطة بعميل مسبقاً.');
      }

      final custRows = await txn.query(
        'customers',
        columns: ['id', 'name'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [customerId, tid],
        limit: 1,
      );
      if (custRows.isEmpty) {
        throw StateError('العميل غير موجود ضمن المتجر الحالي.');
      }
      final customerName = (custRows.first['name'] ?? '').toString().trim();

      final updated = await txn.update(
        'invoices',
        {
          'customerId': customerId,
          'customerName': customerName.isEmpty ? inv['customerName'] : customerName,
          'updatedAt': nowIso,
        },
        where:
            'id = ? AND tenantId = ? AND deleted_at IS NULL AND customerId IS NULL',
        whereArgs: [invoiceId, tid],
      );
      if (updated < 1) {
        throw StateError('تعذر ربط الفاتورة — ربما تم ربطها من جهاز آخر.');
      }
    });

    await BusinessAuditLogService.instance.record(
      eventType: 'debt_invoice_customer_linked',
      entityType: 'invoice',
      entityId: invoiceId.toString(),
      oldValueJson: jsonEncode({'customerId': null}),
      newValueJson: jsonEncode({'customerId': customerId}),
      tenantId: tid,
    );
    OwnerCommandCenterRefreshBridge.instance.invalidateSections([
      OwnerSectionIds.debts,
    ]);
  }
}
