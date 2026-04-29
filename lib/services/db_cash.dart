part of 'database_helper.dart';

// ── الصندوق (cash ledger) ─────────────────────────────────────────────────

extension DbCash on DatabaseHelper {
  int _toFils(double amount) {
    if (!amount.isFinite || amount.isNaN) return 0;
    return (amount * 1000).round();
  }

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
        COALESCE(SUM(CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END), 0) AS balanceFils,
        COALESCE(SUM(CASE WHEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) > 0 THEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) ELSE 0 END), 0) AS totalInFils,
        COALESCE(SUM(CASE WHEN (CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) < 0 THEN -(CASE WHEN amountFils != 0 THEN amountFils ELSE ROUND(amount * 1000) END) ELSE 0 END), 0) AS totalOutFils
      FROM cash_ledger
    ''');
    final m = rows.first;
    return {
      'balance': ((m['balanceFils'] as num?)?.toDouble() ?? 0) / 1000.0,
      'totalIn': ((m['totalInFils'] as num?)?.toDouble() ?? 0) / 1000.0,
      'totalOut': ((m['totalOutFils'] as num?)?.toDouble() ?? 0) / 1000.0,
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
      'amountFils': _toFils(amount),
      'description': description,
      'invoiceId': null,
      'workShiftId': openShiftId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }
}
