import 'package:sqflite/sqflite.dart';

import '../models/oil_change_filter_kind.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// فئات الفلاتر لكل محل (المحرك/الهواء/الكير + فئات يضيفها المستخدم).
class OilChangeFilterKindsRepository {
  OilChangeFilterKindsRepository._();
  static final OilChangeFilterKindsRepository instance =
      OilChangeFilterKindsRepository._();

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

  Future<List<OilChangeFilterKind>> listActive() async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    await _seedBuiltinsIfEmpty(db, tid);

    final rows = await db.query(
      'oil_change_filter_kinds',
      where: 'tenantId = ? AND deletedAt IS NULL',
      whereArgs: [tid],
      orderBy: 'sortOrder ASC, id ASC',
    );
    if (rows.isEmpty) {
      // احتياط إن فشلت الزراعة.
      return List<OilChangeFilterKind>.from(OilChangeFilterKind.builtins);
    }
    return rows.map(OilChangeFilterKind.fromMap).toList();
  }

  Future<void> _seedBuiltinsIfEmpty(Database db, int tid) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) AS c FROM oil_change_filter_kinds '
            'WHERE tenantId = ? AND deletedAt IS NULL',
            [tid],
          ),
        ) ??
        0;
    if (count > 0) return;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final k in OilChangeFilterKind.builtins) {
      await db.insert('oil_change_filter_kinds', {
        'tenantId': tid,
        'code': k.code,
        'labelAr': k.label,
        'sortOrder': k.sortOrder,
        'isBuiltin': 1,
        'createdAt': now,
        'updatedAt': now,
      });
    }
  }

  /// يولد كوداً فريداً لفئة جديدة ضمن التينانت.
  Future<String> _nextCustomCode(Database db, int tid) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var code = 'f_$now';
    var n = 0;
    while (true) {
      final rows = await db.rawQuery(
        'SELECT id FROM oil_change_filter_kinds '
        'WHERE tenantId = ? AND code = ? AND deletedAt IS NULL LIMIT 1',
        [tid, code],
      );
      if (rows.isEmpty) return code;
      n += 1;
      code = 'f_${now}_$n';
    }
  }

  Future<OilChangeFilterKind> insert({required String labelAr}) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final label = labelAr.trim();
    if (label.isEmpty) throw StateError('label_required');

    final dup = await db.rawQuery(
      'SELECT id FROM oil_change_filter_kinds '
      'WHERE tenantId = ? AND deletedAt IS NULL AND LOWER(TRIM(labelAr)) = ? '
      'LIMIT 1',
      [tid, label.toLowerCase()],
    );
    if (dup.isNotEmpty) throw StateError('duplicate_label');

    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM oil_change_filter_kinds '
      'WHERE tenantId = ? AND deletedAt IS NULL',
      [tid],
    );
    final nextSort = ((maxRow.first['m'] as num?)?.toInt() ?? 0) + 1;
    final code = await _nextCustomCode(db, tid);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('oil_change_filter_kinds', {
      'tenantId': tid,
      'code': code,
      'labelAr': label,
      'sortOrder': nextSort,
      'isBuiltin': 0,
      'createdAt': now,
      'updatedAt': now,
    });
    _scheduleSync();
    return OilChangeFilterKind(
      id: id,
      code: code,
      label: label,
      isBuiltin: false,
      sortOrder: nextSort,
    );
  }

  Future<void> rename({
    required int id,
    required String labelAr,
  }) async {
    final tid = await _tenantId();
    final db = await _db;
    await ensureSchema();
    final label = labelAr.trim();
    if (label.isEmpty) throw StateError('label_required');

    final dup = await db.rawQuery(
      'SELECT id FROM oil_change_filter_kinds '
      'WHERE tenantId = ? AND deletedAt IS NULL AND LOWER(TRIM(labelAr)) = ? '
      'AND id != ? LIMIT 1',
      [tid, label.toLowerCase(), id],
    );
    if (dup.isNotEmpty) throw StateError('duplicate_label');

    await db.update(
      'oil_change_filter_kinds',
      {
        'labelAr': label,
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
      'oil_change_filter_kinds',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ? AND tenantId = ? AND deletedAt IS NULL',
      whereArgs: [id, tid],
    );
    _scheduleSync();
  }
}
