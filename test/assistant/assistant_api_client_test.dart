import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';

List<AssistantEvent> parse(String sse) {
  final p = AssistantSseParser();
  final out = <AssistantEvent>[];
  for (final l in sse.split('\n')) {
    final e = p.feedLine(l);
    if (e != null) out.add(e);
  }
  final tail = p.feedLine('');
  if (tail != null) out.add(tail);
  return out;
}

void main() {
  test('أحداث البث الخمسة بالترتيب', () {
    final ev = parse([
      ': keep-alive',
      'event: text',
      'data: {"delta":"هلا "}',
      '',
      'event: tool_call',
      'data: {"id":"c1","name":"stock_search","arguments":{"query":"5W-30"}}',
      '',
      'event: usage',
      'data: {"in":100,"cached":80,"out":12}',
      '',
      'event: done',
      'data: {"finish":"tool_calls","followups":["أ","ب"],"budget":{"mode":"economy","pct":72.5,"renews_on":"2026-12-01"}}',
      '',
    ].join('\n'));
    expect(ev.length, 4);
    expect((ev[0] as AssistantTextEvent).delta, 'هلا ');
    final c = ev[1] as AssistantToolCallEvent;
    expect(c.name, 'stock_search');
    expect(c.arguments['query'], '5W-30');
    expect((ev[2] as AssistantUsageEvent).cached, 80);
    final d = ev[3] as AssistantDoneEvent;
    expect(d.finish, 'tool_calls');
    expect(d.followups, ['أ', 'ب']);
    expect(d.budget!.economy, isTrue);
    expect(d.budget!.renewsOn, '2026-12-01');
  });

  test('خطأ نفاد الرصيد مع الميزانية، وسطر بلا سطر فارغ في الآخر', () {
    final ev = parse('event: error\r\ndata: {"code":"budget_exhausted","budget":{"mode":"exhausted","pct":100}}');
    final e = ev.single as AssistantErrorEvent;
    expect(e.code, 'budget_exhausted');
    expect(e.budget!.exhausted, isTrue);
  });

  test('بيانات تالفة تُتجاهل', () {
    expect(parse('event: text\ndata: {oops\n\n'), isEmpty);
  });

  test('رد بلا بث يتحول للأحداث نفسها', () {
    final ev = AssistantSseParser.fromJsonResponse({
      'ok': true,
      'text': 'تمام',
      'tool_calls': [
        {'id': 'c1', 'name': 'calc', 'arguments': {'expr': '1+1'}},
      ],
      'finish': 'tool_calls',
      'usage': {'in': 1, 'cached': 0, 'out': 2},
      'followups': ['x'],
    }, 200);
    expect(ev.map((e) => e.runtimeType).toList(),
        [AssistantTextEvent, AssistantToolCallEvent, AssistantUsageEvent, AssistantDoneEvent]);
  });

  test('رد خطأ بلا بث', () {
    final a = AssistantSseParser.fromJsonResponse({'ok': false, 'error': 'disabled'}, 403).single as AssistantErrorEvent;
    expect(a.code, 'disabled');
    expect(a.status, 403);
    final b = AssistantSseParser.fromJsonResponse({
      'ok': false,
      'error': {'code': 'budget_exhausted', 'budget': {'mode': 'exhausted', 'pct': 100}},
    }, 402).single as AssistantErrorEvent;
    expect(b.code, 'budget_exhausted');
    expect(b.budget!.exhausted, isTrue);
  });

  test('الطلب يحمل كل حقول الخطوة', () {
    final j = const AssistantStepRequest(threadId: 't', turnId: 'u', step: 2, messages: [], tools: ['calc'], isOwner: true)
        .toJson(stream: true);
    expect(j['op'], 'step');
    expect(j['step'], 2);
    expect(j['stream'], true);
    expect(j['tools'], ['calc']);
  });
}
