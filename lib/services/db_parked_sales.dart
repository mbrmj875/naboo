part of 'database_helper.dart';

// ── مبيعات معلّقة مؤقتاً (Parked Sales) ─────────────────────────────────

extension DbParkedSales on DatabaseHelper {
  Future<int> insertParkedSale({
    String? title,
    required String payloadJson,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('parked_sales', {
      'title': title,
      'payload': payloadJson,
      'createdAt': now,
      'updatedAt': now,
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<void> updateParkedSale({
    required int id,
    String? title,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.update(
      'parked_sales',
      {
        'title': title,
        'payload': payloadJson,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> deleteParkedSale(int id) async {
    final db = await database;
    await db.delete('parked_sales', where: 'id = ?', whereArgs: [id]);
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<Map<String, dynamic>?> getParkedSaleById(int id) async {
    final db = await database;
    final rows = await db.query(
      'parked_sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listParkedSales() async {
    final db = await database;
    return db.query('parked_sales', orderBy: 'updatedAt DESC');
  }

  Future<int> countParkedSales() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM parked_sales');
    if (r.isEmpty) return 0;
    return (r.first['c'] as int?) ?? 0;
  }
}
