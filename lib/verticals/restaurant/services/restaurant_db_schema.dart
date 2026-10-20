import 'package:sqflite/sqflite.dart';

bool _restaurantSchemaEnsured = false;

/// جداول تخصص المطاعم — مطابق لـ docs/specs/vertical_restaurant_v1.md §3.
///
/// الأعمدة snake_case كما في الـspec (معزولة عن camelCase لبقية ERP المحلي).
/// `deleted_at` / الطوابع الزمنية = epoch ms INTEGER.
Future<void> ensureRestaurantTables(Database db) async {
  if (_restaurantSchemaEnsured) return;
  await _floors(db);
  await _tables(db);
  await _floorFixtures(db);
  await _sessions(db);
  await _menuCategories(db);
  await _menuItems(db);
  await _modifiers(db);
  await _itemModifiers(db);
  await _recipes(db);
  await _recipeLines(db);
  await _orders(db);
  await _orderLines(db);
  await _orderLineCosts(db);
  await _reservations(db);
  await _menuTheme(db);
  await _menuItemImages(db);
  _restaurantSchemaEnsured = true;
}

Future<void> _floors(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_floors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        name_ar TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_floors_tenant '
      'ON restaurant_floors(tenant_id, deleted_at, sort_order)',
    );
  } catch (_) {}
}

Future<void> _tables(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_tables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        floor_id INTEGER NOT NULL,
        table_number TEXT NOT NULL,
        capacity INTEGER,
        table_slug TEXT NOT NULL,
        session_seq INTEGER NOT NULL DEFAULT 0,
        layout_x_bp INTEGER NOT NULL DEFAULT -1,
        layout_y_bp INTEGER NOT NULL DEFAULT -1,
        layout_rot_deg INTEGER NOT NULL DEFAULT 0,
        seat_style TEXT NOT NULL DEFAULT 'center',
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_tables_slug '
      'ON restaurant_tables(tenant_id, table_slug) '
      'WHERE deleted_at IS NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_tables_floor '
      'ON restaurant_tables(tenant_id, floor_id, deleted_at)',
    );
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN layout_x_bp INTEGER NOT NULL DEFAULT -1',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN layout_y_bp INTEGER NOT NULL DEFAULT -1',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN layout_rot_deg INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN seat_style TEXT NOT NULL DEFAULT \'center\'',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN layout_w_bp INTEGER NOT NULL DEFAULT 900',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE restaurant_tables ADD COLUMN layout_h_bp INTEGER NOT NULL DEFAULT 900',
      );
    } catch (_) {}
  } catch (_) {}
}

Future<void> _floorFixtures(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_floor_fixtures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        floor_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        label_ar TEXT,
        layout_x_bp INTEGER NOT NULL DEFAULT 1000,
        layout_y_bp INTEGER NOT NULL DEFAULT 1000,
        layout_w_bp INTEGER NOT NULL DEFAULT 1200,
        layout_h_bp INTEGER NOT NULL DEFAULT 900,
        layout_rot_deg INTEGER NOT NULL DEFAULT 0,
        meta_json TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_floor_fixtures '
      'ON restaurant_floor_fixtures(tenant_id, floor_id, deleted_at)',
    );
  } catch (_) {}
}

Future<void> _sessions(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        table_id INTEGER,
        session_seq INTEGER NOT NULL,
        channel TEXT NOT NULL,
        state TEXT NOT NULL,
        invoice_id INTEGER NOT NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        client_fingerprint TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_sessions_active '
      'ON restaurant_sessions(tenant_id, table_id) '
      "WHERE state IN ('open', 'awaiting_payment') "
      'AND deleted_at IS NULL AND table_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_sessions_state '
      'ON restaurant_sessions(tenant_id, state, deleted_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_sessions_table '
      'ON restaurant_sessions(tenant_id, table_id, state)',
    );
  } catch (_) {}
}

Future<void> _menuCategories(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_menu_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        name_ar TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_menu_cats '
      'ON restaurant_menu_categories(tenant_id, deleted_at, sort_order)',
    );
  } catch (_) {}
}

Future<void> _menuItems(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        name_ar TEXT NOT NULL,
        description_ar TEXT,
        price_fils INTEGER NOT NULL,
        image_url TEXT,
        is_available INTEGER NOT NULL DEFAULT 0,
        channels_json TEXT NOT NULL DEFAULT '["qr_table","public_link","cashier"]',
        direct_stock_sku_id INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_menu_items '
      'ON restaurant_menu_items(tenant_id, category_id, deleted_at, sort_order)',
    );
  } catch (_) {}
}

Future<void> _modifiers(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_modifiers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        name_ar TEXT NOT NULL,
        group_ar TEXT,
        price_delta_fils INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_modifiers '
      'ON restaurant_modifiers(tenant_id, deleted_at)',
    );
  } catch (_) {}
}

