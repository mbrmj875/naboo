part of 'database_helper.dart';

/// Ensures the local SQLite schema for product colors + variants exists.
///
/// This follows the project's pattern: idempotent `CREATE TABLE IF NOT EXISTS`
/// + indexes, executed once during DB open (not per repository call).
Future<void> ensureProductColorsAndVariantsSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS product_colors(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL DEFAULT 1,
      global_id TEXT,
      productId INTEGER NOT NULL,
      name TEXT NOT NULL,
      hexCode TEXT,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_product_colors_tenant_product '
    'ON product_colors(tenantId, productId)',
  );

  // Unique color name per product per tenant (ignoring soft-deleted rows).
  try {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_product_colors_product_name_alive
      ON product_colors(tenantId, productId, LOWER(TRIM(name)))
      WHERE deleted_at IS NULL
    ''');
  } catch (_) {}

  await db.execute('''
    CREATE TABLE IF NOT EXISTS product_variants(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenantId INTEGER NOT NULL DEFAULT 1,
      global_id TEXT,
      productId INTEGER NOT NULL,
      colorId INTEGER NOT NULL,
      size TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 0,
      barcode TEXT,
      sku TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      deleted_at TEXT,
      FOREIGN KEY(colorId) REFERENCES product_colors(id) ON DELETE RESTRICT
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_product_variants_tenant_product '
    'ON product_variants(tenantId, productId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_product_variants_tenant_color '
    'ON product_variants(tenantId, colorId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_product_variants_tenant_barcode '
    'ON product_variants(tenantId, barcode)',
  );

  // Unique size within the same color per tenant (ignoring soft-deleted rows).
  try {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_product_variants_color_size_alive
      ON product_variants(tenantId, colorId, LOWER(TRIM(size)))
      WHERE deleted_at IS NULL
    ''');
  } catch (_) {}

  // Barcode unique per tenant when present; NULL/blank allowed.
  try {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_product_variants_barcode_tenant_alive
      ON product_variants(tenantId, UPPER(TRIM(barcode)))
      WHERE barcode IS NOT NULL AND TRIM(barcode) != '' AND deleted_at IS NULL
    ''');
  } catch (_) {}
}

