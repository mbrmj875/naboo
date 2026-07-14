import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_settings_repository.dart';
import '../business_setup_settings.dart';
import '../../utils/app_logger.dart';

/// تخصص النشاط على مستوى الحساب (جدول `profiles`) — مصدر حقيقة
/// يُستورد محلياً على كل جهاز بعد Google/PIN.
abstract final class OwnerBusinessVerticalCloudService {
  OwnerBusinessVerticalCloudService._();

  static const _profilesTable = 'profiles';

  static Future<String?> fetchForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await Supabase.instance.client
          .from(_profilesTable)
          .select('business_vertical')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      final v = (row['business_vertical'] as String?)?.trim() ?? '';
      return BusinessVertical.isKnown(v) ? v : null;
    } on PostgrestException catch (e) {
      if (_isMissingColumn(e)) {
        AppLogger.warn(
          'OwnerBusinessVertical',
          'profiles.business_vertical غير موجود — نفّذ migration 20260706',
        );
        return null;
      }
      AppLogger.warn('OwnerBusinessVertical', 'fetch: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.warn('OwnerBusinessVertical', 'fetch: $e');
      return null;
    }
  }

  /// يُسجّل التخصص على السحابة **مرة واحدة** — لا يُستبدل إن وُجد مسبقاً.
  static Future<void> commitVerticalOnce(String vertical) async {
    if (!BusinessVertical.isKnown(vertical)) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final row = await Supabase.instance.client
          .from(_profilesTable)
          .select('business_vertical')
          .eq('id', user.id)
          .maybeSingle();

      final existing =
          (row?['business_vertical'] as String?)?.trim() ?? '';
      if (existing.isNotEmpty) {
        if (existing != vertical) {
          AppLogger.warn(
            'OwnerBusinessVertical',
            'server vertical locked ($existing) — ignoring local $vertical',
          );
        }
        return;
      }

      await Supabase.instance.client.from(_profilesTable).upsert(
        {
          'id': user.id,
          'email': user.email,
          'business_vertical': vertical,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'id',
      );
    } on PostgrestException catch (e) {
      if (_isMissingColumn(e)) {
        AppLogger.warn(
          'OwnerBusinessVertical',
          'commit skipped — عمود business_vertical غير موجود بعد',
        );
        return;
      }
      AppLogger.warn('OwnerBusinessVertical', 'commit: ${e.message}');
    } catch (e) {
      AppLogger.warn('OwnerBusinessVertical', 'commit: $e');
    }
  }

  /// يطبّق تخصص الحساب من السحابة محلياً إن لم يُضبط بعد أو كان ناقصاً.
  static Future<bool> applyToLocalIfNeeded() async {
    final cloud = await fetchForCurrentUser();
    if (cloud == null) return false;

    final repo = AppSettingsRepository.instance;
    final local = await BusinessSetupSettingsData.load(repo);

    if (local.onboardingCompleted &&
        local.businessVertical == cloud &&
        await BusinessSetupSettingsData.isVerticalLocked(repo)) {
      return false;
    }

    if (local.onboardingCompleted && local.businessVertical == cloud) {
      await BusinessSetupSettingsData.markVerticalLocked(repo);
      return false;
    }

    final preset = BusinessSetupSettingsData.createForVertical(
      cloud,
      onboardingCompleted: true,
      enableLoyaltyCustom: local.enableLoyalty,
      enableDebtsCustom: local.enableDebts,
    );

    await preset.save(repo);
    await BusinessSetupSettingsData.markVerticalLocked(repo);
    BusinessFeaturesRevision.bump();
    AppLogger.info(
      'OwnerBusinessVertical',
      'applied cloud vertical=$cloud to local settings',
    );
    return true;
  }

  /// يُرفع التخصص المحلي إلى السحابة إن كان الحساب مكتملاً لكن العمود فارغاً.
  static Future<bool> syncLocalVerticalToCloudIfMissing() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    final cloud = await fetchForCurrentUser();
    if (cloud != null) return false;

    final local = await BusinessSetupSettingsData.load(
      AppSettingsRepository.instance,
    );
    if (!local.onboardingCompleted) return false;
    final vertical = local.routingVertical;
    if (!BusinessVertical.isKnown(vertical)) return false;

    await commitVerticalOnce(vertical);
    return true;
  }

  static bool _isMissingColumn(PostgrestException e) {
    final m = e.message.toLowerCase();
    return m.contains('business_vertical') &&
        (m.contains('does not exist') || m.contains('could not find'));
  }
}
