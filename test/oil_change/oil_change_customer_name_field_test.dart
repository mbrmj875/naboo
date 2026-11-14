// اختيار عميل من قائمة الاقتراحات يملأ البطاقة: بالفأرة على الحاسوب واللمس
// على الهاتف. على الويندوز كانت القائمة تُغلق لحظة نزول الزر فلا يصل الاختيار.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_record.dart';
import 'package:naboo/verticals/oil_change/widgets/oil_change_customer_name_field.dart';

const _ahmed = CustomerRecord(
  id: 7,
  name: 'أحمد علي',
  phone: '07701234567',
  balance: 0,
  loyaltyPoints: 0,
);

Future<List<CustomerRecord>> _pickWith(
  WidgetTester tester, {
  required TargetPlatform platform,
  required PointerDeviceKind kind,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final picked = <CustomerRecord>[];
  final controller = TextEditingController();
  final focus = FocusNode();
  addTearDown(() {
    controller.dispose();
    focus.dispose();
  });
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: OilChangeCustomerNameField(
            controller: controller,
            focusNode: focus,
            onSelected: picked.add,
            search: (q) => q.isEmpty ? const [] : const [_ahmed],
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.byType(TextFormField));
  await tester.enterText(find.byType(TextFormField), 'أحم');
  await tester.pump();
  expect(find.text('أحمد علي'), findsOneWidget);

  // ضغطة حقيقية: إطارات تمر بين نزول الزر ورفعه (حوالي 100 ms).
  final g = await tester.startGesture(
    tester.getCenter(find.text('أحمد علي')),
    kind: kind,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await g.up();
  await tester.pumpAndSettle();
  debugDefaultTargetPlatformOverride = null;
  return picked;
}

void main() {
  testWidgets('Windows: a mouse click on a suggestion picks the customer',
      (tester) async {
    final picked = await _pickWith(
      tester,
      platform: TargetPlatform.windows,
      kind: PointerDeviceKind.mouse,
    );
    expect(picked.map((c) => c.id), [7]);
    expect(find.text('07701234567'), findsNothing); // القائمة أُغلقت.
  });

  testWidgets('macOS: a mouse click on a suggestion picks the customer',
      (tester) async {
    final picked = await _pickWith(
      tester,
      platform: TargetPlatform.macOS,
      kind: PointerDeviceKind.mouse,
    );
    expect(picked.map((c) => c.id), [7]);
  });

  testWidgets('Android: a touch on a suggestion still picks the customer',
      (tester) async {
    final picked = await _pickWith(
      tester,
      platform: TargetPlatform.android,
      kind: PointerDeviceKind.touch,
    );
    expect(picked.map((c) => c.id), [7]);
  });

  testWidgets('Windows: a click elsewhere still closes the list',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            OilChangeCustomerNameField(
              controller: controller,
              focusNode: focus,
              onSelected: (_) {},
              search: (q) => q.isEmpty ? const [] : const [_ahmed],
            ),
            const SizedBox(height: 300, child: Text('خارج')),
          ],
        ),
      ),
    ));
    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'أحم');
    await tester.pump();
    expect(find.text('أحمد علي'), findsOneWidget);

    await tester.tap(find.text('خارج'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('أحمد علي'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
