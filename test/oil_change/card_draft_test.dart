// المرحلة 3 — مسودة بطاقة جديدة واحدة محلياً، ويُسأل الموظف عند فتح بطاقة جديدة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_product_line.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_card_draft_store.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_employee_home_harness.dart';

Finder _fieldWithText(String text) => find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == text,
    );

void main() {
  setUpEmployeeHomeEnvironment();

  test('المخزن: حفظ واستعادة ومسح، وسطر المنتج بوحدته', () async {
    await OilCardDraftStore.instance.clear();
    await OilCardDraftStore.instance.save(
      {'customerNameSnapshot': basraCustomerName, 'deviceSerial': basraPlate},
      [
        OilChangeProductLine(
          productId: 7,
          productName: 'زيت علبة',
          quantity: 2,
          priceFils: 5000000,
          unitLabel: 'علبة',
          unitFactor: 4,
        ),
      ],
    );
    final d = await OilCardDraftStore.instance.load();
    expect(d, isNotNull);
    expect(d!.summary, '$basraCustomerName — $basraPlate');
    expect(d.productLines.single.stockBaseQty, 8);
    await OilCardDraftStore.instance.clear();
    expect(await OilCardDraftStore.instance.load(), isNull);
  });

  testWidgets('بطاقة جديدة مع مسودة: الاستعادة تملأ الحقول', (tester) async {
    await OilCardDraftStore.instance.save(
      {
        'customerNameSnapshot': basraCustomerName,
        'customerPhone': basraCustomerPhone,
        'deviceName': basraCarName,
        'deviceSerial': basraPlate,
        'issueDescription': 'مسودة اختبار',
      },
      const [],
    );
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1400),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('بطاقة غير محفوظة'), findsOneWidget);
    await tester.tap(find.text('استعادة'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(_fieldWithText(basraCustomerName), findsOneWidget);
    expect(_fieldWithText(basraCarName), findsOneWidget);
  });

  testWidgets('تجاهل المسودة يمسحها ويبقي البطاقة فارغة', (tester) async {
    await OilCardDraftStore.instance.save(
      {'customerNameSnapshot': basraCustomerName, 'deviceName': basraCarName},
      const [],
    );
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1400),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('تجاهلها'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_fieldWithText(basraCarName), findsNothing);
    expect(await OilCardDraftStore.instance.load(), isNull);
  });

  testWidgets('الكتابة في بطاقة جديدة تُحفظ مسودة تلقائياً', (tester) async {
    await OilCardDraftStore.instance.clear();
    await pumpEmployeeHome(
      tester,
      const OilChangeFormScreen(),
      size: const Size(420, 1400),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('بطاقة غير محفوظة'), findsNothing);

    final carField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText ?? '').contains('اسم السيارة'),
    );
    expect(carField, findsWidgets);
    await tester.enterText(carField.first, basraCarName);
    await tester.pump(const Duration(seconds: 5));

    final d = await OilCardDraftStore.instance.load();
    expect(d?.row['deviceName'], basraCarName);
  });
}
