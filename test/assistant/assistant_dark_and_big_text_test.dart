import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_chrome.dart';

// عيوب ظهرت في الاختبار النهائي على الهاتف (1.8): رأس الصفحة بأكبر خط،
// وألوان تختفي في الوضع الداكن.
void main() {
  Widget host(Widget child, {double scale = 1, Brightness b = Brightness.light}) => MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF14213D), brightness: b)),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(appBar: child as PreferredSizeWidget, body: const SizedBox()),
      ),
    ),
  );

  testWidgets('الرأس بأكبر خط بلا تجاوز، والحالة تُخفى', (t) async {
    await t.pumpWidget(host(const AssistantHeader(animateMark: false), scale: 2));
    expect(t.takeException(), isNull);
    expect(find.text('مساعد نابو'), findsOneWidget);
    expect(find.text('جاهز'), findsNothing);
  });

  testWidgets('الرأس بالخط العادي يعرض الحالة', (t) async {
    await t.pumpWidget(host(const AssistantHeader(animateMark: false)));
    expect(find.text('جاهز'), findsOneWidget);
  });

  // 2.2: موظف «إرشاد فقط» لا يُدعى للسؤال عن أرقام لا يراها.
  for (final guide in [true, false]) {
    testWidgets('تحية البداية حسب المستوى (إرشاد فقط: $guide)', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssistantStartView(
            name: 'حيدر',
            fromScreen: 'الرئيسية',
            suggestions: const [],
            animateMark: false,
            guideOnly: guide,
          ),
        ),
      ));
      expect(find.textContaining('المبيعات'), guide ? findsNothing : findsOneWidget);
      expect(find.textContaining('وين تلگى'), findsOneWidget);
    });
  }
}
