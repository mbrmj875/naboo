/*
  محادثات المساعد على الجهاز لا تكسر النسخة الكاملة ولا تُرفع معها.

  جدولا المحادثات معرّفهما نص؛ قارئ النسخة كان يفترض معرّفاً رقمياً لكل
  جدول، فتفشل كل مزامنة كاملة على جهاز استعمل المساعد (2.2.44 قبل الإصلاح).

  flutter test test/suites/sync/assistant_tables_snapshot_test.dart
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_thread_store.dart';
import 'package:naboo/services/sync_tables.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  Directory? tmp;
  Fleet? fleet;

  setUpAll(initOilChangeTestEnvironment);

  tearDown(() async {
    fleet?.dispose();
    await tmp?.delete(recursive: true);
    fleet = null;
    tmp = null;
  });

  void fleetRef(Fleet f) => fleet = f;

  test('محادثات المساعد محلية للجهاز', () {
    expect(SyncTables.isSynced('assistant_threads'), isFalse);
    expect(SyncTables.isSynced('assistant_messages'), isFalse);
    expect(SyncTables.isCaptured('assistant_messages'), isFalse);
  });

  test('جهاز فيه محادثات مساعد يرفع نسخته الكاملة بلا خطأ', () async {
    final dir = await Directory.systemTemp.createTemp('naboo_assistant_snap_');
    tmp = dir;
    SharedPreferences.setMockInitialValues({});
    final fleet = await Fleet.create(1, dir);
    fleetRef(fleet);
    final d = fleet['A'];
    final db = await fleet.activate(d);
    for (final sql in AssistantThreadStore.createSql) {
      await db.execute(sql);
    }
    const at = '2026-11-28T10:00:00Z';
    await db.insert('assistant_threads', {
      'id': 'th-1',
      'tenantId': 1,
      'userKey': 'owner',
      'title': 'سؤال',
      'createdAt': at,
      'updatedAt': at,
    });
    await db.insert('assistant_messages', {
      'id': 'msg-1',
      'threadId': 'th-1',
      'role': 'user',
      'content': 'شكد بعت اليوم؟',
      'createdAt': at,
    });
    await fleet.createCard(d, 'AST-1');

    final ok = await fleet.syncDevice(d);
    expect(ok, isTrue);
    final payload = await fleet.remote.currentPayload();
    expect(payload, isNotNull);
    final text = jsonEncode(payload);
    expect(text, contains('AST-1'));
    expect(text, isNot(contains('assistant_messages')));
    expect(text, isNot(contains('شكد بعت اليوم')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
