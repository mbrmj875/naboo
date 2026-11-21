// شاشة بطاقة الغيار بمزوّدات التطبيق الحقيقية.
//
// المرحلة 2: حُذف كود الصيانة القديم من الشاشة وأُزيلت دائرة التحميل من
// الإطار الأول للبطاقة الجديدة. هذه الاختبارات تحرس الأقسام الحالية
// وتتأكد أن أقسام الصيانة القديمة لم تعد تظهر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';

import 'helpers/oil_employee_home_harness.dart';

void main() {
  setUpEmployeeHomeEnvironment();

  group('OilChangeOrderFormScreen', () {
    Future<void> pumpForm(WidgetTester tester) =>
        pumpEmployeeHome(
          tester,
          const OilChangeFormScreen(),
          size: const Size(420, 900),
        );

    testWidgets('أقسام العميل والسيارة والزيت ظاهرة', (tester) async {
      await pumpForm(tester);
      expect(find.text('بيانات العميل'), findsOneWidget);
      expect(find.text('بيانات السيارة'), findsOneWidget);
      expect(find.text('رقم اللوحة'), findsOneWidget);
      expect(find.text('العداد'), findsOneWidget);
    });

    testWidgets('أقسام الصيانة القديمة لا تظهر', (tester) async {
      await pumpForm(tester);
      expect(find.text('التفاصيل المالية والعملية'), findsNothing);
      expect(find.text('الخدمات المطلوبة'), findsNothing);
      expect(find.text('نوع الفلتر'), findsNothing);
      expect(find.text('المدة المتوقعة لإنجاز العمل'), findsNothing);
      expect(find.text('إنشاء وحفظ بطاقة الصيانة'), findsNothing);
    });

    testWidgets('البطاقة الجديدة بلا دائرة تحميل ولا غطاء تجهيز',
        (tester) async {
      await pumpForm(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('جاري تجهيز البطاقة من السجل…'), findsNothing);
    });
  });
}
