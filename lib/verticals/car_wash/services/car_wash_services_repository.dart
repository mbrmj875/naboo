import 'package:sqflite/sqflite.dart';

import '../models/car_wash_service_item.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// كتالوج أنواع غسيل السيارات — اسم وسعر يُختار عند إنشاء بطاقة غسيل.
class CarWashServicesRepository {
  CarWashServicesRepository._();
  static final CarWashServicesRepository instance =
      CarWashServicesRepository._();

  static const maxNameLength = 60;

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
    await _dbHelper.ensureCarWashServicesSchema();
  }

  /// يوحّد المسافات ويقصّ الطول حتى لا تتكرر الأسماء بفروق شكلية.
  static String normalizeName(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > maxNameLength
        ? compact.substring(0, maxNameLength)
        : compact;
  }

  Future<List<CarWashServiceItem>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'car_wash_services',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy: 'sortOrder ASC, id ASC',
    );
    return rows.map(CarWashServiceItem.fromMap).toList(growable: false);
  }

  /// يُرجع معرّف النوع؛ الاسم المكرر يُحدَّث سعره بدل إنشاء صف ثانٍ.
  Future<int> insert({
    required String name,
    required int priceFils,
  }) async {
    final clean = normalizeName(name);
    if (clean.isEmpty) return 0;

    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();

    final existing = await db.query(
      'car_wash_services',
      columns: ['id'],
      where: 'tenantId = ? AND deletedAt IS NULL AND name = ? COLLATE NOCASE',
      whereArgs: [tid, clean],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = (existing.first['id'] as num).toInt();
      await updateById(id: id, name: clean, priceFils: priceFils);
      return id;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM car_wash_services '
      'WHERE tenantId = ? AND deletedAt IS NULL',
      [tid],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('car_wash_services', {
      'tenantId': tid,
      'name': clean,
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
    final clean = normalizeName(name);
    if (clean.isEmpty) return;
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    await db.update(
      'car_wash_services',
      {
        'name': clean,
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
      'car_wash_services',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
