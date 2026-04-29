part of 'database_helper.dart';

// ── الورديات (Work Shifts) ────────────────────────────────────────────────

extension DbShifts on DatabaseHelper {
  Future<Map<String, dynamic>?> getWorkShiftById(int id) async {
    final db = await database;
    final rows = await db.query(
      'work_shifts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// وردية مفتوحة (إن وُجدت) — closedAt فارغ.
  Future<Map<String, dynamic>?> getOpenWorkShift() async {
    final db = await database;
    final rows = await db.query(
      'work_shifts',
      where: 'closedAt IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
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
    final id = await db.transaction((txn) async {
      final id = await txn.insert('work_shifts', {
        'sessionUserId': sessionUserId,
        'shiftStaffUserId': shiftStaffUserId,
        'openedAt': DateTime.now().toIso8601String(),
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
      });
      if (addedCashAtOpen > 0) {
        await txn.insert('cash_ledger', {
          'transactionType': 'manual_in',
          'amount': addedCashAtOpen,
          'description': 'إيداع عند فتح الوردية #$id',
          'invoiceId': null,
          'workShiftId': id,
          'createdAt': DateTime.now().toIso8601String(),
        });
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
    if (withdrawnAmount < 0 || declaredCashInBox < 0) {
      throw ArgumentError('قيم غير صالحة');
    }
    if (withdrawnAmount > declaredCashInBox + 0.0001) {
      throw ArgumentError('المبلغ المسحوب أكبر من المبلغ في الصندوق');
    }

    await db.transaction((txn) async {
      if (withdrawnAmount > 0) {
        await txn.insert('cash_ledger', {
          'transactionType': 'manual_out',
          'amount': -withdrawnAmount,
          'description': 'سحب عند إغلاق الوردية #$shiftId',
          'invoiceId': null,
          'workShiftId': shiftId,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
      await txn.update(
        'work_shifts',
        {
          'closedAt': DateTime.now().toIso8601String(),
          'declaredClosingCash': declaredClosingCash,
          'systemBalanceAtClose': systemBalanceAtCloseMoment,
          'withdrawnAtClose': withdrawnAmount,
          'declaredCashInBoxAtClose': declaredCashInBox,
        },
        where: 'id = ?',
        whereArgs: [shiftId],
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// عدد فواتير البيع وعدد المرتجعات المرتبطة بوردية محددة.
  Future<Map<String, int>> getWorkShiftInvoiceCounts(int shiftId) async {
    final db = await database;
    final salesRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE workShiftId = ? AND IFNULL(isReturned, 0) = 0
      ''',
      [shiftId],
    );
    final retRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM invoices
      WHERE workShiftId = ? AND IFNULL(isReturned, 0) = 1
      ''',
      [shiftId],
    );
    final s = (salesRows.first['c'] as num?)?.toInt() ?? 0;
    final r = (retRows.first['c'] as num?)?.toInt() ?? 0;
    return {'sales': s, 'returns': r};
  }

  /// بيانات ورديات لربطها بقائمة الفواتير.
  Future<Map<int, Map<String, dynamic>>> getWorkShiftsMapByIds(
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT ws.id, ws.sessionUserId, ws.openedAt, ws.closedAt, ws.shiftStaffName,
             ws.systemBalanceAtOpen, ws.declaredPhysicalCash, ws.addedCashAtOpen,
             ws.declaredClosingCash, ws.systemBalanceAtClose, ws.withdrawnAtClose,
             ws.declaredCashInBoxAtClose,
             u.displayName AS sessionDisplayName,
             u.username AS sessionUsername
      FROM work_shifts ws
      LEFT JOIN users u ON u.id = ws.sessionUserId
      WHERE ws.id IN ($placeholders)
      ''', list);
    final map = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      map[r['id'] as int] = r;
    }
    return map;
  }

  /// ورديات تتقاطع مع شهر تقويمي.
  Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingMonth(
    int year,
    int month,
  ) async {
    final db = await database;
    final monthStart = DateTime(year, month, 1);
    final nextMonthStart = DateTime(year, month + 1, 1);
    return db.rawQuery(
      '''
      SELECT id, sessionUserId, openedAt, closedAt, shiftStaffName,
             declaredPhysicalCash, systemBalanceAtOpen, withdrawnAtClose
      FROM work_shifts
      WHERE openedAt < ? AND (closedAt IS NULL OR closedAt >= ?)
      ORDER BY openedAt DESC
      ''',
      [nextMonthStart.toIso8601String(), monthStart.toIso8601String()],
    );
  }

  /// ورديات تتقاطع مع فترة محددة.
  Future<List<Map<String, dynamic>>> listWorkShiftsOverlappingRange(
    DateTime rangeStartInclusive,
    DateTime rangeEndExclusive,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT id, sessionUserId, openedAt, closedAt, shiftStaffName
      FROM work_shifts
      WHERE openedAt < ? AND (closedAt IS NULL OR closedAt >= ?)
      ORDER BY openedAt ASC
      ''',
      [
        rangeEndExclusive.toIso8601String(),
        rangeStartInclusive.toIso8601String(),
      ],
    );
  }

  /// عدد الفواتير (كلها) لكل وردية.
  Future<Map<int, int>> getInvoiceTotalCountsByShiftIds(Set<int> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT workShiftId, COUNT(*) AS c FROM invoices
      WHERE workShiftId IN ($placeholders)
      GROUP BY workShiftId
      ''', list);
    final m = <int, int>{};
    for (final r in rows) {
      final sid = r['workShiftId'] as int?;
      if (sid != null) {
        m[sid] = (r['c'] as num?)?.toInt() ?? 0;
      }
    }
    return m;
  }
}
