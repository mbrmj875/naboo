import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/qa/assistant_qa_entry.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';

import '../assistant_test_fakes.dart';

void main() {
  group('م7-1 الرابط', () {
    test('السؤال العربي المُرمَّز يصل كما هو، مع الشاشة', () {
      final u = Uri.parse(
        'naboo-qa://assistant/ask?q=${Uri.encodeQueryComponent('شكد عندي زيت 5W-30؟')}&route=app_home',
      );
      final c = parseQaUri(u, qaBuild: true);
      expect(c, isA<QaAsk>());
      final ask = c! as QaAsk;
      expect(ask.question, 'شكد عندي زيت 5W-30؟');
      expect(ask.routeId, 'app_home');
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/state'), qaBuild: true), isA<QaState>());
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/reset'), qaBuild: true), isA<QaReset>());
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/seed'), qaBuild: true), isA<QaSeed>());
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/seed'), qaBuild: false), isNull);
      expect((parseQaUri(Uri.parse('naboo-qa://assistant/seed'), qaBuild: true)! as QaSeed).over, isFalse);
      expect((parseQaUri(Uri.parse('naboo-qa://assistant/seed?over=1'), qaBuild: true)! as QaSeed).over, isTrue);
    });

    test('نسخة المتجر: لا شيء يُنفَّذ، ولا روابط غريبة', () {
      final u = Uri.parse('naboo-qa://assistant/ask?q=hi');
      expect(parseQaUri(u, qaBuild: false), isNull);
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/ask?q='), qaBuild: true), isNull);
      expect(parseQaUri(Uri.parse('naboo-qa://other/ask?q=x'), qaBuild: true), isNull);
      expect(parseQaUri(Uri.parse('basrainvoice://invoice/1'), qaBuild: true), isNull);
      expect(parseQaUri(Uri.parse('naboo-qa://assistant/ask?q=${'س' * 601}'), qaBuild: true), isNull);
    });

    test('الرابط غير مسجّل في نسخة المتجر: الاسم المستعار معطّل إلا مع naboo.qa', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final alias = RegExp(r'<activity-alias[\s\S]*?</activity-alias>').allMatches(manifest).map((m) => m[0]!);
      final qa = alias.where((a) => a.contains('naboo-qa')).single;
      expect(qa, contains(r'android:enabled="${qaLinksEnabled}"'));
      // الرابط لا يظهر في أي مكان آخر من الملف.
      expect(
        'naboo-qa'.allMatches(manifest).length,
        'naboo-qa'.allMatches(qa).length + 1,
        reason: 'سطر التعليق فقط خارج الاسم المستعار',
      );
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('manifestPlaceholders["qaLinksEnabled"] = if (qaBuild) "true" else "false"'));
    });
  });

  group('م7-2 الحالة في السجل', () {
    test('آخر سؤال ورد وأدواته، والمبالغ كما يراها المستخدم', () async {
      final stock = FakeTool(
        'stock_search',
        rows: [
          {'name': 'زيت 5W-30', 'qty': 4, 'sell_price_fils': 15000000},
        ],
      );
      final api = FakeApi(
        (step, req) => step == 0
            ? const [
                AssistantToolCallEvent(id: 'a', name: 'stock_search', arguments: {'query': '5W-30'}),
                AssistantDoneEvent(finish: 'tool_calls'),
              ]
            : const [
                AssistantTextEvent('عندك 4 علب بسعر ⟦m1⟧'),
                AssistantDoneEvent(finish: 'stop', followups: ['وغيره؟']),
              ],
      );
      final c = AssistantController(
        registry: AssistantToolRegistry(tools: [stock]),
        toolContext: () => ctxFor(owner: true),
        api: api,
        isOnline: () async => true,
        v2Enabled: () => true,
      );
      await c.ask('قارن لي بين زيوتي وگلي الأنسب للصيف بالبصرة');
      final s = qaStateOf(c);
      expect(s['question'], 'قارن لي بين زيوتي وگلي الأنسب للصيف بالبصرة');
      expect(s['reply'], 'عندك 4 علب بسعر 15,000 د.ع');
      expect(s['tools'], [
        {'tool': 'stock_search', 'ok': true, 'rows': 1},
      ]);
      expect(s['followups'], ['وغيره؟']);
      expect(s['busy'], isFalse);
    });

    test('السطر الطويل يُقسم بأرقام ويُجمع كما هو', () {
      final data = {'reply': 'ع' * 2500};
      final lines = qaLogLines('state', data, chunk: 900);
      expect(lines.length, greaterThan(1));
      expect(lines.first, startsWith('$kQaLogTag state 1/${lines.length} '));
      final joined = lines.map((l) => l.split(' ').skip(3).join(' ')).join();
      expect(jsonDecode(joined), data);
      expect(qaLogLines('reset', {'deleted_threads': 2}).single, '$kQaLogTag reset {"deleted_threads":2}');
    });
  });
}
