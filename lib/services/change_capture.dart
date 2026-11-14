import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';
import '../utils/db_migration_safety.dart';
import 'sync_safety.dart';
import 'sync_tables.dart';

/// تعديل واحد ملتقط: مفتاح السطر ونوع العملية، والسطر كما هو الآن.
class CapturedChange {
  const CapturedChange({
    required this.outboxId,
    required this.table,
    required this.key,
    required this.op,
    this.row,
  });

  final int outboxId;
  final String table;
  final String key;

  /// 'U' إضافة أو تعديل، و'D' حذف.
  final String op;

  /// السطر الحالي، أو null للحذف.
  final Map<String, dynamic>? row;

  Map<String, dynamic> toJson() => {
        'table': table,
        'key': key,
        'op': op,
        if (row != null) 'row': row,
      };
}

/// المرحلة 3 من خطة المزامنة: التقاط التعديلات (وضع الظل).
///
/// مشغّلات SQLite تسجل مفتاح كل سطر يُضاف أو يُعدَّل أو يُحذف في [outbox]،
/// فتلتقط كل كتابة حتى لو نسيها كود شاشة. يُسجَّل المفتاح فقط، والسطر يُقرأ عند
/// الإرسال، فعشرة تعديلات على سطر واحد تبقى سطراً واحداً في السجل.
///
/// المفتاح: `global_id` إن كان للجدول، وإلا `id`. سطر بلا مفتاح بعد لا يُسجَّل،
/// ويُسجَّل حين يأخذ مفتاحه بتعديل لاحق.
///
/// المشغّلات تتوقف أثناء استيراد ما جاء من الخادم ([setPaused])، فلا يرتد تعديل
/// إلى الخادم. في وضع الظل لا يرسل شيء؛ السجل يُقاس ويُختبر فقط، وله حد أعلى.
/// كل هذا مطفأ حتى [SyncSafety.changeCapture]، والإطفاء يحذف المشغّلات.
class ChangeCapture {
  ChangeCapture._();

  static const outbox = 'sync_outbox';
  static const ctlTable = 'sync_outbox_ctl';
  static const cursorTable = 'sync_cursor';
  static const _triggerPrefix = 'trg_cap_';

  /// حد السجل في وضع الظل: الأقدم يُحذف، فلا يكبر بلا حد ما دام لا يُرسل.
  static const shadowLimit = 20000;

