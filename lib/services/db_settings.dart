part of 'database_helper.dart';

/// وقت الصف الافتراضي لإعدادات الدين والتقسيط: أقدم من أي حفظ حقيقي،
/// فلا يغلب جهازٌ جديد بقيمه الافتراضية إعدادات المالك عند دمج المزامنة.
const String kSettingsDefaultRowStamp = '1970-01-01T00:00:00.000Z';

/// هل صف إعدادات (دين/تقسيط) يحمل القيم الافتراضية فقط؟ null = ليس جدول إعدادات من هذا النوع.
bool? singletonSettingsRowIsDefault(String table, Map<String, dynamic> row) {
  final raw = row['payload']?.toString();
  switch (table) {
    case 'debt_settings':
      return DebtSettingsData.mergeFromJsonString(raw).toJsonString() ==
          DebtSettingsData.defaults().toJsonString();
    case 'installment_settings':
      return InstallmentSettingsData.mergeFromJsonString(raw).toJsonString() ==
          InstallmentSettingsData.defaults().toJsonString();
  }
  return null;
}

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
