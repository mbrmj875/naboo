import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_messages_repository.dart';
import 'package:naboo/verticals/oil_change/utils/whatsapp_failure_reason_ar.dart';
import 'package:naboo/verticals/oil_change/widgets/whatsapp_send_block_banner.dart';

void main() {
  group('WhatsappFailureReasonAr', () {
    test('JSON منظم من Meta 131026', () {
      const raw =
          '{"source":"meta","code":"131026","title":"Undeliverable","message":"x","retryable":false}';
      final r = WhatsappFailureReasonAr.parse(raw);
      expect(r.messageAr, contains('لم تصل إلى هذا الرقم'));
      expect(r.action, WhatsappFixAction.correctPhone);
      expect(r.sourceBadgeAr, 'فشل من Meta');
      expect(r.code, '131026');
      expect(
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: true,
          code: r.code,
          retryableFromServer: r.retryable,
        ),
        isFalse,
      );
    });

    test('كود دفع ميتا 131042 يظهر بالعربية مع زر إعادة يدوي', () {
      const raw =
          '{"source":"meta","code":"131042","title":"Business eligibility payment issue","message":"Business eligibility payment issue","retryable":false}';
      final r = WhatsappFailureReasonAr.parse(raw);
      expect(r.messageAr, contains('دفع'));
      expect(r.code, '131042');
      expect(r.retryable, isFalse);
      expect(
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: true,
          code: r.code,
          retryableFromServer: r.retryable,
        ),
        isTrue,
      );
    });

    test('retryable:false من الخادم لا يُوسَّع لكود ميتا مجهول', () {
      const raw =
          '{"source":"meta","code":"999001","title":"Odd","message":"x","retryable":false}';
      final r = WhatsappFailureReasonAr.parse(raw);
      expect(r.retryable, isFalse);
      expect(
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: true,
          code: r.code,
          retryableFromServer: r.retryable,
        ),
        isFalse,
      );
    });

    test('retryable:true من الخادم يظهر زر الإعادة', () {
      const raw =
          '{"source":"gateway","code":"timeout","title":"t","message":"x","retryable":true}';
      final r = WhatsappFailureReasonAr.parse(raw);
      expect(r.retryable, isTrue);
      expect(
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: true,
          code: r.code,
          retryableFromServer: r.retryable,
        ),
        isTrue,
      );
    });

    test('JSON تالف لا يسبب crash', () {
      final r = WhatsappFailureReasonAr.parse('{not-json');
      expect(r.messageAr, WhatsappFailureReasonAr.unknownAr);
    });

    test('نص قديم legacy', () {
      final r = WhatsappFailureReasonAr.parse('not_ready:preparing');
      expect(r.messageAr, contains('قيد التجهيز'));
    });

    test('outbox noInternet', () {
      final r = WhatsappFailureReasonAr.parse(
        'noInternet',
        fromLocalOutbox: true,
      );
      expect(r.retryable, isTrue);
      expect(r.sourceBadgeAr, 'معلّقة على الجهاز');
      expect(r.fixAr, contains('الإنترنت'));
    });

    test('جلسة منتهية تخبر الموظف بالخروج والدخول', () {
      final r = WhatsappFailureReasonAr.parse(
        'unauthorized',
        fromLocalOutbox: true,
      );
      expect(r.messageAr, contains('جلسة'));
      expect(r.fixAr, contains('سجّل الدخول'));
    });

    test('رصيد أو فاتورة منتهية', () {
      final r = WhatsappFailureReasonAr.parse(
        'insufficientWallet',
        fromLocalOutbox: true,
      );
      expect(r.messageAr, contains('فاتورة'));
      expect(r.fixAr, contains('الباقة'));
    });

    test('فارغ سحابي', () {
      final r = WhatsappFailureReasonAr.parse('');
      expect(r.messageAr, WhatsappFailureReasonAr.unknownAr);
    });

    test('كود ميتا غير معروف يعرض الرمز', () {
      const raw =
          '{"source":"meta","code":"999001","title":"Odd","message":"x","retryable":false}';
      final r = WhatsappFailureReasonAr.parse(raw);
      expect(r.messageAr, contains('999001'));
    });
  });

  group('جدول الفشل عبر reason_code', () {
    String row(String reason, {String code = '1', bool retryable = false}) =>
        '{"source":"meta","code":"$code","title":"t","message":"raw english",'
        '"retryable":$retryable,"reason_code":"$reason"}';

    const expected = <String, (String, WhatsappFixAction)>{
      'recipient_unreachable': (
        'لم تصل إلى هذا الرقم',
        WhatsappFixAction.correctPhone,
      ),
      'account_locked': ('مقفول عند Meta', WhatsappFixAction.openMeta),
      'payment_issue_store': ('بسبب الدفع', WhatsappFixAction.openMeta),
      'platform_issue': ('المشكلة عندنا', WhatsappFixAction.none),
      'window_closed': ('24 ساعة', WhatsappFixAction.none),
      'template_paused': ('قالب الرسالة', WhatsappFixAction.none),
      'reconnect_needed': ('انتهى إذن نابو', WhatsappFixAction.reconnect),
      'temporary': ('عطل مؤقت', WhatsappFixAction.none),
    };

    expected.forEach((reason, want) {
      test('$reason له سبب وحل وزر', () {
        final r = WhatsappFailureReasonAr.parse(row(reason));
        expect(r.reasonCode, reason);
        expect(r.messageAr, contains(want.$1));
        expect(r.fixAr, isNotEmpty);
        expect(r.action, want.$2);
        expect(r.isUnknown, isFalse);
        expect(r.messageAr, isNot(contains('raw english')));
      });
    });

    test('الجدول يغطي كل رموز الخادم عدا unknown', () {
      expect(
        WhatsappFailureReasonAr.reasonCopy.keys.toSet(),
        expected.keys.toSet(),
      );
    });

    test('رقم نابو لا يطلب من المتجر إصلاح الدفع', () {
      final r = WhatsappFailureReasonAr.parse(
        row('platform_issue', code: '131042'),
      );
      expect(r.messageAr, isNot(contains('Meta')));
      expect(r.action, WhatsappFixAction.none);
    });

    test('reason_code يتقدم على المسار القديم لنفس الرمز', () {
      final r = WhatsappFailureReasonAr.parse(
        row('payment_issue_store', code: '131026'),
      );
      expect(r.messageAr, WhatsappFailureReasonAr.paymentAr);
    });

    test('reason_code=unknown يبقى على مسار الرمز', () {
      final r = WhatsappFailureReasonAr.parse(row('unknown', code: '131050'));
      expect(r.messageAr, contains('رسائل التسويق'));
    });

    test('reason_code لا يوسع إعادة الإرسال', () {
      final r = WhatsappFailureReasonAr.parse(row('account_locked'));
      expect(r.retryable, isFalse);
    });
  });

  group('النص القديم من Graph', () {
    test('(#131031) داخل نص إنجليزي', () {
      final r = WhatsappFailureReasonAr.parse(
        '(#131031) Business Account locked',
      );
      expect(r.code, '131031');
      expect(r.messageAr, contains('مقفول عند Meta'));
      expect(r.messageAr, isNot(contains('Business Account locked')));
    });

    test('رمز JSON يحمل نص Graph لا يظهر خامًا', () {
      final r = WhatsappFailureReasonAr.parse(
        '{"source":"gateway","code":"(#100) Invalid parameter","title":"",'
        '"message":"","retryable":false}',
      );
      expect(r.code, '100');
      expect(r.messageAr, contains('غير صالحة'));
    });

    test('Unsupported post request يطلب إعادة الربط', () {
      final r = WhatsappFailureReasonAr.parse(
        '{"source":"gateway","code":"Unsupported post request","title":"",'
        '"message":"","retryable":false}',
      );
      expect(r.code, 'meta_permission');
      expect(r.action, WhatsappFixAction.reconnect);
      expect(r.fixAr, contains('رقم نابو'));
    });

    test('نص إنجليزي بلا رمز يبقى مجهولًا ولا يتحول إلى رمز', () {
      final r = WhatsappFailureReasonAr.parse(
        'Something odd happened on the other side',
      );
      expect(r.code, 'unknown');
      expect(r.isUnknown, isTrue);
      expect(r.messageAr, contains('الرقم المرجعي'));
    });

    test('الانقطاع لا يطلب QR، وأخطاء Evolution تطلبه', () {
      expect(
        WhatsappFailureReasonAr.parse('gateway:disconnected').fixAr,
        isNot(contains('QR')),
      );
      expect(
        WhatsappFailureReasonAr.parse(
          '{"source":"gateway","code":"evolution","retryable":false}',
        ).fixAr,
        contains('QR'),
      );
    });

    test('131042 القديم لا يجزم بأن الدفع على المتجر', () {
      final r = WhatsappFailureReasonAr.parse(
        '{"source":"meta","code":"131042","retryable":false}',
      );
      expect(r.fixAr, contains('رقم نابو'));
    });
  });

  group('الرقم المرجعي', () {
    test('بداية معرّف السجل بأحرف كبيرة', () {
      expect(
        WhatsappFailureReasonAr.referenceFor(
          'a66b5bad-1111-2222-3333-444444444444',
        ),
        'A66B5BAD',
      );
    });
  });

  group('أثر الرسالة على الرصيد', () {
    final now = DateTime.utc(2026, 11, 7, 12);

    test('لا قيد: لا نجزم بشيء', () {
      const e = WhatsappWalletEffect(sends: 0, refunds: 0);
      expect(e.textAr(now), isNull);
    });

    test('عادت الوحدة', () {
      const e = WhatsappWalletEffect(sends: 1, refunds: 1);
      expect(e.textAr(now), contains('عادت'));
    });

    test('خصم حديث يعود تلقائيًا', () {
      final e = WhatsappWalletEffect(
        sends: 1,
        refunds: 0,
        lastDebitAt: now.subtract(const Duration(hours: 3)),
      );
      expect(e.textAr(now), contains('تلقائيًا'));
    });

    test('خصم قديم لم يعد لا يعد بإرجاع تلقائي', () {
      final e = WhatsappWalletEffect(
        sends: 1,
        refunds: 0,
        lastDebitAt: now.subtract(const Duration(days: 5)),
      );
      expect(e.textAr(now), contains('الدعم'));
      expect(e.textAr(now), isNot(contains('تلقائيًا')));
    });

    test('تجميع القيود حسب المفتاح الأصلي', () {
      final g = OilChangeWhatsappMessagesRepository.groupWalletEffects([
        {'idempotency_key': 'K', 'reason': 'send', 'created_at': '2026-11-01T00:00:00Z'},
        {'idempotency_key': 'K#r1', 'reason': 'refund_failed_send', 'created_at': '2026-11-02T00:00:00Z'},
        {'idempotency_key': 'K#2', 'reason': 'send', 'created_at': '2026-11-03T00:00:00Z'},
        {'idempotency_key': 'L#1x', 'reason': 'send', 'created_at': '2026-11-03T00:00:00Z'},
      ]);
      expect(g['K']!.sends, 2);
      expect(g['K']!.refunds, 1);
      expect(g['K']!.lastDebitAt, DateTime.utc(2026, 11, 3));
      expect(g.containsKey('L#1x'), isTrue);
    });
  });

  group('إيقاف الطابور', () {
    test('غياب الحقل أو عدم الإيقاف لا يعرض شريطًا', () {
      expect(WhatsappSendBlock.fromJson(null), isNull);
      expect(WhatsappSendBlock.fromJson({'blocked': false}), isNull);
    });

    test('إيقاف المنصة يعرض مشكلتنا مهما كان السبب', () {
      final b = WhatsappSendBlock.fromJson({
        'blocked': true,
        'scope': 'platform',
        'reason': 'account_locked',
      })!;
      expect(b.copy.messageAr, contains('المشكلة عندنا'));
      expect(b.copy.action, WhatsappFixAction.none);
    });

    testWidgets('شريط واحد وزر واحد ينقل إلى الحل', (tester) async {
      WhatsappFixAction? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsappSendBlockBanner(
              block: const WhatsappSendBlock(
                scope: 'tenant',
                reason: 'reconnect_needed',
              ),
              onAction: (a) => tapped = a,
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('إعادة الربط'));
      expect(tapped, WhatsappFixAction.reconnect);
    });

    testWidgets('إيقاف المنصة بلا زر', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsappSendBlockBanner(
              block: const WhatsappSendBlock(scope: 'platform', reason: 'x'),
              onAction: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
