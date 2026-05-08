part of 'database_helper.dart';

extension DbProductsSync on DatabaseHelper {
  Future<void> ensureCategoriesBrandsGlobalIdSchema(Database db) async {
    final tables = ['categories', 'brands'];
    for (final table in tables) {
      try {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        final hasGid = cols.any((c) => c['name'] == 'global_id');
        if (!hasGid) {
          await db.execute('ALTER TABLE $table ADD COLUMN global_id TEXT');
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_global_id ON $table(global_id)');
        }
        final hasUpd = cols.any((c) => c['name'] == 'updatedAt');
        if (!hasUpd) {
          await db.execute('ALTER TABLE $table ADD COLUMN updatedAt TEXT');
        }
        if (table == 'categories') {
          final hasParentGid = cols.any((c) => c['name'] == 'parent_global_id');
          if (!hasParentGid) {
            await db.execute('ALTER TABLE categories ADD COLUMN parent_global_id TEXT');
          }
        }
      } catch (e, st) {
        AppLogger.error('DBSync', 'فشل ترحيل الجدول $table', e, st);
      }
    }
  }

  Future<void> ensureProductsGlobalIdSchema(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(products)');
      final hasGid = cols.any((c) => c['name'] == 'global_id');
      if (!hasGid) {
        await db.execute('ALTER TABLE products ADD COLUMN global_id TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_products_global_id ON products(global_id)');
      }
      final hasUpd = cols.any((c) => c['name'] == 'updatedAt');
      if (!hasUpd) {
        await db.execute('ALTER TABLE products ADD COLUMN updatedAt TEXT');
      }
    } catch (e, st) {
      AppLogger.error('DBSync', 'فشل ترحيل جدول المنتجات', e, st);
    }
  }
}
