import 'package:sqflite/sqflite.dart';

import '../models/loyalty_settings_data.dart';
import 'database_helper.dart';

/// قراءة/كتابة إعدادات الولاء في جدول [loyalty_settings] (صف واحد id=1).
class LoyaltySettingsRepository {
  LoyaltySettingsRepository._();
  static final LoyaltySettingsRepository instance = LoyaltySettingsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<LoyaltySettingsData> load() async {
    final db = await _db;
    final rows = await db.query(
      'loyalty_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return LoyaltySettingsData.defaults();
    final payload = rows.first['payload'] as String?;
    return LoyaltySettingsData.mergeFromJsonString(payload);
  }

  Future<void> save(LoyaltySettingsData data) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'loyalty_settings',
      {
        'id': 1,
        'payload': data.toJsonString(),
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
