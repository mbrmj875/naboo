import 'package:sqflite/sqflite.dart';

/// البند 4.1: سجل حركات المخزون.
///
/// كل تغيير في `products.qty` على الجهاز يكتب حركة بفرقه في `stock_ledger`،
/// عبر مشغّل في القاعدة، فيشمل البيع والمرتجع والسند والجرد وتعديل المنتج دون
/// المرور على كل شاشة. الجدول يُرفع في اللقطة، وبعد كل استيراد تُحسب الكمية
/// من مجموع الحركات، فيرى كل جهاز بيع الأجهزة الأخرى.
///
/// لكل منتج حركة افتتاحية واحدة معرفها `open-<global_id المنتج>`. الجهاز
/// الذي يصل إلى الخادم أولاً يحدد قيمتها، والباقي يأخذونها منه عند السحب.
/// حركات البيع لا تتغير بعد كتابتها.
///
/// النسخ القديمة لا تعرف الجدول: بيعها لا يدخل السجل، وتبقى كميتها محلية كما
/// كانت.
class StockLedger {
  static const table = 'stock_ledger';

  /// محلي لكل جهاز، لا يُرفع: يوقف المشغّل أثناء الاستيراد وإعادة الحساب.
  static const ctlTable = 'stock_ledger_ctl';
  static const _trigger = 'trg_stock_ledger_qty';
  static const openingPrefix = 'open-';

  static String openingId(String productGid) => '$openingPrefix$productGid';

