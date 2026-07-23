import 'package:sqflite/sqflite.dart';

import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// كتالوج أسعار فلاتر غيار الزيت (فئة + اسم + سعر بالفلس).
class OilChangeFilterCatalogRepository {
  OilChangeFilterCatalogRepository._();
  static final OilChangeFilterCatalogRepository instance =
      OilChangeFilterCatalogRepository._();

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
    await _dbHelper.ensureOilChangeFilterCatalogSchema();
  }

  Future<List<OilChangeFilterCatalogEntry>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'oil_change_filter_catalog',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy:
          'filterKind ASC, name COLLATE NOCASE ASC, sortOrder ASC, id ASC',
    );
    return rows.map(OilChangeFilterCatalogEntry.fromMap).toList();
  }

  static List<OilChangeFilterCatalogEntry> entriesForKind(
    List<OilChangeFilterCatalogEntry> entries,
    OilChangeFilterKind kind,
  ) {
    return entries
        .where((e) => e.kind == kind)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  static OilChangeFilterCatalogEntry? entryById(
    List<OilChangeFilterCatalogEntry> entries,
    int id,
  ) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<bool> existsActiveKindName({
    required OilChangeFilterKind kind,
    required String name,
    int? excludeId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;

    final args = <Object?>[tid, kind.code, n];
    var sql = '''
      SELECT id FROM oil_change_filter_catalog
      WHERE tenantId = ?
        AND deletedAt IS NULL
        AND filterKind = ?
        AND LOWER(TRIM(name)) = ?
    ''';
    if (excludeId != null && excludeId > 0) {
      sql += ' AND id != ?';
      args.add(excludeId);
    }
    sql += ' LIMIT 1';

    final rows = await db.rawQuery(sql, args);
    return rows.isNotEmpty;
  }

  Future<int> insert({
    required OilChangeFilterKind kind,
    required String name,
    required int priceFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final label = name.trim();
    final fils = priceFils < 0 ? 0 : priceFils;
    if (fils <= 0) throw StateError('price_required');
    if (label.isNotEmpty &&
        await existsActiveKindName(kind: kind, name: label)) {
      throw StateError('duplicate_kind_name');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM oil_change_filter_catalog '
      'WHERE tenantId = ? AND deletedAt IS NULL AND filterKind = ?',
      [tid, kind.code],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('oil_change_filter_catalog', {
      'tenantId': tid,
      'filterKind': kind.code,
      'name': label,
      'priceFils': fils,
      'sortOrder': nextSort,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleSync();
    return id;
  }

  Future<void> updateById({
    required int id,
    required OilChangeFilterKind kind,
    required String name,
    required int priceFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final label = name.trim();
    final fils = priceFils < 0 ? 0 : priceFils;
    if (fils <= 0) throw StateError('price_required');
    if (label.isNotEmpty &&
        await existsActiveKindName(
          kind: kind,
          name: label,
          excludeId: id,
        )) {
      throw StateError('duplicate_kind_name');
    }
    await db.update(
      'oil_change_filter_catalog',
      {
        'filterKind': kind.code,
        'name': label,
        'priceFils': fils,
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
      'oil_change_filter_catalog',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
