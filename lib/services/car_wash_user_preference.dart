import 'app_settings_repository.dart';
import 'business_setup_settings.dart';

/// تفضيل «غسل السيارات» لكل مستخدم داخل المستأجر (لا يُشارك بين الموظفين).
class CarWashUserPreference {
  CarWashUserPreference._();

  static const preferenceKey = BusinessSetupKeys.enableCarWash;

  /// مفتاح التخزين — للاختبارات والتوثيق.
  static String storageKey({
    required int tenantId,
    required int userId,
  }) {
    final t = tenantId <= 0 ? 1 : tenantId;
    return 't:$t:u:$userId:$preferenceKey';
  }

  static Future<bool> isEnabledForUser(
    AppSettingsRepository repo, {
    required int userId,
    int? tenantId,
  }) async {
    if (userId <= 0) return false;
    final tid = tenantId ?? await repo.getActiveTenantId();
    final raw = await repo.getForTenantUser(
      preferenceKey,
      userId: userId,
      tenantId: tid,
    );
    return raw == '1';
  }

  static Future<void> setEnabledForUser(
    AppSettingsRepository repo, {
    required int userId,
    required bool enabled,
    int? tenantId,
  }) async {
    if (userId <= 0) {
      throw StateError('لا يوجد مستخدم نشط لحفظ تفضيل غسل السيارات.');
    }
    final tid = tenantId ?? await repo.getActiveTenantId();
    await repo.setForTenantUser(
      preferenceKey,
      enabled ? '1' : '0',
      userId: userId,
      tenantId: tid,
    );
  }
}