  static Future<void> _ensureTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tbl TEXT NOT NULL,
        row_key TEXT NOT NULL,
        op TEXT NOT NULL,
        changed_at TEXT NOT NULL,
        UNIQUE (tbl, row_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ctlTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        paused INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'INSERT OR IGNORE INTO $ctlTable (id, paused) VALUES (1, 0)',
    );
    // مؤشر الاستلام للمرحلة 4: آخر رقم تعديل طُبِّق، ورقم جيل الحساب.
    // يُكتب داخل معاملة الدمج نفسها، فلا يُطبَّق تعديل مرتين ولا يُتجاوز.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cursorTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_seq INTEGER NOT NULL DEFAULT 0,
        generation INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'INSERT OR IGNORE INTO $cursorTable (id, last_seq, generation) '
      'VALUES (1, 0, 0)',
    );
  }

  /// عمود مفتاح واحد على كل جهاز: global_id إن وُجد، وإلا مفتاح أساسي نصي
  /// من عمود واحد (`key` في app_settings).
  ///
  /// الرقم المحلي `id` لا يُقبل: يختلف بين الأجهزة، فحذف بـ id=7 على جهاز آخر
  /// يحذف سطراً آخر. جداوله تبقى على النسخة الكاملة حتى تأخذ معرّفاً عاماً.
  static Future<String?> keyColumn(DatabaseExecutor db, String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == 'global_id')) return 'global_id';
    final pk = cols.where((c) => ((c['pk'] as num?)?.toInt() ?? 0) > 0);
    if (pk.length != 1) return null;
    final name = pk.first['name'].toString();
    final type = (pk.first['type'] ?? '').toString().toUpperCase();
    if (name == 'id' || type.contains('INT')) return null;
    return name;
  }

  /// جداول تُرفع في النسخة ولا تُلتقط لأن مفتاحها رقم محلي.
  static Future<List<String>> localKeyedTables(DatabaseExecutor db) async {
    final out = <String>[];
    for (final t in await _capturedTables(db)) {
      if (await keyColumn(db, t) == null) out.add(t);
    }
    return out;
  }

  static Future<List<String>> _capturedTables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    return [
      for (final r in rows)
        if (SyncTables.isCaptured((r['name'] ?? '').toString()))
          (r['name'] ?? '').toString(),
    ];
  }

  static Future<Set<String>> _existingTriggers(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' "
      "AND name LIKE '$_triggerPrefix%'",
    );
    return {for (final r in rows) (r['name'] ?? '').toString()};
  }

  /// جداول تُلتقط وليس لها مشغّل بعد: أُنشئت بعد فتح القاعدة، مثل
  /// `sync_tombstones` عند أول مزامنة. استعلامان فقط، فيصلح لكل دورة.
  static Future<List<String>> tablesWithoutTriggers(DatabaseExecutor db) async {
    if (!SyncSafety.changeCapture) return const [];
    final existing = await _existingTriggers(db);
    final out = <String>[];
    for (final t in await _capturedTables(db)) {
      if (existing.any((n) => n.startsWith('$_triggerPrefix${t}__'))) continue;
      // جدول بلا مفتاح لا يُلتقط أصلاً.
      if (await keyColumn(db, t) == null) continue;
      out.add(t);
    }
    return out;
  }

  /// يضيف مشغّلات الجداول الجديدة إن وُجدت. يُستدعى في بداية كل دورة.
  static Future<void> ensureLateTables(DatabaseExecutor db) async {
    final late = await tablesWithoutTriggers(db);
    if (late.isEmpty) return;
    await ensure(db);
  }

  /// ينشئ الجداول دائماً، والمشغّلات فقط حين يكون المفتاح مشغّلاً. لا يرمي.
  ///
  /// جدول يأخذ مشغّله أول مرة والالتقاط يعمل من قبل في جداول أخرى: أسطره
  /// الموجودة كُتبت دون التقاط، فتُسجَّل كلها. عند أول تشغيل للالتقاط لا
  /// يُسجَّل شيء، لأن النسخة الكاملة هي الأساس.
  static Future<void> ensure(DatabaseExecutor db) async {
    try {
      await _ensureTables(db);
      final existing = await _existingTriggers(db);
      final running = existing.isNotEmpty;
      // اسم المشغّل يحمل عمود المفتاح: جدول أخذ global_id لاحقاً يُعاد مشغّله.
      final wanted = <String>{};
      if (SyncSafety.changeCapture) {
        for (final table in await _capturedTables(db)) {
          final key = await keyColumn(db, table);
          if (key == null) continue;
          for (final k in const ['i', 'u', 'd']) {
            wanted.add('$_triggerPrefix${table}__${key}_$k');
          }
        }
      }
      for (final name in existing.difference(wanted)) {
        await db.execute('DROP TRIGGER IF EXISTS $name');
      }
      if (!SyncSafety.changeCapture) return;
      const now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
      const live = '(SELECT paused FROM $ctlTable WHERE id = 1) = 0';
      for (final table in await _capturedTables(db)) {
        final key = await keyColumn(db, table);
        if (key == null) continue;
        final base = '$_triggerPrefix${table}__$key';
        if (existing.contains('${base}_d')) continue;
        final isNew =
            running && !existing.any((n) => n.startsWith('$_triggerPrefix${table}__'));
        String put(String ref, String op) =>
            'INSERT OR REPLACE INTO $outbox (tbl, row_key, op, changed_at) '
            "VALUES ('$table', $ref.$key, '$op', $now);";
        String has(String ref) =>
            "$ref.$key IS NOT NULL AND TRIM($ref.$key) <> ''";
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS ${base}_i '
          'AFTER INSERT ON $table WHEN $live AND ${has('NEW')} '
          'BEGIN ${put('NEW', 'U')} END',
        );
        // مفتاح تغيّر (معرّف أُعطي أو وُحِّد): القديم حذف، والجديد إضافة.
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS ${base}_u '
          'AFTER UPDATE ON $table WHEN $live AND ${has('NEW')} '
          'BEGIN '
          'INSERT OR REPLACE INTO $outbox (tbl, row_key, op, changed_at) '
          "SELECT '$table', OLD.$key, 'D', $now "
          "WHERE OLD.$key IS NOT NULL AND TRIM(OLD.$key) <> '' "
          'AND OLD.$key <> NEW.$key; '
          '${put('NEW', 'U')} END',
        );
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS ${base}_d '
          'AFTER DELETE ON $table WHEN $live AND ${has('OLD')} '
          'BEGIN ${put('OLD', 'D')} END',
        );
        if (isNew) {
          await db.rawInsert(
            'INSERT OR IGNORE INTO $outbox (tbl, row_key, op, changed_at) '
            "SELECT '$table', $key, 'U', $now FROM $table "
            "WHERE $key IS NOT NULL AND TRIM($key) <> ''",
          );
        }
      }
      await trimShadow(db);
    } catch (e, st) {
      DbMigrationSafety.noteIgnored('ChangeCapture.ensure', e, st);
    }
  }

  /// يوقف الالتقاط أو يعيده. داخل معاملة: يرجع مع المعاملة إن فشلت.
  static Future<void> setPaused(DatabaseExecutor db, bool paused) async {
    try {
      await db.rawUpdate(
        'UPDATE $ctlTable SET paused = ? WHERE id = 1',
        [paused ? 1 : 0],
      );
    } on DatabaseException catch (e) {
      // قاعدة لم تُنشأ جداولها بعد: لا مشغّلات فيها أصلاً.
      AppLogger.warn('ChangeCapture', 'setPaused skipped: $e');
    }
  }

  /// في وضع الظل فقط. حين يُرسل السجل لا يُقص: سطر واحد لكل مفتاح، فلا يزيد
  /// على عدد أسطر القاعدة، وقصّه يضيّع تعديلاً لم يصل.
  static Future<void> trimShadow(DatabaseExecutor db) async {
    if (SyncSafety.deltaSync) return;
    await db.rawDelete(
      'DELETE FROM $outbox WHERE id <= '
      '(SELECT MAX(id) FROM $outbox) - $shadowLimit',
    );
  }

  static Future<int> pendingCount(DatabaseExecutor db) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $outbox');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// الدفعة التالية بترتيب التسجيل، مع السطر الحالي لكل مفتاح. سطر حُذف بعد
  /// تسجيله يصير حذفاً.
  static Future<List<CapturedChange>> pending(
    DatabaseExecutor db, {
    int limit = 200,
  }) async {
    final entries = await db.query(outbox, orderBy: 'id', limit: limit);
    final keys = <String, String?>{};
    final out = <CapturedChange>[];
    for (final e in entries) {
      final table = e['tbl'].toString();
      final key = e['row_key'].toString();
      final id = (e['id'] as num).toInt();
      final col = keys.containsKey(table)
          ? keys[table]
          : (keys[table] = await keyColumn(db, table));
      Map<String, dynamic>? row;
      if (col != null && e['op'] == 'U') {
        final rows = await db.query(
          table,
          where: '$col = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isNotEmpty) row = Map<String, dynamic>.from(rows.first);
      }
      out.add(CapturedChange(
        outboxId: id,
        table: table,
        key: key,
        op: row == null ? 'D' : 'U',
        row: row,
      ));
    }
    return out;
  }

  /// يحذف ما وصل للخادم. سطر تعدّل بعد قراءته أخذ رقماً جديداً فيبقى.
  static Future<void> ack(DatabaseExecutor db, Iterable<int> outboxIds) async {
    final ids = outboxIds.toList();
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      await db.delete(
        outbox,
        where: 'id IN (${List.filled(part.length, '?').join(',')})',
        whereArgs: part,
      );
    }
  }

  static Future<({int lastSeq, int generation})> readCursor(
    DatabaseExecutor db,
  ) async {
    final r = await db.query(cursorTable, where: 'id = 1', limit: 1);
    if (r.isEmpty) return (lastSeq: 0, generation: 0);
    return (
      lastSeq: (r.first['last_seq'] as num?)?.toInt() ?? 0,
      generation: (r.first['generation'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> writeCursor(
    DatabaseExecutor db, {
    required int lastSeq,
    required int generation,
  }) =>
      db.rawUpdate(
        'UPDATE $cursorTable SET last_seq = ?, generation = ? WHERE id = 1',
        [lastSeq, generation],
      );
}
