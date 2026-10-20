import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../models/print_settings_data.dart';
import '../../../services/tenant_context.dart';
import '../../../utils/app_logger.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/oil_change_auto_whatsapp_message.dart';
import '../utils/oil_change_webhook_order_payload.dart';
import '../utils/oil_change_whatsapp_notify_classifier.dart';
import '../services/oil_change_whatsapp_card_pdf.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_outbox.dart';
import '../services/oil_change_whatsapp_status_store.dart';

/// يرسل إشعار واتساب تلقائي بعد حفظ بطاقة غيار الزيت.
/// يفضّل بوابة whatsapp-gateway (واتس360 / WAHA / …) ثم n8n احتياطاً.
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
    bool includeRatingAsk = true,
    String productsSummary = '',
    PrintSettingsData? printSettings,
    /// تصحيح رقم على نفس البطاقة — يجب تجاوز مانع التكرار حسب orderId.
    bool phoneCorrectionResend = false,
  }) async {
    final templateParams = buildOilChangeCardTemplateParams(
      order: order,
      storeTitle: storeTitle,
      productsSummary: productsSummary,
    );
    final details = buildOilChangeCardDetailsBlock(
      order: order,
      storeFooter: storeFooter,
    );
    final freeText = buildOilChangeAutoWhatsAppMessage(
      order: order,
      storeTitle: storeTitle,
      storeFooter: storeFooter,
      includeRatingAsk: includeRatingAsk,
    );
    final customerName =
        (order['customerNameSnapshot'] ?? '').toString().trim().isEmpty
            ? 'عميلنا الكريم'
            : (order['customerNameSnapshot'] ?? '').toString().trim();
    final technician = (order['technicianName'] ?? '').toString().trim();

    final outcome = await _sendOilChangeCard(
      customerPhone: customerPhone,
      customerName: customerName,
      storeTitle: storeTitle,
      details: details,
      freeText: freeText,
      templateParams: templateParams,
      technician: technician,
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      printSettings: printSettings,
      phoneCorrectionResend: phoneCorrectionResend,
    );

    // Outbox محلي فقط إن لم تصل المحاولة للخادم — وإلا السجل السحابي يكفي.
    if (!outcome.isSent &&
        !outcome.skipLocalOutbox &&
        outcome.reason != OilChangeWhatsappNotifyReason.invalidPhone) {
      await OilChangeWhatsappOutbox.instance.enqueueFailure(
        customerPhone: customerPhone,
        customerName: customerName,
        shopName: storeTitle,
        detailsBlock: details,
        messageText: freeText,
        templateParams: templateParams,
        reason: outcome.reason,
        orderId: orderId ?? 0,
        employeeName: technician,
      );
    }

    return outcome;
  }

  Future<OilChangeWhatsappNotifyOutcome> _sendOilChangeCard({
    required String customerPhone,
    required String customerName,
    required String storeTitle,
    required String details,
    required String freeText,
    required Map<String, String> templateParams,
    required String technician,
    required Map<String, dynamic> order,
    int? orderId,
    int? invoiceId,
    PrintSettingsData? printSettings,
    bool phoneCorrectionResend = false,
  }) async {
    // المسار الرسمي: قالب عبر NotificationDispatcher.
    // القالب ضروري للعميل الذي لم يراسلنا خلال 24 ساعة — النص الحر يُرفض حينها.
    if (Supabase.instance.client.auth.currentUser != null) {
      final gate = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      if (gate?.isOfficialTransport == true) {
        // تصحيح الهاتف على نفس orderId: بدون resend تُرجع البوابة idempotent_hit
        // وتظن أن الرسالة وصلت بينما الرقم الجديد لم يستلم شيئاً.
        final attemptId =
            phoneCorrectionResend ? const Uuid().v4() : null;
        if (phoneCorrectionResend) {
          AppLogger.info(
            'oil_change_wa',
            'phone correction → Meta oil_change_card resend '
                'orderId=$orderId attempt=$attemptId',
          );
        }
        final sent =
            await OilChangeWhatsappGatewayService.instance.sendOilChangeCard(
          customerPhone: customerPhone,
          customerName: customerName,
          shopName: storeTitle,
          detailsBlock: details,
          templateParams: templateParams,
          orderId: orderId,
          employeeName: technician,
          resend: phoneCorrectionResend,
          attemptId: attemptId,
        );
        final viaGateway = _mapGatewaySend(sent);
        if (viaGateway != null) {
          await _persistGatewayStatus(viaGateway);
          if (viaGateway.isSent) {
            AppLogger.info(
              'oil_change_wa',
              phoneCorrectionResend
                  ? 'official card phone-correction send ok'
                  : 'official card send ok',
            );
            final settings = printSettings;
            if (settings != null) {
              unawaited(
                OilChangeWhatsappCardPdfService.instance.prepareAfterOfficialCard(
                  customerPhone: customerPhone,
                  order: order,
                  printSettings: settings,
                  templateParams: templateParams,
                  orderId: orderId,
                ),
              );
            }
            return viaGateway;
          }
          // إعداد ناقص قبل الإرسال فقط → يُسمح بالمسار الاحتياطي (نص/n8n).
          if (viaGateway.reason ==
              OilChangeWhatsappNotifyReason.skippedNotConfigured) {
            AppLogger.warn(
              'oil_change_wa',
              'official not configured — fallback to custom/n8n',
            );
          } else {
            // أي فشل بعد بدء المسار الرسمي: لا إرسال ثانٍ (قالب+نص) ولا Outbox مزدوج.
            AppLogger.warn(
              'oil_change_wa',
              'official card send failed — no secondary send '
                  'reason=${viaGateway.reason.name}',
            );
            return OilChangeWhatsappNotifyOutcome(
              reason: viaGateway.reason,
              httpStatus: viaGateway.httpStatus,
              skipLocalOutbox: viaGateway.reason !=
                      OilChangeWhatsappNotifyReason.noInternet,
            );
          }
        }
      }
    }

    return sendCustomMessage(
      customerPhone: customerPhone,
      messageText: freeText,
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      storeTitle: storeTitle,
      employeeName: technician,
    );
  }

  /// رسالة حملة جماعية أو إشعار بعد الحفظ.
  Future<OilChangeWhatsappNotifyOutcome> sendCustomMessage({
    required String customerPhone,
    required String messageText,
    Map<String, dynamic>? order,
    int? orderId,
    int? invoiceId,
    String storeTitle = '',
    String employeeName = '',
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

    if (!await deviceHasNetworkForWhatsappNotify()) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.noInternet,
      );
    }

    // المسار الأساسي: Edge whatsapp-gateway (يدعم whats360 وغيره).
    if (Supabase.instance.client.auth.currentUser != null) {
      final gateway = await OilChangeWhatsappGatewayService.instance.sendText(
        customerPhone: phone,
        messageText: text,
        orderId: orderId,
        employeeName: employeeName,
      );
      final viaGateway = _mapGatewaySend(gateway);
      if (viaGateway != null) {
        await _persistGatewayStatus(viaGateway);
        if (viaGateway.isSent) {
          AppLogger.info('oil_change_wa', 'gateway send ok');
        } else {
          AppLogger.warn(
            'oil_change_wa',
            'gateway send failed reason=${viaGateway.reason.name} '
                'detail=${gateway.detail}',
          );
        }
        // رصيد المحفظة: لا نكمل إلى n8n أبداً.
        if (viaGateway.reason ==
            OilChangeWhatsappNotifyReason.insufficientWallet) {
          return viaGateway;
        }
        // إن فشل بسبب إعداد ناقص فقط نكمل لـ n8n؛ غير ذلك نعيد نتيجة البوابة.
        final tryN8nFallback = viaGateway.reason ==
                OilChangeWhatsappNotifyReason.skippedNotConfigured ||
            gateway.reason == 'whats360_not_ready' ||
            gateway.reason == 'cloud_not_ready';
        if (!tryN8nFallback || viaGateway.isSent) {
          return viaGateway;
        }
      }
    }

    if (!OilChangeWhatsappConfig.isAutoNotifyEnabled) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.skippedNotConfigured,
      );
    }

    // متصفح الويب يحظر استدعاء n8n مباشرة (CORS) — المسار الوحيد هو البوابة.
    if (kIsWeb) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.timeout,
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
          'n8n send ok status=${response.statusCode}',
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
      return outcome;
    }
  }

  OilChangeWhatsappNotifyOutcome? _mapGatewaySend(
    WhatsappGatewaySendResult gateway,
  ) {
    if (gateway.ok) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.sent,
      );
    }
    final r = gateway.reason.toLowerCase();
    final d = gateway.detail.toLowerCase();
    if (r.contains('insufficient_balance') ||
        r.contains('wallet_frozen') ||
        r.contains('send_blocked') ||
        r == 'wallet' ||
        d.contains('insufficient') ||
        d.contains('wallet_frozen') ||
        d.contains('send_blocked') ||
        gateway.detail.contains('رصيد') ||
        gateway.detail.contains('محفظة')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.insufficientWallet,
      );
    }
    if (r.contains('invalid_phone')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.invalidPhone,
      );
    }
    if (r.contains('disconnect') ||
        r.contains('whatsapp_disconnected') ||
        d.contains('not_open')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.whatsappDisconnected,
      );
    }
    if (r.contains('rate') || r == 'rate_limited') {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.rateLimited,
      );
    }
    if (r.contains('unauthorized')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.unauthorized,
      );
    }
    if (r.contains('timeout') || d.contains('client_timeout')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.timeout,
      );
    }
    if (r.contains('gateway_unreachable') ||
        d.contains('invoke_null') ||
        d.contains('empty_response') ||
        d.startsWith('function_') ||
        d.startsWith('http_')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.timeout,
      );
    }
    if (r.contains('whats360') ||
        r.contains('waha') ||
        r.contains('evolution') ||
        r.contains('cloud_send')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.evolutionError,
      );
    }
    if (r.contains('not_ready') ||
        d.contains('not_ready') ||
        r.contains('missing') ||
        d.contains('missing_from')) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.skippedNotConfigured,
      );
    }
    return const OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.unknown,
    );
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
