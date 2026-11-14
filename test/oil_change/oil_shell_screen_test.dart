import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_kpi_repository.dart';
import 'package:naboo/providers/dashboard_layout_provider.dart';
import 'package:naboo/screens/home_screen.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';
import 'package:naboo/widgets/shell/shell_bottom_nav.dart';
import 'package:naboo/widgets/shell/shell_sidebar.dart';
import 'package:provider/provider.dart';

import 'helpers/oil_change_test_harness.dart';
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

  testWidgets('التحول من الرئيسية العامة إلى الغلاف لا يكسر المحتوى', (
    tester,
  ) async {
    // جهاز جديد: يبدأ بالقطاع العام ثم تصل إعدادات المتجر فيتحول إلى الزيت.
    final showShell = ValueNotifier<bool>(false);
    addTearDown(showShell.dispose);
    await pumpEmployeeHome(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showShell,
        builder: (_, shell, _) => shell
            ? OilChangeShellScreen(canOverride: (_) => true)
            : const HomeScreen(),
      ),
    );

    showShell.value = true;
    await _wait(tester, 1200);

    expect(tester.takeException(), isNull);
    expect(find.byType(OilChangeHomeDashboard), findsOneWidget);
    await _finish(tester);
  });

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

    final cashTile = find.descendant(
      of: find.byType(OilChangeHomeDashboard),
      matching: find.textContaining('صندوق اليوم'),
    );
    expect(cashTile, findsNothing);
    await _finish(tester);
  });

  testWidgets('«السيارات الحالية» تفتح المعلّقة ورقمها يطابقها', (tester) async {
    final builder = ServiceOrderBuilder(OilChangeTestHarness.instance);
    await builder.createPending(plate: 'PEND-1');
    await builder.createSuspended(plate: 'SUSP-1');
    await builder.createSuspended(plate: 'SUSP-2');
    HomeKpiRepository.instance.invalidate();

    await _pumpShell(tester);
    expect(find.textContaining('السيارات الحالية: 2'), findsOneWidget);

    await _tapDashboard(tester, 'السيارات الحالية');
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    await _finish(tester);
  });

  testWidgets('الرجوع إلى الرئيسية يحدّث الرقم فوراً', (tester) async {
    final builder = ServiceOrderBuilder(OilChangeTestHarness.instance);
    await builder.createSuspended(plate: 'SUSP-1');
    HomeKpiRepository.instance.invalidate();

    await _pumpShell(tester, size: _phone);
    expect(find.textContaining('السيارات الحالية: 1'), findsOneWidget);

    await _tapDashboard(tester, 'صندوق اليوم');
    await builder.createSuspended(plate: 'SUSP-2');
    await tester.tap(
      find.descendant(
        of: find.byType(ShellBottomNavBar),
        matching: find.text('الرئيسية'),
      ),
    );
    await _wait(tester);

    expect(find.textContaining('السيارات الحالية: 2'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('الأزرار الأساسية لا تُخفى حتى لو أُخفي قسمها', (tester) async {
    await _pumpShell(tester);
    final element = tester.element(find.byType(OilChangeShellScreen));
    await element.read<DashboardLayoutProvider>().setSectionVisible(
      'orbit',
      false,
    );
    await _wait(tester, 300);

    expect(find.byType(OilChangeHomeDashboard), findsOneWidget);
    expect(find.textContaining('غيار زيت جديد'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('غسيل السيارات يبقى اختيارياً', (tester) async {
    await _pumpShell(tester);
    final element = tester.element(find.byType(OilChangeShellScreen));
    expect(find.textContaining('غسيل السيارات'), findsOneWidget);

    await element.read<DashboardLayoutProvider>().setCarWashButtonVisible(false);
    await _wait(tester, 300);

    expect(find.textContaining('غسيل السيارات'), findsNothing);
    expect(find.textContaining('بيع مباشر'), findsOneWidget);
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
