import '../../../services/app_settings_repository.dart';
import '../models/tenant_whatsapp_gateway_record.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';

/// يخزّن آخر حالة معروفة لجلسة واتساب المحل — محلياً + سحابة.
class OilChangeWhatsappStatusStore {
  OilChangeWhatsappStatusStore._();

  static final OilChangeWhatsappStatusStore instance =
      OilChangeWhatsappStatusStore._();

  static const _statusKey = 'biz.oil.whatsapp_gateway_status';
  static const _updatedAtKey = 'biz.oil.whatsapp_gateway_updated_at';

  /// يقرأ من Supabase أولاً (مزامنة الأجهزة) ثم المحلي.
  /// [refreshFromServer] يستعلم Evolution مباشرة قبل القراءة.
  Future<OilChangeWhatsappGatewayStatus> readStatus({
    bool refreshFromServer = false,
  }) async {
    if (refreshFromServer &&
        OilChangeWhatsappGatewayRepository.instance.hasCloudSession) {
      await OilChangeWhatsappGatewayRepository.instance.refreshStatusFromServer();
    } else if (OilChangeWhatsappGatewayRepository.instance.hasCloudSession) {
      final cloud =
          await OilChangeWhatsappGatewayRepository.instance.fetchForCurrentUser();
      if (cloud != null) {
        final mapped = _mapCloud(cloud.status);
        await _writeLocal(mapped);
        return mapped;
      }
    }
    return _readLocal();
  }

  Future<bool> isDisconnectedBannerVisible() async {
    final status = await readStatus(refreshFromServer: true);
    return status == OilChangeWhatsappGatewayStatus.disconnected;
  }

  /// يحدّث السحابة والمحلي بعد نجاح الإرسال.
  Future<void> markConnected() async {
    await _writeLocal(OilChangeWhatsappGatewayStatus.connected);
    if (OilChangeWhatsappGatewayRepository.instance.hasCloudSession) {
      await OilChangeWhatsappGatewayRepository.instance.refreshStatusFromServer();
    }
  }

  Future<void> markDisconnected() async {
    await _writeLocal(OilChangeWhatsappGatewayStatus.disconnected);
    await OilChangeWhatsappGatewayRepository.instance.reportDisconnected();
  }

  /// مزامنة من السيرفر — تُستدعى عند فتح سجل الغيار.
  Future<void> syncFromCloudIfPossible() async {
    if (!OilChangeWhatsappGatewayRepository.instance.hasCloudSession) return;
    await OilChangeWhatsappGatewayRepository.instance.refreshStatusFromServer();
    final cloud =
        await OilChangeWhatsappGatewayRepository.instance.fetchForCurrentUser();
    if (cloud != null) {
      await _writeLocal(_mapCloud(cloud.status));
    }
  }

  Future<void> _writeLocal(OilChangeWhatsappGatewayStatus status) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      _statusKey,
      status.name,
      tenantId: tenantId,
    );
    await repo.setForTenant(
      _updatedAtKey,
      DateTime.now().toUtc().toIso8601String(),
      tenantId: tenantId,
    );
  }

  Future<OilChangeWhatsappGatewayStatus> _readLocal() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(_statusKey, tenantId: tenantId);
    return _parseLocal(raw);
  }

  static OilChangeWhatsappGatewayStatus _mapCloud(
    TenantWhatsappGatewayStatus status,
  ) {
    switch (status) {
      case TenantWhatsappGatewayStatus.connected:
        return OilChangeWhatsappGatewayStatus.connected;
      case TenantWhatsappGatewayStatus.disconnected:
        return OilChangeWhatsappGatewayStatus.disconnected;
      case TenantWhatsappGatewayStatus.connecting:
        return OilChangeWhatsappGatewayStatus.unknown;
      case TenantWhatsappGatewayStatus.unknown:
        return OilChangeWhatsappGatewayStatus.unknown;
    }
  }

  static OilChangeWhatsappGatewayStatus _parseLocal(String? raw) {
    switch (raw?.trim()) {
      case 'connected':
        return OilChangeWhatsappGatewayStatus.connected;
      case 'disconnected':
        return OilChangeWhatsappGatewayStatus.disconnected;
      default:
        return OilChangeWhatsappGatewayStatus.unknown;
    }
  }
}

/// حالة اتصال بوابة واتساب المحل (Evolution) — لكل تينانت محلياً.
enum OilChangeWhatsappGatewayStatus {
  unknown,
  connected,
  disconnected,
}
