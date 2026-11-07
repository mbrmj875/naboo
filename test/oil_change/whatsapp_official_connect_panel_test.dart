import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/whatsapp_connect_method.dart';
import 'package:naboo/verticals/oil_change/widgets/whatsapp_official_connect_panel.dart';

void main() {
  Future<void> pump(
    WidgetTester t,
    WhatsappConnectMethod method, {
    Future<void> Function(bool)? onOpenMeta,
    bool stops = false,
  }) async {
    t.view.physicalSize = const Size(1080, 3200);
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WhatsappOfficialConnectPanel(
              method: method,
              preparing: false,
              messageAr: 'x',
              onOpenMeta: onOpenMeta,
              stopsCurrentSending: stops,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('الخطوات الأربع بالترتيب', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    final ys = [
      'ما نوع الرقم؟',
      'جهّز قبل أن تبدأ',
      'أكمل الربط في نافذة Meta',
      'ارجع إلى هنا',
    ].map((s) => t.getTopLeft(find.text(s)).dy).toList();
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.textContaining('2.24.17'), findsOneWidget);
  });

  testWidgets('رقم جديد: لا تحديث تطبيق ولا QR', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    await t.tap(find.text('رقم جديد'));
    await t.pumpAndSettle();
    expect(find.text('تحديث التطبيق'), findsNothing);
    expect(find.textContaining('QR'), findsNothing);
    expect(find.textContaining('داخل نافذة Meta'), findsOneWidget);
  });

  testWidgets('فتح Meta يرسل نوع الرقم، ثم يظهر تحديث الحالة', (t) async {
    final seen = <bool>[];
    await pump(t, WhatsappConnectMethod.metaDirect, onOpenMeta: (v) async {
      seen.add(v);
    });
    expect(find.text('تحديث الحالة'), findsNothing);
    await t.tap(find.text('رقم جديد'));
    await t.pumpAndSettle();
    await t.tap(find.text('فتح Meta'));
    await t.pumpAndSettle();
    expect(seen, [false]);
    expect(find.text('تحديث الحالة'), findsOneWidget);
    expect(find.text('فتح Meta مرة أخرى'), findsOneWidget);
  });

  testWidgets('يحذّر متجرًا يرسل الآن قبل فتح Meta', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect, stops: true);
    expect(find.textContaining('تتوقف رسائل متجرك'), findsOneWidget);
  });

  testWidgets('زر الصلاحية يشرح الخطوات', (t) async {
    await pump(t, WhatsappConnectMethod.metaDirect);
    await t.tap(find.text('كيف أحصل على الصلاحية'));
    await t.pumpAndSettle();
    expect(find.textContaining('business.facebook.com'), findsOneWidget);
  });

  testWidgets('رقم نابو الرسمي بلا خطوات Meta', (t) async {
    await pump(t, WhatsappConnectMethod.nabooShared);
    expect(find.text('ما نوع الرقم؟'), findsNothing);
  });
}
