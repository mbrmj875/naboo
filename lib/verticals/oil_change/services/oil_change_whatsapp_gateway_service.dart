import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/auth/ensure_fresh_session.dart';
import '../../../services/supabase_config.dart';
import '../../../utils/app_logger.dart';

class WhatsappGatewayQrResult {
  const WhatsappGatewayQrResult({
    required this.ok,
    this.base64,
    this.pairingCode,
    this.alreadyConnected = false,
    this.phone,
    this.messageAr,
    this.errorCode,
  });

  final bool ok;
  final String? base64;
  final String? pairingCode;

  /// الجلسة كانت مفتوحة — لم يُطلب QR ولم تُفصل.
  final bool alreadyConnected;
  final String? phone;
  final String? messageAr;
  final String? errorCode;
}

class WhatsappGatewayStatusResult {
  const WhatsappGatewayStatusResult({
    required this.ok,
    this.status,
    this.connected = false,
    this.phone,
    this.instanceName,
    this.readyState,
    this.messageAr,
  });

  final bool ok;
  final String? status;
  final bool connected;
  final String? phone;
  final String? instanceName;
  final String? readyState;
  final String? messageAr;
}

class WhatsappGatewaySendResult {
  const WhatsappGatewaySendResult({
    required this.ok,
    this.reason = '',
    this.detail = '',
    this.sentTo = '',
  });

  final bool ok;
  final String reason;
  final String detail;
  final String sentTo;
}

/// يستدعي Edge Function `whatsapp-gateway` — مفتاح Evolution على الخادم فقط.
class OilChangeWhatsappGatewayService {
  OilChangeWhatsappGatewayService._();

  static final OilChangeWhatsappGatewayService instance =
      OilChangeWhatsappGatewayService._();

  static const _functionName = 'whatsapp-gateway';

  String instanceNameForUserId(String userId) {
    return 'shop_${userId.replaceAll('-', '_')}';
  }

  Future<bool> provision() async {
    final data = await _invoke({'action': 'provision'});
    return data?['ok'] == true;
  }

