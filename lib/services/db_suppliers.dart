part of 'database_helper.dart';

// ── الموردون والحسابات الدائنة (AP) ──────────────────────────────────────

extension DbSuppliers on DatabaseHelper {
  Future<List<SupplierApSummary>> getSupplierApSummaries() async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.phone, s.notes, s.isActive, s.createdAt,
        COALESCE(b.tb, 0) AS totalBilled,
        COALESCE(p.tp, 0) AS totalPaid
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts GROUP BY supplierId
      ) p ON p.supplierId = s.id
      WHERE s.isActive = 1
      ORDER BY s.name COLLATE NOCASE
    ''');
    return rows.map((r) {
      final sup = Supplier(
        id: r['id'] as int,
        name: (r['name'] as String?)?.trim() ?? '',
        phone: (r['phone'] as String?)?.trim(),
        notes: (r['notes'] as String?)?.trim(),
        isActive: ((r['isActive'] as int?) ?? 1) == 1,
        createdAt: DateTime.parse(r['createdAt'] as String),
      );
      return SupplierApSummary(
        supplier: sup,
        totalBilled: (r['totalBilled'] as num?)?.toDouble() ?? 0,
        totalPaid: (r['totalPaid'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  Future<double> getSupplierApTotalOpenPayable() async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(COALESCE(b.tb, 0) - COALESCE(p.tp, 0)), 0) AS open
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts GROUP BY supplierId
      ) p ON p.supplierId = s.id
      WHERE s.isActive = 1
    ''');
    if (rows.isEmpty) return 0;
    return (rows.first['open'] as num?)?.toDouble() ?? 0;
  }

  Future<List<SupplierApSummary>> querySupplierApSummariesPage({
    required String query,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final q = query.trim().toLowerCase();

    final where = <String>['s.isActive = 1'];
    final args = <Object?>[];
    if (q.isNotEmpty) {
      where.add('LOWER(s.name) LIKE ?');
      args.add('%$q%');
    }
    final whereSql = 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.phone, s.notes, s.isActive, s.createdAt,
        COALESCE(b.tb, 0) AS totalBilled,
        COALESCE(p.tp, 0) AS totalPaid
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts GROUP BY supplierId
      ) p ON p.supplierId = s.id
      $whereSql
      ORDER BY s.name COLLATE NOCASE
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    return rows.map((r) {
      final sup = Supplier(
        id: r['id'] as int,
        name: (r['name'] as String?)?.trim() ?? '',
        phone: (r['phone'] as String?)?.trim(),
        notes: (r['notes'] as String?)?.trim(),
        isActive: ((r['isActive'] as int?) ?? 1) == 1,
        createdAt: DateTime.parse(r['createdAt'] as String),
      );
      return SupplierApSummary(
        supplier: sup,
        totalBilled: (r['totalBilled'] as num?)?.toDouble() ?? 0,
        totalPaid: (r['totalPaid'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  Future<Supplier?> getSupplierById(int id) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Supplier(
      id: r['id'] as int,
      name: (r['name'] as String?)?.trim() ?? '',
      phone: (r['phone'] as String?)?.trim(),
      notes: (r['notes'] as String?)?.trim(),
      isActive: ((r['isActive'] as int?) ?? 1) == 1,
      createdAt: DateTime.parse(r['createdAt'] as String),
    );
  }

  Future<int> insertSupplier({
    required String name,
    String? phone,
    String? notes,
    int tenantId = 1,
  }) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('name');
    final id = await db.insert('suppliers', {
      'tenantId': tenantId,
      'name': n,
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<int?> findActiveSupplierIdByName(
    String name, {
    int tenantId = 1,
  }) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.rawQuery(
      '''
      SELECT id
      FROM suppliers
      WHERE isActive = 1
        AND tenantId = ?
        AND TRIM(LOWER(name)) = TRIM(LOWER(?))
      LIMIT 1
      ''',
      [tenantId, n],
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  Future<void> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? notes,
  }) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('name');
    await db.update(
      'suppliers',
      {
        'name': n,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<int> insertSupplierBill({
    required int supplierId,
    String? theirReference,
    DateTime? theirBillDate,
    required double amount,
    String? note,
    String? imagePath,
    String? createdByUserName,
    int tenantId = 1,
    int? linkedStockVoucherId,
  }) async {
    if (amount <= 0) throw ArgumentError('amount');
    final db = await database;
    await _ensureSupplierApTables(db);
    final id = await db.insert('supplier_bills', {
      'tenantId': tenantId,
      'supplierId': supplierId,
      'theirReference': theirReference?.trim().isEmpty == true
          ? null
          : theirReference?.trim(),
      'theirBillDate': theirBillDate?.toIso8601String(),
      'amount': amount,
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'imagePath':
          imagePath?.trim().isEmpty == true ? null : imagePath?.trim(),
      'createdAt': DateTime.now().toIso8601String(),
      'createdByUserName': createdByUserName?.trim().isEmpty == true
          ? null
          : createdByUserName?.trim(),
      'linkedStockVoucherId': linkedStockVoucherId,
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<void> updateSupplierBillImagePath(
    int billId,
    String? imagePath,
  ) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    await db.update(
      'supplier_bills',
      {
        'imagePath':
            imagePath?.trim().isEmpty == true ? null : imagePath?.trim(),
      },
      where: 'id = ?',
      whereArgs: [billId],
    );
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<List<SupplierBill>> getSupplierBills(int supplierId) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    await _ensureSupplierBillStockLinkColumns(db);
    final rows = await db.rawQuery(
      '''
      SELECT b.id, b.supplierId, b.theirReference, b.theirBillDate, b.amount, b.note, b.imagePath,
        b.createdAt, b.createdByUserName, b.linkedStockVoucherId,
        v.voucherNo AS linkedVoucherNo
      FROM supplier_bills b
      LEFT JOIN stock_vouchers v ON v.id = b.linkedStockVoucherId
      WHERE b.supplierId = ?
      ORDER BY b.createdAt DESC
      ''',
      [supplierId],
    );
    return rows.map((r) {
      final d = r['theirBillDate'] as String?;
      final linkId = r['linkedStockVoucherId'];
      return SupplierBill(
        id: r['id'] as int,
        supplierId: r['supplierId'] as int,
        theirReference: (r['theirReference'] as String?)?.trim(),
        theirBillDate:
            d != null && d.isNotEmpty ? DateTime.tryParse(d) : null,
        amount: (r['amount'] as num).toDouble(),
        note: (r['note'] as String?)?.trim(),
        imagePath: (r['imagePath'] as String?)?.trim(),
        createdAt: DateTime.parse(r['createdAt'] as String),
        createdByUserName: (r['createdByUserName'] as String?)?.trim(),
        linkedStockVoucherId:
            linkId == null ? null : (linkId as num).toInt(),
        linkedVoucherNo: (r['linkedVoucherNo'] as String?)?.trim(),
      );
    }).toList();
  }

  Future<List<SupplierPayout>> getSupplierPayouts(int supplierId) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final rows = await db.query(
      'supplier_payouts',
      where: 'supplierId = ?',
      whereArgs: [supplierId],
      orderBy: 'createdAt DESC',
    );
    return rows
        .map(
          (r) => SupplierPayout(
            id: r['id'] as int,
            supplierId: r['supplierId'] as int,
            amount: (r['amount'] as num).toDouble(),
            note: (r['note'] as String?)?.trim(),
            createdAt: DateTime.parse(r['createdAt'] as String),
            createdByUserName: (r['createdByUserName'] as String?)?.trim(),
            affectsCash: ((r['affectsCash'] as int?) ?? 1) == 1,
            receiptInvoiceId: (r['receiptInvoiceId'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  /// دفعة للمورد؛ تُنشأ فاتورة سند [InvoiceType.supplierPayment].
  Future<SupplierPayoutResult?> recordSupplierPayout({
    required int supplierId,
    required double amount,
    String? note,
    required bool affectsCash,
    required String recordedByUserName,
  }) async {
    if (amount <= 0) return null;
    final db = await database;
    await _ensureSupplierApTables(db);
    final user = recordedByUserName.trim();
    final result = await db.transaction((txn) async {
      final loyaltySettings = await _readLoyaltySettings(txn);
      final sup = await txn.query(
        'suppliers',
        columns: ['name', 'tenantId'],
        where: 'id = ?',
        whereArgs: [supplierId],
        limit: 1,
      );
      final name =
          (sup.isNotEmpty ? sup.first['name'] as String? : null)?.trim() ??
          'مورد';
      final tenantId = (sup.isNotEmpty ? (sup.first['tenantId'] as num?)?.toInt() : null) ?? 1;

      var meta = 'مورد #$supplierId';
      final n = note?.trim();
      if (n != null && n.isNotEmpty) meta = '$meta — ملاحظة: $n';
      if (meta.length > 900) meta = meta.substring(0, 900);

      final receiptInv = Invoice(
        customerName: name,
        date: DateTime.now(),
        type: InvoiceType.supplierPayment,
        items: [
          InvoiceItem(
            productName: 'دفع ذمة مورد',
            quantity: 1,
            price: amount,
            total: amount,
            productId: null,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: amount,
        isReturned: false,
        createdByUserName: user.isEmpty ? null : user,
        deliveryAddress: meta,
        supplierPaymentAffectsCash: affectsCash,
      );
      final invoiceId = await _insertInvoiceInTransaction(
        txn,
        receiptInv,
        loyaltySettings,
      );
      final actor = user.isEmpty ? 'غير معروف' : user;
      await _insertActivityLogInTxn(
        txn,
        type: 'supplier_receipt_created',
        refTable: 'invoices',
        refId: invoiceId,
        title: 'إنشاء سند دفع مورد',
        details: 'المورد: $name (#$supplierId) • المنفذ: $actor',
        amount: amount,
        tenantId: tenantId,
      );

      final pid = await txn.insert('supplier_payouts', {
        'supplierId': supplierId,
        'amount': amount,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'createdAt': DateTime.now().toIso8601String(),
        'createdByUserName': user.isEmpty ? null : user,
        'affectsCash': affectsCash ? 1 : 0,
        'receiptInvoiceId': invoiceId,
      });
      await _insertActivityLogInTxn(
        txn,
        type: 'supplier_payout_created',
        refTable: 'supplier_payouts',
        refId: pid,
        title: 'تسجيل دفعة مورد',
        details: 'المورد: $name (#$supplierId) • الفاتورة المرجعية: #$invoiceId • المنفذ: $actor',
        amount: amount,
        tenantId: tenantId,
      );

      int? ledgerId;
      if (affectsCash) {
        final led = await txn.query(
          'cash_ledger',
          columns: ['id'],
          where: 'invoiceId = ? AND transactionType = ?',
          whereArgs: [invoiceId, 'supplier_payment'],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (led.isNotEmpty) ledgerId = led.first['id'] as int;
      }
      return SupplierPayoutResult(
        payoutId: pid,
        cashLedgerId: ledgerId,
        receiptInvoiceId: invoiceId,
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return result;
  }

  /// حذف دفعة مورد مسجّلة بالخطأ؛ إن وُجد قيد صندوق يُضاف قيد عكسي.
  Future<bool> deleteSupplierPayoutReversingCash({
    required int payoutId,
    required int supplierId,
  }) async {
    final db = await database;
    await _ensureSupplierApTables(db);
    final deleted = await db.transaction((txn) async {
      final rows = await txn.query(
        'supplier_payouts',
        where: 'id = ? AND supplierId = ?',
        whereArgs: [payoutId, supplierId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final r = rows.first;
      final affectsCash = ((r['affectsCash'] as int?) ?? 1) == 1;
      final amount = (r['amount'] as num).toDouble();
      final receiptInvoiceId = (r['receiptInvoiceId'] as num?)?.toInt();
      final tenantId = (r['tenantId'] as num?)?.toInt() ?? 1;
      final actor = ((r['createdByUserName'] as String?) ?? '').trim().isEmpty
          ? 'غير معروف'
          : ((r['createdByUserName'] as String?) ?? '').trim();

      if (receiptInvoiceId != null && receiptInvoiceId > 0) {
        await txn.delete(
          'cash_ledger',
          where: 'invoiceId = ?',
          whereArgs: [receiptInvoiceId],
        );
        await txn.delete(
          'invoice_items',
          where: 'invoiceId = ?',
          whereArgs: [receiptInvoiceId],
        );
        await txn.delete(
          'invoices',
          where: 'id = ?',
          whereArgs: [receiptInvoiceId],
        );
        await _insertActivityLogInTxn(
          txn,
          type: 'supplier_receipt_deleted',
          refTable: 'invoices',
          refId: receiptInvoiceId,
          title: 'حذف سند دفع مورد',
          details: 'المورد #$supplierId • الحذف ضمن عكس دفعة #$payoutId • المنفذ: $actor',
          amount: amount,
          tenantId: tenantId,
        );
      }

      if (affectsCash && amount > 1e-9) {
        int? openShiftId;
        final ws = await txn.query(
          'work_shifts',
          columns: ['id'],
          where: 'closedAt IS NULL',
          limit: 1,
        );
        if (ws.isNotEmpty) {
          openShiftId = ws.first['id'] as int;
        }
        final sup = await txn.query(
          'suppliers',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [supplierId],
          limit: 1,
        );
        final name =
            (sup.isNotEmpty ? sup.first['name'] as String? : null)?.trim() ??
            'مورد';
        await txn.insert('cash_ledger', {
          'transactionType': 'supplier_payment_reversal',
          'amount': amount,
          'description':
              'عكس دفعة مورد #$supplierId — $name (كانت دفعة #$payoutId)',
          'invoiceId': null,
          'workShiftId': openShiftId,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await _insertActivityLogInTxn(
          txn,
          type: 'supplier_payout_reversed',
          refTable: 'supplier_payouts',
          refId: payoutId,
          title: 'عكس دفعة مورد',
          details: 'المورد: $name (#$supplierId) • المنفذ: $actor',
          amount: amount,
          tenantId: tenantId,
        );
      }
      final n = await txn.delete(
        'supplier_payouts',
        where: 'id = ?',
        whereArgs: [payoutId],
      );
      if (n > 0) {
        await _insertActivityLogInTxn(
          txn,
          type: 'supplier_payout_deleted',
          refTable: 'supplier_payouts',
          refId: payoutId,
          title: 'حذف دفعة مورد',
          details: 'المورد #$supplierId • المنفذ: $actor',
          amount: amount,
          tenantId: tenantId,
        );
      }
      return n > 0;
    });
    if (deleted) {
      CloudSyncService.instance.scheduleSyncSoon();
    }
    return deleted;
  }
}
