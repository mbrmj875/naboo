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

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        global_id TEXT PRIMARY KEY,
        product_global_id TEXT NOT NULL,
        delta REAL NOT NULL,
        created_at TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
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
    if (!await _hasProducts(db)) return;
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS $_trigger
      AFTER UPDATE OF qty ON products
      WHEN (SELECT paused FROM $ctlTable WHERE id = 1) = 0
        AND NEW.global_id IS NOT NULL AND TRIM(NEW.global_id) <> ''
        AND COALESCE(NEW.qty, 0) <> COALESCE(OLD.qty, 0)
      BEGIN
        INSERT INTO $table (global_id, product_global_id, delta, created_at, updatedAt)
        VALUES (
          lower(hex(randomblob(16))),
          NEW.global_id,
          COALESCE(NEW.qty, 0) - COALESCE(OLD.qty, 0),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );
      END
    ''');
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
  }

  /// دمج حركة واردة: الافتتاحية الواردة تغلب المحلية دائماً، فتتفق كل
  /// الأجهزة على افتتاحية من وصل إلى الخادم أولاً. باقي الحركات لا تتغير.
  static Future<void> mergeIncoming(
    DatabaseExecutor txn,
    Map<String, dynamic> row,
  ) async {
    final gid = (row['global_id'] ?? '').toString().trim();
    final pgid = (row['product_global_id'] ?? '').toString().trim();
    final delta = (row['delta'] as num?)?.toDouble();
    if (gid.isEmpty || pgid.isEmpty || delta == null) return;
    final clean = {
      'global_id': gid,
      'product_global_id': pgid,
      'delta': delta,
      'created_at': (row['created_at'] ?? '').toString(),
      'updatedAt': (row['updatedAt'] ?? row['created_at'] ?? '').toString(),
    };
    await txn.insert(
      table,
      clean,
      conflictAlgorithm: gid.startsWith(openingPrefix)
          ? ConflictAlgorithm.replace
          : ConflictAlgorithm.ignore,
    );
  }
}
