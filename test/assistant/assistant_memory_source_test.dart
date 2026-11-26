import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool_result.dart';
import 'package:naboo/assistant/data/assistant_memory_store.dart';
import 'package:naboo/assistant/ui/assistant_card_mapper.dart';
import 'package:naboo/assistant/ui/assistant_memory_screen.dart';
import 'package:naboo/assistant/ui/assistant_source_line.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';

class _FakeMemory implements AssistantMemoryStore {
  _FakeMemory(this.items);
  final List<AssistantMemoryItem> items;
  final deleted = <int>[];

  @override
  Future<List<AssistantMemoryItem>> list() async => List.of(items);

  @override
  Future<void> delete(int id) async {
    deleted.add(id);
    items.removeWhere((x) => x.id == id);
  }
}

AssistantToolResult _server(Map<String, Object?> m) => AssistantToolResult.fromStore(m)!;

void main() {
  group('source line (ق68)', () {
    test('describes each tool from its own result, with period and count', () {
      final r = AssistantToolResult.success('sales_summary', [
        {'period': 'this_week', 'count': 12},
      ], source: 'من شاشة التقارير');
      final s = AssistantSourceLine.of([r])!;
      expect(s.summary, startsWith('من بيانات محلك · '));
      expect(s.details, ['من شاشة التقارير · هذا الأسبوع · 1 سجل']);
    });

    test('library titles and the car guide appear; calc and memory do not', () {
      final car = _server({
        'ok': true,
        'tool': 'car_spec',
        'rows': [
          {'model': 'corolla'},
        ],
        'total': 1,
        'source': 'من دليل نابو للسيارات',
      });
      final calc = AssistantToolResult.success('calc', [
        {'result': 5},
      ]);
      final s = AssistantSourceLine.of([car, calc], knowledge: ['زيت القير'])!;
      expect(s.summary, 'من دليل نابو للسيارات · من مكتبة نابو');
      expect(s.details, ['من دليل نابو للسيارات', 'من مكتبة نابو: زيت القير']);
      expect(AssistantSourceLine.of([calc]), isNull);
    });
  });

  group('memory and support cards', () {
    test('memory_save result becomes a chip with the saved row id', () {
      final c = AssistantCardMapper.fromResult(
        _server({
          'ok': true,
          'tool': 'memory_save',
          'rows': [
            {'id': 7, 'text': 'نغلق الجمعة'},
          ],
          'total': 1,
        }),
      );
      expect(c, isA<AssistantMemoryCard>());
      expect((c! as AssistantMemoryCard).id, 7);
    });

    test('full memory and support handoff show a notice', () {
      final full = AssistantCardMapper.fromResult(
        _server({'ok': false, 'tool': 'memory_save', 'error': 'memory_full'}),
      );
      expect((full! as AssistantNoticeCard).kind, 'memory_full');
      final sent = AssistantCardMapper.fromResult(
        _server({
          'ok': true,
          'tool': 'support_handoff',
          'rows': [
            {'sent': true},
          ],
          'total': 1,
        }),
      );
      expect((sent! as AssistantNoticeCard).kind, 'support');
    });

    test('done event carries library titles, streamed or not', () {
      final p = AssistantSseParser();
      p.feedLine('event: done');
      p.feedLine('data: {"finish":"stop","knowledge":[{"id":1,"kind":"library","title":"زيت القير"}]}');
      final done = p.feedLine('')! as AssistantDoneEvent;
      expect(done.knowledge, ['زيت القير']);
      final ev = AssistantSseParser.fromJsonResponse({
        'ok': true,
        'text': 'x',
        'finish': 'stop',
        'knowledge': [
          {'title': 'تجديد الاشتراك'},
        ],
      }, 200);
      expect(ev.whereType<AssistantDoneEvent>().single.knowledge, ['تجديد الاشتراك']);
    });
  });

  group('«ما أعرفه عنك» page (م2-15)', () {
    final items = [
      const AssistantMemoryItem(id: 1, text: 'نغلق الجمعة', createdBy: 'المالك'),
      const AssistantMemoryItem(id: 2, text: 'ما نبيع معدني'),
    ];

    testWidgets('the owner sees the list and deletes after confirming', (tester) async {
      final store = _FakeMemory(List.of(items));
      await tester.pumpWidget(MaterialApp(home: AssistantMemoryScreen(canDelete: true, store: store)));
      await tester.pumpAndSettle();
      expect(find.text('نغلق الجمعة'), findsOneWidget);
      expect(find.text('حفظها المالك'), findsOneWidget);
      await tester.tap(find.byTooltip('احذف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'احذف'));
      await tester.pumpAndSettle();
      expect(store.deleted, [1]);
      expect(find.text('نغلق الجمعة'), findsNothing);
    });

    testWidgets('an employee sees the list without delete buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AssistantMemoryScreen(canDelete: false, store: _FakeMemory(List.of(items)))),
      );
      await tester.pumpAndSettle();
      expect(find.text('ما نبيع معدني'), findsOneWidget);
      expect(find.byTooltip('احذف'), findsNothing);
      expect(find.text('الحذف لصاحب المحل.'), findsOneWidget);
    });
  });
}
