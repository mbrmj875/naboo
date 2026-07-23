import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../models/print_settings_data.dart';
import '../../../services/tenant_context.dart';
import '../../../utils/app_logger.dart';
import '../models/oil_change_wa_notify_status.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/oil_change_auto_whatsapp_message.dart';
import '../utils/oil_change_webhook_order_payload.dart';
import '../utils/oil_change_whatsapp_notify_classifier.dart';
import '../services/oil_change_orders_repository.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_status_store.dart';

/// يرسل إشعار واتساب تلقائي بعد حفظ بطاقة غيار الزيت عبر Workflow n8n.
class OilChangeWhatsappNotifyService {
  OilChangeWhatsappNotifyService._();

  static final OilChangeWhatsappNotifyService instance =
      OilChangeWhatsappNotifyService._();

  Future<OilChangeWhatsappNotifyOutcome> notifyAfterOilChangeSave({
    required String customerPhone,
    required Map<String, dynamic> order,
    required PrintSettingsData printSettings,
    int? orderId,
    int? invoiceId,
  }) async {
    // نص فقط: مرفق PDF كان يسبب Evolution 400 + بطء/انقطاع على شبكات الجوال،
    // وn8n الحالي يتجاهل pdf_base64 أصلاً.
    return sendCustomMessage(
      customerPhone: customerPhone,
      messageText: buildOilChangeAutoWhatsAppMessage(
        order: order,
        storeTitle: printSettings.whatsappStoreTitle,
        storeFooter: printSettings.whatsappStoreFooter,
      ),
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      storeTitle: printSettings.whatsappStoreTitle,
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
    String? pdfBase64,
    String pdfFilename = 'oil_change_service.pdf',
  }) async {
    final phone = customerPhone.trim();
    if (phone.isEmpty) {
      final outcome = const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.invalidPhone,
      );
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }

