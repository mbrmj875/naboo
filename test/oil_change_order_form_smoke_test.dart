import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';

import 'oil_change/helpers/oil_employee_home_harness.dart';

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('بطاقة غيار زيت جديدة — لا crash وحقول أساسية', (tester) async {
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 900),
    );

    expect(find.text('بيانات العميل'), findsOneWidget);
    expect(find.text('بيانات السيارة'), findsOneWidget);
    expect(find.text('العداد'), findsOneWidget);
    expect(find.text('رقم اللوحة'), findsOneWidget);
  });
}
