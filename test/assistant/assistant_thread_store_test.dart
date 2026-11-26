import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_thread_store.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'assistant_test_fakes.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late AssistantThreadStore store;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    store = AssistantThreadStore(() async => db);
  });
  tearDown(() => db.close());

  test('آخر 50 محادثة فقط لكل مستخدم، والأقدم تُحذف مع رسائلها', () async {
    final t0 = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < 55; i++) {
      await store.touchThread(id: 't$i', tenantId: 1, userKey: 'u', title: 'سؤال $i', now: t0.add(Duration(minutes: i)));
      await store.addMessage(id: 'm$i', threadId: 't$i', role: 'user', content: 'سؤال $i');
    }
    // مستخدم آخر لا يتأثر.
    await store.touchThread(id: 'x', tenantId: 1, userKey: 'other', title: 'غيري');
    final list = await store.listThreads(tenantId: 1, userKey: 'u');
    expect(list.length, 50);
    expect(list.first.id, 't54');
    expect(list.any((t) => t.id == 't4'), isFalse);
    expect(await store.loadMessages('t0'), isEmpty);
    expect((await store.listThreads(tenantId: 1, userKey: 'other')).single.id, 'x');
    expect(await store.listThreads(tenantId: 2, userKey: 'u'), isEmpty);
  });

  test('البحث في العنوان والرسائل، والحذف', () async {
    await store.touchThread(id: 'a', tenantId: 1, userKey: 'u', title: 'زيت 5W-30');
    await store.addMessage(id: '1', threadId: 'a', role: 'assistant', content: 'عندك 4 علب');
    await store.touchThread(id: 'b', tenantId: 1, userKey: 'u', title: 'الصندوق');
    await store.addMessage(id: '2', threadId: 'b', role: 'assistant', content: 'الرصيد ⟦m1⟧ وفلتر كامري');
    expect((await store.listThreads(tenantId: 1, userKey: 'u', search: '5W')).single.id, 'a');
    expect((await store.listThreads(tenantId: 1, userKey: 'u', search: 'كامري')).single.id, 'b');
    final all = await store.listThreads(tenantId: 1, userKey: 'u');
    expect(all.firstWhere((t) => t.id == 'a').preview, 'عندك 4 علب');
    await store.deleteThread('a');
    expect((await store.listThreads(tenantId: 1, userKey: 'u')).single.id, 'b');
    expect(await store.loadMessages('a'), isEmpty);
  });

  test('المتحكم يحفظ ثم يعيد فتح المحادثة: البطاقات والمبالغ والسياق ترجع', () async {
    final stock = FakeTool('stock_search', rows: [{'name': 'زيت 5W-30', 'qty': 4, 'sell_price_fils': 15000000}]);
    final api = FakeApi((step, req) => step == 0
        ? const [
            AssistantToolCallEvent(id: 'a', name: 'stock_search', arguments: {'query': '5W-30'}),
            AssistantDoneEvent(finish: 'tool_calls'),
          ]
        : const [AssistantTextEvent('عندك 4 علب بسعر ⟦m1⟧'), AssistantDoneEvent(finish: 'stop', followups: ['وغيره؟'])]);
    AssistantController make() => AssistantController(
          registry: AssistantToolRegistry(tools: [stock]),
          toolContext: () => ctxFor(owner: true),
          api: api,
          isOnline: () async => true,
          v2Enabled: () => true,
          store: store,
          tenantId: () => 7,
          userKey: () => 'owner',
        );
    final c = make();
    await c.ask('قارن لي بين زيوتي وگلي الأنسب للصيف بالبصرة');
    await c.lastSave;
    final id = c.threadId;

    final threads = await store.listThreads(tenantId: 7, userKey: 'owner');
    expect(threads.single.id, id);
    expect(threads.single.title, startsWith('قارن لي'));

    final d = make();
    await d.openThread(id);
    expect(d.threadId, id);
    expect(d.messages.length, 2);
    final reply = d.messages.last;
    expect(d.display(reply), contains('15,000'));
    expect(reply.results.single.rows.single['sell_price_fils'], 15000000);
    expect(reply.followups, ['وغيره؟']);
    expect(d.historyForTest.map((m) => m['role']), ['user', 'assistant']);
    // علامة جديدة لا تصطدم بالمحفوظة.
    expect(d.moneyRefs.ref(1), '⟦m2⟧');

    d.newThread();
    expect(d.messages, isEmpty);
    expect(d.threadId, isNot(id));
  });

  test('«جواب خاطئ» يرسل إشارة سلبية مع التصحيح', () async {
    final api = FakeApi((step, req) => const [AssistantTextEvent('جواب'), AssistantDoneEvent(finish: 'stop')]);
    final c = AssistantController(
      registry: AssistantToolRegistry(tools: const []),
      toolContext: () => ctxFor(owner: true),
      api: api,
      isOnline: () async => true,
      v2Enabled: () => true,
    );
    await c.ask('سؤال طويل ما يعرفه الموجّه المحلي أبداً');
    await c.reportWrong(c.messages.last, correction: '  الصحيح 6 علب ');
    expect(api.signals.single['s_thumb'], -1);
    expect(api.signals.single['user_correction'], 'الصحيح 6 علب');
    expect(api.signals.single['turn_id'], c.messages.last.turnId);
  });
}
