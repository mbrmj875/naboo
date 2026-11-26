import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';

import 'assistant_test_fakes.dart';

void main() {
  AssistantController make({
    FakeApi? api,
    bool online = true,
    bool enabled = true,
    List<FakeTool> tools = const [],
    void Function(AssistantUiAction)? onUi,
  }) =>
      AssistantController(
        registry: AssistantToolRegistry(tools: tools),
        toolContext: () => ctxFor(owner: true),
        api: api,
        isOnline: () async => online,
        v2Enabled: () => enabled,
        onUiAction: onUi,
      );

  test('أداتان ثم جواب: الحلقة ترسل النتائج وتعرض المبالغ منسّقة', () async {
    final stock = FakeTool('stock_search', rows: [{'name': 'زيت 5W-30', 'qty': 4, 'price_fils': 15000000}]);
    final sales = FakeTool('sales_summary', rows: [{'count': 2}]);
    late FakeApi api;
    api = FakeApi((step, req) {
      if (step == 0) {
        return const [
          AssistantToolCallEvent(id: 'a', name: 'stock_search', arguments: {'query': '5W-30'}),
          AssistantToolCallEvent(id: 'b', name: 'sales_summary', arguments: {'period': 'today'}),
          AssistantDoneEvent(finish: 'tool_calls'),
        ];
      }
      return const [
        AssistantTextEvent('عندك 4 علب بسعر ⟦m1⟧'),
        AssistantDoneEvent(finish: 'stop', followups: ['شكد بعنا منه؟'], budget: AssistantBudget(mode: 'full', pct: 3)),
      ];
    });
    final c = make(api: api, tools: [stock, sales]);
    await c.ask('شنو وضع الزيت 5W-30 مع مبيعاته اليوم وشكد سعره');

    expect(api.requests.length, 2);
    expect(api.requests.first.tools, ['sales_summary', 'stock_search']);
    final second = api.requests[1].messages;
    expect(second.where((m) => m['role'] == 'tool').length, 2);
    final toolMsg = second.firstWhere((m) => m['tool_call_id'] == 'a')['content'] as String;
    expect(toolMsg.contains('15000000'), isFalse, reason: 'المبلغ لا يصل للنموذج');
    expect(toolMsg.contains('⟦m1⟧'), isTrue);

    final m = c.messages.last;
    expect(m.status, AssistantMessageStatus.done);
    expect(m.results.length, 2);
    expect(m.followups, ['شكد بعنا منه؟']);
    expect(c.display(m), contains('15,000'));
    expect(c.budget!.mode, 'full');
    expect(c.historyForTest.last['role'], 'assistant');
  });

  test('أداة الخادم (car_spec): نتيجتها تُستعمل كما هي ولا تُنفَّذ على الجهاز', () async {
    final api = FakeApi((step, req) {
      if (step == 0) {
        return const [
          AssistantToolCallEvent(
            id: 'c',
            name: 'car_spec',
            arguments: {'make': 'toyota', 'model': 'corolla'},
            serverResult: {
              'ok': true,
              'tool': 'car_spec',
              'rows': [
                {'model': 'toyota corolla 2015', 'capacity_l': 4.2, 'oil': '0W-20', 'confidence': 'verified'},
              ],
              'total': 1,
            },
          ),
          AssistantDoneEvent(finish: 'tool_calls'),
        ];
      }
      return const [AssistantTextEvent('تاخذ 4.2 لتر'), AssistantDoneEvent(finish: 'stop')];
    });
    final c = make(api: api);
    await c.ask('كم لتر تاخذ كورولا 2015');
    final tool = api.requests[1].messages.firstWhere((m) => m['role'] == 'tool');
    expect('${tool['content']}', contains('4.2'));
    expect(c.messages.last.results.single.tool, 'car_spec');
  });

  test('تتوقف عند 5 خطوات', () async {
    final t = FakeTool('calc');
    final api = FakeApi((step, _) => const [
          AssistantToolCallEvent(id: 'x', name: 'calc', arguments: {}),
          AssistantDoneEvent(finish: 'tool_calls'),
        ]);
    final c = make(api: api, tools: [t]);
    await c.ask('احسب لي شي معقد جداً جداً جداً بخطوات كثيرة وكثيرة');
    expect(api.requests.length, 5);
    expect(c.messages.last.status, AssistantMessageStatus.done);
    expect(c.messages.last.text, isNotEmpty);
  });

  test('الموجّه المحلي أولاً: لا طلب للخادم', () async {
    final api = FakeApi((_, __) => throw StateError('لا يجب أن يُستدعى'));
    final low = FakeTool('stock_low', rows: [{'name': 'فلتر'}]);
    final c = make(api: api, tools: [low]);
    await c.ask('هلا');
    await c.ask('النواقص');
    expect(api.requests, isEmpty);
    expect(c.messages.last.local, isTrue);
    expect(c.messages.last.results.single.rows.single['name'], 'فلتر');
  });

  test('فتح شاشة محلياً عبر فعل الواجهة', () async {
    final actions = <AssistantUiAction>[];
    final c = make(api: FakeApi((_, __) => const []), onUi: actions.add);
    await c.ask('افتح الديون');
    expect((actions.single as AssistantOpenRoute).routeId, 'app_debts');
    expect(c.messages.last.text, contains('الديون'));
  });

  test('بلا إنترنت: المطابِق المحلي يجيب ويقترح جولة', () async {
    final api = FakeApi((_, __) => throw StateError('no'));
    final c = make(api: api, online: false);
    await c.ask('شلون اسجل غيار زيت');
    final m = c.messages.last;
    expect(api.requests, isEmpty);
    expect(m.errorCode, 'offline');
    expect(m.suggestedTourId, isNotNull);
    expect(m.text, contains('ماكو إنترنت'));
  });

  test('نفاد الرصيد: رسالة بتاريخ التجدد والمطابِق المحلي', () async {
    final api = FakeApi((_, __) => const [
          AssistantErrorEvent('budget_exhausted',
              budget: AssistantBudget(mode: 'exhausted', pct: 100, renewsOn: '2026-12-01')),
        ]);
    final c = make(api: api);
    await c.ask('قارن مبيعات هذا الاسبوع بالاسبوع الماضي');
    final m = c.messages.last;
    expect(m.errorCode, 'budget_exhausted');
    expect(m.text, contains('2026-12-01'));
    expect(c.budget!.exhausted, isTrue);
    expect(c.historyForTest, isEmpty, reason: 'السؤال غير المجاب لا يبقى في السياق');
  });

  test('خطأ اتصال عام: حالة خطأ، وإعادة المحاولة تعيد السؤال', () async {
    var fail = true;
    final api = FakeApi((_, __) => fail
        ? const [AssistantErrorEvent('upstream')]
        : const [AssistantTextEvent('تمام'), AssistantDoneEvent(finish: 'stop')]);
    final c = make(api: api);
    await c.ask('شنو احسن زيت للصيف');
    expect(c.messages.last.status, AssistantMessageStatus.error);
    fail = false;
    await c.retryLast();
    expect(c.messages.where((m) => m.fromUser).length, 1);
    expect(c.messages.last.text, 'تمام');
  });

  test('الإشارات تُرسل مع السؤال التالي', () async {
    final api = FakeApi((_, __) => const [AssistantTextEvent('x'), AssistantDoneEvent(finish: 'stop')]);
    final c = make(api: api);
    c.queueSignal('turn-1', {'s_copied': true});
    await c.ask('سؤال عن شي بعيد عن النوايا المحلية تماماً');
    expect(api.signals.single['turn_id'], 'turn-1');
  });

  test('المساعد الجديد غير مفعّل: المطابِق المحلي', () async {
    final api = FakeApi((_, __) => throw StateError('no'));
    final c = make(api: api, enabled: false);
    await c.ask('سؤال ما يعرفه المطابق نهائياً xyz');
    expect(api.requests, isEmpty);
    expect(c.messages.last.text, contains('غير مفعّل'));
  });
}
