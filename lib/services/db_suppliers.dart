part of 'database_helper.dart';

// ── الموردون والحسابات الدائنة (AP) ──────────────────────────────────────
//
// Step 8 (tenant isolation):
// Every read/write for suppliers, supplier_bills and supplier_payouts goes
// through [TenantContext.requireTenantId] before touching SQLite, and every
// SQL statement carries `tenantId = ?`. JOIN sub-queries on bills/payouts
// also filter by tenantId so a tenant-2 row can never inflate a tenant-1
// summary, even when the int `supplierId` collides across tenants. The pure
// SQL is exposed via [DbSuppliersSqlOps] so unit tests can drive it against
// the in-memory FFI database from `test/helpers/in_memory_db.dart` without
// instantiating the production [DatabaseHelper] singleton.

Supplier _supplierFromRow(Map<String, dynamic> r) {
  return Supplier(
    id: r['id'] as int,
    name: (r['name'] as String?)?.trim() ?? '',
    phone: (r['phone'] as String?)?.trim(),
    notes: (r['notes'] as String?)?.trim(),
    isActive: ((r['isActive'] as int?) ?? 1) == 1,
    createdAt: DateTime.parse(r['createdAt'] as String),
  );
}

SupplierApSummary _supplierApSummaryFromRow(Map<String, dynamic> r) {
  return SupplierApSummary(
    supplier: _supplierFromRow(r),
    totalBilled: (r['totalBilled'] as num?)?.toDouble() ?? 0,
    totalPaid: (r['totalPaid'] as num?)?.toDouble() ?? 0,
  );
}

/// Pure SQL operations for the supplier-AP domain, parameterised over
/// `tenantId` so they can be covered by unit tests with the in-memory schema.
/// Production callers must always go through the [DbSuppliers] extension on
/// [DatabaseHelper], which gates each call on
/// [TenantContext.requireTenantId] before invoking these helpers.
@visibleForTesting
class DbSuppliersSqlOps {
  DbSuppliersSqlOps._();