  /// اختيار المزود: `evolution` | `whats360` | `dualhook`(=رقم نابو/Meta) | `ycloud` | `cloud_api` | `waha`
  Future<({bool ok, String? messageAr, String? provider})> setProvider(
    String provider,
  ) async {
    final data = await _invoke({
      'action': 'set_provider',
      'provider': provider,
    });
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString(),
      provider: data?['provider']?.toString(),
    );
  }

  /// بدء الربط الرسمي (بدون ذكر اسم المزود للمستخدم).
  Future<({bool ok, String? messageAr, String? onboardingUrl})>
      connectOfficial() async {
    final data = await _invoke({'action': 'connect_official'});
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString(),
      onboardingUrl: data?['onboardingUrl']?.toString() ??
          data?['onboarding_url']?.toString(),
    );
  }

  Future<({bool ok, String? messageAr, String? skipped})> submitFollowupTemplate(
    String bodyTemplateAr,
  ) async {
    final data = await _invoke({
      'action': 'submit_followup_template',
      'body_template': bodyTemplateAr,
    });
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString(),
      skipped: data?['skipped']?.toString(),
    );
  }

  Future<({bool ok, String? messageAr})> completeOfficialConnect({
    String? wabaId,
    String? phoneNumberId,
    String? fromPhone,
    String? connectionId,
    String? oauthCode,
  }) async {
    final data = await _invoke({
      'action': 'complete_official_connect',
      if (wabaId != null) 'waba_id': wabaId,
      if (phoneNumberId != null) 'phone_number_id': phoneNumberId,
      if (fromPhone != null) 'from_phone': fromPhone,
      if (connectionId != null) 'connection_id': connectionId,
      if (oauthCode != null && oauthCode.trim().isNotEmpty)
        'oauth_code': oauthCode.trim(),
    });
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString(),
    );
  }

  Future<WhatsappGatewayStatusResult> fetchReadyStatus() async {
    final data = await _invoke({'action': 'ready_status'});
    if (data == null) {
      return const WhatsappGatewayStatusResult(ok: false);
    }
    return WhatsappGatewayStatusResult(
      ok: data['ok'] == true,
      status: data['status']?.toString(),
      connected: data['connected'] == true,
      phone: data['phone']?.toString(),
      readyState: data['ready_state']?.toString(),
      messageAr: data['message_ar']?.toString(),
    );
  }

  Future<({bool ok, String? messageAr})> dismissFailedMessage({
    required String logId,
  }) async {
    final data = await _invoke({
      'action': 'dismiss_failed_message',
      'log_id': logId.trim(),
    });
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString(),
    );
  }

  Future<WhatsappGatewaySendResult> sendOilChangeCard({
    required String customerPhone,
    required String customerName,
    required String shopName,
    required String detailsBlock,
    Map<String, String> templateParams = const {},
    int? orderId,
    String employeeName = '',
    bool resend = false,
    String? attemptId,
    String? originalLogId,
  }) async {
    final data = await _invoke({
      'action': 'send_oil_change_card',
      'customer_phone': customerPhone,
      'customer_name': customerName,
      'shop_name': shopName,
      'details_block': detailsBlock,
      if (templateParams.isNotEmpty) 'template_params': templateParams,
      if (orderId != null && orderId > 0) 'order_id': orderId,
      if (employeeName.trim().isNotEmpty) 'employee_name': employeeName.trim(),
      if (resend) 'resend': true,
      if (attemptId != null && attemptId.trim().isNotEmpty)
        'attempt_id': attemptId.trim(),
      if (originalLogId != null && originalLogId.trim().isNotEmpty)
        'original_log_id': originalLogId.trim(),
    });
    if (data == null) {
      return const WhatsappGatewaySendResult(
        ok: false,
        reason: 'gateway_unreachable',
        detail: 'invoke_null',
      );
    }
    return WhatsappGatewaySendResult(
      ok: data['ok'] == true,
      reason: (data['reason'] ?? data['error'] ?? data['detail'] ?? '')
          .toString(),
      detail: (data['detail'] ?? data['message_ar'] ?? '').toString(),
      sentTo: customerPhone,
    );
  }

  /// حفظ توكن ومعرّف جهاز واتس360 (لا يُعاد التوكن للتطبيق بعد الحفظ).
  Future<({bool ok, String? messageAr})> configureWhats360({
    required String token,
    required String instanceId,
  }) async {
    final data = await _invoke({
      'action': 'configure_whats360',
      'whats360_token': token.trim(),
      'whats360_instance_id': instanceId.trim(),
    });
    return (
      ok: data?['ok'] == true,
      messageAr: data?['message_ar']?.toString() ?? data?['error']?.toString(),
    );
  }

  Future<WhatsappGatewayQrResult> fetchQr({bool forceReset = false}) async {
    final data = await _invoke({
      'action': 'qr',
      if (forceReset) 'force_reset': true,
    });
    if (data == null) {
      return const WhatsappGatewayQrResult(
        ok: false,
        messageAr:
            'تعذّر الاتصال بخدمة QR. تحقق من الإنترنت أو جرّب الربط الرسمي.',
        errorCode: 'invoke_null',
      );
    }
    final rawPairing = data['pairing_code']?.toString().trim();
    final pairing = _sanitizePairingCode(rawPairing);
    final messageAr = data['message_ar']?.toString();
    final ok = data['ok'] == true;
    final base64 = data['base64']?.toString();
    return WhatsappGatewayQrResult(
      ok: ok,
      base64: base64,
      pairingCode: pairing,
      alreadyConnected: data['already_connected'] == true ||
          data['connected'] == true,
      phone: data['phone']?.toString(),
      messageAr: (messageAr ?? '').trim().isNotEmpty
          ? messageAr
          : (ok && (base64 ?? '').isNotEmpty)
              ? null
              : 'تعذّر جلب رمز QR من السيرفر. أعد المحاولة أو اختر الربط الرسمي.',
      errorCode: data['error']?.toString(),
    );
  }

  /// رموز الإقران قصيرة فقط — نص `2@…` حمولة QR وليس للعرض.
  static String? _sanitizePairingCode(String? raw) {
    final t = (raw ?? '').trim();
    if (t.length < 4 || t.length > 16) return null;
    if (t.contains('@') || t.contains(',')) return null;
    return t;
  }

  Future<WhatsappGatewayStatusResult> checkStatus() async {
    final data = await _invoke({'action': 'status'});
    if (data == null) {
      return const WhatsappGatewayStatusResult(ok: false);
    }
    return WhatsappGatewayStatusResult(
      ok: data['ok'] == true,
      status: data['status']?.toString(),
      connected: data['connected'] == true,
      phone: data['phone']?.toString(),
      instanceName: data['instance_name']?.toString(),
      readyState: data['ready_state']?.toString(),
      messageAr: data['message_ar']?.toString(),
    );
  }

  /// إرسال نص عبر Edge Function → Evolution (نفس قناة QR التي تعمل من الجوال).
  /// [employeeName] يُسجَّل مع الرسالة ليُسنَد تقييم العميل للفني لاحقاً.
  /// [attemptId] يمنع التكرار عند انقطاع الرد بعد قبول المزود.
  Future<WhatsappGatewaySendResult> sendText({
    required String customerPhone,
    required String messageText,
    int? orderId,
    String employeeName = '',
    bool resend = false,
    String? attemptId,
    String? originalLogId,
  }) async {
    final data = await _invoke({
      'action': 'send_text',
      'customer_phone': customerPhone,
      'message_text': messageText,
      if (orderId != null && orderId > 0) 'order_id': orderId,
      if (employeeName.trim().isNotEmpty) 'employee_name': employeeName.trim(),
      if (resend) 'resend': true,
      if (attemptId != null && attemptId.trim().isNotEmpty)
        'attempt_id': attemptId.trim(),
      if (originalLogId != null && originalLogId.trim().isNotEmpty)
        'original_log_id': originalLogId.trim(),
    });
    if (data == null) {
      return const WhatsappGatewaySendResult(
        ok: false,
        reason: 'gateway_unreachable',
        detail: 'invoke_null',
      );
    }
    return WhatsappGatewaySendResult(
      ok: data['ok'] == true,
      reason: (data['reason'] ?? data['error'] ?? data['detail'] ?? '')
          .toString(),
      detail: (data['detail'] ?? '').toString(),
      sentTo: (data['sent_to'] ?? '').toString(),
    );
  }

  /// بلاغ انقطاع من العميل — السيرفر يتحقق حياً (false_alarm إن الجلسة open).
  Future<WhatsappReportDisconnectedResult> reportDisconnected() async {
    final data = await _invoke({'action': 'report_disconnected'});
    if (data == null) {
      return const WhatsappReportDisconnectedResult(ok: false);
    }
    return WhatsappReportDisconnectedResult.fromJson(data);
  }

  /// يفصل جلسة واتساب المحل ويحدّث حالة الحساب على السحابة.
  /// إن كان نشر Edge Function قديماً بلا `disconnect`، نرجع إلى
  /// `report_disconnected` — ولا نعتبر النجاح إلا إذا تأكد الانقطاع حياً.
  Future<WhatsappDisconnectResult> disconnect() async {
    final data = await _invoke({'action': 'disconnect'});
    if (data?['ok'] == true) {
      return WhatsappDisconnectResult(
        ok: true,
        evolutionLoggedOut: data?['evolution_ok'] == true,
        usedStatusFallback: false,
      );
    }

    final reported = await reportDisconnected();
    return WhatsappDisconnectResult(
      ok: reported.confirmedNotOpen,
      evolutionLoggedOut: false,
      usedStatusFallback: true,
    );
  }

  static const _invokeTimeout = Duration(seconds: 55);

  Future<Map<String, dynamic>?> _invoke(Map<String, dynamic> body) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      return {
        'ok': false,
        'reason': 'unauthorized',
        'detail': 'no_session',
        'message_ar': 'سجّل الدخول للحساب السحابي ثم أعد المحاولة.',
      };
    }
    try {
      await ensureFreshSession();
    } on SessionRefreshTransientException catch (e) {
      return {
        'ok': false,
        'reason': 'temporary',
        'detail': 'session_refresh_deferred',
        'message_ar': e.message,
      };
    } on SessionExpiredException catch (e) {
      return {
        'ok': false,
        'reason': 'unauthorized',
        'detail': 'session_expired',
        'message_ar': e.message,
      };
    } catch (e) {
      AppLogger.warn('oil_change_wa_gateway', 'ensureFreshSession: $e');
    }

    try {
      final response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: body,
          )
          .timeout(_invokeTimeout);
      final parsed = _asStringKeyedMap(response.data);
      if (parsed != null) return parsed;
      if (kIsWeb) {
        return await _invokeViaHttp(body);
      }
      return {
        'ok': false,
        'reason': 'gateway_unreachable',
        'detail': 'empty_response',
      };
    } on FunctionException catch (e) {
      AppLogger.warn(
        'oil_change_wa_gateway',
        'function ${body['action']} failed status=${e.status}: ${e.details}',
      );
      final fromDetails = _asStringKeyedMap(e.details);
      if (fromDetails != null) return fromDetails;
      if (kIsWeb) {
        final viaHttp = await _invokeViaHttp(body);
        if (viaHttp != null) return viaHttp;
      }
      return {
        'ok': false,
        'reason': 'gateway_unreachable',
        'detail': 'function_${e.status}',
        'message_ar': 'تعذّر الاتصال بخدمة واتساب. أعد المحاولة.',
      };
    } on TimeoutException {
      AppLogger.warn(
        'oil_change_wa_gateway',
        'function ${body['action']} client timeout',
      );
      if (kIsWeb) {
        final viaHttp = await _invokeViaHttp(body);
        if (viaHttp != null) return viaHttp;
      }
      return {
        'ok': false,
        'reason': 'timeout',
        'detail': 'client_timeout',
        'message_ar': 'انتهت مهلة الاتصال بخدمة واتساب.',
      };
    } catch (e, st) {
      AppLogger.error(
        'oil_change_wa_gateway',
        'function ${body['action']} error',
        e,
        st,
      );
      if (kIsWeb) {
        final viaHttp = await _invokeViaHttp(body);
        if (viaHttp != null) return viaHttp;
      }
      return {
        'ok': false,
        'reason': 'gateway_unreachable',
        'detail': e.toString(),
        'message_ar': 'تعذّر الاتصال بخدمة واتساب. أعد المحاولة.',
      };
    }
  }

  /// احتياطي للويب عندما يرمي `functions.invoke` خطأ بلا جسم JSON قابل للقراءة.
  Future<Map<String, dynamic>?> _invokeViaHttp(Map<String, dynamic> body) async {
    final base = SupabaseConfig.url.trim();
    final anon = SupabaseConfig.anonKey.trim();
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken.trim() ?? '';
    if (base.isEmpty || anon.isEmpty || token.isEmpty) return null;
    try {
      final uri = Uri.parse('$base/functions/v1/$_functionName');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'apikey': anon,
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_invokeTimeout);
      final parsed = _asStringKeyedMap(response.body);
      if (parsed != null) return parsed;
      try {
        final decoded = jsonDecode(response.body);
        return _asStringKeyedMap(decoded);
      } catch (_) {
        return {
          'ok': false,
          'reason': 'gateway_unreachable',
          'detail': 'http_${response.statusCode}',
        };
      }
    } catch (e) {
      AppLogger.warn('oil_change_wa_gateway', 'http fallback failed: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _asStringKeyedMap(Object? raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      try {
        final decoded = jsonDecode(t);
        return _asStringKeyedMap(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class WhatsappDisconnectResult {
  const WhatsappDisconnectResult({
    required this.ok,
    required this.evolutionLoggedOut,
    required this.usedStatusFallback,
  });

  final bool ok;
  final bool evolutionLoggedOut;
  final bool usedStatusFallback;
}

/// نتيجة `report_disconnected` بعد التحقق الحي على السيرفر.
class WhatsappReportDisconnectedResult {
  const WhatsappReportDisconnectedResult({
    required this.ok,
    this.falseAlarm = false,
    this.confirmed = false,
    this.connected = false,
    this.statusUnchanged = false,
    this.status,
  });

  final bool ok;
  final bool falseAlarm;
  final bool confirmed;
  final bool connected;
  final bool statusUnchanged;
  final String? status;

  /// الجلسة ما زالت مفتوحة — صحّح المحلي ولا تعرض بانر انقطاع.
  bool get shouldTreatAsConnected =>
      ok && (falseAlarm || connected);

  /// تأكد حياً أن الجلسة ليست open.
  bool get confirmedNotOpen => ok && confirmed && !connected;

  factory WhatsappReportDisconnectedResult.fromJson(Map<String, dynamic> data) {
    final connected = data['connected'] == true;
    final falseAlarm = data['false_alarm'] == true;
    return WhatsappReportDisconnectedResult(
      ok: data['ok'] == true,
      falseAlarm: falseAlarm,
      confirmed: data['confirmed'] == true,
      connected: connected || falseAlarm,
      statusUnchanged: data['status_unchanged'] == true,
      status: data['status']?.toString(),
    );
  }
}
