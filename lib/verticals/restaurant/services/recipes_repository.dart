import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'restaurant_db_schema.dart';

class RecipesRepository {
  RecipesRepository({
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

  Future<RestaurantRecipe?> recipeForMenuItem(int menuItemId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_recipes',
      where: 'tenant_id = ? AND menu_item_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid, menuItemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RestaurantRecipe.fromMap(rows.first);
  }

  Future<List<RestaurantRecipeLine>> listLines(int recipeId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT l.*, p.name AS product_name
      FROM restaurant_recipe_lines l
      LEFT JOIN products p ON p.id = l.product_id
      WHERE l.recipe_id = ? AND l.deleted_at IS NULL
      ORDER BY l.sort_order ASC, l.id ASC
    ''', [recipeId]);
    return rows.map(RestaurantRecipeLine.fromMap).toList();
  }

  Future<int> upsertRecipe({
    required int menuItemId,
    int yieldQty = 1,
    String? notesAr,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final existing = await recipeForMenuItem(menuItemId);
    if (existing != null) {
      await db.update(
        'restaurant_recipes',
        {
          'yield_qty': yieldQty,
          'notes_ar': notesAr,
        },
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [existing.id, tid],
      );
      return existing.id;
    }
    return db.insert('restaurant_recipes', {
      'tenant_id': tid,
      'menu_item_id': menuItemId,
      'yield_qty': yieldQty,
      'notes_ar': notesAr,
    });
  }

  Future<int> addLine({
    required int recipeId,
    required int productId,
    required RecipeBaseUnit baseUnit,
    required int qtyMicro,
    bool isCritical = true,
    int sortOrder = 0,
  }) async {
    if (qtyMicro <= 0) {
      throw ArgumentError('qty_micro يجب أن يكون أكبر من صفر');
    }
    await _ensure();
    final db = await _dbHelper.database;
    return db.insert('restaurant_recipe_lines', {
      'recipe_id': recipeId,
      'product_id': productId,
      'base_unit': RestaurantRecipeLine.unitToDb(baseUnit),
      'qty_micro': qtyMicro,
      'is_critical': isCritical ? 1 : 0,
      'sort_order': sortOrder,
    });
  }

  Future<void> softDeleteLine(int lineId) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_recipe_lines',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [lineId],
    );
  }

  Future<void> softDeleteRecipe(int recipeId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'restaurant_recipes',
      {'deleted_at': now},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [recipeId, _tid],
    );
    await db.update(
      'restaurant_recipe_lines',
      {'deleted_at': now},
      where: 'recipe_id = ? AND deleted_at IS NULL',
      whereArgs: [recipeId],
    );
  }
}
