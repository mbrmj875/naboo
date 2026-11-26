import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_activity_icons.dart';
import 'package:naboo/assistant/ui/assistant_chrome.dart';
import 'package:naboo/widgets/inputs/arabic_speech_mic_button.dart' show SpeechHoldState;
import 'package:naboo/assistant/ui/assistant_typewriter_text.dart';

// ط3 وط5 وط7: الكتابة التدريجية والأيقونات المتحركة، ومع «تقليل الحركة» كل شيء ساكن وكامل.
void main() {
  setUp(AssistantReveal.reset);

  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: child),
    ),
  );

  String visible(WidgetTester t) {
    final rich = t.widget<RichText>(find.byType(RichText).first);
    final span = rich.text as TextSpan;
    final first = (span.children!.first as TextSpan).children!.first as TextSpan;
    return first.text ?? '';
  }

  const answer = 'عندك زيت توتال 5W-30 أربع عبوات، والحد خمسة.';

  testWidgets('الجواب يظهر تدريجياً من البداية للنهاية ثم كاملاً', (t) async {
    await t.pumpWidget(host(const AssistantTypewriterText(id: 'a', text: answer, animate: true, complete: true)));
    await t.pump(const Duration(milliseconds: 200));
    final part = visible(t);
    expect(part.isNotEmpty && part.length < answer.length, isTrue, reason: part);
    expect(answer.startsWith(part), isTrue);
    expect(AssistantReveal.doneOf('a').value, isFalse);
    await t.pump(const Duration(seconds: 2));
    expect(visible(t), answer);
    expect(AssistantReveal.doneOf('a').value, isTrue);
  });

  testWidgets('مع «تقليل الحركة» يظهر الجواب كاملاً فوراً', (t) async {
    await t.pumpWidget(
      host(const AssistantTypewriterText(id: 'b', text: answer, animate: true, complete: true), reduceMotion: true),
    );
    expect(visible(t), answer);
    expect(AssistantReveal.doneOf('b').value, isTrue);
  });

  testWidgets('الجواب القديم يظهر كاملاً ولا يُعاد كتابته', (t) async {
    await t.pumpWidget(host(const AssistantTypewriterText(id: 'c', text: answer, animate: false, complete: true)));
    expect(visible(t), answer);
  });

  testWidgets('قارئ الشاشة يقرأ الجواب كاملاً وهو يُكتب', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host(const AssistantTypewriterText(id: 'd', text: answer, animate: true, complete: true)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel(answer), findsOneWidget);
    h.dispose();
  });

  for (final a in AssistantActivity.values) {
    testWidgets('أيقونة ${a.name} ترسم بلا خطأ ومع تقليل الحركة', (t) async {
      await t.pumpWidget(host(AssistantActivityLine(activity: a, text: 'أفكّر…')));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      await t.pumpWidget(host(AssistantActivityLine(activity: a, text: 'أفكّر…'), reduceMotion: true));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(t.hasRunningAnimations, isFalse);
    });
  }

  // ط9: لوحة الصورة، الكاميرا والصور في الأعلى وتُرجعان اختيارهما.
  testWidgets('لوحة الصورة ترجع الكاميرا أو الصور', (t) async {
    Object? picked;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showModalBottomSheet<Object>(
              context: ctx,
              builder: (_) => const AssistantAttachSheet(canImage: true, canCarPhoto: true, canScan: true),
            ),
            child: const Text('افتح'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.text('صوّر الآن'), findsOneWidget);
    expect(find.text('من الصور'), findsOneWidget);
    expect(find.text('امسح باركود منتج'), findsOneWidget);
    await t.tap(find.text('من الصور'));
    await t.pumpAndSettle();
    expect(picked, ImageSourceChoice.gallery);
  });

  // ط8: شريط التسجيل يظهر مكان الحقل، وفي القفل زرّا إلغاء وإرسال، بلا تجاوز في الشاشة الضيقة.
  for (final locked in [false, true]) {
    testWidgets('شريط التسجيل (مقفل: $locked) بخط كبير في 320', (t) async {
      final hold = ValueNotifier<SpeechHoldState?>(
        SpeechHoldState(startedAt: DateTime.now(), level: 0.6, locked: locked),
      );
      var sent = false;
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AssistantComposer(
                  controller: TextEditingController(text: 'شكد باقي زيت'),
                  hold: hold,
                  onHoldFinish: () => sent = true,
                  mic: const SizedBox.square(dimension: 24),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(find.byType(AssistantRecordingBar), findsOneWidget);
      expect(find.text('شكد باقي زيت'), findsOneWidget);
      if (locked) {
        await t.tap(find.byTooltip('إرسال').last);
        expect(sent, isTrue);
      }
      hold.value = null;
      await t.pump();
      expect(find.byType(AssistantRecordingBar), findsNothing);
    });
  }
}
