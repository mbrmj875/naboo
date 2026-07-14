part of 'database_helper.dart';

extension DbOilProductGrades on DatabaseHelper {
  Future<void> ensureOilProductGradesSchema(Database db) async {
    try {
      if (!await _tableHasColumn(db, 'products', 'variantKind')) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN variantKind INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!await _tableHasColumn(db, 'products', 'parentProductId')) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN parentProductId INTEGER',
        );
      }
    } catch (e, st) {
      AppLogger.error('DBMigrate', 'فشل أعمدة products للزيوت', e, st);
    }

    await db.execute('''
    CREATE TABLE IF NOT EXISTS product_oil_grades(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL DEFAULT 1,
      global_id TEXT,
      parentProductId INTEGER NOT NULL,
      viscosity TEXT NOT NULL,
      linkedProductId INTEGER NOT NULL,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      deleted_at TEXT,
      FOREIGN KEY(parentProductId) REFERENCES products(id) ON DELETE RESTRICT,
      FOREIGN KEY(linkedProductId) REFERENCES products(id) ON DELETE RESTRICT
    )
  ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_oil_grades_tenant_parent '
      'ON product_oil_grades(tenantId, parentProductId)',
    );

    try {
      await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_oil_grades_viscosity_alive
      ON product_oil_grades(tenantId, parentProductId, LOWER(TRIM(viscosity)))
      WHERE deleted_at IS NULL
    ''');
    } catch (e, st) {
      AppLogger.error('DBMigrate', 'فشل فهرس product_oil_grades viscosity', e, st);
    }
  }
}
