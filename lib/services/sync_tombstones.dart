import 'package:sqflite/sqflite.dart';

/// شاهد حذف للجداول التي يُزال فيها الصف كله (الزبائن الآن).
///
/// الجهاز الذي يحذف يكتب سطراً هنا. الجدول يُرفع في اللقطة كأي جدول، فيصل
/// إلى كل جهاز، وكل جهاز يحذف الصف عنده بعد الاستيراد. لولاه لرفع جهاز لم
/// يتزامن بعد الصفَّ حياً فيعود إلى الجميع.
///
/// النسخ القديمة لا تعرف الجدول فتتجاهله. يبقى السطر 90 يوماً ثم يُزال.
class SyncTombstones {
  static const table = 'sync_tombstones';
  static const keepDays = 90;

  /// الجداول التي يطبَّق عليها الشاهد. لا يُحذف شيء من جدول خارجها.
  static const tables = {'customers'};

  /// العمود `removed_at` وليس `deletedAt`: الدمج يعدّ أي صف وارد فيه
  /// `deletedAt` صفاً محذوفاً فيزيله، فيضيع الشاهد نفسه.
  static Future<void> ensureTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        table_name TEXT NOT NULL,
        global_id TEXT NOT NULL,
        removed_at TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        PRIMARY KEY (table_name, global_id)
      )
    ''');
  }

  static Future<void> record(
    DatabaseExecutor txn,
    String tableName,
    String globalId,
  ) async {
    if (!tables.contains(tableName) || globalId.trim().isEmpty) return;
    await ensureTable(txn);
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert(
      table,
      {
        'table_name': tableName,
        'global_id': globalId.trim(),
        'removed_at': now,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// يحذف كل صف له شاهد. يُستدعى بعد دمج اللقطة.
  static Future<int> apply(DatabaseExecutor txn) async {
    await ensureTable(txn);
    var removed = 0;
    for (final t in tables) {
      final cols = await txn.rawQuery('PRAGMA table_info($t)');
      if (!cols.any((c) => c['name'] == 'global_id')) continue;
      final plans = await txn.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' "
        "AND name = 'installment_plans'",
      );
      if (t == 'customers' && plans.isNotEmpty) {
        // كما في حذف الزبون على الجهاز نفسه: تبقى الخطة بلا زبون.
        await txn.rawUpdate('''
          UPDATE installment_plans SET customerId = NULL
          WHERE customerId IN (
            SELECT c.id FROM customers c
            JOIN $table s ON s.table_name = 'customers'
              AND s.global_id = c.global_id
          )
        ''');
      }
      removed += await txn.rawDelete('''
        DELETE FROM $t WHERE global_id IN (
          SELECT global_id FROM $table WHERE table_name = ?
        )
      ''', [t]);
    }
    return removed;
  }

  static Future<void> purgeOld(DatabaseExecutor txn) async {
    await ensureTable(txn);
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: keepDays))
        .toIso8601String();
    await txn.delete(table, where: 'removed_at < ?', whereArgs: [cutoff]);
  }
}
