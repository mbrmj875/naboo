part of 'database_helper.dart';

/// ترحيل [cash_ledger.global_id] للمزامنة عبر اللقطة والطابور (بدون UNIQUE في ALTER).
///
/// Known limitation (مرحلة المصروفات): تعبئة [global_id] هنا **backfill** لكل القيود بما فيها
/// فواتير/موردين؛ **الطابور + RPC** يغطيان قيود المصروف المدفوع فقط. بقية الحركات تُزامَن عبر
/// اللقطة حتى مراحل لاحقة.
Future<void> ensureCashLedgerGlobalIdSchema(Database db) async {
  Future<void> addColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(cash_ledger)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE cash_ledger ADD COLUMN $col $type');
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[ensureCashLedgerGlobalIdSchema] ALTER cash_ledger ADD $col failed: $e\n$st',
          );
        }
      }
    }
  }

  await addColumn('global_id', 'TEXT');
  await addColumn('updatedAt', 'TEXT');
  await addColumn('work_shift_global_id', 'TEXT');

  Future<bool> colExists(String name) async {
    final rows = await db.rawQuery('PRAGMA table_info(cash_ledger)');
    return rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == name.toLowerCase(),
    );
  }

  if (await colExists('global_id')) {
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_cash_ledger_global_id
        ON cash_ledger(global_id)
        WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
      ''');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[ensureCashLedgerGlobalIdSchema] CREATE INDEX uq_cash_ledger_global_id failed: $e\n$st',
        );
      }
    }
  }

  if (!await colExists('global_id')) return;

  final missing = await db.rawQuery('''
    SELECT id FROM cash_ledger
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');
  final nowIso = DateTime.now().toUtc().toIso8601String();
  for (final r in missing) {
    final id = r['id'] as int?;
    if (id == null) continue;
    await db.update(
      'cash_ledger',
      {
        'global_id': const Uuid().v4(),
        'updatedAt': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute('''
    UPDATE cash_ledger
    SET updatedAt = createdAt
    WHERE updatedAt IS NULL OR TRIM(IFNULL(updatedAt, '')) = ''
  ''');
}

// ── الصندوق (cash ledger) ─────────────────────────────────────────────────
//
// Step 6 (tenant isolation):
// Every read/write for the cash ledger goes through
// [TenantContext.requireTenantId] before touching SQLite, and every SQL
// statement carries `tenantId = ?` so a session belonging to one tenant can
// never observe (or mutate) rows belonging to another tenant. The pure SQL
// is exposed via [DbCashSqlOps] so unit tests can drive it against the
// in-memory FFI database from `test/helpers/in_memory_db.dart` without
// instantiating the production [DatabaseHelper] singleton.

/// Pure SQL operations for the cash-ledger domain, parameterised over
/// `tenantId` so they can be covered by unit tests with the in-memory schema.
/// Production callers must always go through the [DbCash] extension on
/// [DatabaseHelper], which gates each call on
/// [TenantContext.requireTenantId] before invoking these helpers.
@visibleForTesting
class DbCashSqlOps {
  DbCashSqlOps._();

  static Future<List<Map<String, dynamic>>> getCashLedgerEntries(
    DatabaseExecutor db,
    int tenantId, {
    int limit = 300,
  }) {
    return db.rawQuery(
      '''
      SELECT
        cl.*,
        au.displayName AS actorDisplayName,
        au.username AS actorUsername,
        su.displayName AS shiftOwnerDisplayName,
        su.username AS shiftOwnerUsername
      FROM cash_ledger cl
      LEFT JOIN users au ON au.id = cl.actorUserId
      LEFT JOIN users su ON su.id = cl.shiftOwnerUserId
      WHERE cl.tenantId = ?
        AND cl.deleted_at IS NULL
      ORDER BY cl.id DESC
      LIMIT ?
      ''',
      [tenantId, limit],
    );
  }

  static Future<Map<int, int?>> getInvoiceShiftIdsByInvoiceIds(
    DatabaseExecutor db,
    int tenantId,
    Set<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return {};
    final list = invoiceIds.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT id, workShiftId
      FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND id IN ($placeholders)
      ''',
      [tenantId, ...list],
    );
    final out = <int, int?>{for (final id in invoiceIds) id: null};
    for (final r in rows) {
      out[r['id'] as int] = r['workShiftId'] as int?;
    }
    return out;
  }

  static Future<Map<String, double>> getCashSummary(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END), 0) AS balanceFils,
        COALESCE(SUM(CASE WHEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) > 0 THEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) ELSE 0 END), 0) AS totalInFils,
        COALESCE(SUM(CASE WHEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) < 0 THEN -(CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) ELSE 0 END), 0) AS totalOutFils
      FROM cash_ledger
      WHERE tenantId = ?
        AND deleted_at IS NULL
      ''',
      [tenantId],
    );
    final m = rows.first;
    return {
      'balance': ((m['balanceFils'] as num?)?.toDouble() ?? 0) / 1000.0,
      'totalIn': ((m['totalInFils'] as num?)?.toDouble() ?? 0) / 1000.0,
      'totalOut': ((m['totalOutFils'] as num?)?.toDouble() ?? 0) / 1000.0,
    };
  }

  /// Inserts a `cash_ledger` row, stamping `tenantId` from the active session
  /// regardless of whatever the caller passed in [values].
  static Future<int> insertCashLedgerEntry(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('cash_ledger', stamped);
  }

  /// Soft-deletes a `cash_ledger` row by stamping `deleted_at`. Cross-tenant
  /// or already-deleted rows return 0 rows affected and are left untouched.
  /// This replaces the previous hard `txn.delete('cash_ledger', ...)` call
  /// sites — financial ledger rows are now retained for audit.
  static Future<int> softDeleteCashLedgerEntry(
    DatabaseExecutor txn,
    int tenantId, {
    required String where,
    required List<Object?> whereArgs,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return txn.update(
      'cash_ledger',
      {'deleted_at': nowIso, 'updatedAt': nowIso},
      where: '$where AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [...whereArgs, tenantId],
    );
  }
}

extension DbCash on DatabaseHelper {
  Future<int> _activeTenantIdForCash(Database db, String sessionTenant) async {
    return _resolveActiveTenantIdForLocalDb(db);
  }

  /// يُزيل قيوداً مكررة لنفس الفاتورة (invoiceId) — يُبقي الأقدم ويُ soft-delete الباقي.
  Future<void> _dedupeCashLedgerByInvoice(Database db, int tid) async {
    final dupes = await db.rawQuery('''
      SELECT invoiceId, COUNT(*) AS c
      FROM cash_ledger
      WHERE deleted_at IS NULL
        AND invoiceId IS NOT NULL
        AND invoiceId > 0
      GROUP BY invoiceId
      HAVING COUNT(*) > 1
      LIMIT 100
    ''');
    if (dupes.isEmpty) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final d in dupes) {
        final invoiceId = (d['invoiceId'] as num?)?.toInt();
        if (invoiceId == null || invoiceId <= 0) continue;
        final rows = await txn.query(
          'cash_ledger',
          columns: ['id'],
          where: 'invoiceId = ? AND deleted_at IS NULL',
          whereArgs: [invoiceId],
          orderBy: 'id ASC',
        );
        if (rows.length <= 1) continue;
        for (var i = 1; i < rows.length; i++) {
          final rowId = rows[i]['id'] as int?;
          if (rowId == null) continue;
          await txn.update(
            'cash_ledger',
            {'deleted_at': nowIso, 'updatedAt': nowIso},
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [rowId],
          );
        }
      }
    });
  }

  /// يُصلح workShiftId الناقص على قيود مرتبطة بفاتورة.
  Future<void> _repairCashLedgerShiftIds(Database db, int tid) async {
    await db.rawUpdate(
      '''
      UPDATE cash_ledger
      SET workShiftId = (
        SELECT i.workShiftId
        FROM invoices i
        WHERE i.id = cash_ledger.invoiceId
          AND i.tenantId = ?
          AND i.deleted_at IS NULL
          AND i.workShiftId IS NOT NULL
          AND i.workShiftId > 0
        LIMIT 1
      )
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND invoiceId IS NOT NULL
        AND invoiceId > 0
        AND (workShiftId IS NULL OR workShiftId <= 0)
        AND EXISTS (
          SELECT 1 FROM invoices i
          WHERE i.id = cash_ledger.invoiceId
            AND i.tenantId = ?
            AND i.workShiftId IS NOT NULL
            AND i.workShiftId > 0
        )
      ''',
      [tid, tid, tid],
    );
  }

  /// يُوحّد tenantId للقيود القديمة ويُنشئ قيوداً ناقصة من الفواتير النقدية.
  Future<void> _ensureCashLedgerIntegrity(Database db, int tid) async {
    await db.rawUpdate(
      '''
      UPDATE cash_ledger
      SET tenantId = ?
      WHERE deleted_at IS NULL
        AND tenantId != ?
        AND NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = cash_ledger.tenantId)
      ''',
      [tid, tid],
    );

    await db.rawUpdate(
      '''
      UPDATE cash_ledger
      SET tenantId = ?
      WHERE deleted_at IS NULL
        AND tenantId != ?
        AND invoiceId IS NOT NULL
        AND invoiceId > 0
        AND EXISTS (
          SELECT 1 FROM invoices i
          WHERE i.id = cash_ledger.invoiceId
            AND i.tenantId = ?
            AND i.deleted_at IS NULL
        )
      ''',
      [tid, tid, tid],
    );

    await _dedupeCashLedgerByInvoice(db, tid);
    await _repairCashLedgerShiftIds(db, tid);

    final missing = await db.rawQuery(
      '''
      SELECT i.id, i.type, i.total, i.advancePayment, i.customerName, i.workShiftId, i.date,
             i.actorUserId, i.shiftOwnerUserId
      FROM invoices i
      WHERE i.tenantId = ?
        AND i.deleted_at IS NULL
        AND IFNULL(i.isReturned, 0) = 0
        AND NOT EXISTS (
          SELECT 1 FROM cash_ledger cl
          WHERE cl.invoiceId = i.id
            AND cl.deleted_at IS NULL
            AND cl.invoiceId IS NOT NULL
            AND cl.invoiceId > 0
        )
        AND (
          i.type = ?
          OR i.type = ?
          OR (i.type = ? AND ${MoneySql.invoiceAdvancePaymentFilsOf('i')} > 0)
          OR (i.type = ? AND ${MoneySql.invoiceAdvancePaymentFilsOf('i')} > 0)
          OR i.type = ?
          OR i.type = ?
        )
      LIMIT 200
      ''',
      [
        tid,
        InvoiceType.cash.index,
        InvoiceType.delivery.index,
        InvoiceType.credit.index,
        InvoiceType.installment.index,
        InvoiceType.debtCollection.index,
        InvoiceType.installmentCollection.index,
      ],
    );
    if (missing.isEmpty) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final row in missing) {
        final invoiceId = (row['id'] as num?)?.toInt();
        if (invoiceId == null || invoiceId <= 0) continue;
        final type = invoiceTypeFromDb(row['type']);
        final total = (row['total'] as num?)?.toDouble() ?? 0;
        final advance = (row['advancePayment'] as num?)?.toDouble() ?? 0;
        final cashAmountFils = switch (type) {
          InvoiceType.cash || InvoiceType.delivery => _toFils(total),
          InvoiceType.credit ||
          InvoiceType.installment =>
            advance > 0 ? _toFils(advance) : 0,
          InvoiceType.debtCollection ||
          InvoiceType.installmentCollection =>
            _toFils(total),
          InvoiceType.supplierPayment => 0,
        };
        if (cashAmountFils <= 0) continue;
        final cashAmount = cashAmountFils / 1000.0;

        final cust = (row['customerName'] as String?)?.trim() ?? '';
        final label = cust.isEmpty ? 'عميل' : cust;
        final typeLabel = switch (type) {
          InvoiceType.cash => 'sale_cash',
          InvoiceType.debtCollection => 'debt_collection',
          InvoiceType.installmentCollection => 'installment_collection',
          _ => advance > 0 ? 'sale_advance' : 'sale_other',
        };
        final desc = switch (type) {
          InvoiceType.debtCollection =>
            'سند تحصيل دين #$invoiceId — $label',
          InvoiceType.installmentCollection =>
            'سند تسديد قسط #$invoiceId — $label',
          _ => 'فاتورة بيع #$invoiceId — $label',
        };
        final globalId = const Uuid().v4();
        final shiftId = row['workShiftId'] as int?;
        final payload = {
          'global_id': globalId,
          'tenantId': tid,
          'transactionType': typeLabel,
          'amount': cashAmount,
          'amountFils': cashAmountFils,
          'description': desc,
          'invoiceId': invoiceId,
          'workShiftId': shiftId,
          'actorUserId': (row['actorUserId'] as num?)?.toInt(),
          'shiftOwnerUserId': (row['shiftOwnerUserId'] as num?)?.toInt(),
          'createdAt': (row['date'] as String?) ?? nowIso,
          'updatedAt': nowIso,
        };
        await DbCashSqlOps.insertCashLedgerEntry(txn, tid, payload);
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'cash_ledger',
          globalId: globalId,
          operation: 'INSERT',
          payload: payload,
        );
      }
    });
  }

  int _toFils(double amount) {
    if (!amount.isFinite || amount.isNaN) return 0;
    return (amount * 1000).round();
  }

  /// حركات الصندوق (الأحدث أولاً).
  Future<List<Map<String, dynamic>>> getCashLedgerEntries({
    int limit = 300,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    await _ensureCashLedgerIntegrity(db, tid);
    return DbCashSqlOps.getCashLedgerEntries(db, tid, limit: limit);
  }

  /// workShiftId لكل فاتورة — لربط قيود الصندوق بالوردية.
  Future<Map<int, int?>> getInvoiceShiftIdsByInvoiceIds(
    Set<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return {};
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    return DbCashSqlOps.getInvoiceShiftIdsByInvoiceIds(db, tid, invoiceIds);
  }

  /// dedupe + إصلاح tenant/وردية قبل أي عرض لرصيد الصندوق.
  Future<void> ensureCashLedgerIntegrityForSummary() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    await _ensureCashLedgerIntegrity(db, tid);
  }

  Future<Map<String, double>> getCashSummary() async {
    await ensureCashLedgerIntegrityForSummary();
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    return DbCashSqlOps.getCashSummary(db, tid);
  }

  Future<int> insertManualCashEntry({
    required double amount,
    required String description,
    required String transactionType,
    int? actorUserId,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    await ensureCashLedgerGlobalIdSchema(db);
    int? openShiftId;
    int? openShiftOwnerUserId;
    String? openShiftGlobalId;
    final ws = await db.query(
      'work_shifts',
      columns: ['id', 'global_id', 'shiftStaffUserId'],
      where: 'closedAt IS NULL AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [tid],
      limit: 1,
    );
    if (ws.isNotEmpty) {
      openShiftId = ws.first['id'] as int;
      openShiftGlobalId = ws.first['global_id'] as String?;
      openShiftOwnerUserId = (ws.first['shiftStaffUserId'] as num?)?.toInt();
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final globalId = const Uuid().v4();
    final payload = {
      'global_id': globalId,
      'tenantId': tid,
      'transactionType': transactionType,
      'amount': amount,
      'amountFils': _toFils(amount),
      'description': description,
      'invoiceId': null,
      'workShiftId': openShiftId,
      'actorUserId': actorUserId,
      'shiftOwnerUserId': openShiftOwnerUserId,
      'work_shift_global_id': openShiftGlobalId,
      'createdAt': nowIso,
      'updatedAt': nowIso,
    };

    final id = await db.transaction((txn) async {
      final insertId =
          await DbCashSqlOps.insertCashLedgerEntry(txn, tid, payload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'cash_ledger',
        globalId: globalId,
        operation: 'INSERT',
        payload: payload,
      );
      return insertId;
    });

    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }
}
