import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/screens/home_screen.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/widgets/app_breadcrumb_strip.dart';

import 'helpers/oil_employee_home_harness.dart';

Finder _strip(String text) => find.descendant(
  of: find.byType(AppBreadcrumbStrip),
  matching: find.text(text),
);

Future<void> _wait(WidgetTester tester, [int ms = 900]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _openFromDashboard(WidgetTester tester, String title) async {
  final button = find.descendant(
    of: find.byType(OilChangeHomeDashboard),
    matching: find.textContaining(title),
  );
  await tester.ensureVisible(button.first);
  await tester.pump();
  await tester.tap(button.first, warnIfMissed: false);
  await _wait(tester);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('«الرئيسية» يسأل عن المسودة ويحترم «البقاء» و«مغادرة»', (
    tester,
  ) async {
    await pumpEmployeeHome(tester, const HomeScreen());
    await _openFromDashboard(tester, 'غيار زيت جديد');
    expect(find.byType(OilChangeHomeDashboard), findsNothing);

    await tester.tap(_strip('الرئيسية'));
    await _wait(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('البقاء'));
    await _wait(tester);
    expect(find.byType(OilChangeHomeDashboard), findsNothing);
    expect(_strip('بطاقة غيار زيت جديدة'), findsOneWidget);

    await tester.tap(_strip('الرئيسية'));
    await _wait(tester);
    await tester.tap(find.text('مغادرة'));
    await _wait(tester);
    expect(find.byType(OilChangeHomeDashboard), findsOneWidget);
    expect(_strip('بطاقة غيار زيت جديدة'), findsNothing);
    await _finish(tester);
  });

  testWidgets('«الرئيسية» يخفي الوحدة المحفوظة ويطابق الشريط ما يظهر', (
    tester,
  ) async {
    await pumpEmployeeHome(tester, const HomeScreen());
    await _openFromDashboard(tester, 'المخزون');
    expect(_strip('المخزون'), findsOneWidget);

    await tester.tap(_strip('الرئيسية'));
    await _wait(tester);

    expect(find.byType(OilChangeHomeDashboard), findsOneWidget);
    expect(_strip('المخزون'), findsNothing);
    await _finish(tester);
  });

  testWidgets('فتح وحدة لأول مرة لا يترك الشريط على الرئيسية', (tester) async {
    await pumpEmployeeHome(tester, const HomeScreen());
    await _openFromDashboard(tester, 'صندوق اليوم');

    expect(_strip('الصندوق'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('سجل الزيت يظهر خطوة واحدة', (tester) async {
    await pumpEmployeeHome(tester, const HomeScreen());
    await _openFromDashboard(tester, 'سجل الغيارات');

    expect(_strip('سجل غيارات الزيت'), findsOneWidget);
    await _finish(tester);
  });
}
