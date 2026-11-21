import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/providers/theme_provider.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';
import 'package:naboo/widgets/adaptive/home_user_menu.dart';
import 'package:naboo/widgets/shell/global_search_page.dart';
import 'package:provider/provider.dart';

import 'helpers/oil_employee_home_harness.dart';

const _phone = Size(390, 844);

Future<void> _wait(WidgetTester tester, [int ms = 900]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = _phone,
  bool Function(String)? can,
}) {
  return pumpEmployeeHome(
    tester,
    OilChangeShellScreen(canOverride: can ?? (_) => true),
    size: size,
  );
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<void> _seedRow(String table, Map<String, Object?> values) async {
  final db = await DatabaseHelper().database;
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  final row = <String, Object?>{};
  for (final c in columns) {
    final name = c['name']! as String;
    if (c['pk'] != 0 || c['notnull'] != 1 || c['dflt_value'] != null) continue;
    final type = (c['type']! as String).toUpperCase();
    row[name] = type.contains('INT') || type.contains('REAL') ? 1 : 'x';
  }
  row.addAll(values);
  row.removeWhere((key, _) => !columns.any((c) => c['name'] == key));
  await db.insert(table, row);
}

Future<void> _openSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byIcon(Icons.search_rounded));
  await _wait(tester);
  expect(find.byType(GlobalSearchPage), findsOneWidget);
  await tester.enterText(find.byType(TextField), query);
  await _wait(tester, 1200);
}

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('الشريط يحوي كل أزراره كما في الرئيسية', (tester) async {
    await _pumpShell(tester);
    for (final tooltip in const [
      'فتح وردية',
      'تزامن سحابي',
      'مساعد نابو',
      'التنبيهات',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    expect(find.byType(HomeUserMenu), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('الوردية المفتوحة تعرض زر الإغلاق وحواره', (tester) async {
    await _seedRow('users', {'id': 41});
    await pumpEmployeeHome(
      tester,
      OilChangeShellScreen(canOverride: (_) => true),
      size: _phone,
    );
    await DatabaseHelper().openWorkShift(
      sessionUserId: 41,
      shiftStaffUserId: 41,
      systemBalanceAtOpen: 0,
      declaredPhysicalCash: 0,
      addedCashAtOpen: 0,
      shiftStaffName: 'علي',
      shiftStaffPin: '',
    );
    final element = tester.element(find.byType(OilChangeShellScreen));
    await element.read<ShiftProvider>().refresh();
    await _wait(tester);

    final close = find.byTooltip('وردية: علي — إغلاق');
    expect(close, findsOneWidget);
    await tester.tap(close);
    await _wait(tester);
    expect(find.byType(Dialog), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('قائمة الحساب تعمل: المظهر والإعدادات وقفل الجلسة', (
    tester,
  ) async {
    await _pumpShell(tester);
    final element = tester.element(find.byType(OilChangeShellScreen));
    final theme = element.read<ThemeProvider>();
    final wasDark = theme.isDarkMode;

    await tester.tap(find.byType(HomeUserMenu));
    await _wait(tester);
    expect(find.text('حاسبة'), findsOneWidget);
    expect(find.text('الإعدادات'), findsWidgets);
    expect(find.text('قفل الجلسة'), findsOneWidget);
    expect(find.text('تخصيص الوحدات'), findsNothing);

    await tester.tap(find.text(wasDark ? 'الوضع النهاري' : 'الوضع الليلي'));
    await _wait(tester);
    expect(theme.isDarkMode, !wasDark);

    await tester.tap(find.byType(HomeUserMenu));
    await _wait(tester);
    await tester.tap(find.text('قفل الجلسة'));
    await _wait(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await _wait(tester);

    await tester.tap(find.byType(HomeUserMenu));
    await _wait(tester);
    await tester.tap(find.text('الإعدادات').last);
    await _wait(tester);
    expect(find.byType(OilChangeHomeDashboard), findsNothing);
    await _finish(tester);
  });

  testWidgets('الشريط العلوي للرئيسية فقط', (tester) async {
    await _pumpShell(tester);
    final cash = find.descendant(
      of: find.byType(OilChangeHomeDashboard),
      matching: find.textContaining('صندوق اليوم'),
    );
    await tester.ensureVisible(cash.first);
    await tester.pump();
    await tester.tap(cash.first, warnIfMissed: false);
    await _wait(tester);
    expect(find.byType(HomeUserMenu), findsNothing);
    await _finish(tester);
  });

  testWidgets('البحث يقدّم سجل الزيت ويفتحه داخل الغلاف', (tester) async {
    await _pumpShell(tester);
    await _openSearch(tester, '1234');

    expect(find.text('البحث في سجل غيارات الزيت'), findsOneWidget);
    await tester.tap(find.text('البحث في سجل غيارات الزيت'));
    await _wait(tester);

    expect(find.byType(GlobalSearchPage), findsNothing);
    final titles = tester
        .widgetList<AppBar>(find.byType(AppBar))
        .map((bar) => bar.title is Text ? (bar.title! as Text).data : null);
    expect(titles, contains('سجل غيارات الزيت'));
    await _finish(tester);
  });

  testWidgets('نتائج العملاء تخضع للصلاحية', (tester) async {
    final tenant = TenantContextService.instance.activeTenantId;
    await _seedRow('customers', {
      'name': 'زبون تجريبي',
      'tenantId': tenant,
      'phone': '07700000000',
    });

    await _pumpShell(tester);
    await _openSearch(tester, 'زبون');
    expect(find.text('زبون تجريبي'), findsOneWidget);
    await _finish(tester);

    await _pumpShell(
      tester,
      can: (key) => key != PermissionKeys.customersView,
    );
    await _openSearch(tester, 'زبون');
    expect(find.text('زبون تجريبي'), findsNothing);
    await _finish(tester);
  });

  testWidgets('لا فيضان على أضيق هاتف، والبحث يبقى على 360', (tester) async {
    await _pumpShell(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    await _finish(tester);

    await _pumpShell(tester, size: const Size(360, 780));
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    await _finish(tester);
  });
}
