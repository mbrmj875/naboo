import 'package:sqflite/sqflite.dart';

import '../models/oil_change_oil_catalog_entry.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// تطبيع لزوجة للمقارنة (5w30 = 5W30).
String normalizeOilViscosityKey(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

/// كتالوج أسعار زيت غيار الزيت (ماركة + لزوجة + سعر البيع/لتر بالفلس).
class OilChangeOilCatalogRepository {
  OilChangeOilCatalogRepository._();
  static final OilChangeOilCatalogRepository instance =
      OilChangeOilCatalogRepository._();

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
    await _dbHelper.ensureOilChangeOilCatalogSchema();
  }

  Future<List<OilChangeOilCatalogEntry>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'oil_change_oil_catalog',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy: 'brandName COLLATE NOCASE ASC, sortOrder ASC, viscosity COLLATE NOCASE ASC',
    );
    return dedupeCatalogEntries(
      rows.map(OilChangeOilCatalogEntry.fromMap).toList(),
    );
  }

  /// أول صف لكل (ماركة + لزوجة) — يتجاهل التكرارات القديمة في DB.
  static List<OilChangeOilCatalogEntry> dedupeCatalogEntries(
    List<OilChangeOilCatalogEntry> raw,
  ) {
    final seen = <String>{};
    final out = <OilChangeOilCatalogEntry>[];
    for (final e in raw) {
      final key =
          '${e.brandName.toLowerCase()}|${normalizeOilViscosityKey(e.viscosity)}';
      if (seen.add(key)) out.add(e);
    }
    return out;
  }

  static List<String> brandNamesFrom(List<OilChangeOilCatalogEntry> entries) {
    final names = <String>{};
    for (final e in entries) {
      if (e.brandName.isNotEmpty) names.add(e.brandName);
    }
    final out = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  static List<OilChangeOilCatalogEntry> entriesForBrand(
    List<OilChangeOilCatalogEntry> entries,
    String brandName,
  ) {
    final key = brandName.trim().toLowerCase();
    return entries
        .where((e) => e.brandName.toLowerCase() == key)
        .toList()
      ..sort(
        (a, b) => a.viscosity.toLowerCase().compareTo(b.viscosity.toLowerCase()),
      );
  }

  static OilChangeOilCatalogEntry? entryForBrandViscosity(
    List<OilChangeOilCatalogEntry> entries, {
    required String brandName,
    required String viscosity,
  }) {
    final b = brandName.trim().toLowerCase();
    final v = normalizeOilViscosityKey(viscosity);
    for (final e in entries) {
      if (e.brandName.toLowerCase() == b &&
          normalizeOilViscosityKey(e.viscosity) == v) {
        return e;
      }
    }
    return null;
  }

  Future<List<String>> listBrandNames() async {
    final items = await listActive();
    final names = <String>{};
    for (final e in items) {
      if (e.brandName.isNotEmpty) names.add(e.brandName);
    }
    final out = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  Future<bool> existsActiveBrandViscosity({
    required String brandName,
    required String viscosity,
    int? excludeId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim().toLowerCase();
    final vis = normalizeOilViscosityKey(viscosity);
    if (brand.isEmpty || vis.isEmpty) return false;

    final args = <Object?>[tid, brand, vis];
    var sql = '''
      SELECT id FROM oil_change_oil_catalog
      WHERE tenantId = ?
        AND deletedAt IS NULL
        AND LOWER(TRIM(brandName)) = ?
        AND UPPER(REPLACE(TRIM(viscosity), ' ', '')) = ?
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
    required String brandName,
    required String viscosity,
    required int sellPerLiterFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim();
    final vis = normalizeOilViscosityKey(viscosity);
    if (brand.isEmpty || vis.isEmpty) {
      throw StateError('brand_viscosity_required');
    }
    if (await existsActiveBrandViscosity(brandName: brand, viscosity: vis)) {
      throw StateError('duplicate_brand_viscosity');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM oil_change_oil_catalog '
      'WHERE tenantId = ? AND deletedAt IS NULL AND brandName = ? COLLATE NOCASE',
      [tid, brand],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('oil_change_oil_catalog', {
      'tenantId': tid,
      'brandName': brand,
      'viscosity': vis,
      'sellPerLiterFils': sellPerLiterFils < 0 ? 0 : sellPerLiterFils,
      'sortOrder': nextSort,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleSync();
    return id;
  }

  Future<void> updateById({
    required int id,
    required String brandName,
    required String viscosity,
    required int sellPerLiterFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim();
    final vis = normalizeOilViscosityKey(viscosity);
    if (await existsActiveBrandViscosity(
      brandName: brand,
      viscosity: vis,
      excludeId: id,
    )) {
      throw StateError('duplicate_brand_viscosity');
    }
    await db.update(
      'oil_change_oil_catalog',
      {
        'brandName': brand,
        'viscosity': vis,
        'sellPerLiterFils': sellPerLiterFils < 0 ? 0 : sellPerLiterFils,
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
      'oil_change_oil_catalog',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
