import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';
import 'package:naboo/assistant/ui/cards/assistant_cards.dart';
import 'package:naboo/utils/customer_phone_launch.dart';

/// ق43: هاتف الزبون يظهر لمن يملك صلاحية العملاء، مع زر اتصال وواتساب.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AssistantCard(AssistantCustomerCard(customerId: 7, name: 'زبون'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => AssistantCustomerPhone.resolve = null);

  testWidgets('بالصلاحية: الرقم مع نسخ واتصال وواتساب', (tester) async {
    AssistantCustomerPhone.resolve = (_) async => '07701234567';
    await pump(tester);
    expect(find.textContaining('07701234567'), findsOneWidget);
    expect(find.byTooltip('اتصل'), findsOneWidget);
    expect(find.byTooltip('واتساب'), findsOneWidget);
    expect(customerWhatsAppUri('07701234567').toString(), 'https://wa.me/9647701234567');
  });

  testWidgets('بلا صلاحية: لا رقم ولا أزرار', (tester) async {
    AssistantCustomerPhone.resolve = (_) async => null;
    await pump(tester);
    expect(find.byTooltip('اتصل'), findsNothing);
    expect(find.byTooltip('واتساب'), findsNothing);
  });
}
