import '../utils/app_logger.dart';
import 'app_settings_repository.dart';
import 'business_setup_settings.dart';
import 'database_helper.dart';

/// يحمي صفحة الديون من الاختفاء في تخصص الزيوت.
///
/// بطاقة الغيار تنشئ فواتير آجلة دائماً، فإن كانت ميزة الديون مطفأة والمحل
/// عنده ديون مفتوحة، يملك ديوناً لا صفحة لرؤيتها أو تسديدها. هنا تُفعَّل
/// الميزة تلقائياً في هذه الحالة فقط.
abstract final class DebtsFeatureGuard {
  DebtsFeatureGuard._();

  /// يُرجع true إن فعّل الميزة.
  static Future<bool> ensureOilDebtsEnabledIfOpenDebts(
    AppSettingsRepository repo,
  ) async {
    try {
      final settings = await BusinessSetupSettingsData.load(repo);
      if (settings.enableDebts) return false;
      if (settings.routingVertical != BusinessVertical.oilChange) return false;

      final tenantId = await repo.getActiveTenantId();
      final summary = await DatabaseHelper()
          .summarizeOpenCreditDebtForDashboard(tenantId: tenantId);
      if (summary.debtorCount <= 0) return false;

      await settings
          .copyWith(enableDebts: true)
          .save(repo, forceVerticalCorrection: true);
      BusinessFeaturesRevision.bump();
      AppLogger.info(
        'DebtsFeatureGuard',
        'enabled debts: ${summary.debtorCount} open debtors',
      );
      return true;
    } catch (e) {
      AppLogger.warn('DebtsFeatureGuard', 'ensure failed: $e');
      return false;
    }
  }
}
