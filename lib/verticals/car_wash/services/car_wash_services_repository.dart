import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/car_wash_service_item.dart';

/// كتالوج أنواع/خدمات الغسل (اسم + سعر) — يبدأ فارغاً؛ يضيفه المستخدم.
class CarWashServicesRepository {
  CarWashServicesRepository._();
  static final CarWashServicesRepository instance =
      CarWashServicesRepository._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<CarWashServiceItem>? _cache;
  DateTime? _cacheAt;
  Future<void>? _schemaReady;

  /// لقطة كاش فورية لفتح البطاقة بسرعة.
  List<CarWashServiceItem>? get cachedActive => _cache;

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  void invalidateCache() {
    _cache = null;
    _cacheAt = null;
  }

  Future<void> ensureSchema() {
    return _schemaReady ??= _dbHelper.ensureCarWashServicesSchema();
  }

  static const _activeWhere =
      "tenantId = ? AND (deletedAt IS NULL OR TRIM(COALESCE(deletedAt, '')) = '')";

  Future<List<CarWashServiceItem>> listActive({bool force = false}) async {
    if (!force &&
        _cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < const Duration(seconds: 45)) {
      return _cache!;
    }
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'car_wash_services',
      where: _activeWhere,
      whereArgs: [tid],
      orderBy: 'sortOrder ASC, id ASC',
    );
    final list = rows.map(CarWashServiceItem.fromMap).toList();
    _cache = list;
    _cacheAt = DateTime.now();
    return list;
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
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM car_wash_services '
      'WHERE $_activeWhere',
      [tid],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('car_wash_services', {
      'tenantId': tid,
      'name': name.trim(),
      'priceFils': priceFils < 0 ? 0 : priceFils,
      'sortOrder': nextSort,
      'createdAt': now,
      'updatedAt': now,
    });
    invalidateCache();
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
    final n = await db.update(
      'car_wash_services',
      {
        'name': name.trim(),
        'priceFils': priceFils < 0 ? 0 : priceFils,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND $_activeWhere',
      whereArgs: [id, tid],
    );
    if (n <= 0) {
      throw StateError('تعذر تحديث الخدمة.');
    }
    invalidateCache();
  }

  /// يعيد true إذا حُذفت صف فعلياً.
  Future<bool> softDeleteById(int id) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final now = DateTime.now().toUtc().toIso8601String();
    final n = await db.update(
      'car_wash_services',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND $_activeWhere',
      whereArgs: [id, tid],
    );
    if (n > 0) {
      invalidateCache();
      return true;
    }
    return false;
  }
}
