import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// حفظ محادثات المساعد على الجهاز (خطة المساعد 4.6، م2-2، م2-7).
///
/// جدولان محليان لا يدخلان المزامنة: المحادثة تبقى على هذا الجهاز فقط.
/// آخر 50 محادثة لكل مستخدم في كل محل، والأقدم تُحذف عند كل حفظ.
/// الجداول تُنشأ عند أول استعمال (`IF NOT EXISTS`)، فلا تغيير على رقم نسخة
/// القاعدة ولا على مسار الترقية العام.
class AssistantThreadStore {
  AssistantThreadStore(this._db, {this.maxThreads = 50});

  final Future<Database> Function() _db;
  final int maxThreads;
  bool _ready = false;

  static const createSql = [
    '''CREATE TABLE IF NOT EXISTS assistant_threads (
  id TEXT PRIMARY KEY, tenantId INTEGER NOT NULL, userKey TEXT NOT NULL,
  title TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
)''',
    '''CREATE TABLE IF NOT EXISTS assistant_messages (
  id TEXT PRIMARY KEY, threadId TEXT NOT NULL, turnId TEXT,
  role TEXT NOT NULL, content TEXT, toolName TEXT, toolPayload TEXT,
  cardType TEXT, createdAt TEXT NOT NULL
)''',
    'CREATE INDEX IF NOT EXISTS idx_assistant_messages_thread ON assistant_messages(threadId, createdAt)',
    'CREATE INDEX IF NOT EXISTS idx_assistant_threads_user ON assistant_threads(tenantId, userKey, updatedAt)',
  ];

  Future<Database> _open() async {
    final db = await _db();
    if (!_ready) {
      for (final sql in createSql) {
        await db.execute(sql);
      }
      _ready = true;
    }
    return db;
  }

  /// ينشئ المحادثة إن لم توجد ويحدّث وقتها، ثم يقصّ الزائد عن [maxThreads].
  Future<void> touchThread({
    required String id,
    required int tenantId,
    required String userKey,
    required String title,
    DateTime? now,
  }) async {
    final db = await _open();
    final at = (now ?? DateTime.now()).toUtc().toIso8601String();
    await db.transaction((tx) async {
      final n = await tx.update('assistant_threads', {'updatedAt': at}, where: 'id = ?', whereArgs: [id]);
      if (n == 0) {
        await tx.insert('assistant_threads', {
          'id': id,
          'tenantId': tenantId,
          'userKey': userKey,
          'title': _clip(title, 60),
          'createdAt': at,
          'updatedAt': at,
        });
      }
      await _prune(tx, tenantId, userKey);
    });
  }

  Future<void> _prune(DatabaseExecutor tx, int tenantId, String userKey) async {
    final old = await tx.query(
      'assistant_threads',
      columns: ['id'],
      where: 'tenantId = ? AND userKey = ?',
      whereArgs: [tenantId, userKey],
      orderBy: 'updatedAt DESC',
      limit: -1,
      offset: maxThreads,
    );
    for (final r in old) {
      await _deleteIn(tx, r['id']! as String);
    }
  }

  Future<void> addMessage({
    required String id,
    required String threadId,
    required String role,
    String? turnId,
    String? content,
    Map<String, Object?>? payload,
    String? cardType,
    DateTime? now,
  }) async {
    final db = await _open();
    await db.insert('assistant_messages', {
      'id': id,
      'threadId': threadId,
      'turnId': turnId,
      'role': role,
      'content': content,
      'toolPayload': payload == null ? null : jsonEncode(payload),
      'cardType': cardType,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// آخر المحادثات، والبحث في العنوان ونص الرسائل.
  Future<List<StoredThread>> listThreads({required int tenantId, required String userKey, String? search}) async {
    final db = await _open();
    final q = search?.trim() ?? '';
    final rows = await db.rawQuery(
      '''
SELECT t.id, t.title, t.updatedAt,
  (SELECT m.content FROM assistant_messages m
     WHERE m.threadId = t.id AND m.role = 'assistant'
     ORDER BY m.createdAt DESC LIMIT 1) AS preview
FROM assistant_threads t
WHERE t.tenantId = ? AND t.userKey = ?
  ${q.isEmpty ? '' : '''AND (t.title LIKE ? OR EXISTS (
    SELECT 1 FROM assistant_messages m2 WHERE m2.threadId = t.id AND m2.content LIKE ?))'''}
ORDER BY t.updatedAt DESC
LIMIT ?''',
      [
        tenantId,
        userKey,
        if (q.isNotEmpty) ...['%$q%', '%$q%'],
        maxThreads,
      ],
    );
    return [
      for (final r in rows)
        StoredThread(
          id: r['id']! as String,
          title: (r['title'] as String?) ?? '',
          preview: (r['preview'] as String?) ?? '',
          updatedAt: DateTime.tryParse(r['updatedAt']! as String)?.toLocal() ?? DateTime.now(),
        ),
    ];
  }

  Future<List<StoredMessage>> loadMessages(String threadId) async {
    final db = await _open();
    final rows = await db.query(
      'assistant_messages',
      where: 'threadId = ?',
      whereArgs: [threadId],
      orderBy: 'createdAt ASC, rowid ASC',
    );
    return [
      for (final r in rows)
        StoredMessage(
          id: r['id']! as String,
          role: r['role']! as String,
          turnId: r['turnId'] as String?,
          content: (r['content'] as String?) ?? '',
          payload: _decode(r['toolPayload'] as String?),
          cardType: r['cardType'] as String?,
        ),
    ];
  }

  Future<void> deleteMessages(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _open();
    await db.delete('assistant_messages', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<void> deleteThread(String id) async {
    final db = await _open();
    await db.transaction((tx) => _deleteIn(tx, id));
  }

  Future<void> _deleteIn(DatabaseExecutor tx, String id) async {
    await tx.delete('assistant_messages', where: 'threadId = ?', whereArgs: [id]);
    await tx.delete('assistant_threads', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, Object?>? _decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final v = jsonDecode(s);
      return v is Map<String, Object?> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _clip(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n - 1)}…';
  }
}

class StoredThread {
  const StoredThread({required this.id, required this.title, required this.preview, required this.updatedAt});
  final String id;
  final String title;
  final String preview;
  final DateTime updatedAt;
}

class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.role,
    required this.content,
    this.turnId,
    this.payload,
    this.cardType,
  });
  final String id;
  final String role;
  final String? turnId;
  final String content;
  final Map<String, Object?>? payload;
  final String? cardType;
}
