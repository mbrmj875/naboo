import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// معرّف هذا الجهاز، محفوظ في قاعدته هو ولا يُرفع في اللقطة.
///
/// يُكتب على الوردية عند فتحها (البند 4.3)، فيعرف كل جهاز ورديته ولا يغلق
/// وردية جهاز آخر.
class LocalDevice {
  static const table = 'sync_local_device';

  static Future<String> id(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        k INTEGER PRIMARY KEY CHECK (k = 1),
        device_id TEXT NOT NULL
      )
    ''');
    final r = await db.query(table, columns: ['device_id'], limit: 1);
    if (r.isNotEmpty) return r.first['device_id'].toString();
    final fresh = const Uuid().v4();
    await db.insert(
      table,
      {'k': 1, 'device_id': fresh},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final again = await db.query(table, columns: ['device_id'], limit: 1);
    return again.first['device_id'].toString();
  }

  /// وردية هذا الجهاز، أو وردية قديمة بلا جهاز (قبل التحديث) فتبقى كما كانت.
  static const shiftWhere =
      "(device_id IS NULL OR TRIM(device_id) = '' OR device_id = ?)";
}
