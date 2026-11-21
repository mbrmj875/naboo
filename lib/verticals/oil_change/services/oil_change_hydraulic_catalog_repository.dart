import 'package:sqflite/sqflite.dart';

import '../models/oil_change_hydraulic_catalog_entry.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// تطبيع درجة الهيدروليك للمقارنة (AW 46 = AW46).
String normalizeHydraulicGradeKey(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

/// كتالوج أسعار هيدروليك غيار الزيت (ماركة + درجة + سعر البيع/لتر بالفلس).
class OilChangeHydraulicCatalogRepository {
  OilChangeHydraulicCatalogRepository._();
  static final OilChangeHydraulicCatalogRepository instance =
      OilChangeHydraulicCatalogRepository._();

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
    await _dbHelper.ensureOilChangeHydraulicCatalogSchema();
  }

  Future<List<OilChangeHydraulicCatalogEntry>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final rows = await db.query(
      'oil_change_hydraulic_catalog',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy:
          'brandName COLLATE NOCASE ASC, sortOrder ASC, grade COLLATE NOCASE ASC',
    );
    return dedupeCatalogEntries(
      rows.map(OilChangeHydraulicCatalogEntry.fromMap).toList(),
    );
  }

  static List<OilChangeHydraulicCatalogEntry> dedupeCatalogEntries(
    List<OilChangeHydraulicCatalogEntry> raw,
  ) {
    final seen = <String>{};
    final out = <OilChangeHydraulicCatalogEntry>[];
    for (final e in raw) {
      final key =
          '${e.brandName.toLowerCase()}|${normalizeHydraulicGradeKey(e.grade)}';
      if (seen.add(key)) out.add(e);
    }
    return out;
  }

  static List<String> brandNamesFrom(
    List<OilChangeHydraulicCatalogEntry> entries,
  ) {
    final names = <String>{};
    for (final e in entries) {
      if (e.brandName.isNotEmpty) names.add(e.brandName);
    }
    final out = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  static List<OilChangeHydraulicCatalogEntry> entriesForBrand(
    List<OilChangeHydraulicCatalogEntry> entries,
    String brandName,
  ) {
    final key = brandName.trim().toLowerCase();
    return entries
        .where((e) => e.brandName.toLowerCase() == key)
        .toList()
      ..sort((a, b) => a.grade.toLowerCase().compareTo(b.grade.toLowerCase()));
  }

  static OilChangeHydraulicCatalogEntry? entryForBrandGrade(
    List<OilChangeHydraulicCatalogEntry> entries, {
    required String brandName,
    required String grade,
  }) {
    final b = brandName.trim().toLowerCase();
    final g = normalizeHydraulicGradeKey(grade);
    for (final e in entries) {
      if (e.brandName.toLowerCase() == b &&
          normalizeHydraulicGradeKey(e.grade) == g) {
        return e;
      }
    }
    return null;
  }

  Future<bool> existsActiveBrandGrade({
    required String brandName,
    required String grade,
    int? excludeId,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim().toLowerCase();
    final g = normalizeHydraulicGradeKey(grade);
    if (brand.isEmpty || g.isEmpty) return false;

    final args = <Object?>[tid, brand, g];
    var sql = '''
      SELECT id FROM oil_change_hydraulic_catalog
      WHERE tenantId = ?
        AND deletedAt IS NULL
        AND LOWER(TRIM(brandName)) = ?
        AND UPPER(REPLACE(TRIM(grade), ' ', '')) = ?
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
    required String grade,
    required int sellPerLiterFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim();
    final g = normalizeHydraulicGradeKey(grade);
    if (brand.isEmpty || g.isEmpty) {
      throw StateError('brand_grade_required');
    }
    if (await existsActiveBrandGrade(brandName: brand, grade: g)) {
      throw StateError('duplicate_brand_grade');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM oil_change_hydraulic_catalog '
      'WHERE tenantId = ? AND deletedAt IS NULL AND brandName = ? COLLATE NOCASE',
      [tid, brand],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final id = await db.insert('oil_change_hydraulic_catalog', {
      'tenantId': tid,
      'brandName': brand,
      'grade': g,
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
    required String grade,
    required int sellPerLiterFils,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final brand = brandName.trim();
    final g = normalizeHydraulicGradeKey(grade);
    if (await existsActiveBrandGrade(
      brandName: brand,
      grade: g,
      excludeId: id,
    )) {
      throw StateError('duplicate_brand_grade');
    }
    await db.update(
      'oil_change_hydraulic_catalog',
      {
        'brandName': brand,
        'grade': g,
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
      'oil_change_hydraulic_catalog',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
