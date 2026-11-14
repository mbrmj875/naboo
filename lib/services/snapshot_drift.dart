import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';
import '../utils/db_migration_safety.dart';
import 'change_capture.dart';
import 'sync_tables.dart';

/// المرحلة 5: كشف الانحراف بعد أخذ نسخة كاملة.
///
/// الدمج يضيف ويأخذ الأحدث، فالنسخة اليومية تصلح وحدها السطر الناقص والتعديل
/// الضائع. ما لا تصلحه هو الحذف الضائع: سطر بقي هنا وحُذف عند غيره. هذا الفحص
/// يعدّ لكل جدول الأسطر الموجودة هنا فقط، وهي:
/// * أقدم من وقت النسخة (ما بعده ربما لم يصل إلى الجهاز الرافع بعد)،
/// * وليست في سجل هذا الجهاز تنتظر الإرسال.
///
/// للسجل فقط: لا يحذف ولا يغيّر شيئاً. السطر الزائد قد يكون حذفاً ضاع هنا، أو
/// إضافة لم تصل إلى الجهاز الرافع؛ الفرق يُعرف من الجهة الأخرى.
class SnapshotDrift {
  SnapshotDrift._();

  static const _stampColumns = ['updatedAt', 'updated_at', 'createdAt', 'created_at'];

  static Future<Map<String, int>> extraLocalRows(
    DatabaseExecutor db,
    Map<String, dynamic> payload,
  ) async {
    final takenAt = DateTime.tryParse((payload['takenAt'] ?? '').toString());
    final tables = payload['tables'];
    if (takenAt == null || tables is! Map) return const {};
    final local = {
      for (final r in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        r['name'].toString(),
    };
    final out = <String, int>{};
    for (final entry in tables.entries) {
      final table = entry.key.toString();
      final rows = entry.value;
      if (rows is! List) continue;
      if (!SyncTables.isCaptured(table) || !local.contains(table)) continue;
      final key = await ChangeCapture.keyColumn(db, table);
      if (key == null) continue;
      final cols = {
        for (final c in await db.rawQuery('PRAGMA table_info($table)'))
          c['name'].toString(),
      };
      final stamp = _stampColumns.where(cols.contains).firstOrNull;
      // بلا وقت لا يُعرف إن كان السطر أقدم من النسخة: لا يُحكم عليه.
      if (stamp == null) continue;

      final inSnapshot = {
        for (final r in rows)
          if (r is Map && r[key] != null) r[key].toString(),
      };
      final waiting = {
        for (final r in await db.query(
          ChangeCapture.outbox,
          columns: ['row_key'],
          where: 'tbl = ?',
          whereArgs: [table],
        ))
          r['row_key'].toString(),
      };
      var extra = 0;
      for (final r in await db.rawQuery(
        'SELECT $key AS k, $stamp AS s FROM $table '
        "WHERE $key IS NOT NULL AND TRIM($key) <> ''",
      )) {
        final k = r['k'].toString();
        if (inSnapshot.contains(k) || waiting.contains(k)) continue;
        final at = DateTime.tryParse((r['s'] ?? '').toString());
        if (at == null || !at.isBefore(takenAt)) continue;
        extra++;
      }
      if (extra > 0) out[table] = extra;
    }
    return out;
  }

  /// يفحص ويسجّل، ولا يرمي أبداً.
  static Future<Map<String, int>> check(
    DatabaseExecutor db,
    Map<String, dynamic> payload,
  ) async {
    try {
      final extra = await extraLocalRows(db, payload);
      if (extra.isNotEmpty) {
        AppLogger.warn('SnapshotDrift', 'rows only on this device: $extra');
        DbMigrationSafety.noteIgnored(
          'SnapshotDrift',
          StateError('rows only on this device: $extra'),
        );
      }
      return extra;
    } catch (e, st) {
      AppLogger.error('SnapshotDrift', 'check failed', e, st);
      return const {};
    }
  }
}
