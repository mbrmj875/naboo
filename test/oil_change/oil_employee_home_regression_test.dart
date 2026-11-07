import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_root_selection.dart';
import 'package:naboo/screens/home_screen.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/oil_change/home/oil_change_home_dashboard.dart';
import 'package:naboo/verticals/oil_change/shell/oil_change_shell_screen.dart';

import 'helpers/oil_employee_home_harness.dart';

/// الزر في لوحة الزيت → عنوان الصفحة التي يجب أن يفتحها فعلاً.
const _expectedPages = <String, String>{
  'غيار زيت جديد': 'بطاقة غيار زيت جديدة',
  'بيع مباشر': 'بيع مباشر',
  'غسيل السيارات': 'بطاقة غسيل سيارة',
  'سجل الغيارات': 'سجل غيارات الزيت',
  'السيارات الحالية': 'سجل غيارات الزيت',
  'المخزون': 'مركز المخزون',
  'صندوق اليوم': 'الصندوق',
};

Widget _employeeHome() {
  final root = resolveEmployeeHomeRoot(
    featuresLoaded: true,
    features: BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
    ),
  );
  return switch (root) {
    EmployeeHomeRoot.oilChangeStandalone =>
      const OilChangeShellScreen(),
    _ => const HomeScreen(),
  };
}

List<String?> _appBarTitles(WidgetTester tester) => tester
    .widgetList<AppBar>(find.byType(AppBar))
    .map((bar) => bar.title)
    .map((title) => title is Text ? title.data : null)
    .toList();

void main() {
  setUpEmployeeHomeEnvironment();

  test('موظف الزيت يعود إلى الرئيسية المجرّبة ريثما يكتمل الغلاف الزيتي', () {
    expect(
      resolveEmployeeHomeRoot(
        featuresLoaded: true,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
        ),
      ),
      EmployeeHomeRoot.shared,
    );
  });

  for (final entry in _expectedPages.entries) {
    testWidgets('زر «${entry.key}» يفتح صفحته بلا إنترنت', (tester) async {
      await pumpEmployeeHome(tester, _employeeHome());
      final button = find.descendant(
        of: find.byType(OilChangeHomeDashboard),
        matching: find.textContaining(entry.key),
      );
      expect(button, findsWidgets);
      await tester.ensureVisible(button.first);
      await tester.pump();

      await tester.tap(button.first, warnIfMissed: false);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await tester.pump();

      expect(find.textContaining('غير متاح'), findsNothing);
      expect(_appBarTitles(tester), contains(entry.value));

      // تحميل الصفحة غير المنتظر يجب أن ينتهي قبل تفكيك بيئة الاختبار.
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
  }
}
