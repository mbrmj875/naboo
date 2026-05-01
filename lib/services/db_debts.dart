part of 'database_helper.dart';

// ── الديون الآجلة وتسديد العملاء ─────────────────────────────────────────

extension DbDebts on DatabaseHelper {
  /// كل فواتير «دين / آجل» غير المرتجعة.
  Future<List<CreditDebtInvoice>> getAllNonReturnedCreditInvoices() async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date, total, advancePayment
      FROM invoices
      WHERE type = ? AND IFNULL(isReturned, 0) = 0
      ORDER BY date DESC
      ''',
      [t],
    );
    return rows
        .map(
          (r) => CreditDebtInvoice(
            invoiceId: r['id'] as int,
            customerName: (r['customerName'] as String?)?.trim() ?? '',
            customerId: r['customerId'] as int?,
            date: DateTime.parse(r['date'] as String),
            total: (r['total'] as num).toDouble(),
            advancePayment: (r['advancePayment'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  /// فواتير «دين / آجل» ذات متبقٍ > 0 (غير مرتجعة).
  Future<List<CreditDebtInvoice>> getOpenCreditDebtInvoices() async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date, total, advancePayment
      FROM invoices
      WHERE type = ?
        AND IFNULL(isReturned, 0) = 0
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ORDER BY date DESC
      ''',
      [t],
    );
    return rows
        .map(
          (r) => CreditDebtInvoice(
            invoiceId: r['id'] as int,
            customerName: (r['customerName'] as String?)?.trim() ?? '',
            customerId: r['customerId'] as int?,
            date: DateTime.parse(r['date'] as String),
            total: (r['total'] as num).toDouble(),
            advancePayment: (r['advancePayment'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  /// كل فواتير «آجل» غير المرتجعة لعميل مسجّل (للعرض والربط بإيصال البيع).
  Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForCustomerId(
    int customerId,
  ) async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT id, customerName, customerId, date, total, advancePayment
      FROM invoices
      WHERE type = ?
        AND IFNULL(isReturned, 0) = 0
        AND customerId = ?
      ORDER BY date DESC
      ''',
      [t, customerId],
    );
    return rows
        .map(
          (r) => CreditDebtInvoice(
            invoiceId: r['id'] as int,
            customerName: (r['customerName'] as String?)?.trim() ?? '',
            customerId: r['customerId'] as int?,
            date: DateTime.parse(r['date'] as String),
            total: (r['total'] as num).toDouble(),
            advancePayment: (r['advancePayment'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<double> sumOpenCreditDebtForCustomer(int customerId) async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total - IFNULL(advancePayment, 0)), 0) AS s
      FROM invoices
      WHERE type = ?
        AND IFNULL(isReturned, 0) = 0
        AND customerId = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ''',
      [t, customerId],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<double> sumOpenCreditDebtForUnlinkedCustomerName(
    String rawName,
  ) async {
    final n = rawName.trim().toLowerCase();
    if (n.isEmpty) return 0;
    final db = await database;
    final t = InvoiceType.credit.index;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total - IFNULL(advancePayment, 0)), 0) AS s
      FROM invoices
      WHERE type = ?
        AND IFNULL(isReturned, 0) = 0
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ''',
      [t, n],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0;
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

  double _openRemainingForCreditRow(Map<String, dynamic> r) {
    final tot = (r['total'] as num).toDouble();
    final adv = (r['advancePayment'] as num?)?.toDouble() ?? 0;
    return max(0.0, tot - adv);
  }

  Future<List<Map<String, dynamic>>> _queryOpenCreditInvoiceMapsForParty(
    DatabaseExecutor ex,
    CustomerDebtParty party,
  ) async {
    final t = InvoiceType.credit.index;
    if (party.customerId != null) {
      return ex.rawQuery(
        '''
        SELECT id, customerName, total, advancePayment, date
        FROM invoices
        WHERE type = ? AND IFNULL(isReturned, 0) = 0 AND customerId = ?
          AND (total - IFNULL(advancePayment, 0)) > 0.009
        ORDER BY date ASC, id ASC
        ''',
        [t, party.customerId],
      );
    }
    return ex.rawQuery(
      '''
      SELECT id, customerName, total, advancePayment, date
      FROM invoices
      WHERE type = ? AND IFNULL(isReturned, 0) = 0
        AND customerId IS NULL
        AND LOWER(TRIM(customerName)) = ?
        AND (total - IFNULL(advancePayment, 0)) > 0.009
      ORDER BY date ASC, id ASC
      ''',
      [t, party.normalizedName],
    );
  }

  Future<double> sumOpenCreditDebtForParty(CustomerDebtParty party) async {
    final db = await database;
    final rows = await _queryOpenCreditInvoiceMapsForParty(db, party);
    var s = 0.0;
    for (final r in rows) {
      s += _openRemainingForCreditRow(r);
    }
    return s;
  }

  Future<List<CustomerDebtLineItem>> getCustomerDebtLineItems(
    CustomerDebtParty party,
  ) async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final List<Map<String, dynamic>> rows;
    if (party.customerId != null) {
      rows = await db.rawQuery(
        '''
        SELECT ii.productName, ii.quantity, ii.price, ii.total AS lineTotal,
               i.id AS invoiceId, i.date AS invDate, i.createdByUserName
        FROM invoice_items ii
        INNER JOIN invoices i ON i.id = ii.invoiceId
        WHERE i.type = ? AND IFNULL(i.isReturned, 0) = 0
          AND i.customerId = ?
        ORDER BY i.date DESC, ii.id ASC
        ''',
        [t, party.customerId],
      );
    } else {
      rows = await db.rawQuery(
        '''
        SELECT ii.productName, ii.quantity, ii.price, ii.total AS lineTotal,
               i.id AS invoiceId, i.date AS invDate, i.createdByUserName
        FROM invoice_items ii
        INNER JOIN invoices i ON i.id = ii.invoiceId
        WHERE i.type = ? AND IFNULL(i.isReturned, 0) = 0
          AND i.customerId IS NULL
          AND LOWER(TRIM(i.customerName)) = ?
        ORDER BY i.date DESC, ii.id ASC
        ''',
        [t, party.normalizedName],
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

  Future<List<CreditDebtInvoice>> getCreditDebtInvoicesForParty(
    CustomerDebtParty party,
  ) async {
    final db = await database;
    final t = InvoiceType.credit.index;
    final List<Map<String, dynamic>> rows;
    if (party.customerId != null) {
      rows = await db.rawQuery(
        '''
        SELECT id, customerName, customerId, date, total, advancePayment
        FROM invoices
        WHERE type = ? AND IFNULL(isReturned, 0) = 0 AND customerId = ?
        ORDER BY date DESC
        ''',
        [t, party.customerId],
      );
    } else {
      rows = await db.rawQuery(
        '''
        SELECT id, customerName, customerId, date, total, advancePayment
        FROM invoices
        WHERE type = ? AND IFNULL(isReturned, 0) = 0
          AND customerId IS NULL AND LOWER(TRIM(customerName)) = ?
        ORDER BY date DESC
        ''',
        [t, party.normalizedName],
      );
    }
    return rows
        .map(
          (r) => CreditDebtInvoice(
            invoiceId: r['id'] as int,
            customerName: (r['customerName'] as String?)?.trim() ?? '',
            customerId: r['customerId'] as int?,
            date: DateTime.parse(r['date'] as String),
            total: (r['total'] as num).toDouble(),
            advancePayment: (r['advancePayment'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
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
    await _ensureCustomerDebtPaymentsTable(db);
    return db.transaction((txn) async {
      final openMaps = await _queryOpenCreditInvoiceMapsForParty(txn, party);
      var debtBefore = 0.0;
      for (final r in openMaps) {
        debtBefore += _openRemainingForCreditRow(r);
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
        await txn.update(
          'invoices',
          {'advancePayment': newAdv},
          where: 'id = ?',
          whereArgs: [id],
        );
        left -= add;
      }
      final applied = toApply - max(0.0, left);
      if (applied < 1e-9) return null;

      var debtAfter = 0.0;
      final afterMaps = await _queryOpenCreditInvoiceMapsForParty(txn, party);
      for (final r in afterMaps) {
        debtAfter += _openRemainingForCreditRow(r);
      }

      final trimmedUser = recordedByUserName.trim();
      final pid = await txn.insert('customer_debt_payments', {
        'customerId': party.customerId,
        'customerNameSnapshot': party.displayName,
        'amount': applied,
        'debtBefore': debtBefore,
        'debtAfter': debtAfter,
        'createdAt': DateTime.now().toIso8601String(),
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
