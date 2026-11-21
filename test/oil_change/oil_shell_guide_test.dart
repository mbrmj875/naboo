import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';
import 'package:naboo/widgets/shell/shell_bottom_nav.dart';
import 'package:naboo/widgets/shell/shell_sidebar.dart';
import 'package:provider/provider.dart';

import 'helpers/oil_employee_home_harness.dart';

const _guideRoutes = <String>[
  AppContentRoutes.oilServicesLog,
  AppContentRoutes.oilChangeServices,
  AppContentRoutes.oilChangeCreate,
  AppContentRoutes.oilWhatsappConnect,
  AppContentRoutes.carWashCreate,
  AppContentRoutes.settingsDashboardLayout,
  AppContentRoutes.inventoryProducts,
  AppContentRoutes.addProduct,
  AppContentRoutes.users,
  AppContentRoutes.userForm,
  AppContentRoutes.staffShiftsWeek,
  AppContentRoutes.employeeIdentity,
];

Future<void> _wait(WidgetTester tester, [int ms = 700]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<GuideHostBridge> _pumpGuide(
  WidgetTester tester, {
  bool Function(String)? can,
  Size size = const Size(1366, 900),
}) async {
  await pumpEmployeeHome(
    tester,
    OilChangeShellScreen(canOverride: can ?? (_) => true),
    size: size,
  );
  final element = tester.element(find.byType(OilChangeShellScreen));
  return element.read<GuideController>().hostForTesting!;
}

/// يمرر إطارات أثناء انتظار المضيف، فالفتح يتم بعد الإطار.
Future<void> _ensure(
  WidgetTester tester,
  GuideHostBridge host,
  String routeId,
) async {
  var done = false;
  final pending = host.ensureRoute(routeId).whenComplete(() => done = true);
  for (var i = 0; i < 60 && !done; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
  await pending;
  await _wait(tester, 300);
}

void main() {
  setUpEmployeeHomeEnvironment();

  test('كل مسار تطلبه الجولات معروف للغلاف', () {
    final known = File(
      'lib/verticals/oil_change/shell/oil_shell_guide_routes.dart',
    ).readAsStringSync();
    final pattern = RegExp(r'ensureRouteId:\s*AppContentRoutes\.(\w+)');
    final tours = Directory('lib/guides/tours').listSync().whereType<File>();
    for (final tour in tours) {
      for (final match in pattern.allMatches(tour.readAsStringSync())) {
        final name = match.group(1)!;
        if (name == 'home') continue;
        expect(known, contains('AppContentRoutes.$name:'), reason: name);
      }
    }
  });

  for (final routeId in _guideRoutes) {
    testWidgets('الجولة تفتح $routeId داخل الغلاف', (tester) async {
      final host = await _pumpGuide(tester);
      await _ensure(tester, host, routeId);

      expect(host.currentRouteId(), routeId);
      expect(find.byType(ShellSidebar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });
  }

  testWidgets('الاسم البديل للسجل يصل إلى المسار الفعلي', (tester) async {
    final host = await _pumpGuide(tester);
    await _ensure(tester, host, AppContentRoutes.oilChangeHub);

    expect(host.currentRouteId(), AppContentRoutes.oilServicesLog);
    await _finish(tester);
  });

  testWidgets('ربط واتساب يُفتح فوق السجل ويعود إليه', (tester) async {
    final host = await _pumpGuide(tester);
    await _ensure(tester, host, AppContentRoutes.oilWhatsappConnect);


    await _ensure(tester, host, AppContentRoutes.home);
    expect(host.currentRouteId(), AppContentRoutes.home);
    await _finish(tester);
  });

  testWidgets('الجولة لا تتجاوز صلاحية الموظف', (tester) async {
    final host = await _pumpGuide(
      tester,
      can: (key) => key != PermissionKeys.usersView,
    );
    await _ensure(tester, host, AppContentRoutes.users);

    expect(host.currentRouteId(), AppContentRoutes.home);
    await _finish(tester);
  });

  testWidgets('الهاتف: القائمة الفرعية تفتح الفواتير والخدمات', (tester) async {
    await _pumpGuide(tester, size: const Size(390, 844));

    await tester.tap(
      find.descendant(
        of: find.byType(ShellBottomNavBar),
        matching: find.text('سجل غيارات الزيت'),
      ),
    );
    await _wait(tester);
    expect(find.byType(ShellSubMenuPopover), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(ShellSubMenuPopover),
        matching: find.text('الفواتير'),
      ),
    );
    await _wait(tester);

    final host = tester
        .element(find.byType(OilChangeShellScreen))
        .read<GuideController>()
        .hostForTesting!;
    expect(host.currentRouteId(), AppContentRoutes.oilInvoices);
    expect(find.byType(ShellSubMenuPopover), findsNothing);
    await _finish(tester);
  });

  testWidgets('الحاسبة: الشريط الجانبي يوسع الفروع ويفتحها', (tester) async {
    final host = await _pumpGuide(tester);
    await tester.tap(find.byTooltip('توسيع القائمة'));
    await _wait(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(ShellSidebar),
        matching: find.text('سجل غيارات الزيت'),
      ),
    );
    await _wait(tester);
    await tester.tap(find.text('الخدمات وأسعارها'));
    await _wait(tester);

    expect(host.currentRouteId(), AppContentRoutes.oilChangeServices);
    await _finish(tester);
  });
}
