import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../utils/app_logger.dart';
import '../models/tenant_whatsapp_gateway_record.dart';
import 'oil_change_whatsapp_gateway_service.dart';

/// يقرأ/يكتب حالة واتساب المحل من Supabase — مزامنة بين الأجهزة.
class OilChangeWhatsappGatewayRepository {
  OilChangeWhatsappGatewayRepository._();

  static final OilChangeWhatsappGatewayRepository instance =
      OilChangeWhatsappGatewayRepository._();

  static const _table = 'tenant_whatsapp_gateways';

  bool get hasCloudSession =>
      Supabase.instance.client.auth.currentUser != null;

  /// اسم instance في Evolution — من السحابة أو من UID أو الإعداد الافتراضي.
  Future<String> resolveInstanceName() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final row = await fetchForCurrentUser();
      if (row != null && row.evolutionInstanceName.isNotEmpty) {
        return row.evolutionInstanceName;
      }
      return OilChangeWhatsappGatewayService.instance
          .instanceNameForUserId(user.id);
    }
    return OilChangeWhatsappConfig.instanceName;
  }

  Future<TenantWhatsappGatewayRecord?> fetchForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await Supabase.instance.client
          .from(_table)
          .select(
            'evolution_instance_name, status, whatsapp_phone, updated_at',
          )
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return TenantWhatsappGatewayRecord.fromMap(row);
    } catch (e) {
      AppLogger.warn('oil_change_wa_gateway', 'fetch failed: $e');
      return null;
    }
  }

  /// يستدعي Edge Function `status` ويُحدّث السحابة.
  Future<TenantWhatsappGatewayRecord?> refreshStatusFromServer() async {
    final result = await OilChangeWhatsappGatewayService.instance.checkStatus();
    if (!result.ok) return fetchForCurrentUser();
    return fetchForCurrentUser();
  }

  Future<void> reportDisconnected() async {
    if (!hasCloudSession) return;
    await OilChangeWhatsappGatewayService.instance.reportDisconnected();
  }
}
