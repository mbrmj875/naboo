part of 'database_helper.dart';

// ── إعدادات التقسيط ───────────────────────────────────────────────────────

extension DbSettings on DatabaseHelper {
  Future<InstallmentSettingsData> getInstallmentSettings() async {
    final db = await database;
    await _ensureInstallmentSettingsTable(db);
    final rows = await db.query(
      'installment_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return InstallmentSettingsData.defaults();
    return InstallmentSettingsData.mergeFromJsonString(
      rows.first['payload'] as String?,
    );
  }

  Future<void> saveInstallmentSettings(InstallmentSettingsData data) async {
    final db = await database;
    await _ensureInstallmentSettingsTable(db);
    await db.insert('installment_settings', {
      'id': 1,
      'payload': data.toJsonString(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── إعدادات الديون (آجل) ─────────────────────────────────────────────────

  Future<DebtSettingsData> getDebtSettings() async {
    final db = await database;
    await _ensureDebtSettingsTable(db);
    final rows = await db.query(
      'debt_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return DebtSettingsData.defaults();
    return DebtSettingsData.mergeFromJsonString(
      rows.first['payload'] as String?,
    );
  }

  Future<void> saveDebtSettings(DebtSettingsData data) async {
    final db = await database;
    await _ensureDebtSettingsTable(db);
    await db.insert('debt_settings', {
      'id': 1,
      'payload': data.toJsonString(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
