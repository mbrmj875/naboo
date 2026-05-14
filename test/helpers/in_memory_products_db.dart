import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class InMemoryProductsDb {
  InMemoryProductsDb._(this.db);

  final Database db;

  static Future<InMemoryProductsDb> open({
    List<int> tenantIds = const [1, 2],
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tenants (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    ''');
    for (final id in tenantIds) {
      await db.insert('tenants', {
        'id': id,
        'code': 'tenant_$id',
        'name': 'Tenant $id',
        'isActive': 1,
        'createdAt': now,
      });
    }

    return InMemoryProductsDb._(db);
  }

  Future<void> close() => db.close();

  static Future<void> _onCreate(Database db, int _) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        name TEXT NOT NULL,
        barcode TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_products_tenant ON products(tenantId)');

    await db.execute('''
      CREATE TABLE product_colors(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
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
      'CREATE INDEX idx_product_colors_tenant_product '
      'ON product_colors(tenantId, productId)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX uq_product_colors_product_name_alive
      ON product_colors(tenantId, productId, LOWER(TRIM(name)))
      WHERE deleted_at IS NULL
    ''');

    await db.execute('''
      CREATE TABLE product_variants(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
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
      'CREATE INDEX idx_product_variants_tenant_product '
      'ON product_variants(tenantId, productId)',
    );
    await db.execute(
      'CREATE INDEX idx_product_variants_tenant_barcode '
      'ON product_variants(tenantId, barcode)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX uq_product_variants_color_size_alive
      ON product_variants(tenantId, colorId, LOWER(TRIM(size)))
      WHERE deleted_at IS NULL
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX uq_product_variants_barcode_tenant_alive
      ON product_variants(tenantId, UPPER(TRIM(barcode)))
      WHERE barcode IS NOT NULL AND TRIM(barcode) != '' AND deleted_at IS NULL
    ''');
  }
}

class ProductFixtures {
  ProductFixtures(this.db);
  final Database db;

  int _tid(String tenantId) => int.tryParse(tenantId) ?? 1;

  Future<int> insertProduct({
    required String tenantId,
    required String name,
    String? barcode,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('products', {
      'tenantId': _tid(tenantId),
      'name': name,
      'barcode': barcode,
      'isActive': 1,
      'createdAt': now,
      'updatedAt': now,
      'deleted_at': null,
    });
  }

  Future<int> insertColor({
    required String tenantId,
    required int productId,
    required String name,
    String? hexCode,
    int sortOrder = 0,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('product_colors', {
      'tenantId': _tid(tenantId),
      'productId': productId,
      'name': name,
      'hexCode': hexCode,
      'sortOrder': sortOrder,
      'createdAt': now,
      'updatedAt': now,
      'deleted_at': null,
    });
  }

  Future<int> insertVariant({
    required String tenantId,
    required int productId,
    required int colorId,
    required String size,
    required int quantity,
    String? barcode,
    String? sku,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('product_variants', {
      'tenantId': _tid(tenantId),
      'productId': productId,
      'colorId': colorId,
      'size': size,
      'quantity': quantity,
      'barcode': barcode,
      'sku': sku,
      'createdAt': now,
      'updatedAt': now,
      'deleted_at': null,
    });
  }
}

