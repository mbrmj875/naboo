import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/whatsapp_connect_method.dart';
import 'package:naboo/verticals/oil_change/widgets/whatsapp_official_connect_panel.dart';

void main() {
  Future<void> pump(WidgetTester t, WhatsappConnectMethod method) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WhatsappOfficialConnectPanel(
                method: method,
                preparing: false,
                messageAr: 'x',
              ),
            ),
          ),
        ),
      );

  testWidgets('يجهّز صاحب المتجر قبل فتح Meta', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    expect(find.textContaining('2.24.17'), findsOneWidget);
    expect(find.text('تحديث التطبيق'), findsOneWidget);
    expect(find.text('كيف أحصل على الصلاحية'), findsOneWidget);
  });

  testWidgets('الرقم الجديد لا يطلب تحديث التطبيق', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    await t.tap(find.text('رقم جديد'));
    await t.pumpAndSettle();
    expect(find.text('تحديث التطبيق'), findsNothing);
    expect(find.textContaining('داخل نافذتها'), findsOneWidget);
  });

  testWidgets('زر الصلاحية يشرح الخطوات', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    await t.tap(find.text('كيف أحصل على الصلاحية'));
    await t.pumpAndSettle();
    expect(find.textContaining('business.facebook.com'), findsOneWidget);
  });

  testWidgets('رقم نابو الرسمي بلا هذه القائمة', (t) async {
    await pump(t, WhatsappConnectMethod.nabooShared);
    expect(find.text('قبل أن تبدأ'), findsNothing);
  });
}
