import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import '../theme/theme_schema_validator.dart';
import 'restaurant_db_schema.dart';

class MenuThemeRepository {
  MenuThemeRepository({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance;

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;

  Future<void> _ensure() async {
    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
  }

  int get _tid => _tenant.requireActiveTenantId();

  Future<RestaurantMenuThemeRow> getOrCreate() async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final rows = await db.query(
      'restaurant_menu_theme',
      where: 'tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [tid],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return RestaurantMenuThemeRow.fromMap(rows.first);
    }
    final defaults = RestaurantThemeCustomization.defaults();
    final err = ThemeSchemaValidator.validate(defaults.toJson());
    if (err != null) throw StateError(err);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('restaurant_menu_theme', {
      'tenant_id': tid,
      'draft_json': defaults.toJsonString(),
      'published_json': null,
      'draft_version': 0,
      'published_version': 0,
      'menu_content_version': 0,
      'updated_at': now,
    });
    final created = await db.query(
      'restaurant_menu_theme',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return RestaurantMenuThemeRow.fromMap(created.first);
  }

  Future<RestaurantMenuThemeRow> saveDraft(
    RestaurantThemeCustomization draft, {
    int? updatedBy,
  }) async {
    final err = ThemeSchemaValidator.validate(draft.toJson());
    if (err != null) throw ArgumentError(err);
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final row = await getOrCreate();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'restaurant_menu_theme',
      {
        'draft_json': draft.toJsonString(),
        'draft_version': row.draftVersion + 1,
        'updated_at': now,
        'updated_by': updatedBy,
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [row.id, tid],
    );
    return getOrCreate();
  }

  Future<RestaurantMenuThemeRow> publish({int? publishedBy}) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final row = await getOrCreate();
    final err = ThemeSchemaValidator.validateJsonString(row.draftJson);
    if (err != null) throw ArgumentError(err);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'restaurant_menu_theme',
      {
        'published_json': row.draftJson,
        'published_version': row.publishedVersion + 1,
        'menu_content_version': row.menuContentVersion + 1,
        'published_at': now,
        'published_by': publishedBy,
        'updated_at': now,
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [row.id, tid],
    );
    // لا Realtime في المرحلة 2 — البث في المرحلة 4.
    return getOrCreate();
  }

  /// رجوع للمنشور: published_json → draft_json.
  Future<RestaurantMenuThemeRow> rollbackToPublished() async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final row = await getOrCreate();
    final published = row.publishedJson;
    if (published == null || published.isEmpty) {
      throw StateError('لا يوجد ثيم منشور للرجوع إليه');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'restaurant_menu_theme',
      {
        'draft_json': published,
        'draft_version': row.publishedVersion,
        'updated_at': now,
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: [row.id, tid],
    );
    return getOrCreate();
  }
}
