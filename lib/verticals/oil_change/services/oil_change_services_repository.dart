import 'package:sqflite/sqflite.dart';

import '../models/oil_change_service_item.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// كتالوج خدمات غيار الزيت الإضافية (بجانب سعر تبديل الزيت الأساسي).
class OilChangeServicesRepository {
  OilChangeServicesRepository._();
  static final OilChangeServicesRepository instance =
      OilChangeServicesRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  void _scheduleSync() {
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<void> ensureSchema() async {
    await _dbHelper.ensureOilChangeServicesSchema();
  }

  Future<List<OilChangeServiceItem>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'oil_change_services',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy: 'sortOrder ASC, id ASC',
    );
    return rows.map(OilChangeServiceItem.fromMap).toList();
  }

  Future<int> insert({
    required String name,
    required int priceFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM oil_change_services '
      'WHERE tenantId = ? AND deletedAt IS NULL',
      [tid],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('oil_change_services', {
      'tenantId': tid,
      'name': name.trim(),
      'priceFils': priceFils < 0 ? 0 : priceFils,
      'sortOrder': nextSort,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleSync();
    return id;
  }

  Future<void> updateById({
    required int id,
    required String name,
    required int priceFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    await db.update(
      'oil_change_services',
      {
        'name': name.trim(),
        'priceFils': priceFils < 0 ? 0 : priceFils,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }

  Future<void> softDeleteById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'oil_change_services',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
