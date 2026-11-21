// المرحلة 3 — الزيت زر ضمن أزرار الأقسام: مفتوح افتراضياً ما دام إلزامياً،
// ويُطوى بالضغط ويبقى ملخصه، والعداد ظاهر دائماً في قسمه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';

import 'helpers/oil_employee_home_harness.dart';

Future<void> _scrollToBar(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('إضافات عند الحاجة'),
    300,
    scrollable: find
        .ancestor(
          of: find.text('العداد'),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _oilChip() => find.ancestor(
      of: find.text('الزيت'),
      matching: find.byType(FilterChip),
    );

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('الافتراضي: قسم الزيت مفتوح، والضغط يطويه والعداد يبقى',
      (tester) async {
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1600),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _scrollToBar(tester);
    expect(_oilChip(), findsOneWidget);
    expect(find.text('الزيت'), findsNWidgets(2),
        reason: 'الزر + عنوان القسم المفتوح');

    await tester.tap(_oilChip());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('الزيت'), findsOneWidget, reason: 'الزر فقط');
    await tester.scrollUntilVisible(
      find.text('العداد'),
      -300,
      scrollable: find
          .ancestor(
            of: find.text('إضافات عند الحاجة'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('العداد'), findsOneWidget,
        reason: 'العداد خارج قسم الزيت ويبقى بعد طيّه');
  });

  testWidgets('الزيت اختياري في الإعدادات: القسم مطوي في البطاقة الجديدة',
      (tester) async {
    await OilChangeSettings.setFieldRequired(OilCardField.oil, false);
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1600),
    );
    await tester.pump(const Duration(milliseconds: 800));

    await _scrollToBar(tester);
    expect(_oilChip(), findsOneWidget);
    expect(find.text('الزيت'), findsOneWidget, reason: 'القسم مطوي');
    await OilChangeSettings.setFieldRequired(OilCardField.oil, true);
  });
}