    final text = messageText.trim();
    if (text.isEmpty) {
      final outcome = const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.unknown,
      );
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }

    if (!OilChangeWhatsappConfig.isAutoNotifyEnabled) {
      final outcome = const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.skippedNotConfigured,
      );
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }

    if (!await deviceHasNetworkForWhatsappNotify()) {
      final outcome = const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.noInternet,
      );
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }

    // إرسال لرقم المحل نفسه: Evolution يقبل الطلب والتطبيق يظهر «تم» دون رسالة واردة.
    final shopPhone = await _resolveShopWhatsappDigits();
    final customerDigits = _normalizeWaDigits(phone);
    if (shopPhone.isNotEmpty &&
        customerDigits.isNotEmpty &&
        shopPhone == customerDigits) {
      AppLogger.warn(
        'oil_change_wa',
        'blocked send: customer phone equals shop whatsapp phone',
      );
      final outcome = const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.sameAsShopPhone,
      );
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }

    // المسار الأساسي: Supabase Edge (نفس قناة ربط QR التي تعمل من الجوال).
    // n8n المباشر يفشل غالباً على شبكات الجوال (:5678 أو DNS محظور).
    try {
      AppLogger.info('oil_change_wa', 'gateway send_text start');
      final gw = await OilChangeWhatsappGatewayService.instance
          .sendText(
        customerPhone: phone,
        messageText: text,
        orderId: orderId,
      )
          .timeout(OilChangeWhatsappConfig.requestTimeout);
      if (gw.ok) {
        final outcome = const OilChangeWhatsappNotifyOutcome(
          reason: OilChangeWhatsappNotifyReason.sent,
        );
        await _persistGatewayStatus(outcome);
        await _persistOrderWaStatus(orderId, outcome);
        AppLogger.info(
          'oil_change_wa',
          'gateway send ok sent_to=${gw.sentTo}',
        );
        return outcome;
      }
      final mapped = classifyWhatsappWebhookResponse(
        statusCode: 200,
        body: jsonEncode({
          'ok': false,
          'reason': gw.reason,
          'detail': gw.detail,
        }),
      );
      // إن كانت الجلسة منفصلة أو رقم غير صالح — لا نفع من n8n.
      if (mapped.reason == OilChangeWhatsappNotifyReason.whatsappDisconnected ||
          mapped.reason == OilChangeWhatsappNotifyReason.invalidPhone ||
          mapped.reason == OilChangeWhatsappNotifyReason.sameAsShopPhone ||
          mapped.reason == OilChangeWhatsappNotifyReason.unauthorized) {
        await _persistGatewayStatus(mapped);
        await _persistOrderWaStatus(orderId, mapped);
        return mapped;
      }
      AppLogger.warn(
        'oil_change_wa',
        'gateway send failed reason=${gw.reason}; trying n8n fallback',
      );
    } catch (e, st) {
      AppLogger.error(
        'oil_change_wa',
        'gateway send failed; trying n8n fallback',
        e,
        st,
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
      // لا نرفق PDF — كان يسبب 400/بطء؛ النص كافٍ للتسليم.
    };

    try {
      AppLogger.info('oil_change_wa', 'n8n webhook fallback post');
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
      await _persistOrderWaStatus(orderId, outcome);

      if (outcome.isSent) {
        AppLogger.info(
          'oil_change_wa',
          'n8n send ok status=${response.statusCode} body=${response.body}',
        );
      } else {
        AppLogger.warn(
          'oil_change_wa',
          'n8n send failed reason=${outcome.reason.name}',
        );
      }

      return outcome;
    } catch (e, st) {
      AppLogger.error('oil_change_wa', 'n8n send failed', e, st);
      final outcome = classifyWhatsappNotifyException(e);
      await _persistGatewayStatus(outcome);
      await _persistOrderWaStatus(orderId, outcome);
      return outcome;
    }
  }

  Future<void> _persistOrderWaStatus(
    int? orderId,
    OilChangeWhatsappNotifyOutcome outcome,
  ) async {
    if (orderId == null || orderId <= 0) return;
    try {
      await OilChangeOrdersRepository.instance.setWaNotifyStatus(
        orderId: orderId,
        status: waNotifyStatusFromOutcome(outcome),
        lastError: waNotifyErrorFromOutcome(outcome),
      );
    } catch (e, st) {
      AppLogger.error('oil_change_wa', 'persist waNotifyStatus failed', e, st);
    }
  }

  /// يسلّم حملة كاملة للسيرفر (n8n) — الإرسال يكمل بعد إغلاق التطبيق.
  Future<OilChangeWhatsappNotifyOutcome> submitCampaignBatch({
    required List<Map<String, dynamic>> messages,
    required int intervalSeconds,
    required int restEveryMessages,
    required int restMinutes,
    String storeTitle = '',
  }) async {
    if (messages.isEmpty) {
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
    final body = <String, dynamic>{
      'webhook_secret': OilChangeWhatsappConfig.webhookSecret,
      'campaign_batch': true,
      'instance_name': instanceName,
      if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
      'store_title': storeTitle,
      'interval_seconds': intervalSeconds,
      'rest_every_messages': restEveryMessages,
      'rest_minutes': restMinutes,
      'messages': messages,
    };

    try {
      final url = OilChangeWhatsappConfig.resolvedCampaignWebhookUrl;
      AppLogger.info(
        'oil_change_wa_campaign',
        'batch submit count=${messages.length} url=$url',
      );
      final response = await http
          .post(
            Uri.parse(url),
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
          'oil_change_wa_campaign',
          'batch accepted status=${response.statusCode} body=${response.body}',
        );
      } else {
        AppLogger.warn(
          'oil_change_wa_campaign',
          'batch rejected reason=${outcome.reason.name} body=${response.body}',
        );
      }
      return outcome;
    } catch (e, st) {
      AppLogger.error('oil_change_wa_campaign', 'batch submit failed', e, st);
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

  static String _normalizeWaDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (!d.startsWith('964')) {
      if (d.startsWith('0')) {
        d = '964${d.substring(1)}';
      } else if (d.length == 10 && d.startsWith('7')) {
        d = '964$d';
      }
    }
    return d;
  }

  Future<String> _resolveShopWhatsappDigits() async {
    try {
      final row = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      final fromRow = _normalizeWaDigits(row?.whatsappPhone ?? '');
      if (fromRow.isNotEmpty) return fromRow;
      final live =
          await OilChangeWhatsappGatewayService.instance.checkStatus();
      return _normalizeWaDigits(live.phone ?? '');
    } catch (_) {
      return '';
    }
  }
}