  /// قاعدة بلا جدول منتجات (قيد الإنشاء أو اختبار) لا مشغّل لها ولا حساب.
  static Future<bool> _hasProducts(DatabaseExecutor db) async {
    final r = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'products'",
    );
    return r.isNotEmpty;
  }

  /// الحركات الأقدم من هذا تُضم إلى الافتتاحية.
  static const keepDays = 90;

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        global_id TEXT PRIMARY KEY,
        product_global_id TEXT NOT NULL,
        delta REAL NOT NULL,
        created_at TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        compacted_before TEXT
      )
    ''');
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == 'compacted_before')) {
      await db.execute('ALTER TABLE $table ADD COLUMN compacted_before TEXT');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_ledger_product '
      'ON $table (product_global_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ctlTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        paused INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'INSERT OR IGNORE INTO $ctlTable (id, paused) VALUES (1, 0)',
    );
    for (final c in _metaCols.entries) {
      if (!cols.any((x) => x['name'] == c.key)) {
        await db.execute('ALTER TABLE $table ADD COLUMN ${c.key} ${c.value}');
      }
    }
    final ctlCols = await db.rawQuery('PRAGMA table_info($ctlTable)');
    for (final c in _ctxCols) {
      if (!ctlCols.any((x) => x['name'] == c)) {
        await db.execute('ALTER TABLE $ctlTable ADD COLUMN $c TEXT');
      }
    }
    if (!await _hasProducts(db)) return;
    final pCols = await db.rawQuery('PRAGMA table_info(products)');
    if (!pCols.any((c) => c['name'] == storeQtyCol)) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN $storeQtyCol REAL NOT NULL DEFAULT 0',
      );
    }
    // النسخة الأولى من المشغّل لا تكتب نوع الحركة ومرجعها.
    await db.execute('DROP TRIGGER IF EXISTS $_trigger');
    await db.execute(_ledgerTrigger(_triggerShop, 'qty', 'NEW.global_id', null));
    await db.execute(_ledgerTrigger(
      _triggerStore,
      storeQtyCol,
      "'$storeKeyPrefix' || NEW.global_id",
      'store',
    ));
    await _ensureWarehouseMirror(db);
  }

  /// أعمدة وصف الحركة: نوعها ومرجعها وملاحظتها ومن عملها وكلفة الوحدة
  /// ومكانها. النسخ القديمة تتجاهلها عند الدمج، فلا تفسد شيئاً.
  static const _metaCols = <String, String>{
    'kind': 'TEXT',
    'ref': 'TEXT',
    'note': 'TEXT',
    'actor': 'TEXT',
    'unit_cost_fils': 'INTEGER',
    'location': 'TEXT',
  };

  /// وصف الحركة الجارية: يكتبه [StockMoveContext] قبل التعديل ويمسحه بعده،
  /// ويقرؤه المشغّل. محلي لكل جهاز مثل [ctlTable].
  static const _ctxCols = <String>[
    'ctx_kind',
    'ctx_ref',
    'ctx_note',
    'ctx_actor',
    'ctx_cost',
  ];

  static const _triggerShop = 'trg_stock_ledger_qty_v2';
  static const _triggerStore = 'trg_stock_ledger_store_qty';

  /// رصيد «المخزن» (ق-1). `products.qty` يبقى رصيد «المحل» الذي يخصم منه
  /// كل بيع (ق-2)، فلا يتغير أي مسار بيع.
  static const storeQtyCol = 'store_qty';

  /// حركات المخزن تُكتب بمفتاح `store:<global_id المنتج>`: النسخ القديمة
  /// لا تجد منتجاً بهذا المعرّف، فلا تضيف حركات المخزن إلى رصيد المحل.
  static const storeKeyPrefix = 'store:';

  static String storeKey(String productGid) => '$storeKeyPrefix$productGid';

  static String _ledgerTrigger(
    String name,
    String col,
    String keyExpr,
    String? location,
  ) {
    String ctx(String c) => '(SELECT $c FROM $ctlTable WHERE id = 1)';
    return '''
      CREATE TRIGGER IF NOT EXISTS $name
      AFTER UPDATE OF $col ON products
      WHEN (SELECT paused FROM $ctlTable WHERE id = 1) = 0
        AND NEW.global_id IS NOT NULL AND TRIM(NEW.global_id) <> ''
        AND COALESCE(NEW.$col, 0) <> COALESCE(OLD.$col, 0)
      BEGIN
        INSERT INTO $table (global_id, product_global_id, delta, created_at,
          updatedAt, kind, ref, note, actor, unit_cost_fils, location)
        VALUES (
          lower(hex(randomblob(16))),
          $keyExpr,
          COALESCE(NEW.$col, 0) - COALESCE(OLD.$col, 0),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          COALESCE(${ctx('ctx_kind')}, 'edit'),
          ${ctx('ctx_ref')},
          ${ctx('ctx_note')},
          ${ctx('ctx_actor')},
          CAST(${ctx('ctx_cost')} AS INTEGER),
          ${location == null ? "'shop'" : "'$location'"}
        );
      END
    ''';
  }

  /// `product_warehouse_stock` يصير مرآة: رصيد المستودع الافتراضي = رصيد
  /// المحل، وأول مستودع آخر = رصيد المخزن، والكلفة = متوسط الصنف. فلا يبقى
  /// رصيدان مختلفان للصنف نفسه (ع-2)، وكل شاشة قديمة تقرأ الرقم الصحيح.
  static Future<void> ensureWarehouseMirror(DatabaseExecutor db) =>
      _ensureWarehouseMirror(db);

  static Future<void> _ensureWarehouseMirror(DatabaseExecutor db) async {
    final t = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('warehouses', 'product_warehouse_stock')",
    );
    if (t.length < 2) return;
    final pws = await db.rawQuery('PRAGMA table_info(product_warehouse_stock)');
    final wh = await db.rawQuery('PRAGMA table_info(warehouses)');
    final prod = await db.rawQuery('PRAGMA table_info(products)');
    bool has(List<Map<String, Object?>> c, String n) =>
        c.any((x) => x['name'] == n);
    if (!has(pws, 'tenantId') ||
        !has(pws, 'avgCostFils') ||
        !has(wh, 'tenantId') ||
        !has(prod, 'tenantId')) {
      return;
    }
    const shopWh = '(SELECT id FROM warehouses WHERE tenantId = NEW.tenantId '
        'AND isActive = 1 ORDER BY isDefault DESC, id LIMIT 1)';
    const storeWh = '(SELECT id FROM warehouses WHERE tenantId = NEW.tenantId '
        'AND isActive = 1 AND id <> $shopWh ORDER BY isDefault DESC, id LIMIT 1)';
    String upsert(String wExpr, String col) => '''
        UPDATE product_warehouse_stock
        SET qty = COALESCE(NEW.$col, 0),
            avgCostFils = CAST(ROUND(COALESCE(NEW.buyPrice, 0) * 1000) AS INTEGER),
            updatedAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE productId = NEW.id AND warehouseId = $wExpr;
        INSERT OR IGNORE INTO product_warehouse_stock
          (tenantId, productId, warehouseId, qty, avgCostFils, updatedAt)
        SELECT NEW.tenantId, NEW.id, $wExpr, COALESCE(NEW.$col, 0),
          CAST(ROUND(COALESCE(NEW.buyPrice, 0) * 1000) AS INTEGER),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE $wExpr IS NOT NULL;
    ''';
    final body = '${upsert(shopWh, 'qty')}${upsert(storeWh, storeQtyCol)}';
    await db.execute('DROP TRIGGER IF EXISTS trg_pws_mirror_u');
    await db.execute('DROP TRIGGER IF EXISTS trg_pws_mirror_i');
    await db.execute('''
      CREATE TRIGGER trg_pws_mirror_u
      AFTER UPDATE OF qty, $storeQtyCol, buyPrice ON products
      BEGIN
