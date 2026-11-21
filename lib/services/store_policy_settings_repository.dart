import 'package:sqflite/sqflite.dart';

import '../models/store_policy.dart';
import 'database_helper.dart';
import 'returns/returns_offers_db_schema.dart';

/// سياسات المحل (الاسترجاع وعروض الغسيل) — صف واحد id=1 يُزامن مع اللقطة.
class StorePolicySettingsRepository {
  StorePolicySettingsRepository._();
  static final StorePolicySettingsRepository instance =
      StorePolicySettingsRepository._();

  /// للاختبارات: قاعدة بديلة.
  static Future<Database> Function()? databaseOverride;

  Future<Database> get _db async => databaseOverride != null
      ? databaseOverride!()
      : DatabaseHelper().database;

  Future<StorePolicy> load() async {
    final db = await _db;
    await ensureReturnsAndOffersSchema(db);
    final rows = await db.query(
      'store_policy_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return const StorePolicy();
    return StorePolicy.fromJsonString(rows.first['payload'] as String?);
  }

  Future<void> save(StorePolicy policy, {String? updatedBy}) async {
    final db = await _db;
    await ensureReturnsAndOffersSchema(db);
    await db.insert('store_policy_settings', {
      'id': 1,
      'payload': policy.toJsonString(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedBy': updatedBy,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
