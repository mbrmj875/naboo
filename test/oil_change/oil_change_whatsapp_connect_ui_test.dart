import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_anchor.dart';
import 'package:naboo/guides/tours/oil_change_tours.dart';
import 'package:naboo/guides/guide_tour.dart';
import 'package:naboo/verticals/oil_change/models/tenant_whatsapp_gateway_record.dart';
import 'package:naboo/verticals/oil_change/models/whatsapp_connect_method.dart';
import 'package:naboo/verticals/oil_change/utils/whatsapp_onboarding_copy.dart';
import 'package:naboo/verticals/oil_change/widgets/whatsapp_connect_method_picker.dart';
import 'package:naboo/verticals/oil_change/widgets/whatsapp_connect_test_card.dart';

Widget _rtlPicker({
  required WhatsappConnectMethod selected,
  required ValueChanged<WhatsappConnectMethod> onChanged,
  bool enabled = true,
}) {
  return MaterialApp(
    locale: const Locale('ar', 'SA'),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: WhatsappConnectMethodPicker(
            selected: selected,
            onChanged: onChanged,
            enabled: enabled,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('طرق الربط الثلاث — انحدار التحديثات (dualhook / ycloud / QR)', () {
    test('nabooShared يُخزَّن dualhook للتوافق مع الصفوف القديمة', () {
      expect(
        WhatsappConnectMethod.nabooShared.providerApiValue,
        'dualhook',
      );
      expect(
        WhatsappConnectMethod.metaDirect.providerApiValue,
        'cloud_api',
      );
      expect(WhatsappConnectMethod.qrCode.providerApiValue, 'evolution');
    });

    test('fromProvider: dualhook و ycloud → رقم نابو الرسمي', () {
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.dualhook),
        WhatsappConnectMethod.nabooShared,
      );
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.ycloud),
        WhatsappConnectMethod.nabooShared,
      );
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.cloudApi),
        WhatsappConnectMethod.metaDirect,
      );
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.evolution),
        WhatsappConnectMethod.qrCode,
      );
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.waha),
        WhatsappConnectMethod.qrCode,
      );
      expect(
        WhatsappConnectMethodX.fromProvider(TenantWhatsappProvider.whats360),
        isNull,
      );
    });

    test('سجل بلا مزود معروف يبدأ برقم المحل', () {
      expect(
        WhatsappConnectMethodX.fromRecord(null),
        WhatsappConnectMethod.metaDirect,
      );
      final whats360 = TenantWhatsappGatewayRecord.fromMap({
        'evolution_instance_name': 'shop-1',
        'status': 'connected',
        'whatsapp_provider': 'whats360',
        'ready_state': 'ready',
      });
      expect(
        WhatsappConnectMethodX.fromRecord(whats360),
        WhatsappConnectMethod.metaDirect,
      );
    });

    TenantWhatsappGatewayRecord rec(String provider, String status) =>
        TenantWhatsappGatewayRecord.fromMap({
          'evolution_instance_name': 'shop-1',
          'status': status,
          'whatsapp_provider': provider,
        });

    test('المتجر الجديد لا يرى QR ولا يبدأ به رغم أن مزوده الافتراضي waha', () {
      final fresh = rec('waha', 'disconnected');
      expect(
        WhatsappConnectMethodX.fromRecord(fresh),
        WhatsappConnectMethod.metaDirect,
      );
      expect(
        WhatsappConnectMethodX.visibleFor(fresh),
        isNot(contains(WhatsappConnectMethod.qrCode)),
      );
      expect(
        WhatsappConnectMethodX.visibleFor(null),
        isNot(contains(WhatsappConnectMethod.qrCode)),
      );
    });

    test('من يستخدم QR الآن يبقى يراه', () {
      for (final status in ['connected', 'connecting']) {
        final r = rec('evolution', status);
        expect(
          WhatsappConnectMethodX.fromRecord(r),
          WhatsappConnectMethod.qrCode,
        );
        expect(
          WhatsappConnectMethodX.visibleFor(r),
          contains(WhatsappConnectMethod.qrCode),
        );
      }
    });

    test('متجر رقم نابو المفصول يبقى على طريقته', () {
      expect(
        WhatsappConnectMethodX.fromRecord(rec('dualhook', 'disconnected')),
        WhatsappConnectMethod.nabooShared,
      );
    });

    test('لا توجد عبارة موصى به', () {
      for (final m in WhatsappConnectMethod.values) {
        expect(m.badgeAr, isNot(contains('موصى')));
      }
    });

    test('سبب توقف الربط بلا نص خام', () {
      expect(WhatsappOnboardingCopy.stopReasonAr(step: 'completed'), isNull);
      expect(
        WhatsappOnboardingCopy.stopReasonAr(step: 'meta_opened'),
        contains('لم يتغير شيء'),
      );
      expect(
        WhatsappOnboardingCopy.stopReasonAr(
          step: 'failed',
          errorCode: 'meta_phone_list_error_100 raw english',
        ),
        isNot(contains('raw')),
      );
      expect(
        WhatsappOnboardingCopy.stopReasonAr(
          step: 'failed',
          errorCode: 'phone_register_failed',
        ),
        contains('تسجيل الرقم'),
      );
    });

    Future<void> pumpTest(
      WidgetTester tester, {
      required ConnectTestSend send,
      required ConnectTestStatus status,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsappConnectTestCard(
              send: send,
              fetchStatus: status,
              pollInterval: const Duration(seconds: 1),
              maxPolls: 2,
            ),
          ),
        ),
      );
      await tester.tap(find.text('أرسل رسالة تجربة لرقمي'));
      await tester.pump();
    }

    testWidgets('لا نجاح قبل تأكيد الوصول', (tester) async {
      var status = 'sent';
      await pumpTest(
        tester,
        send: (_) async => (ok: true, key: 'k', messageAr: null),
        status: (_) async => (status: status, error: ''),
      );
      await tester.pump();
      expect(find.textContaining('ننتظر تأكيد الوصول'), findsOneWidget);
      status = 'delivered';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('وصلت رسالة التجربة'), findsOneWidget);
    });

    testWidgets('انتهاء الانتظار لا يدّعي النجاح', (tester) async {
      await pumpTest(
        tester,
        send: (_) async => (ok: true, key: 'k', messageAr: null),
        status: (_) async => (status: 'sent', error: ''),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('وصلت رسالة'), findsNothing);
      expect(find.textContaining('لم يصلنا تأكيد'), findsOneWidget);
    });

    testWidgets('الفشل يعرض سببًا عربيًا', (tester) async {
      await pumpTest(
        tester,
        send: (_) async => (ok: true, key: 'k', messageAr: null),
        status: (_) async => (
          status: 'failed',
          error: '{"source":"meta","code":"131026","retryable":false,'
              '"reason_code":"recipient_unreachable"}',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('لم تصل إلى هذا الرقم'), findsOneWidget);
    });

    test('الرسمي = Meta مباشرة أو رقم نابو — QR غير رسمي وفيه تحذير', () {
      expect(WhatsappConnectMethod.metaDirect.isOfficial, isTrue);
      expect(WhatsappConnectMethod.nabooShared.isOfficial, isTrue);
      expect(WhatsappConnectMethod.qrCode.isOfficial, isFalse);
      expect(WhatsappConnectMethod.qrCode.showStabilityWarning, isTrue);
      expect(WhatsappConnectMethod.metaDirect.showStabilityWarning, isFalse);
    });

    test('عناوين الواجهة عربية مع أسماء المنصات فقط (Meta/QR)', () {
      for (final m in WhatsappConnectMethod.values) {
        expect(m.titleAr, isNot(isEmpty));
        expect(m.subtitleAr, isNot(isEmpty));
        expect(m.badgeAr, isNot(isEmpty));
        final brandsStripped = m.titleAr
            .replaceAll('Meta', '')
            .replaceAll('QR', '');
        expect(RegExp(r'[A-Za-z]{4,}').hasMatch(brandsStripped), isFalse);
      }
      expect(WhatsappConnectMethod.nabooShared.badgeAr, 'بلا رقم');
      expect(WhatsappConnectMethod.qrCode.titleAr, contains('QR'));
    });
  });

  group('TenantWhatsappGatewayRecord — مزودون بعد التحديثات', () {
    test('cloud_api متصل وجاهز = نقل رسمي', () {
      final row = TenantWhatsappGatewayRecord.fromMap({
        'evolution_instance_name': 'uid-abc',
        'status': 'connected',
        'whatsapp_phone': '9647884289711',
        'whatsapp_provider': 'cloud_api',
        'cloud_setup_status': 'linked',
        'ready_state': 'ready',
      });
      expect(row.isCloudApi, isTrue);
      expect(row.isOfficialTransport, isTrue);
      expect(row.usesQr, isFalse);
      expect(row.isConnected, isTrue);
      expect(row.readyStateLabelAr, 'جاهز');
      expect(row.needsApiCredentialSetup, isFalse);
    });

    test('dualhook = رقم نابو الرسمي حتى لو الاسم التاريخي dualhook', () {
      final row = TenantWhatsappGatewayRecord.fromMap({
        'evolution_instance_name': 'shared',
        'status': 'connecting',
        'whatsapp_provider': 'dualhook',
        'ready_state': 'preparing',
      });
      expect(row.isNabooShared, isTrue);
      expect(row.isOfficialTransport, isTrue);
      expect(row.readyStateLabelAr, 'جاري تجهيز الخدمة…');
    });

    test('evolution/waha يستخدمان QR وليسا نقلاً رسمياً', () {
      final evo = TenantWhatsappGatewayRecord.fromMap({
        'evolution_instance_name': 'evo-1',
        'status': 'disconnected',
        'whatsapp_provider': 'evolution',
        'ready_state': 'disconnected',
      });
      expect(evo.usesQr, isTrue);
      expect(evo.isOfficialTransport, isFalse);
      expect(evo.readyStateLabelAr, 'غير متصل');
    });

    test('مزود فارغ يسقط إلى WAHA لا إلى cloud_api', () {
      final row = TenantWhatsappGatewayRecord.fromMap({
        'evolution_instance_name': 'x',
        'status': 'weird',
      });
      expect(row.provider, TenantWhatsappProvider.waha);
      expect(row.status, TenantWhatsappGatewayStatus.unknown);
    });
  });

  group('واجهة اختيار طريقة الربط', () {
    testWidgets('تعرض الطرق الثلاث بالعربية وRTL', (tester) async {
      await tester.pumpWidget(
        _rtlPicker(
          selected: WhatsappConnectMethod.nabooShared,
          onChanged: (_) {},
        ),
      );
      expect(find.text('الإرسال من رقم نابو الرسمي'), findsOneWidget);
      expect(find.text('ربط رسمي عبر Meta مباشرة'), findsOneWidget);
      expect(find.text('ربط سريع بمسح QR'), findsOneWidget);
      expect(find.text('بلا رقم'), findsOneWidget);
      expect(find.text('تنبيه: قد ينقطع أكثر من الربط الرسمي.'), findsOneWidget);
    });

    testWidgets('الضغط على QR يغيّر الاختيار', (tester) async {
      var selected = WhatsappConnectMethod.nabooShared;
      await tester.pumpWidget(
        _rtlPicker(
          selected: selected,
          onChanged: (m) => selected = m,
        ),
      );
      await tester.tap(find.text('ربط سريع بمسح QR'));
      await tester.pump();
      expect(selected, WhatsappConnectMethod.qrCode);
    });

    testWidgets('الضغط على Meta مباشرة يغيّر الاختيار', (tester) async {
      var selected = WhatsappConnectMethod.nabooShared;
      await tester.pumpWidget(
        _rtlPicker(
          selected: selected,
          onChanged: (m) => selected = m,
        ),
      );
      await tester.tap(find.text('ربط رسمي عبر Meta مباشرة'));
      await tester.pump();
      expect(selected, WhatsappConnectMethod.metaDirect);
    });

    testWidgets('التعطيل لا يغيّر الطريقة المختارة', (tester) async {
      var selected = WhatsappConnectMethod.nabooShared;
      await tester.pumpWidget(
        _rtlPicker(
          selected: selected,
          onChanged: (m) => selected = m,
          enabled: false,
        ),
      );
      await tester.tap(find.text('ربط سريع بمسح QR'));
      await tester.pump();
      expect(selected, WhatsappConnectMethod.nabooShared);
    });

    testWidgets('مراسي الجولة موجودة للطرق الثلاث', (tester) async {
      await tester.pumpWidget(
        _rtlPicker(
          selected: WhatsappConnectMethod.nabooShared,
          onChanged: (_) {},
        ),
      );
      expect(
        WhatsappConnectMethodPicker.anchorIdFor(
          WhatsappConnectMethod.nabooShared,
        ),
        OilGuideAnchors.waMethodNaboo,
      );
      expect(
        WhatsappConnectMethodPicker.anchorIdFor(
          WhatsappConnectMethod.metaDirect,
        ),
        OilGuideAnchors.waMethodMeta,
      );
      expect(
        WhatsappConnectMethodPicker.anchorIdFor(WhatsappConnectMethod.qrCode),
        OilGuideAnchors.waMethodQr,
      );
    });
  });

  group('جولة المساعد لشاشة الربط', () {
    test('جولة واتساب تغطي الطرق الثلاث والفصل وإعادة الربط', () {
      final tour = oilChangeTours.singleWhere(
        (t) => t.id == GuideTourIds.oilWhatsapp,
      );
      expect(tour.title, contains('واتساب'));
      final bodies = tour.steps.map((s) => '${s.title} ${s.body}').join('\n');
      expect(bodies, contains('رقم نابو'));
      expect(bodies, contains('Meta'));
      expect(bodies, contains('QR'));
      expect(bodies, contains('PIN'));
      expect(bodies, contains('إلغاء الربط'));
      expect(bodies, contains('إعادة الربط'));
      expect(
        tour.steps.any((s) => s.ensureRouteId?.contains('whatsapp') == true),
        isTrue,
      );
    });
  });
}
