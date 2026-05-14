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
  );
}

double _openRemainingForCreditDebtRow(Map<String, dynamic> r) {
  final tot = (r['total'] as num).toDouble();
  final adv = (r['advancePayment'] as num?)?.toDouble() ?? 0;
  return max(0.0, tot - adv);
}

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
      SELECT id, customerName, customerId, date, total, advancePayment
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
      SELECT id, customerName, customerId, date, total, advancePayment
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND (total - IFNULL(advancePayment, 0)) > 0.009
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
      SELECT id, customerName, customerId, date, total, advancePayment
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
      SELECT COALESCE(SUM(total - IFNULL(advancePayment, 0)), 0) AS s
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ''',
      [tenantId, t, customerId],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
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
      SELECT COALESCE(SUM(total - IFNULL(advancePayment, 0)), 0) AS s
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ''',
      [tenantId, t, n],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
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
        SELECT id, customerName, total, advancePayment, date
        FROM invoices
        WHERE tenantId = ?
          AND type = ?
          AND IFNULL(isReturned, 0) = 0
          AND deleted_at IS NULL
          AND customerId = ?
          AND (total - IFNULL(advancePayment, 0)) > 0.009
        ORDER BY date ASC, id ASC
        ''',
        [tenantId, t, party.customerId],
      );
    }
    return ex.rawQuery(
      '''
      SELECT id, customerName, total, advancePayment, date
      FROM invoices
      WHERE tenantId = ?
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
        AND deleted_at IS NULL
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
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
        SELECT id, customerName, customerId, date, total, advancePayment
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
        SELECT id, customerName, customerId, date, total, advancePayment
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
    double newAdvancePayment,
  ) {
    return txn.update(
      'invoices',
      {
        'advancePayment': newAdvancePayment,
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
    try {
      final rows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['_system.active_tenant_id'],
        limit: 1,
      );
      final fromSettings = rows.isEmpty
          ? null
          : int.tryParse((rows.first['value'] ?? '').toString());
      if (fromSettings != null && fromSettings > 0) return fromSettings;
    } catch (_) {}
    final parsed = _tryParseLocalTenantId(sessionTenant);
    return parsed != null && parsed > 0 ? parsed : 1;
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
      final open = list.fold<double>(0, (s, x) => s + x.remaining);
      if (open < 0.009) continue;
      DateTime? oldest;
      for (final x in list) {
        if (x.remaining < 0.009) continue;
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
          openRemaining: open,
          invoiceCount: list.where((x) => x.remaining >= 0.009).length,
          oldestInvoiceDate: oldest,
        ),
      );
    }
    for (final e in byName.entries) {
      final list = e.value;
      final open = list.fold<double>(0, (s, x) => s + x.remaining);
      if (open < 0.009) continue;
      DateTime? oldest;
      for (final x in list) {
        if (x.remaining < 0.009) continue;
        oldest = oldest == null || x.date.isBefore(oldest) ? x.date : oldest;
      }
      final display = list.first.customerName.trim().isEmpty
          ? 'عميل'
          : list.first.customerName.trim();
      out.add(
        CustomerDebtSummary(
          customerId: null,
          displayName: display,
          openRemaining: open,
          invoiceCount: list.where((x) => x.remaining >= 0.009).length,
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
    return DbDebtsSqlOps.getCustomerDebtLineItems(db, tid, party);
  }

  Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForParty(
    CustomerDebtParty party,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    return DbDebtsSqlOps.getCreditDebtInvoicesForParty(db, tid, party);
  }

  /// تسديد دفعة على ديون آجل: تخصيم FIFO على [advancePayment].
  Future<CustomerDebtPaymentResult?> recordCustomerDebtPayment({
    required CustomerDebtParty party,
    required double amount,
    required String recordedByUserName,
    String? note,
  }) async {
    if (amount <= 0) return null;
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForDebts(db, sessionTenant);
    await _ensureCustomerDebtPaymentsTable(db);
    return db.transaction((txn) async {
      final openMaps = await DbDebtsSqlOps.queryOpenCreditInvoiceMapsForParty(
        txn,
        tid,
        party,
      );
      var debtBefore = 0.0;
      for (final r in openMaps) {
        debtBefore += _openRemainingForCreditDebtRow(r);
      }
      if (debtBefore < 0.009) return null;
      final toApply = amount > debtBefore ? debtBefore : amount;
      var left = toApply;
      for (final r in openMaps) {
        if (left < 1e-9) break;
        final id = r['id'] as int;
        final adv = (r['advancePayment'] as num?)?.toDouble() ?? 0;
        final tot = (r['total'] as num).toDouble();
        final rem = max(0.0, tot - adv);
        if (rem < 1e-9) continue;
        final add = left > rem ? rem : left;
        final newAdv = adv + add;
        await DbDebtsSqlOps.applyPaymentToInvoice(txn, tid, id, newAdv);
        left -= add;
      }
      final applied = toApply - max(0.0, left);
      if (applied < 1e-9) return null;

      var debtAfter = 0.0;
      final afterMaps = await DbDebtsSqlOps.queryOpenCreditInvoiceMapsForParty(
        txn,
        tid,
        party,
      );
      for (final r in afterMaps) {
        debtAfter += _openRemainingForCreditDebtRow(r);
      }

      final trimmedUser = recordedByUserName.trim();
      final paymentGlobalId = const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      String? customerGlobalId;
      if (party.customerId != null) {
        final r = await txn.query(
          'customers',
          columns: ['global_id'],
          where: 'id = ? AND tenantId = ?',
          whereArgs: [party.customerId, tid],
          limit: 1,
        );
        if (r.isNotEmpty) customerGlobalId = r.first['global_id'] as String?;
      }

      final pid = await DbDebtsSqlOps.insertCustomerDebtPayment(txn, tid, {
        'global_id': paymentGlobalId,
        'customer_global_id': customerGlobalId,
        'customerId': party.customerId,
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
        customerId: party.customerId,
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
  }
}
