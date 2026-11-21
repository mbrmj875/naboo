import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_filter_kind.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_rating.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_whatsapp_notify_outcome.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_messages_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_whatsapp_notify_classifier.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_whatsapp_user_messages.dart';

import 'fixtures/basra_oil_visit_fixture.dart';

void main() {
  group('تصنيف ردود البوابة — أعطال التحديثات (n8n / Evolution / Meta)', () {
    test('401 و 403 = جلسة غير مصرّح لا انقطاع واتساب', () {
      for (final code in [401, 403]) {
        final o = classifyWhatsappWebhookResponse(
          statusCode: code,
          body: '{"ok":false,"reason":"invalid jwt"}',
        );
        expect(o.reason, OilChangeWhatsappNotifyReason.unauthorized);
        expect(o.marksGatewayDisconnected, isFalse);
      }
    });

    test('سبب secret في الجسم = unauthorized', () {
      final o = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: '{"ok":false,"reason":"webhook_secret_mismatch"}',
      );
      expect(o.reason, OilChangeWhatsappNotifyReason.unauthorized);
    });

    test('evolution instance error لا يُحسب انقطاع QR عام', () {
      final o = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: '{"ok":false,"reason":"evolution_instance_not_found"}',
      );
      expect(o.reason, OilChangeWhatsappNotifyReason.evolutionError);
      expect(o.marksGatewayDisconnected, isFalse);
    });

    test('رقم غير صالح', () {
      final o = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: '{"ok":false,"error":"invalid phone number"}',
      );
      expect(o.reason, OilChangeWhatsappNotifyReason.invalidPhone);
    });

    test('تعبير n8n غير المعوّض يبقى خطأ خادم', () {
      final o = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body:
            r'{"ok":"={{ $json.ok }}","reason":"={{ $json.reason }}","sent_to":""}',
      );
      expect(o.reason, OilChangeWhatsappNotifyReason.serverError);
      expect(
        OilChangeWhatsappUserMessages.snackbarForOutcome(o),
        contains('سيرفر الإرسال'),
      );
    });

    test('500 و Timeout و Socket تُصنَّف دون تسريب الاستثناء', () {
      expect(
        classifyWhatsappWebhookResponse(statusCode: 502, body: 'Bad Gateway')
            .reason,
        OilChangeWhatsappNotifyReason.serverError,
      );
      expect(
        classifyWhatsappNotifyException(TimeoutException('gateway')),
        isA<OilChangeWhatsappNotifyOutcome>().having(
          (o) => o.reason,
          'reason',
          OilChangeWhatsappNotifyReason.timeout,
        ),
      );
      expect(
        classifyWhatsappNotifyException(
          const SocketException('Failed host lookup'),
        ).reason,
        OilChangeWhatsappNotifyReason.noInternet,
      );
    });

    test('رسائل المستخدم عربية ولا تكشف أسراراً', () {
      for (final reason in OilChangeWhatsappNotifyReason.values) {
        final msg = OilChangeWhatsappUserMessages.snackbarForOutcome(
          OilChangeWhatsappNotifyOutcome(reason: reason),
        );
        expect(msg.trim(), isNotEmpty);
        expect(msg.toLowerCase(), isNot(contains('token')));
        expect(msg.toLowerCase(), isNot(contains('secret')));
        expect(msg.toLowerCase(), isNot(contains('exception')));
      }
    });
  });

  group('سجل الرسائل والتقييم — تحليل الصفوف السحابية', () {
    test('بطاقة غيار زيت قابلة لإعادة الإرسال من الحمولة', () {
      final entry = OilChangeMessageLogEntry.fromMap({
        'id': 'log-basra-1',
        'created_at': '2026-08-13T08:20:00.000Z',
        'status': 'failed',
        'to_phone': basraCustomerPhone,
        'template_key': 'oil_change_card',
        'employee_name': basraTechnician,
        'order_ref': '14212',
        'body': '',
        'error': 'whatsapp_disconnected',
        'card_payload': {
          'customer': basraCustomerName,
          'shop': basraStoreTitle,
          'total': '75,000 د.ع',
        },
      });
      expect(entry.isOilChangeCard, isTrue);
      expect(entry.status.isFailure, isTrue);
      expect(entry.status.reachedCustomer, isFalse);
      expect(entry.canResend, isTrue);
      expect(entry.customerName, basraCustomerName);
      expect(entry.status.labelAr, 'لم يتم الإرسال');
    });

    test('delivered/read تعني وصلت للزبون', () {
      expect(
        OilChangeMessageLogEntry.fromMap({
          'id': '1',
          'created_at': '2026-08-13T00:00:00Z',
          'status': 'read',
          'to_phone': basraCustomerPhone,
        }).status.reachedCustomer,
        isTrue,
      );
      expect(
        OilChangeMessageLogEntry.fromMap({
          'id': '2',
          'created_at': '2026-08-13T00:00:00Z',
          'status': 'sent',
          'to_phone': basraCustomerPhone,
        }).status.reachedCustomer,
        isFalse,
      );
    });

    test('تقييم من رد البطاقة يُسند للفني', () {
      final row = OilChangeRatingEntry.fromMap({
        'id': 'r1',
        'customer_phone': basraCustomerPhone,
        'created_at': '2026-08-13T09:00:00.000Z',
        'employee_name': basraTechnician,
        'order_ref': '14212',
        'score': 9,
        'note': 'شغل نظيف',
        'source': 'reply_context',
      });
      expect(row.isExactMatch, isTrue);
      expect(row.score, 9);
      expect(row.employeeName, basraTechnician);
      expect(row.customerPhone, isNot(contains(' ')));
    });

    test('ملخص فني بلا ردود لا يختلق معدلاً', () {
      final empty = OilChangeEmployeeRatingSummary.empty(basraTechnician);
      expect(empty.ratingsCount, 0);
      expect(empty.averageScore, isNull);
      expect(empty.hasReplies, isFalse);
    });
  });

  group('مفاتيح فلاتر البطاقة', () {
    test('أعمدة الفلتر تطابق صف service_orders', () {
      expect(OilChangeFilterKind.engine.nameColumnKey, 'engineFilterName');
      expect(OilChangeFilterKind.engine.priceColumnKey, 'engineFilterPriceFils');
      expect(OilChangeFilterKind.air.nameColumnKey, 'airFilterName');
      expect(OilChangeFilterKind.gear.nameColumnKey, 'gearFilterName');
    });

    test('سطر الفلتر يعرض السعر بالدينار من الفلس', () {
      final lines = oilFilterLinesFromRow({
        'engineFilterName': basraEngineFilter,
        'engineFilterPriceFils': basraEngineFilterFils,
        'airFilterName': basraAirFilter,
        'airFilterPriceFils': 0,
      });
      expect(lines, hasLength(2));
      expect(lines.first, contains('فلتر المحرك'));
      expect(lines.first, contains('15,000 د.ع'));
      expect(lines.last, isNot(contains('د.ع')));
    });
  });
}
