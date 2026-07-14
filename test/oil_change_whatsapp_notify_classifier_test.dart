import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_whatsapp_notify_outcome.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_whatsapp_notify_classifier.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_whatsapp_user_messages.dart';

void main() {
  group('classifyWhatsappWebhookResponse', () {
    test('ok true → sent', () {
      final outcome = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: '{"ok":true}',
      );
      expect(outcome.reason, OilChangeWhatsappNotifyReason.sent);
    });

    test('whatsapp_disconnected reason', () {
      final outcome = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: '{"ok":false,"reason":"whatsapp_disconnected"}',
      );
      expect(outcome.reason, OilChangeWhatsappNotifyReason.whatsappDisconnected);
      expect(outcome.marksGatewayDisconnected, isTrue);
    });

    test('429 → rateLimited', () {
      final outcome = classifyWhatsappWebhookResponse(
        statusCode: 429,
        body: '',
      );
      expect(outcome.reason, OilChangeWhatsappNotifyReason.rateLimited);
    });
  });

  test('broken n8n expression → serverError', () {
    final outcome = classifyWhatsappWebhookResponse(
      statusCode: 200,
      body: r'{"ok":"={{ $json.ok }}","reason":"={{ $json.reason }}","sent_to":""}',
    );
    expect(outcome.reason, OilChangeWhatsappNotifyReason.serverError);
  });

  test('user messages are Arabic for disconnect', () {
    const outcome = OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.whatsappDisconnected,
    );
    final msg = OilChangeWhatsappUserMessages.snackbarForOutcome(outcome);
    expect(msg.contains('غير متصل'), isTrue);
    expect(msg.contains('QR'), isTrue);
  });
}
