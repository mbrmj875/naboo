import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final bool ok;
  final String? status;
  final bool connected;
  final String? phone;
  final String? instanceName;
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

  Future<WhatsappGatewayQrResult> fetchQr({bool forceReset = false}) async {
    final data = await _invoke({
      'action': 'qr',
      if (forceReset) 'force_reset': true,
    });
    if (data == null) {
      return const WhatsappGatewayQrResult(ok: false);
    }
    final rawPairing = data['pairing_code']?.toString().trim();
    final pairing = _sanitizePairingCode(rawPairing);
    return WhatsappGatewayQrResult(
      ok: data['ok'] == true,
      base64: data['base64']?.toString(),
      pairingCode: pairing,
      alreadyConnected: data['already_connected'] == true ||
          data['connected'] == true,
      phone: data['phone']?.toString(),
      messageAr: data['message_ar']?.toString(),
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
    );
  }

  /// إرسال نص عبر Edge Function → Evolution (نفس قناة QR التي تعمل من الجوال).
  Future<WhatsappGatewaySendResult> sendText({
    required String customerPhone,
    required String messageText,
    int? orderId,
  }) async {
    final data = await _invoke({
      'action': 'send_text',
      'customer_phone': customerPhone,
      'message_text': messageText,
      if (orderId != null && orderId > 0) 'order_id': orderId,
    });
    if (data == null) {
      return const WhatsappGatewaySendResult(
        ok: false,
        reason: 'timeout',
      );
    }
    return WhatsappGatewaySendResult(
      ok: data['ok'] == true,
      reason: (data['reason'] ?? data['error'] ?? '').toString(),
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

  Future<Map<String, dynamic>?> _invoke(Map<String, dynamic> body) async {
    if (Supabase.instance.client.auth.currentUser == null) return null;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        _functionName,
        body: body,
      );
      final raw = response.data;
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return null;
    } on FunctionException catch (e) {
      AppLogger.warn(
        'oil_change_wa_gateway',
        'function ${body['action']} failed: ${e.details}',
      );
      final details = e.details;
      if (details is Map<String, dynamic>) return details;
      if (details is Map) return Map<String, dynamic>.from(details);
      return null;
    } catch (e, st) {
      AppLogger.error(
        'oil_change_wa_gateway',
        'function ${body['action']} error',
        e,
        st,
      );
      return null;
    }
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