Future<void> _itemModifiers(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_item_modifiers (
        menu_item_id INTEGER NOT NULL,
        modifier_id INTEGER NOT NULL,
        is_required INTEGER NOT NULL DEFAULT 0,
        min_select INTEGER NOT NULL DEFAULT 0,
        max_select INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (menu_item_id, modifier_id)
      )
    ''');
  } catch (_) {}
}

Future<void> _recipes(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        menu_item_id INTEGER NOT NULL,
        yield_qty INTEGER NOT NULL DEFAULT 1,
        notes_ar TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_recipes_item '
      'ON restaurant_recipes(tenant_id, menu_item_id) '
      'WHERE deleted_at IS NULL',
    );
  } catch (_) {}
}

Future<void> _recipeLines(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_recipe_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        base_unit TEXT NOT NULL,
        qty_micro INTEGER NOT NULL,
        is_critical INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_recipe_lines '
      'ON restaurant_recipe_lines(recipe_id, deleted_at, sort_order)',
    );
  } catch (_) {}
}

Future<void> _orders(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        session_id INTEGER NOT NULL,
        invoice_id INTEGER NOT NULL,
        channel TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        accepted_at INTEGER,
        preparing_at INTEGER,
        ready_at INTEGER,
        served_at INTEGER,
        notes_ar TEXT,
        client_generated_id TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_orders_session '
      'ON restaurant_orders(tenant_id, session_id, deleted_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_orders_state '
      'ON restaurant_orders(tenant_id, state, created_at)',
    );
    try {
      await db.execute(
        'ALTER TABLE restaurant_orders ADD COLUMN client_generated_id TEXT',
      );
    } catch (_) {}
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_orders_client_gen '
      'ON restaurant_orders(tenant_id, client_generated_id) '
      'WHERE client_generated_id IS NOT NULL AND deleted_at IS NULL',
    );
    // SQLite: فرض invoice_id == session.invoice_id
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_restaurant_order_invoice_match
      BEFORE INSERT ON restaurant_orders
      FOR EACH ROW
      BEGIN
        SELECT RAISE(ABORT, 'order.invoice_id must equal session.invoice_id')
        WHERE NEW.invoice_id <> (
          SELECT invoice_id FROM restaurant_sessions WHERE id = NEW.session_id
        );
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_restaurant_order_invoice_match_upd
      BEFORE UPDATE OF invoice_id, session_id ON restaurant_orders
      FOR EACH ROW
      BEGIN
        SELECT RAISE(ABORT, 'order.invoice_id must equal session.invoice_id')
        WHERE NEW.invoice_id <> (
          SELECT invoice_id FROM restaurant_sessions WHERE id = NEW.session_id
        );
      END
    ''');
  } catch (_) {}
}

Future<void> _orderLines(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        menu_item_id INTEGER NOT NULL,
        qty INTEGER NOT NULL,
        unit_price_fils_at_sale INTEGER NOT NULL,
        modifiers_json TEXT,
        line_state TEXT NOT NULL DEFAULT 'active',
        void_reason_ar TEXT,
        notes_ar TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_order_lines '
      'ON restaurant_order_lines(order_id, deleted_at)',
    );
    try {
      await db.execute(
        'ALTER TABLE restaurant_order_lines ADD COLUMN notes_ar TEXT',
      );
    } catch (_) {}
  } catch (_) {}
}

Future<void> _orderLineCosts(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_order_line_costs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_line_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        base_unit TEXT NOT NULL,
        qty_micro INTEGER NOT NULL,
        unit_cost_fils_at_sale INTEGER NOT NULL,
        total_cost_fils_at_sale INTEGER NOT NULL,
        consumed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_order_line_costs '
      'ON restaurant_order_line_costs(order_line_id)',
    );
  } catch (_) {}
}

Future<void> _reservations(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_ingredient_reservations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        order_id INTEGER NOT NULL,
        session_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty_micro_reserved INTEGER NOT NULL,
        state TEXT NOT NULL,
        reserved_at INTEGER NOT NULL,
        resolved_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restaurant_reservations_product '
      'ON restaurant_ingredient_reservations(tenant_id, product_id, state)',
    );
  } catch (_) {}
}

Future<void> _menuTheme(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_menu_theme (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL UNIQUE,
        draft_json TEXT NOT NULL,
        published_json TEXT,
        draft_version INTEGER NOT NULL DEFAULT 0,
        published_version INTEGER NOT NULL DEFAULT 0,
        menu_content_version INTEGER NOT NULL DEFAULT 0,
        published_at INTEGER,
        published_by INTEGER,
        updated_at INTEGER NOT NULL,
        updated_by INTEGER,
        deleted_at INTEGER
      )
    ''');
  } catch (_) {}
}

Future<void> _menuItemImages(Database db) async {
  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_menu_item_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        menu_item_id INTEGER NOT NULL,
        image_url TEXT NOT NULL,
        variants_json TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        width_px INTEGER,
        height_px INTEGER,
        bytes INTEGER,
        mime TEXT NOT NULL,
        alt_ar TEXT,
        alt_en TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_menu_item_primary_image '
      'ON restaurant_menu_item_images(tenant_id, menu_item_id) '
      'WHERE is_primary = 1 AND deleted_at IS NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_item_images_item '
      'ON restaurant_menu_item_images(tenant_id, menu_item_id, deleted_at, sort_order)',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_menu_item_images_max5
      BEFORE INSERT ON restaurant_menu_item_images
      FOR EACH ROW
      WHEN NEW.deleted_at IS NULL
      BEGIN
        SELECT RAISE(ABORT, 'max_5_images_per_item')
        WHERE (
          SELECT COUNT(*) FROM restaurant_menu_item_images
          WHERE tenant_id = NEW.tenant_id
            AND menu_item_id = NEW.menu_item_id
            AND deleted_at IS NULL
        ) >= 5;
      END
    ''');
  } catch (_) {}
}
