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
    return db.query(
      'cash_ledger',
      where: 'tenantId = ? AND deleted_at IS NULL',
      whereArgs: [tenantId],
      orderBy: 'id DESC',
      limit: limit,
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

  Future<Map<String, double>> getCashSummary() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    return DbCashSqlOps.getCashSummary(db, tid);
  }

  Future<int> insertManualCashEntry({
    required double amount,
    required String description,
    required String transactionType,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForCash(db, sessionTenant);
    await ensureCashLedgerGlobalIdSchema(db);
    int? openShiftId;
    String? openShiftGlobalId;
    final ws = await db.query(
      'work_shifts',
      columns: ['id', 'global_id'],
      where: 'closedAt IS NULL AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [tid],
      limit: 1,
    );
    if (ws.isNotEmpty) {
      openShiftId = ws.first['id'] as int;
      openShiftGlobalId = ws.first['global_id'] as String?;
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