  static Future<List<SupplierApSummary>> getSupplierApSummaries(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.phone, s.notes, s.isActive, s.createdAt,
        COALESCE(b.tb, 0) AS totalBilled,
        COALESCE(p.tp, 0) AS totalPaid
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills
        WHERE tenantId = ?
        GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts
        WHERE tenantId = ?
        GROUP BY supplierId
      ) p ON p.supplierId = s.id
      WHERE s.tenantId = ?
        AND s.isActive = 1
      ORDER BY s.name COLLATE NOCASE
      ''',
      [tenantId, tenantId, tenantId],
    );
    return rows.map(_supplierApSummaryFromRow).toList();
  }

  static Future<double> getSupplierApTotalOpenPayable(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(COALESCE(b.tb, 0) - COALESCE(p.tp, 0)), 0) AS open
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills
        WHERE tenantId = ?
        GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts
        WHERE tenantId = ?
        GROUP BY supplierId
      ) p ON p.supplierId = s.id
      WHERE s.tenantId = ?
        AND s.isActive = 1
      ''',
      [tenantId, tenantId, tenantId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['open'] as num?)?.toDouble() ?? 0;
  }

  static Future<List<SupplierApSummary>> querySupplierApSummariesPage(
    DatabaseExecutor db,
    int tenantId, {
    required String query,
    required int limit,
    required int offset,
  }) async {
    final q = query.trim().toLowerCase();
    final where = <String>['s.tenantId = ?', 's.isActive = 1'];
    final args = <Object?>[tenantId];
    if (q.isNotEmpty) {
      where.add('LOWER(s.name) LIKE ?');
      args.add('%$q%');
    }
    final whereSql = 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.phone, s.notes, s.isActive, s.createdAt,
        COALESCE(b.tb, 0) AS totalBilled,
        COALESCE(p.tp, 0) AS totalPaid
      FROM suppliers s
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tb FROM supplier_bills
        WHERE tenantId = ?
        GROUP BY supplierId
      ) b ON b.supplierId = s.id
      LEFT JOIN (
        SELECT supplierId, SUM(amount) AS tp FROM supplier_payouts
        WHERE tenantId = ?
        GROUP BY supplierId
      ) p ON p.supplierId = s.id
      $whereSql
      ORDER BY s.name COLLATE NOCASE
      LIMIT ? OFFSET ?
      ''',
      [tenantId, tenantId, ...args, limit, offset],
    );
    return rows.map(_supplierApSummaryFromRow).toList();
  }

  static Future<Supplier?> getSupplierById(
    DatabaseExecutor db,
    int tenantId,
    int id,
  ) async {
    final rows = await db.query(
      'suppliers',
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _supplierFromRow(rows.first);
  }

  static Future<int?> findActiveSupplierIdByName(
    DatabaseExecutor db,
    int tenantId,
    String name,
  ) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final rows = await db.rawQuery(
      '''
      SELECT id
      FROM suppliers
      WHERE tenantId = ?
        AND isActive = 1
        AND TRIM(LOWER(name)) = TRIM(LOWER(?))
      LIMIT 1
      ''',
      [tenantId, n],
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  static Future<List<Map<String, dynamic>>> getSupplierBillsRaw(
    DatabaseExecutor db,
    int tenantId,
    int supplierId,
  ) {
    return db.rawQuery(
      '''
      SELECT b.id, b.supplierId, b.theirReference, b.theirBillDate, b.amount,
             b.note, b.imagePath, b.createdAt, b.createdByUserName,
             b.linkedStockVoucherId,
             v.voucherNo AS linkedVoucherNo
      FROM supplier_bills b
      LEFT JOIN stock_vouchers v ON v.id = b.linkedStockVoucherId
      WHERE b.tenantId = ?
        AND b.supplierId = ?
      ORDER BY b.createdAt DESC
      ''',
      [tenantId, supplierId],
    );
  }

  static Future<List<Map<String, dynamic>>> getSupplierPayoutsRaw(
    DatabaseExecutor db,
    int tenantId,
    int supplierId,
  ) {
    return db.query(
      'supplier_payouts',
      where: 'tenantId = ? AND supplierId = ?',
      whereArgs: [tenantId, supplierId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Inserts a `suppliers` row, stamping `tenantId` from the active session
  /// regardless of whatever the caller passed in [values].
  static Future<int> insertSupplier(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('suppliers', stamped);
  }

  /// Updates a `suppliers` row, blocking cross-tenant updates.
  static Future<int> updateSupplier(
    DatabaseExecutor txn,
    int tenantId,
    int id,
    Map<String, dynamic> values,
  ) {
    return txn.update(
      'suppliers',
      values,
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tenantId],
    );
  }

  static Future<int> insertSupplierBill(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('supplier_bills', stamped);
  }

  static Future<int> updateSupplierBill(
    DatabaseExecutor txn,
    int tenantId,
    int billId,
    Map<String, dynamic> values,
  ) {
    return txn.update(
      'supplier_bills',
      values,
      where: 'id = ? AND tenantId = ?',
      whereArgs: [billId, tenantId],
    );
  }

  static Future<int> insertSupplierPayout(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('supplier_payouts', stamped);
  }

  static Future<int> deleteSupplierPayout(
    DatabaseExecutor txn,
    int tenantId,
    int payoutId,
    int supplierId,
  ) {
    return txn.delete(
      'supplier_payouts',
      where: 'id = ? AND supplierId = ? AND tenantId = ?',
      whereArgs: [payoutId, supplierId, tenantId],
    );
  }
}

extension DbSuppliers on DatabaseHelper {
  Future<int> _activeTenantIdForSuppliers(Database db, String sessionTenant) async {
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

  /// ترحيل [suppliers.global_id] و [updatedAt] للطابور واللقطة.
  Future<void> ensureSuppliersGlobalIdSchema([Database? optionalDb]) async {
    final db = optionalDb ?? await database;
    await _ensureSupplierApTables(db);

    Future<void> addColumn(String col, String type) async {
      final rows = await db.rawQuery('PRAGMA table_info(suppliers)');
      final exists = rows.any(
        (r) =>
            (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
      );
      if (!exists) {
        try {
          await db.execute('ALTER TABLE suppliers ADD COLUMN $col $type');
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint(
              '[ensureSuppliersGlobalIdSchema] ALTER suppliers ADD $col failed: $e\n$st',
            );
          }
        }
      }
    }

    await addColumn('global_id', 'TEXT');
    await addColumn('updatedAt', 'TEXT');

    Future<bool> colExists(String name) async {
      final rows = await db.rawQuery('PRAGMA table_info(suppliers)');
      return rows.any(
        (r) =>
            (r['name']?.toString().toLowerCase() ?? '') == name.toLowerCase(),
      );
    }

    if (await colExists('global_id')) {
      try {
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS uq_suppliers_global_id
          ON suppliers(global_id)
          WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
        ''');
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[ensureSuppliersGlobalIdSchema] CREATE INDEX uq_suppliers_global_id failed: $e\n$st',
          );
        }
      }
    }

    if (!await colExists('global_id')) return;

    final missing = await db.rawQuery('''
      SELECT id, createdAt FROM suppliers
      WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
    ''');
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final r in missing) {
      final id = r['id'] as int?;
      if (id == null) continue;
      final ca = (r['createdAt'] as String?) ?? nowIso;
      await db.update(
        'suppliers',
        {
          'global_id': const Uuid().v4(),
          'updatedAt': ca,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await db.execute('''
      UPDATE suppliers
      SET updatedAt = createdAt
      WHERE updatedAt IS NULL OR TRIM(IFNULL(updatedAt, '')) = ''
    ''');
  }

  Future<List<SupplierApSummary>> getSupplierApSummaries() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    return DbSuppliersSqlOps.getSupplierApSummaries(db, tid);
  }

  Future<double> getSupplierApTotalOpenPayable() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    return DbSuppliersSqlOps.getSupplierApTotalOpenPayable(db, tid);
  }

  Future<List<SupplierApSummary>> querySupplierApSummariesPage({
    required String query,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    return DbSuppliersSqlOps.querySupplierApSummariesPage(
      db,
      tid,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  Future<Supplier?> getSupplierById(int id) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    return DbSuppliersSqlOps.getSupplierById(db, tid, id);
  }

  Future<int> insertSupplier({
    required String name,
    String? phone,
    String? notes,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    await ensureSuppliersGlobalIdSchema();
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('name');
    final globalId = const Uuid().v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    late final int id;
    await db.transaction((txn) async {
      final payload = <String, dynamic>{
        'global_id': globalId,
        'tenantId': tid,
        'name': n,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'isActive': 1,
        'createdAt': nowIso,
        'updatedAt': nowIso,
      };
      id = await DbSuppliersSqlOps.insertSupplier(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'supplier',
        globalId: globalId,
        operation: 'INSERT',
        payload: Map<String, dynamic>.from(payload),
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<int?> findActiveSupplierIdByName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    return DbSuppliersSqlOps.findActiveSupplierIdByName(db, tid, n);
  }

  Future<void> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? notes,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    await ensureSuppliersGlobalIdSchema();
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('name');
    final rows = await db.query(
      'suppliers',
      columns: ['global_id', 'tenantId', 'createdAt', 'isActive'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, tid],
      limit: 1,
    );
    if (rows.isEmpty) return;
    var gid = (rows.first['global_id'] as String?)?.trim() ?? '';
    final tenantInt = (rows.first['tenantId'] as num?)?.toInt() ?? 1;
    final createdAt = (rows.first['createdAt'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    final isActive = (rows.first['isActive'] as num?)?.toInt() ?? 1;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (gid.isEmpty) {
        gid = const Uuid().v4();
        await DbSuppliersSqlOps.updateSupplier(txn, tid, id, {
          'global_id': gid,
          'updatedAt': nowIso,
        });
      }
      final updatedPayload = {
        'name': n,
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'updatedAt': nowIso,
      };
      await DbSuppliersSqlOps.updateSupplier(txn, tid, id, updatedPayload);
      final queuePayload = <String, dynamic>{
        'global_id': gid,
        'tenantId': tenantInt,
        'name': n,
        'phone': updatedPayload['phone'],
        'notes': updatedPayload['notes'],
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': nowIso,
      };
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'supplier',
        globalId: gid,
        operation: 'UPDATE',
        payload: queuePayload,
      );
    });
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
    int? linkedStockVoucherId,
  }) async {
    if (amount <= 0) throw ArgumentError('amount');
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    final globalId = const Uuid().v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    String? supplierGlobalId;
    final sr = await db.query(
      'suppliers',
      columns: ['global_id'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [supplierId, tid],
      limit: 1,
    );
    if (sr.isNotEmpty) supplierGlobalId = sr.first['global_id'] as String?;

    final id = await DbSuppliersSqlOps.insertSupplierBill(db, tid, {
      'global_id': globalId,
      'supplier_global_id': supplierGlobalId,
      'supplierId': supplierId,
      'theirReference': theirReference?.trim().isEmpty == true
          ? null
          : theirReference?.trim(),
      'theirBillDate': theirBillDate?.toIso8601String(),
      'amount': amount,
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'imagePath':
          imagePath?.trim().isEmpty == true ? null : imagePath?.trim(),
      'createdAt': nowIso,
      'updatedAt': nowIso,
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
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    await DbSuppliersSqlOps.updateSupplierBill(db, tid, billId, {
      'imagePath':
          imagePath?.trim().isEmpty == true ? null : imagePath?.trim(),
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<List<SupplierBill>> getSupplierBills(int supplierId) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    await _ensureSupplierBillStockLinkColumns(db);
    final rows =
        await DbSuppliersSqlOps.getSupplierBillsRaw(db, tid, supplierId);
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
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    final rows =
        await DbSuppliersSqlOps.getSupplierPayoutsRaw(db, tid, supplierId);
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
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    final user = recordedByUserName.trim();
    final result = await db.transaction((txn) async {
      final loyaltySettings = await _readLoyaltySettings(txn);
      final sup = await txn.query(
        'suppliers',
        columns: ['name', 'tenantId'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [supplierId, tid],
        limit: 1,
      );
      final name = (sup.isNotEmpty ? sup.first['name'] as String? : null)
              ?.trim() ??
          'مورد';
      // Tenant-scoped lookup guarantees this `tenantId` matches the active
      // session; use it for activity_logs writes that still take an int.
      final tenantInt =
          (sup.isNotEmpty ? (sup.first['tenantId'] as num?)?.toInt() : null) ??
              1;

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
        enforceStockNonZero: false,
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
        tenantId: tenantInt,
      );

      final payoutGlobalId = const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      String? supplierGlobalId;
      final sr = await txn.query(
        'suppliers',
        columns: ['global_id'],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [supplierId, tid],
        limit: 1,
      );
      if (sr.isNotEmpty) supplierGlobalId = sr.first['global_id'] as String?;

      final pid = await DbSuppliersSqlOps.insertSupplierPayout(txn, tid, {
        'global_id': payoutGlobalId,
        'supplier_global_id': supplierGlobalId,
        'supplierId': supplierId,
        'amount': amount,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'createdAt': nowIso,
        'updatedAt': nowIso,
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
        details:
            'المورد: $name (#$supplierId) • الفاتورة المرجعية: #$invoiceId • المنفذ: $actor',
        amount: amount,
        tenantId: tenantInt,
      );

      int? ledgerId;
      if (affectsCash) {
        final led = await txn.query(
          'cash_ledger',
          columns: ['id'],
          where:
              'invoiceId = ? AND tenantId = ? AND transactionType = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId, tid, 'supplier_payment'],
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
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForSuppliers(db, sessionTenant);
    await _ensureSupplierApTables(db);
    final deleted = await db.transaction((txn) async {
      final rows = await txn.query(
        'supplier_payouts',
        where: 'id = ? AND supplierId = ? AND tenantId = ?',
        whereArgs: [payoutId, supplierId, tid],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final r = rows.first;
      final affectsCash = ((r['affectsCash'] as int?) ?? 1) == 1;
      final amount = (r['amount'] as num).toDouble();
      final receiptInvoiceId = (r['receiptInvoiceId'] as num?)?.toInt();
      final tenantInt = (r['tenantId'] as num?)?.toInt() ?? 1;
      final actor = ((r['createdByUserName'] as String?) ?? '').trim().isEmpty
          ? 'غير معروف'
          : ((r['createdByUserName'] as String?) ?? '').trim();

      if (receiptInvoiceId != null && receiptInvoiceId > 0) {
        // Step 10 (soft delete): financial rows must never be hard-deleted —
        // audit relies on `deleted_at` being present and the original row
        // intact. Each table is in the soft-delete migration scope, so a
        // simple UPDATE stamps the tombstone tenant-scoped.
        final nowIso = DateTime.now().toUtc().toIso8601String();
        await DbCashSqlOps.softDeleteCashLedgerEntry(
          txn,
          tenantInt,
          where: 'invoiceId = ?',
          whereArgs: [receiptInvoiceId],
        );
        await txn.update(
          'invoice_items',
          {'deleted_at': nowIso, 'updatedAt': nowIso},
          where:
              'invoiceId = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [receiptInvoiceId, tid],
        );
        await txn.update(
          'invoices',
          {'deleted_at': nowIso, 'updatedAt': nowIso},
          where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [receiptInvoiceId, tid],
        );
        await _insertActivityLogInTxn(
          txn,
          type: 'supplier_receipt_deleted',
          refTable: 'invoices',
          refId: receiptInvoiceId,
          title: 'حذف سند دفع مورد',
          details:
              'المورد #$supplierId • الحذف ضمن عكس دفعة #$payoutId • المنفذ: $actor',
          amount: amount,
          tenantId: tenantInt,
        );
      }

      if (affectsCash && amount > 1e-9) {
        int? openShiftId;
        final ws = await txn.query(
          'work_shifts',
          columns: ['id'],
          where: 'closedAt IS NULL AND tenantId = ? AND deleted_at IS NULL',
          whereArgs: [tid],
          limit: 1,
        );
        if (ws.isNotEmpty) {
          openShiftId = ws.first['id'] as int;
        }
        final sup = await txn.query(
          'suppliers',
          columns: ['name'],
          where: 'id = ? AND tenantId = ?',
          whereArgs: [supplierId, tid],
          limit: 1,
        );
        final name = (sup.isNotEmpty ? sup.first['name'] as String? : null)
                ?.trim() ??
            'مورد';
        await DbCashSqlOps.insertCashLedgerEntry(txn, tenantInt, {
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
          tenantId: tenantInt,
        );
      }
      final n = await DbSuppliersSqlOps.deleteSupplierPayout(
        txn,
        tid,
        payoutId,
        supplierId,
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
          tenantId: tenantInt,
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
