import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// تذكير طلبه المستخدم صراحة (ق38، م4-11). على الجهاز فقط، بلا مزامنة.
@immutable
class AssistantReminder {
  const AssistantReminder({required this.id, required this.text, required this.when, required this.status});

  final int id;
  final String text;
  final DateTime when;

  /// pending | fired | cancelled
  final String status;
}

/// موعد التذكير من كلام النموذج: ISO أو كلمة ثابتة.
abstract final class AssistantReminderWhen {
  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}[t ]\d{2}:\d{2}');
  static final _in = RegExp(r'^in_(\d{1,4})_(minute|minutes|hour|hours|day|days)$');
  static final _day = RegExp(r'^(today|tomorrow)_(\d{1,2})(?::?(\d{2}))?(am|pm)?$');

  /// null إن لم يُفهم الموعد، أو كان ماضياً، أو بعد أكثر من سنة.
  static DateTime? parse(String raw, DateTime now) {
    final s = raw.trim().toLowerCase();
    DateTime? at;
    if (_iso.hasMatch(s)) {
      final d = DateTime.tryParse(raw.trim());
      at = d == null ? null : (d.isUtc ? d.toLocal() : d);
    } else if (_in.firstMatch(s) case final m?) {
      final n = int.parse(m[1]!);
      at = switch (m[2]!) {
        'minute' || 'minutes' => now.add(Duration(minutes: n)),
        'hour' || 'hours' => now.add(Duration(hours: n)),
        _ => now.add(Duration(days: n)),
      };
    } else if (_day.firstMatch(s) case final m?) {
      var h = int.parse(m[2]!);
      final min = int.tryParse(m[3] ?? '') ?? 0;
      final ap = m[4];
      if (h > 23 || min > 59 || (ap != null && (h < 1 || h > 12))) return null;
      if (ap == 'pm' && h < 12) h += 12;
      if (ap == 'am' && h == 12) h = 0;
      final base = m[1] == 'tomorrow' ? now.add(const Duration(days: 1)) : now;
      at = DateTime(base.year, base.month, base.day, h, min);
    }
    if (at == null) return null;
    if (!at.isAfter(now.add(const Duration(seconds: 30)))) return null;
    if (at.isAfter(now.add(const Duration(days: 366)))) return null;
    return at;
  }
}

/// جدول `assistant_reminders` المحلي، مربوط بالمستخدم: كل مستخدم يرى تذكيراته.
class AssistantReminderStore {
  AssistantReminderStore(this._open);

  final Future<Database> Function() _open;
  static const table = 'assistant_reminders';
  static const maxPending = 30;

  Future<Database> _db() async {
    final db = await _open();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId TEXT NOT NULL,
        userKey TEXT NOT NULL,
        text TEXT NOT NULL,
        whenAt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        createdAt TEXT NOT NULL
      )
    ''');
    return db;
  }

  Future<int?> add({
    required String tenantId,
    required String userKey,
    required String text,
    required DateTime when,
  }) async {
    final db = await _db();
    final n =
        Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM $table WHERE tenantId = ? AND userKey = ? AND status = 'pending'", [
            tenantId,
            userKey,
          ]),
        ) ??
        0;
    if (n >= maxPending) return null;
    return db.insert(table, {
      'tenantId': tenantId,
      'userKey': userKey,
      'text': text,
      'whenAt': when.toIso8601String(),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<AssistantReminder>> list({
    required String tenantId,
    required String userKey,
    bool pendingOnly = true,
  }) async {
    final db = await _db();
    final rows = await db.query(
      table,
      where: pendingOnly ? "tenantId = ? AND userKey = ? AND status = 'pending'" : 'tenantId = ? AND userKey = ?',
      whereArgs: [tenantId, userKey],
      orderBy: 'whenAt ASC',
      limit: 100,
    );
    return [
      for (final r in rows)
        AssistantReminder(
          id: (r['id'] as num).toInt(),
          text: '${r['text']}',
          when: DateTime.tryParse('${r['whenAt']}') ?? DateTime.now(),
          status: '${r['status']}',
        ),
    ];
  }

  Future<void> setStatus(int id, String status) async {
    final db = await _db();
    await db.update(table, {'status': status}, where: 'id = ?', whereArgs: [id]);
  }
}

/// يجدول إشعار التذكير. أندرويد: إشعار نظام حتى والتطبيق مغلق. غيره (ويندوز):
/// مؤقت داخل التطبيق، ويُعاد بناؤه عند كل تشغيل من الجدول.
class AssistantReminderScheduler {
  AssistantReminderScheduler({required this.store, required this.scheduleSystem, required this.showNow});

  final AssistantReminderStore store;

  /// يرجع false إن لم تدعم المنصة الجدولة، فيُستعمل المؤقت.
  final Future<bool> Function({required int id, required String text, required DateTime when}) scheduleSystem;
  final Future<void> Function({required int id, required String text}) showNow;
  final Map<int, Timer> _timers = {};

  Future<void> schedule(AssistantReminder r, {required DateTime now}) async {
    if (await scheduleSystem(id: r.id, text: r.text, when: r.when)) return;
    _timers.remove(r.id)?.cancel();
    final wait = r.when.difference(now);
    _timers[r.id] = Timer(wait.isNegative ? Duration.zero : wait, () async {
      _timers.remove(r.id);
      await showNow(id: r.id, text: r.text);
      await store.setStatus(r.id, 'fired');
    });
  }

  /// عند التشغيل: ما فات وقته يُعلَّم منتهياً. إشعار النظام ظهر في وقته، أما
  /// المؤقت فلم يظهر لأن التطبيق كان مغلقاً، فيظهر الآن مرة واحدة.
  Future<void> restore({
    required String tenantId,
    required String userKey,
    required DateTime now,
    required bool systemScheduling,
  }) async {
    for (final r in await store.list(tenantId: tenantId, userKey: userKey)) {
      if (r.when.isAfter(now)) {
        await schedule(r, now: now);
        continue;
      }
      if (!systemScheduling) await showNow(id: r.id, text: r.text);
      await store.setStatus(r.id, 'fired');
    }
  }

  void cancel(int id) => _timers.remove(id)?.cancel();
}
