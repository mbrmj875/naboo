import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/customer_record.dart';
import 'package:naboo/verticals/oil_change/widgets/oil_change_customer_name_field.dart';

CustomerRecord _customer(int id, String name, [String? phone]) =>
    CustomerRecord(
      id: id,
      name: name,
      phone: phone,
      balance: 0,
      loyaltyPoints: 0,
    );

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late List<CustomerRecord> picked;
  late List<String> queries;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    picked = [];
    queries = [];
  });

  tearDown(() {
    focusNode.unfocus();
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: OilChangeCustomerNameField(
              controller: controller,
              focusNode: focusNode,
              onSelected: picked.add,
              prepareIndex: () async {},
              search: (q) {
                queries.add(q);
                return [
                  _customer(1, 'محمد باقر', '07884289711'),
                  _customer(2, 'محمد فوزي'),
                  _customer(3, 'أحمد كريم'),
                ];
              },
            ),
          ),
        ),
      ),
    );
  }

  test('حرف واحد يفعّل البحث والحقل الفارغ لا يفعّله', () {
    expect(oilCustomerFirstNameReady(''), isFalse);
    expect(oilCustomerFirstNameReady('م'), isTrue);
    expect(oilCustomerFirstNameReady('مح'), isTrue);
    expect(oilCustomerFirstNameReady('محمد'), isTrue);
    expect(oilCustomerFirstNameReady('محمد ف'), isTrue);
  });

  testWidgets('لا اقتراحات والحقل فارغ', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();

    controller.text = '   ';
    controller.notifyListeners();
    await tester.pump();

    expect(find.text('محمد باقر'), findsNothing);
    expect(queries, isEmpty);
  });

  testWidgets('بعد الاسم الأول تظهر قائمة تحت الحقل', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();

    controller.text = 'محمد';
    controller.notifyListeners();
    await tester.pump();

    expect(find.text('محمد باقر'), findsOneWidget);
    expect(find.text('محمد فوزي'), findsOneWidget);
    expect(queries, ['محمد']);
  });

  testWidgets('اختيار اقتراح يبلّغ الشاشة', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    controller.text = 'محمد';
    controller.notifyListeners();
    await tester.pump();

    await tester.tap(find.text('محمد فوزي'));
    await tester.pumpAndSettle();

    expect(picked.map((c) => c.id).toList(), [2]);
  });
}
