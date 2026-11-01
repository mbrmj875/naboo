import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';
import 'package:naboo/widgets/shell/shell_bottom_nav.dart';
import 'package:naboo/widgets/shell/shell_sidebar.dart';

import 'helpers/oil_employee_home_harness.dart';

const _phone = Size(390, 844);
const _desktop = Size(1366, 900);

const _expectedPages = <String, String>{
  'غيار زيت جديد': 'بطاقة غيار زيت جديدة',
  'بيع مباشر': 'بيع مباشر',
  'غسيل السيارات': 'بطاقة غسيل سيارة',
  'سجل الغيارات': 'سجل غيارات الزيت',
  'السيارات الحالية': 'سجل غيارات الزيت',
  'المخزون': 'مركز المخزون',
  'صندوق اليوم': 'الصندوق',
};

Future<void> _wait(WidgetTester tester, [int ms = 900]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = _desktop,
  bool Function(String)? can,
}) {
  return pumpEmployeeHome(
    tester,
    OilChangeShellScreen(canOverride: can ?? (_) => true),
    size: size,
  );
}

Future<void> _tapDashboard(WidgetTester tester, String title) async {
  final button = find.descendant(
    of: find.byType(OilChangeHomeDashboard),
    matching: find.textContaining(title),
  );
  expect(button, findsWidgets);
  await tester.ensureVisible(button.first);
  await tester.pump();
  await tester.tap(button.first, warnIfMissed: false);
  await _wait(tester);
}

List<String?> _titles(WidgetTester tester) => tester
    .widgetList<AppBar>(find.byType(AppBar))
    .map((bar) => bar.title is Text ? (bar.title! as Text).data : null)
    .toList();

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

void main() {
  setUpEmployeeHomeEnvironment();

  for (final entry in _expectedPages.entries) {
    testWidgets('«${entry.key}» يفتح داخل الغلاف ويبقى الشريط الجانبي', (
      tester,
    ) async {
      await _pumpShell(tester);
      await _tapDashboard(tester, entry.key);

      expect(find.textContaining('غير متاح'), findsNothing);
      expect(_titles(tester), contains(entry.value));
      expect(find.byType(ShellSidebar), findsOneWidget);
      await _finish(tester);
    });
  }

  testWidgets('الهاتف: الشريط السفلي يبقى داخل الصفحات', (tester) async {
    await _pumpShell(tester, size: _phone);
    expect(find.byType(ShellBottomNavBar), findsOneWidget);
    expect(find.byType(ShellSidebar), findsNothing);
    expect(find.byType(Drawer), findsNothing);

    await _tapDashboard(tester, 'صندوق اليوم');

    expect(_titles(tester), contains('الصندوق'));
    expect(find.byType(ShellBottomNavBar), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('الهاتف: بطاقة الغيار تأخذ الشاشة كاملة', (tester) async {
    await _pumpShell(tester, size: _phone);
    await _tapDashboard(tester, 'غيار زيت جديد');

    expect(find.byType(ShellBottomNavBar), findsNothing);
    await _finish(tester);
  });

  testWidgets('الحد 840: الأقل شريط سفلي والأكثر شريط جانبي', (tester) async {
    await _pumpShell(tester, size: const Size(800, 600));
    expect(find.byType(ShellBottomNavBar), findsOneWidget);
    await _finish(tester);

    await _pumpShell(tester, size: const Size(900, 700));
    expect(find.byType(ShellSidebar), findsOneWidget);
    expect(find.byType(ShellBottomNavBar), findsNothing);
    await _finish(tester);
  });

  testWidgets('لا overflow على مقاسات الهاتف والتابلت والحاسبة', (
    tester,
  ) async {
    for (final size in const [
      Size(320, 568),
      Size(768, 1024),
      Size(800, 600),
      Size(1366, 768),
    ]) {
      await _pumpShell(tester, size: size);
      expect(tester.takeException(), isNull, reason: '$size');
      await _finish(tester);
    }
  });

  testWidgets('موظف بلا صلاحية صندوق لا يراه في القائمة ولا يفتحه', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: _phone,
      can: (key) => key != PermissionKeys.cashView,
    );
    final bar = tester.widget<ShellBottomNavBar>(
      find.byType(ShellBottomNavBar),
    );
    expect(bar.items.map((item) => item.title), isNot(contains('الصندوق')));

    await _tapDashboard(tester, 'صندوق اليوم');

    expect(find.textContaining('لا تملك صلاحية'), findsOneWidget);
    expect(_titles(tester), isNot(contains('الصندوق')));
    await _finish(tester);
  });

  testWidgets('القائمة الفرعية تعيد الفواتير والخدمات للموظف', (tester) async {
    await _pumpShell(tester, size: _phone);
    final bar = tester.widget<ShellBottomNavBar>(
      find.byType(ShellBottomNavBar),
    );
    final log = bar.items.firstWhere((i) => i.title == 'سجل غيارات الزيت');
    final subs = log.subItems!.map((sub) => sub.title);
    expect(subs, containsAll(['الفواتير', 'الخدمات وأسعارها']));
    expect(bar.items.first.title, 'الرئيسية');
    await _finish(tester);
  });
}
