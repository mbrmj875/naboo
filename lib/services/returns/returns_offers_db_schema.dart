import 'package:sqflite/sqflite.dart';

/// أعمدة وجداول الاسترجاع المحمي وعروض الغسيل — تُضاف بأمان عند فتح القاعدة.
///
/// كل ما هنا يُرفع مع لقطة المزامنة تلقائياً (كل الجداول المحلية تُزامن).
Future<void> ensureReturnsAndOffersSchema(Database db) async {
  Future<bool> hasCol(String table, String col) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => (r['name'] ?? '').toString() == col);
  }

  Future<void> addCol(String table, String col, String type) async {
    try {
      if (!await hasCol(table, col)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
      }
    } catch (_) {}
  }

  await addCol('invoices', 'originalInvoiceGlobalId', 'TEXT');
  await addCol('invoices', 'returnReason', 'TEXT');
  await addCol('invoices', 'returnMeta', 'TEXT');
  try {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_original_gid '
      'ON invoices(originalInvoiceGlobalId)',
    );
  } catch (_) {}

  await addCol('service_orders', 'washOfferCode', 'TEXT');
  // سبب الخصم والسطر التشجيعي كما طُبعا على الإيصال.
  await addCol('service_orders', 'washOfferNote', 'TEXT');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS store_policy_settings (
      id INTEGER PRIMARY KEY,
      payload TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      updatedBy TEXT
    )
  ''');
}
