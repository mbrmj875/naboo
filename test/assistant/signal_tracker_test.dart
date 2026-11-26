import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/learning/assistant_signal_tracker.dart';

void main() {
  late DateTime now;
  late List<String> out;
  late AssistantSignalTracker t;

  setUp(() {
    now = DateTime(2026, 11, 24, 10);
    out = [];
    t = AssistantSignalTracker(emit: (id, s) => out.add('$id $s'), clock: () => now);
  });

  test('م5-1 s_rephrased: نفس السؤال بصيغة ثانية خلال 90 ثانية', () {
    t.answered('t1', 'شكد باقي دهن 5W-30؟');
    now = now.add(const Duration(seconds: 40));
    t.asked('شكد باقي من دهن ٥w-٣٠');
    expect(out, [
      't1 {s_rephrased: true}',
    ]);
    t.asked('شكد باقي دهن 5W-30');
    expect(out.length, 1, reason: 'مرة واحدة لكل دور');
  });

  test('سؤال مختلف أو بعد المهلة لا يُحسب', () {
    t.answered('t1', 'شكد باقي دهن 5W-30؟');
    t.asked('وين أضيف موظف جديد؟');
    t.answered('t2', 'شكد بعت اليوم؟');
    now = now.add(const Duration(minutes: 3));
    t.asked('شكد بعت اليوم؟');
    expect(out, isEmpty);
  });

  test('s_closed_fast: إغلاق خلال 5 ثوانٍ بلا تفاعل فقط', () {
    t.answered('t1', 'س');
    now = now.add(const Duration(seconds: 3));
    t.closed();
    expect(out, [
      't1 {s_closed_fast: true}',
    ]);

    out.clear();
    t.answered('t2', 'س');
    t.interacted();
    t.closed();
    t.answered('t3', 'س');
    now = now.add(const Duration(seconds: 9));
    t.closed();
    expect(out, isEmpty);
  });

  test('الجولة: بداية ثم نهاية أو خطوة التوقف، على دورها', () {
    t.guideStarted('g1');
    t.guideEnded(completed: false, step: 3);
    t.guideEnded(completed: true, step: 4);
    t.guideStarted('g2');
    t.guideEnded(completed: true, step: 5);
    expect(out, [
      'g1 {s_guide_started: true}',
      'g1 {s_guide_abandon_step: 3}',
      'g2 {s_guide_started: true}',
      'g2 {s_guide_done: true}',
    ]);
  });

  test('التطبيع والتشابه', () {
    expect(AssistantSignalTracker.normalize('أين الفاتورةُ؟'), 'اين الفاتوره');
    expect(AssistantSignalTracker.similarity('وين اغير السعر', 'وين أغيّر السعر؟'), 1);
    expect(AssistantSignalTracker.similarity('شكد باقي زيت', 'شلون اسوي جرد'), lessThan(0.4));
  });
}
