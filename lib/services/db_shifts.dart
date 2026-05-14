part of 'database_helper.dart';

// ── الورديات (Work Shifts) ────────────────────────────────────────────────
//
// Step 7 (tenant isolation):
// Every read/write for work_shifts (and the related shift→invoice joins)
// goes through [TenantContext.requireTenantId] before touching SQLite, and
// every SQL statement carries `tenantId = ?` so a session belonging to one
// tenant can never observe (or mutate) another tenant's shifts. The pure
// SQL is exposed via [DbShiftsSqlOps] so unit tests can drive it against
// the in-memory FFI database from `test/helpers/in_memory_db.dart` without
// instantiating the production [DatabaseHelper] singleton.

/// ترحيل [work_shifts.global_id] للمزامنة عبر اللقطة والطابور.
Future<void> ensureWorkShiftsGlobalIdSchema(Database db) async {
  Future<void> addColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(work_shifts)');
    final exists = rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
    );
    if (!exists) {
      try {
        await db.execute('ALTER TABLE work_shifts ADD COLUMN $col $type');
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[ensureWorkShiftsGlobalIdSchema] ALTER work_shifts ADD $col failed: $e\n$st',
          );
        }
      }
    }
  }

  await addColumn('global_id', 'TEXT');
  await addColumn('updatedAt', 'TEXT');
  await addColumn('tenantId', 'INTEGER NOT NULL DEFAULT 1');

  Future<bool> colExists(String name) async {
    final rows = await db.rawQuery('PRAGMA table_info(work_shifts)');
    return rows.any(
      (r) => (r['name']?.toString().toLowerCase() ?? '') == name.toLowerCase(),
    );
  }

  if (await colExists('global_id')) {
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_work_shifts_global_id
        ON work_shifts(global_id)
        WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
      ''');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[ensureWorkShiftsGlobalIdSchema] CREATE INDEX uq_work_shifts_global_id failed: $e\n$st',
        );
      }
    }
  }

  if (!await colExists('global_id')) return;

  final missing = await db.rawQuery('''
    SELECT id FROM work_shifts
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');
  final nowIso = DateTime.now().toUtc().toIso8601String();
  for (final r in missing) {
    final id = r['id'] as int?;
    if (id == null) continue;
    await db.update(
      'work_shifts',
      {
        'global_id': const Uuid().v4(),
        'updatedAt': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute('''
    UPDATE work_shifts
    SET updatedAt = openedAt
    WHERE updatedAt IS NULL OR TRIM(IFNULL(updatedAt, '')) = ''
  ''');
}

/// Pure SQL operations for the work-shifts domain, parameterised over
/// `tenantId` so they can be covered by unit tests with the in-memory schema.
/// Production callers must always go through the [DbShifts] extension on
/// [DatabaseHelper], which gates each call on
/// [TenantContext.requireTenantId] before invoking these helpers.
@visibleForTesting
class DbShiftsSqlOps {
  DbShiftsSqlOps._();

  static Future<Map<String, dynamic>?> getWorkShiftById(
    DatabaseExecutor db,
    int tenantId,
    int id,
  ) async {
    final rows = await db.query(
      'work_shifts',
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [id, tenantId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> getOpenWorkShift(
    DatabaseExecutor db,
    int tenantId,
  ) async {
    final rows = await db.query(
      'work_shifts',
      where: 'closedAt IS NULL AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [tenantId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, int>> getWorkShiftInvoiceCounts(
    DatabaseExecutor db,
    int tenantId,
    int shiftId,
  ) async {
    final salesRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND workShiftId = ?
        AND IFNULL(isReturned, 0) = 0
      ''',
      [tenantId, shiftId],
    );
    final retRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND workShiftId = ?
        AND IFNULL(isReturned, 0) = 1
      ''',
      [tenantId, shiftId],
    );
    final s = (salesRows.first['c'] as num?)?.toInt() ?? 0;
    final r = (retRows.first['c'] as num?)?.toInt() ?? 0;
    return {'sales': s, 'returns': r};
  }

  static Future<Map<int, Map<String, dynamic>>> getWorkShiftsMapByIds(
    DatabaseExecutor db,
    int tenantId,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT ws.id, ws.sessionUserId, ws.openedAt, ws.closedAt, ws.shiftStaffName,
             ws.systemBalanceAtOpen, ws.declaredPhysicalCash, ws.addedCashAtOpen,
             ws.declaredClosingCash, ws.systemBalanceAtClose, ws.withdrawnAtClose,
             ws.declaredCashInBoxAtClose,
             u.displayName AS sessionDisplayName,
             u.username AS sessionUsername
      FROM work_shifts ws
      LEFT JOIN users u ON u.id = ws.sessionUserId
      WHERE ws.tenantId = ?
        AND ws.deleted_at IS NULL
        AND ws.id IN ($placeholders)
      ''',
      [tenantId, ...list],
    );
    final map = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      map[r['id'] as int] = r;
    }
    return map;
  }

  static Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingRange(
    DatabaseExecutor db,
    int tenantId,
    DateTime rangeStartInclusive,
    DateTime rangeEndExclusive, {
    String orderBy = 'openedAt ASC',
    List<String>? columns,
  }) {
    final cols = columns ??
        const [
          'id',
          'sessionUserId',
          'openedAt',
          'closedAt',
          'shiftStaffName',
        ];
    return db.rawQuery(
      '''
      SELECT ${cols.join(', ')}
      FROM work_shifts
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND openedAt < ?
        AND (closedAt IS NULL OR closedAt >= ?)
      ORDER BY $orderBy
      ''',
      [
        tenantId,
        rangeEndExclusive.toIso8601String(),
        rangeStartInclusive.toIso8601String(),
      ],
    );
  }

  static Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingMonth(
    DatabaseExecutor db,
    int tenantId,
    int year,
    int month,
  ) {
    final monthStart = DateTime(year, month, 1);
    final nextMonthStart = DateTime(year, month + 1, 1);
    return listWorkShiftsOverlappingRange(
      db,
      tenantId,
      monthStart,
      nextMonthStart,
      orderBy: 'openedAt DESC',
      columns: const [
        'id',
        'sessionUserId',
        'openedAt',
        'closedAt',
        'shiftStaffName',
        'declaredPhysicalCash',
        'systemBalanceAtOpen',
        'withdrawnAtClose',
      ],
    );
  }

  static Future<Map<int, int>> getInvoiceTotalCountsByShiftIds(
    DatabaseExecutor db,
    int tenantId,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT workShiftId, COUNT(*) AS c FROM invoices
      WHERE tenantId = ?
        AND deleted_at IS NULL
        AND workShiftId IN ($placeholders)
      GROUP BY workShiftId
      ''',
      [tenantId, ...list],
    );
    final m = <int, int>{};
    for (final r in rows) {
      final sid = r['workShiftId'] as int?;
      if (sid != null) {
        m[sid] = (r['c'] as num?)?.toInt() ?? 0;
      }
    }
    return m;
  }

  /// Inserts a `work_shifts` row, stamping `tenantId` from the active session
  /// regardless of whatever the caller passed in [values].
  static Future<int> insertWorkShift(
    DatabaseExecutor txn,
    int tenantId,
    Map<String, dynamic> values,
  ) {
    final stamped = Map<String, dynamic>.from(values);
    stamped['tenantId'] = tenantId;
    return txn.insert('work_shifts', stamped);
  }

  /// Updates a single work_shift, blocking cross-tenant updates via the
  /// `tenantId = ?` predicate (returns 0 rows affected on mismatch). Also
  /// excludes soft-deleted shifts so an UPDATE cannot resurrect a tombstoned
  /// row.
  static Future<int> updateWorkShift(
    DatabaseExecutor txn,
    int tenantId,
    int shiftId,
    Map<String, dynamic> values,
  ) {
    return txn.update(
      'work_shifts',
      values,
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [shiftId, tenantId],
    );
  }

  /// Soft-deletes a `work_shifts` row by stamping `deleted_at`. Cross-tenant
  /// or already-deleted rows return 0 rows affected.
  static Future<int> softDeleteWorkShift(
    DatabaseExecutor txn,
    int tenantId,
    int shiftId,
  ) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return txn.update(
      'work_shifts',
      {'deleted_at': nowIso, 'updatedAt': nowIso},
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [shiftId, tenantId],
    );
  }
}

extension DbShifts on DatabaseHelper {
  Future<int> _activeTenantIdForShifts(Database db, String sessionTenant) async {
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

  Future<Map<String, dynamic>?> getWorkShiftById(int id) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.getWorkShiftById(db, tid, id);
  }

  /// وردية مفتوحة (إن وُجدت) — closedAt فارغ.
  Future<Map<String, dynamic>?> getOpenWorkShift() async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.getOpenWorkShift(db, tid);
  }

  /// فتح وردية جديدة.
  Future<int> openWorkShift({
    required int sessionUserId,
    required int shiftStaffUserId,
    required double systemBalanceAtOpen,
    required double declaredPhysicalCash,
    required double addedCashAtOpen,
    required String shiftStaffName,
    required String shiftStaffPin,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    await ensureCashLedgerGlobalIdSchema(db);
    await ensureWorkShiftsGlobalIdSchema(db);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final globalId = const Uuid().v4();

    final shiftPayload = {
      'global_id': globalId,
      'tenantId': tid,
      'sessionUserId': sessionUserId,
      'shiftStaffUserId': shiftStaffUserId,
      'openedAt': nowIso,
      'closedAt': null,
      'systemBalanceAtOpen': systemBalanceAtOpen,
      'declaredPhysicalCash': declaredPhysicalCash,
      'addedCashAtOpen': addedCashAtOpen,
      'shiftStaffName': shiftStaffName,
      'shiftStaffPin': shiftStaffPin,
      'declaredClosingCash': null,
      'systemBalanceAtClose': null,
      'withdrawnAtClose': null,
      'declaredCashInBoxAtClose': null,
      'updatedAt': nowIso,
    };

    final id = await db.transaction((txn) async {
      final id = await DbShiftsSqlOps.insertWorkShift(txn, tid, shiftPayload);

      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'work_shift',
        globalId: globalId,
        operation: 'INSERT',
        payload: shiftPayload,
      );

      if (addedCashAtOpen > 0) {
        final cashGlobalId = const Uuid().v4();
        final cashPayload = {
          'global_id': cashGlobalId,
          'tenantId': tid,
          'transactionType': 'manual_in',
          'amount': addedCashAtOpen,
          'amountFils': (addedCashAtOpen * 1000).round(),
          'description': 'إيداع عند فتح الوردية #$id',
          'invoiceId': null,
          'workShiftId': id,
          'work_shift_global_id': globalId,
          'createdAt': nowIso,
          'updatedAt': nowIso,
        };
        await DbCashSqlOps.insertCashLedgerEntry(txn, tid, cashPayload);
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'cash_ledger',
          globalId: cashGlobalId,
          operation: 'INSERT',
          payload: cashPayload,
        );
      }
      return id;
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  /// إغلاق وردية: تسجيل الجرد، سحب المستخدم، وقيد manual_out عند السحب.
  Future<void> closeWorkShift({
    required int shiftId,
    required double systemBalanceAtCloseMoment,
    required double declaredCashInBox,
    required double withdrawnAmount,
    required double declaredClosingCash,
  }) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    if (withdrawnAmount < 0 || declaredCashInBox < 0) {
      throw ArgumentError('قيم غير صالحة');
    }
    if (withdrawnAmount > declaredCashInBox + 0.0001) {
      throw ArgumentError('المبلغ المسحوب أكبر من المبلغ في الصندوق');
    }

    // Tenant-scoped fetch — a cross-tenant or soft-deleted shiftId silently
    // no-ops, matching the pre-existing "shift not found" semantics.
    final wsRows = await db.query(
      'work_shifts',
      where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
      whereArgs: [shiftId, tid],
    );
    if (wsRows.isEmpty) return;
    final wsGlobalId = wsRows.first['global_id'] as String?;

    await db.transaction((txn) async {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (withdrawnAmount > 0) {
        final cashGlobalId = const Uuid().v4();
        final cashPayload = {
          'global_id': cashGlobalId,
          'tenantId': tid,
          'transactionType': 'manual_out',
          'amount': -withdrawnAmount,
          'amountFils': (-withdrawnAmount * 1000).round(),
          'description': 'سحب عند إغلاق الوردية #$shiftId',
          'invoiceId': null,
          'workShiftId': shiftId,
          'work_shift_global_id': wsGlobalId,
          'createdAt': nowIso,
          'updatedAt': nowIso,
        };
        await DbCashSqlOps.insertCashLedgerEntry(txn, tid, cashPayload);
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'cash_ledger',
          globalId: cashGlobalId,
          operation: 'INSERT',
          payload: cashPayload,
        );
      }

      final updatedPayload = {
        'closedAt': nowIso,
        'declaredClosingCash': declaredClosingCash,
        'systemBalanceAtClose': systemBalanceAtCloseMoment,
        'withdrawnAtClose': withdrawnAmount,
        'declaredCashInBoxAtClose': declaredCashInBox,
        'updatedAt': nowIso,
      };

      await DbShiftsSqlOps.updateWorkShift(txn, tid, shiftId, updatedPayload);

      if (wsGlobalId != null) {
        final fullRow = Map<String, dynamic>.from(wsRows.first)
          ..addAll(updatedPayload);
        await SyncQueueService.instance.enqueueMutation(
          txn,
          entityType: 'work_shift',
          globalId: wsGlobalId,
          operation: 'UPDATE',
          payload: fullRow,
        );
      }
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// عدد فواتير البيع وعدد المرتجعات المرتبطة بوردية محددة.
  Future<Map<String, int>> getWorkShiftInvoiceCounts(int shiftId) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.getWorkShiftInvoiceCounts(db, tid, shiftId);
  }

  /// بيانات ورديات لربطها بقائمة الفواتير.
  Future<Map<int, Map<String, dynamic>>> getWorkShiftsMapByIds(
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.getWorkShiftsMapByIds(db, tid, ids);
  }

  /// ورديات تتقاطع مع شهر تقويمي.
  Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingMonth(
    int year,
    int month,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.listWorkShiftsOverlappingMonth(db, tid, year, month);
  }

  /// ورديات تتقاطع مع فترة محددة.
  Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingRange(
    DateTime rangeStartInclusive,
    DateTime rangeEndExclusive,
  ) async {
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.listWorkShiftsOverlappingRange(
      db,
      tid,
      rangeStartInclusive,
      rangeEndExclusive,
    );
  }

  /// عدد الفواتير (كلها) لكل وردية.
  Future<Map<int, int>> getInvoiceTotalCountsByShiftIds(Set<int> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final sessionTenant = TenantContext.instance.requireTenantId();
    final tid = await _activeTenantIdForShifts(db, sessionTenant);
    return DbShiftsSqlOps.getInvoiceTotalCountsByShiftIds(db, tid, ids);
  }
}
