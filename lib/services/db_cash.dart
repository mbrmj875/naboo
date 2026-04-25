part of 'database_helper.dart';

// ── الصندوق (cash ledger) ─────────────────────────────────────────────────

extension DbCash on DatabaseHelper {
  /// حركات الصندوق (الأحدث أولاً).
  Future<List<Map<String, dynamic>>> getCashLedgerEntries({
    int limit = 300,
  }) async {
    final db = await database;
    return db.query('cash_ledger', orderBy: 'id DESC', limit: limit);
  }

  /// workShiftId لكل فاتورة — لربط قيود الصندوق بالوردية.
  Future<Map<int, int?>> getInvoiceShiftIdsByInvoiceIds(
    Set<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return {};
    final db = await database;
    final list = invoiceIds.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT id, workShiftId
      FROM invoices
      WHERE id IN ($placeholders)
      ''', list);
    final out = <int, int?>{for (final id in invoiceIds) id: null};
    for (final r in rows) {
      out[r['id'] as int] = r['workShiftId'] as int?;
    }
    return out;
  }

  Future<Map<String, double>> getCashSummary() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(amount), 0) AS balance,
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS totalIn,
        COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS totalOut
      FROM cash_ledger
    ''');
    final m = rows.first;
    return {
      'balance': (m['balance'] as num).toDouble(),
      'totalIn': (m['totalIn'] as num).toDouble(),
      'totalOut': (m['totalOut'] as num).toDouble(),
    };
  }

  /// قيد يدوي (إيداع/سحب) في الصندوق.
  Future<int> insertManualCashEntry({
    required double amount,
    required String description,
    required String transactionType,
  }) async {
    final db = await database;
    int? openShiftId;
    final ws = await db.query(
      'work_shifts',
      columns: ['id'],
      where: 'closedAt IS NULL',
      limit: 1,
    );
    if (ws.isNotEmpty) {
      openShiftId = ws.first['id'] as int;
    }
    final id = await db.insert('cash_ledger', {
      'transactionType': transactionType,
      'amount': amount,
      'description': description,
      'invoiceId': null,
      'workShiftId': openShiftId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }
}