$body
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_pws_mirror_i
      AFTER INSERT ON products
      BEGIN
$body
      END
    ''');
  }

  /// يعيد بناء المرآة لكل الأصناف (بعد الترقية أو تغيير المستودعات).
  static Future<void> rebuildWarehouseMirror(DatabaseExecutor db) async {
    if (!await _hasProducts(db)) return;
    await db.rawUpdate(
      'UPDATE products SET $storeQtyCol = COALESCE($storeQtyCol, 0)',
    );
  }

  static Future<void> setPaused(DatabaseExecutor db, bool paused) =>
      db.rawUpdate(
        'UPDATE $ctlTable SET paused = ? WHERE id = 1',
        [paused ? 1 : 0],
      );

  /// لكل منتج بلا حركة افتتاحية: افتتاحية تجعل مجموع حركاته يساوي كميته الآن.
  /// لا تغيّر كمية أي منتج.
  static Future<void> ensureOpenings(DatabaseExecutor db) async {
    if (!await _hasProducts(db)) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert('''
      INSERT INTO $table (global_id, product_global_id, delta, created_at, updatedAt)
      SELECT '$openingPrefix' || p.global_id, p.global_id,
             COALESCE(p.qty, 0) - COALESCE((
               SELECT SUM(l.delta) FROM $table l
               WHERE l.product_global_id = p.global_id
             ), 0),
             ?, ?
      FROM products p
      WHERE p.global_id IS NOT NULL AND TRIM(p.global_id) <> ''
        AND NOT EXISTS (
          SELECT 1 FROM $table o WHERE o.global_id = '$openingPrefix' || p.global_id
        )
    ''', [now, now]);
    await db.rawInsert('''
      INSERT INTO $table (global_id, product_global_id, delta, created_at,
        updatedAt, kind, location)
      SELECT '$openingPrefix$storeKeyPrefix' || p.global_id,
             '$storeKeyPrefix' || p.global_id,
             COALESCE(p.$storeQtyCol, 0) - COALESCE((
               SELECT SUM(l.delta) FROM $table l
               WHERE l.product_global_id = '$storeKeyPrefix' || p.global_id
             ), 0),
             ?, ?, 'opening', 'store'
      FROM products p
      WHERE p.global_id IS NOT NULL AND TRIM(p.global_id) <> ''
        AND NOT EXISTS (
          SELECT 1 FROM $table o
          WHERE o.global_id = '$openingPrefix$storeKeyPrefix' || p.global_id
        )
    ''', [now, now]);
  }

  /// الكمية = مجموع الحركات، للمنتجات التي لها افتتاحية.
  static Future<void> recompute(DatabaseExecutor db) async {
    if (!await _hasProducts(db)) return;
    await db.rawUpdate('''
      UPDATE products SET qty = (
        SELECT ROUND(SUM(l.delta), 3) FROM $table l
        WHERE l.product_global_id = products.global_id
      )
      WHERE global_id IN (
        SELECT product_global_id FROM $table
        WHERE global_id LIKE '$openingPrefix%'
      )
    ''');
    await db.rawUpdate('''
      UPDATE products SET $storeQtyCol = (
        SELECT ROUND(SUM(l.delta), 3) FROM $table l
        WHERE l.product_global_id = '$storeKeyPrefix' || products.global_id
      )
      WHERE '$storeKeyPrefix' || global_id IN (
        SELECT product_global_id FROM $table
        WHERE global_id LIKE '$openingPrefix$storeKeyPrefix%'
      )
    ''');
  }

  /// دمج حركة واردة: الافتتاحية الواردة تغلب المحلية، إلا إذا كانت المحلية
  /// مضغوطة إلى تاريخ أحدث، فتتفق كل الأجهزة على افتتاحية واحدة. باقي
  /// الحركات لا تتغير.
  static Future<void> mergeIncoming(
    DatabaseExecutor txn,
    Map<String, dynamic> row,
  ) async {
    final gid = (row['global_id'] ?? '').toString().trim();
    final pgid = (row['product_global_id'] ?? '').toString().trim();
    final delta = (row['delta'] as num?)?.toDouble();
    if (gid.isEmpty || pgid.isEmpty || delta == null) return;
    final cut = (row['compacted_before'] ?? '').toString().trim();
    final clean = {
      'global_id': gid,
      'product_global_id': pgid,
      'delta': delta,
      'created_at': (row['created_at'] ?? '').toString(),
      'updatedAt': (row['updatedAt'] ?? row['created_at'] ?? '').toString(),
      'compacted_before': cut.isEmpty ? null : cut,
      for (final c in _metaCols.keys)
        if (row.containsKey(c)) c: row[c],
    };
    if (!gid.startsWith(openingPrefix)) {
      await txn.insert(table, clean,
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    final local = await txn.query(table,
        columns: ['compacted_before'],
        where: 'global_id = ?',
        whereArgs: [gid],
        limit: 1);
    final localCut = local.isEmpty
        ? ''
        : (local.first['compacted_before'] ?? '').toString();
    if (local.isNotEmpty && localCut.compareTo(cut) > 0) return;
    await txn.insert(table, clean,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// بعد الاستيراد: حركة أقدم من تاريخ ضغط افتتاحيتها محسوبة فيها، فتُزال.
  static Future<int> dropCompacted(DatabaseExecutor db) => db.rawDelete('''
        DELETE FROM $table
        WHERE global_id NOT LIKE '$openingPrefix%'
          AND EXISTS (
            SELECT 1 FROM $table o
            WHERE o.global_id = '$openingPrefix' || $table.product_global_id
              AND o.compacted_before IS NOT NULL
              AND $table.created_at < o.compacted_before
          )
      ''');

  /// يضم الحركات الأقدم من [keepDays] إلى افتتاحية منتجها، ويكتب تاريخ الضغط
  /// عليها. لا تتغير الكمية. التاريخ بداية يوم، فتتفق الأجهزة عليه.
  static Future<int> compact(DatabaseExecutor db, {DateTime? now}) async {
    final day = (now ?? DateTime.now()).toUtc();
    final cutDay = DateTime.utc(day.year, day.month, day.day)
        .subtract(const Duration(days: keepDays));
    final cut = cutDay.toIso8601String();
    final stamp = day.toIso8601String();
    await db.rawUpdate('''
      UPDATE $table SET
        delta = ROUND(delta + COALESCE((
          SELECT SUM(l.delta) FROM $table l
          WHERE l.product_global_id = $table.product_global_id
            AND l.global_id NOT LIKE '$openingPrefix%'
            AND l.created_at < ?
        ), 0), 3),
        compacted_before = ?,
        updatedAt = ?
      WHERE global_id LIKE '$openingPrefix%'
        AND (compacted_before IS NULL OR compacted_before < ?)
        AND EXISTS (
          SELECT 1 FROM $table l
          WHERE l.product_global_id = $table.product_global_id
            AND l.global_id NOT LIKE '$openingPrefix%'
            AND l.created_at < ?
        )
    ''', [cut, cut, stamp, cut, cut]);
    return dropCompacted(db);
  }
}
