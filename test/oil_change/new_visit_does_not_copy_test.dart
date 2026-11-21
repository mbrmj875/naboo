// المرحلة 3 — زيارة جديدة من سجل سابق لا تنسخ ما يخص الزيارة السابقة:
// قراءة العداد (تظهر تلميحاً فقط)، الملاحظات، الخدمات الإضافية، الفني.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_employee_home_harness.dart';

void main() {
  setUpEmployeeHomeEnvironment();

  testWidgets('زيارة جديدة من السجل: السيارة تُنسخ، العداد والملاحظات والفني لا',
      (tester) async {
    const notes = 'صوت في المحرك عند التشغيل';
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(
        prefillFromOrder: {
          'id': 5001,
          'customerNameSnapshot': basraCustomerName,
          'customerPhone': basraCustomerPhone,
          'deviceName': basraCarName,
          'deviceSerial': basraPlate,
          'carModel': basraCarModel,
          'odometerCurrent': basraOdometerCurrent,
          'odometerNext': basraOdometerNext,
          'technicianName': basraTechnician,
          'issueDescription': notes,
          'requestedServices': 'غسيل محرك',
        },
      ),
      size: const Size(420, 1400),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // السيارة نُسخت.
    expect(find.text(basraCarName), findsOneWidget);
    expect(find.text(basraPlate), findsOneWidget);

    // العداد لم يُنسخ؛ القراءة السابقة تلميح فقط.
    expect(find.textContaining('السابقة: 153,000 كم'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            (w.controller.text.replaceAll(',', '') == basraOdometerCurrent ||
                w.controller.text.replaceAll(',', '') == basraOdometerNext),
      ),
      findsNothing,
    );

    // الملاحظات والفني لم يُنسخا.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            (w.controller.text == notes ||
                w.controller.text == basraTechnician),
      ),
      findsNothing,
    );
  });
}
