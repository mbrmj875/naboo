import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';

import 'helpers/oil_employee_home_harness.dart';

const _pages = <String, String>{
  'غيار زيت جديد': 'بطاقة غيار زيت جديدة',
  'بيع مباشر': 'بيع مباشر',
  'غسيل السيارات': 'بطاقة غسيل سيارة',
  'سجل الغيارات': 'سجل غيارات الزيت',
  'المخزون': 'مركز المخزون',
  'صندوق اليوم': 'الصندوق',
};

Future<void> _wait(WidgetTester tester, [int ms = 900]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _pumpShell(WidgetTester tester, {bool online = false}) {
  return pumpEmployeeHome(
    tester,
    OilChangeShellScreen(
      canOverride: (_) => true,
      hasNetworkOverride: () async => online,
    ),
    size: const Size(390, 844),
  );
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('الرئيسية لا تطلب خطوطاً من الإنترنت', (tester) async {
    attemptedNetworkRequests.clear();
    await _pumpShell(tester);
    await _wait(tester);

    final fontRequests = attemptedNetworkRequests.where(
      (url) => url.host.contains('fonts'),
    );
    expect(fontRequests, isEmpty);
    await _finish(tester);
  });

  testWidgets('المزامنة بلا إنترنت تطمئن الموظف ولا تحاول الرفع', (
    tester,
  ) async {
    await _pumpShell(tester);
    await tester.tap(find.byTooltip('تزامن سحابي'));
    await _wait(tester);

    expect(find.textContaining('عملك محفوظ على الجهاز'), findsOneWidget);
    expect(find.textContaining('جارٍ التزامن'), findsNothing);
    await _finish(tester);
  });

  for (final entry in _pages.entries) {
    testWidgets('«${entry.key}» يفتح صفحته بلا إنترنت على الهاتف', (
      tester,
    ) async {
      await _pumpShell(tester);
      final button = find.descendant(
        of: find.byType(OilChangeHomeDashboard),
        matching: find.textContaining(entry.key),
      );
      await tester.ensureVisible(button.first);
      await tester.pump();
      await tester.tap(button.first, warnIfMissed: false);
      await _wait(tester);

      final titles = tester
          .widgetList<AppBar>(find.byType(AppBar))
          .map((bar) => bar.title is Text ? (bar.title! as Text).data : null);
      expect(titles, contains(entry.value));
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });
  }
}
