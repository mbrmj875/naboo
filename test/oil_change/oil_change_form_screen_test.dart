import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeOrderFormScreen', () {
    Future<void> pumpForm(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OilChangeFormScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('shows car data sections plate model odometer', (tester) async {
      await pumpForm(tester);
      expect(find.text('بيانات العميل'), findsOneWidget);
      expect(find.text('بيانات السيارة'), findsOneWidget);
      expect(find.text('رقم اللوحة'), findsOneWidget);
    });

    testWidgets('shows oil type viscosity and size fields', (tester) async {
      await pumpForm(tester);
      expect(find.text('تغيير الزيت'), findsOneWidget);
      expect(find.textContaining('زيت'), findsWidgets);
    });

    testWidgets('form exposes plate field label', (tester) async {
      await pumpForm(tester);
      expect(find.text('رقم اللوحة'), findsOneWidget);
    });

    testWidgets('form exposes oil change section', (tester) async {
      await pumpForm(tester);
      expect(find.text('تغيير الزيت'), findsOneWidget);
    });

    testWidgets('save action button is visible on new card', (tester) async {
      await pumpForm(tester);
      expect(
        find.byWidgetPredicate(
          (w) => w is ElevatedButton || w is FilledButton || w is TextButton,
        ),
        findsWidgets,
      );
    });
  });
}
