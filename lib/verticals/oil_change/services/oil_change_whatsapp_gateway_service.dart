import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';

class WhatsappGatewayQrResult {
  const WhatsappGatewayQrResult({
    required this.ok,
    this.base64,
    this.pairingCode,
  });

  final bool ok;
  final String? base64;
  final String? pairingCode;
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

  Future<WhatsappGatewayQrResult> fetchQr() async {
    final data = await _invoke({'action': 'qr'});
    if (data == null) {
      return const WhatsappGatewayQrResult(ok: false);
    }
    return WhatsappGatewayQrResult(
      ok: data['ok'] == true,
      base64: data['base64']?.toString(),
      pairingCode: data['pairing_code']?.toString(),
    );
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

  Future<bool> reportDisconnected() async {
    final data = await _invoke({'action': 'report_disconnected'});
    return data?['ok'] == true;
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
