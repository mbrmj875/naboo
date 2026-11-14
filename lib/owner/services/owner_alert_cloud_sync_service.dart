import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';
import '../../utils/app_logger.dart';
import '../models/owner_alert_settings.dart';
import '../services/owner_dashboard_studio_store.dart';
import '../../services/tenant_context_service.dart';

/// مزامنة تفضيلات التنبيه وتوكن FCM إلى Supabase — يقرأها cron الخادم.
abstract final class OwnerAlertCloudSyncService {
  OwnerAlertCloudSyncService._();

  static const _prefsTable = 'owner_alert_preferences';
  static const _tokensTable = 'owner_fcm_tokens';

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  /// يرفع العتبات وقائمة Push بعد حفظ Studio محلياً.
  static Future<void> upsertAlertPreferences({
    required int localTenantId,
    required OwnerAlertSettings settings,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || localTenantId <= 0) return;

    try {
      final features = await BusinessSetupSettingsData.load(
        AppSettingsRepository.instance,
      );
      final payload = settings.toServerSyncPayload(
        businessVertical: features.businessVertical,
        enableDebts: features.enableDebts,
        enableInstallments: features.enableInstallments,
      );
      await Supabase.instance.client.from(_prefsTable).upsert(
        {
          'user_id': user.id,
          'local_tenant_id': localTenantId,
          'vertical': payload['vertical'],
          'thresholds': payload['thresholds'],
          'push_alert_ids': payload['pushAlertIds'],
          'feature_flags': payload['featureFlags'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,local_tenant_id',
      );
    } catch (e, st) {
      AppLogger.error('OwnerAlertCloud', 'فشل رفع تفضيلات التنبيه', e, st);
    }
  }

  /// يسجّل توكن FCM للمالك — cron يرسل إليه فقط.
  static Future<void> registerFcmToken({
    required int localTenantId,
    required String token,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || localTenantId <= 0 || token.trim().isEmpty) return;

    try {
      await Supabase.instance.client.from(_tokensTable).upsert(
        {
          'user_id': user.id,
          'local_tenant_id': localTenantId,
          'token': token.trim(),
          'platform': _platformLabel,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,local_tenant_id,platform',
      );
    } catch (e, st) {
      AppLogger.error('OwnerAlertCloud', 'فشل تسجيل توكن FCM', e, st);
    }
  }

  static void scheduleUpsertAlertPreferences({
    required int localTenantId,
    required OwnerAlertSettings settings,
  }) {
    unawaited(
      upsertAlertPreferences(
        localTenantId: localTenantId,
        settings: settings,
      ),
    );
  }

  /// يعيد رفع التفضيلات بعد تغيير Feature Gate (ديون/أقساط).
  static Future<void> resyncActiveTenantPreferences() async {
    final tenantId = TenantContextService.instance.activeTenantId;
    if (tenantId <= 0) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final raw = await OwnerDashboardStudioStore().load(tenantId: tenantId);
      await upsertAlertPreferences(
        localTenantId: tenantId,
        settings: raw.alertSettings,
      );
    } catch (e, st) {
      AppLogger.error('OwnerAlertCloud', 'فشل إعادة مزامنة التفضيلات', e, st);
    }
  }

  static void scheduleResyncActiveTenantPreferences() {
    unawaited(resyncActiveTenantPreferences());
  }
}
