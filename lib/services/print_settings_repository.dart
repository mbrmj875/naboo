import 'package:sqflite/sqflite.dart';

import '../models/print_settings_data.dart';
import 'database_helper.dart';

/// قراءة/كتابة إعدادات الطباعة في جدول [print_settings] (صف واحد id=1).
class PrintSettingsRepository {
  PrintSettingsRepository._();
  static final PrintSettingsRepository instance = PrintSettingsRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<PrintSettingsData> load() async {
    final db = await _db;
    final rows = await db.query(
      'print_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return PrintSettingsData.defaults();
    final payload = rows.first['payload'] as String?;
    return PrintSettingsData.mergeFromJsonString(payload);
  }

  Future<void> save(PrintSettingsData data) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'print_settings',
      {
        'id': 1,
        'payload': data.toJsonString(),
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
