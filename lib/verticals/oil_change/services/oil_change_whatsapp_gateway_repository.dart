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
            'evolution_instance_name, status, whatsapp_phone, updated_at, '
            'whatsapp_provider, cloud_setup_status, rating_auto_reply',
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

  /// يستدعي Edge Function `status` / `ready_status` ودمج الحالة المحسوبة.
  Future<TenantWhatsappGatewayRecord?> refreshStatusFromServer() async {
    final ready =
        await OilChangeWhatsappGatewayService.instance.fetchReadyStatus();
    final row = await fetchForCurrentUser();
    if (row == null) return null;
    if (!ready.ok) return row;
    return TenantWhatsappGatewayRecord(
      evolutionInstanceName: row.evolutionInstanceName,
      status: ready.connected
          ? TenantWhatsappGatewayStatus.connected
          : (row.status == TenantWhatsappGatewayStatus.connecting
              ? TenantWhatsappGatewayStatus.connecting
              : TenantWhatsappGatewayStatus.disconnected),
      whatsappPhone: ready.phone ?? row.whatsappPhone,
      updatedAt: row.updatedAt,
      provider: row.provider,
      cloudSetupStatus: row.cloudSetupStatus,
      readyState: TenantWhatsappGatewayRecord.fromMap({
        'ready_state': ready.readyState ?? 'disconnected',
      }).readyState,
      ratingAutoReply: row.ratingAutoReply,
    );
  }

  /// هل الرد التلقائي / الإجابة الذكية داخل واتساب مفعّل لهذا المحل؟
  Future<bool> fetchRatingAutoReplyEnabled() async {
    final row = await fetchForCurrentUser();
    return row?.ratingAutoReply ?? true;
  }

  /// تشغيل أو إيقاف ردود واتساب التلقائية (ذكاء + تحية + شكر تقييم).
  Future<bool> setRatingAutoReplyEnabled(bool enabled) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      await Supabase.instance.client.from(_table).update({
        'rating_auto_reply': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', user.id);
      return true;
    } catch (e) {
      AppLogger.warn('oil_change_wa_gateway', 'set rating_auto_reply failed: $e');
      return false;
    }
  }

  Future<WhatsappReportDisconnectedResult> reportDisconnected() async {
    if (!hasCloudSession) {
      return const WhatsappReportDisconnectedResult(ok: false);
    }
    return OilChangeWhatsappGatewayService.instance.reportDisconnected();
  }
}
