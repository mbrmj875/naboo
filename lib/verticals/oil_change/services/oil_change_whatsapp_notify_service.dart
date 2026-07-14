import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../services/tenant_context.dart';
import '../../../utils/app_logger.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/oil_change_auto_whatsapp_message.dart';
import '../utils/oil_change_webhook_order_payload.dart';
import '../utils/oil_change_whatsapp_notify_classifier.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_status_store.dart';

/// يرسل إشعار واتساب تلقائي بعد حفظ بطاقة غيار الزيت عبر Workflow n8n.
class OilChangeWhatsappNotifyService {
  OilChangeWhatsappNotifyService._();

  static final OilChangeWhatsappNotifyService instance =
      OilChangeWhatsappNotifyService._();

  Future<OilChangeWhatsappNotifyOutcome> notifyAfterOilChangeSave({
    required String customerPhone,
    required Map<String, dynamic> order,
    required String storeTitle,
    required String storeFooter,
    int? orderId,
    int? invoiceId,
  }) {
    return sendCustomMessage(
      customerPhone: customerPhone,
      messageText: buildOilChangeAutoWhatsAppMessage(
        order: order,
        storeTitle: storeTitle,
        storeFooter: storeFooter,
      ),
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      storeTitle: storeTitle,
    );
  }

  /// رسالة حملة جماعية — نفس مسار n8n/Evolution مع نص مخصّص.
  Future<OilChangeWhatsappNotifyOutcome> sendCustomMessage({
    required String customerPhone,
    required String messageText,
    Map<String, dynamic>? order,
    int? orderId,
    int? invoiceId,
    String storeTitle = '',
  }) async {
    final phone = customerPhone.trim();
    if (phone.isEmpty) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.invalidPhone,
      );
    }

    final text = messageText.trim();
    if (text.isEmpty) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.unknown,
      );
    }

    if (!OilChangeWhatsappConfig.isAutoNotifyEnabled) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.skippedNotConfigured,
      );
    }

    if (!await deviceHasNetworkForWhatsappNotify()) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.noInternet,
      );
    }

    final tenantId = TenantContext.instance.tenantId?.trim();
    final instanceName =
        await OilChangeWhatsappGatewayRepository.instance.resolveInstanceName();
    final orderMap = order ?? const <String, dynamic>{};
    final body = <String, dynamic>{
      'webhook_secret': OilChangeWhatsappConfig.webhookSecret,
      'customer_phone': phone,
      if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
      'instance_name': instanceName,
      if (orderId != null && orderId > 0) 'order_id': orderId,
      if (invoiceId != null && invoiceId > 0) 'invoice_id': invoiceId,
      if (orderMap.isNotEmpty)
        'order': buildOilChangeWebhookOrderPayload(
          order: orderMap,
          storeTitle: storeTitle,
        ),
      'message_text': text,
      'campaign': true,
    };

    try {
      final response = await http
          .post(
            Uri.parse(OilChangeWhatsappConfig.webhookUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(OilChangeWhatsappConfig.requestTimeout);

      final outcome = classifyWhatsappWebhookResponse(
        statusCode: response.statusCode,
        body: response.body,
      );

      await _persistGatewayStatus(outcome);

      if (outcome.isSent) {
        AppLogger.info(
          'oil_change_wa',
          'campaign send ok status=${response.statusCode}',
        );
      } else {
        AppLogger.warn(
          'oil_change_wa',
          'campaign send failed reason=${outcome.reason.name}',
        );
      }

      return outcome;
    } catch (e, st) {
      AppLogger.error('oil_change_wa', 'campaign send failed', e, st);
      final outcome = classifyWhatsappNotifyException(e);
      await _persistGatewayStatus(outcome);
      return outcome;
    }
  }

  Future<void> _persistGatewayStatus(OilChangeWhatsappNotifyOutcome outcome) async {
    if (outcome.marksGatewayConnected) {
      await OilChangeWhatsappStatusStore.instance.markConnected();
      return;
    }
    if (outcome.marksGatewayDisconnected) {
      await OilChangeWhatsappStatusStore.instance.markDisconnected();
    }
  }
}
