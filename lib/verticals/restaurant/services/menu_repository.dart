import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'restaurant_db_schema.dart';

class MenuRepository {
  MenuRepository({
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

  Future<List<RestaurantMenuCategory>> listCategories() async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_menu_categories',
      where: 'tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(RestaurantMenuCategory.fromMap).toList();
  }

  Future<int> upsertCategory({
    int? id,
    required String nameAr,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    if (id != null) {
      await db.update(
        'restaurant_menu_categories',
        {
          'name_ar': nameAr.trim(),
          'sort_order': sortOrder,
          'is_active': isActive ? 1 : 0,
        },
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
      );
      return id;
    }
    return db.insert('restaurant_menu_categories', {
      'tenant_id': tid,
      'name_ar': nameAr.trim(),
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
    });
  }

  Future<void> softDeleteCategory(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_menu_categories',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<List<RestaurantMenuItem>> listItems({int? categoryId}) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final where = StringBuffer('i.tenant_id = ? AND i.deleted_at IS NULL');
    final args = <Object?>[tid];
    if (categoryId != null) {
      where.write(' AND i.category_id = ?');
      args.add(categoryId);
    }
    final rows = await db.rawQuery('''
      SELECT i.*,
             CASE WHEN r.id IS NOT NULL THEN 1 ELSE 0 END AS has_recipe
      FROM restaurant_menu_items i
      LEFT JOIN restaurant_recipes r
        ON r.menu_item_id = i.id
       AND r.tenant_id = i.tenant_id
       AND r.deleted_at IS NULL
      WHERE $where
      ORDER BY i.sort_order ASC, i.id ASC
    ''', args);
    return rows
        .map(
          (m) => RestaurantMenuItem.fromMap(
            m,
            hasRecipe: ((m['has_recipe'] as int?) ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<RestaurantMenuItem?> getItem(int id) async {
    final items = await listItems();
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// يرفض تفعيل التوفّر بدون وصفة أو SKU مباشر (spec §3.5).
  Future<int> upsertItem({
    int? id,
    required int categoryId,
    required String nameAr,
    String? descriptionAr,
    required int priceFils,
    bool isAvailable = false,
    int? directStockSkuId,
    int sortOrder = 0,
    String? imageUrl,
    String channelsJson = '["qr_table","public_link","cashier"]',
  }) async {
    if (priceFils < 0) {
      throw ArgumentError('السعر بالفلس لا يمكن أن يكون سالباً');
    }
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;

    var hasRecipe = false;
    if (id != null) {
      final recipeRows = await db.query(
        'restaurant_recipes',
        columns: ['id'],
        where: 'menu_item_id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
        limit: 1,
      );
      hasRecipe = recipeRows.isNotEmpty;
    }
    if (isAvailable && !hasRecipe && directStockSkuId == null) {
      throw StateError(
        'لا يمكن إتاحة الصنف بدون وصفة أو رمز مخزون مباشر',
      );
    }

    final data = <String, Object?>{
      'category_id': categoryId,
      'name_ar': nameAr.trim(),
      'description_ar': descriptionAr?.trim(),
      'price_fils': priceFils,
      'is_available': isAvailable ? 1 : 0,
      'direct_stock_sku_id': directStockSkuId,
      'sort_order': sortOrder,
      'channels_json': channelsJson,
      if (imageUrl != null) 'image_url': imageUrl,
    };

    if (id != null) {
      await db.update(
        'restaurant_menu_items',
        data,
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
      );
      if (isAvailable) {
        await _bumpMenuContentVersion();
      }
      return id;
    }
    final newId = await db.insert('restaurant_menu_items', {
      'tenant_id': tid,
      ...data,
    });
    return newId;
  }

  Future<void> softDeleteItem(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_menu_items',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch, 'is_available': 0},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<void> _bumpMenuContentVersion() async {
    final db = await _dbHelper.database;
    final tid = _tid;
    await db.rawUpdate(
      'UPDATE restaurant_menu_theme SET menu_content_version = menu_content_version + 1, '
      'updated_at = ? WHERE tenant_id = ? AND deleted_at IS NULL',
      [DateTime.now().millisecondsSinceEpoch, tid],
    );
  }
}
