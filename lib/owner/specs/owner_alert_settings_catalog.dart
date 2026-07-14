import '../../services/business_setup_settings.dart';
import '../models/owner_action_alert.dart';
import '../models/owner_alert_settings.dart';
import 'owner_dashboard_profile.dart';

/// metadata استوديو v3.3 — عتبات وقنوات لكل تنبيه.
class OwnerAlertSettingsEntry {
  const OwnerAlertSettingsEntry({
    required this.alertId,
    required this.titleAr,
    this.thresholdKey,
    this.thresholdLabelAr,
    this.thresholdMin = 1,
    this.thresholdMax = 99,
  });

  final String alertId;
  final String titleAr;
  final String? thresholdKey;
  final String? thresholdLabelAr;
  final int thresholdMin;
  final int thresholdMax;
}

abstract final class OwnerAlertSettingsCatalog {
  OwnerAlertSettingsCatalog._();

  static const _oil = {
    OwnerDashboardProfile.oilChangeService,
    OwnerDashboardProfile.oilChangeHybrid,
  };
  static const _retail = {
    OwnerDashboardProfile.supermarket,
    OwnerDashboardProfile.generalRetail,
    OwnerDashboardProfile.pharmacy,
  };
  static const _clothing = {OwnerDashboardProfile.clothingStore};

  static List<OwnerAlertSettingsEntry> entriesForProfile(
    OwnerDashboardProfile profile, {
    required BusinessSetupSettingsData features,
  }) {
    final out = <OwnerAlertSettingsEntry>[];

    if (_oil.contains(profile)) {
      out.addAll(const [
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.oilGarageStale,
          titleAr: 'سيارات متأخرة في الورشة',
          thresholdKey: 'garageStaleMinCount',
          thresholdLabelAr: 'عدد السيارات المتأخرة',
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.oilGarageStale,
          titleAr: 'مدة انتظار الورشة (ساعات)',
          thresholdKey: 'garageStaleHours',
          thresholdLabelAr: 'ساعات قبل اعتبار السيارة متأخرة',
          thresholdMin: 1,
          thresholdMax: 24,
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.oilActiveGarage,
          titleAr: 'سيارات في الورشة',
          thresholdKey: 'activeGarageMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد السيارات',
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.oilStockShortage,
          titleAr: 'نواقص زيوت وفلاتر',
          thresholdKey: 'stockShortageMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد النواقص',
        ),
      ]);
    }

    if (_retail.contains(profile)) {
      out.add(
        const OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.retailStockShortage,
          titleAr: 'نواقص الرفوف',
          thresholdKey: 'stockShortageMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد النواقص',
        ),
      );
    }

    if (_clothing.contains(profile)) {
      out.addAll(const [
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.clothingVariantShortage,
          titleAr: 'نواقص المقاسات والألوان',
          thresholdKey: 'variantShortageMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد المتغيّرات الناقصة',
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.clothingSlowMovers,
          titleAr: 'أرصدة راكدة',
          thresholdKey: 'slowMoversMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد الأرصدة الراكدة',
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.clothingSlowMovers,
          titleAr: 'مدة الركود (أيام)',
          thresholdKey: 'slowMoversDays',
          thresholdLabelAr: 'أيام بدون مبيعات',
          thresholdMin: 7,
          thresholdMax: 180,
        ),
      ]);
    }

    if (features.enableInstallments) {
      out.addAll(const [
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.installmentOverdue,
          titleAr: 'أقساط متأخرة',
          thresholdKey: 'installmentOverdueMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد الأقساط المتأخرة',
        ),
        OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.installmentDueToday,
          titleAr: 'أقساط مستحقة اليوم',
          thresholdKey: 'installmentDueTodayMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد الأقساط',
        ),
      ]);
    }

    if (features.enableDebts) {
      out.add(
        const OwnerAlertSettingsEntry(
          alertId: OwnerActionAlertIds.debtCustomers,
          titleAr: 'عملاء مدينون',
          thresholdKey: 'debtorsMinCount',
          thresholdLabelAr: 'الحد الأدنى لعدد العملاء',
        ),
      );
    }

    return out;
  }

  /// تنبيهات فريدة لقسم «قنوات الإشعار» (بدون تكرار threshold-only rows).
  static List<String> distinctAlertIds(
    OwnerDashboardProfile profile, {
    required BusinessSetupSettingsData features,
  }) {
    final seen = <String>{};
    final out = <String>[];
    for (final e in entriesForProfile(profile, features: features)) {
      if (seen.add(e.alertId)) out.add(e.alertId);
    }
    return out;
  }

  static int readThresholdValue(OwnerAlertThresholds t, String key) {
    switch (key) {
      case 'stockShortageMinCount':
        return t.stockShortageMinCount;
      case 'variantShortageMinCount':
        return t.variantShortageMinCount;
      case 'slowMoversMinCount':
        return t.slowMoversMinCount;
      case 'slowMoversDays':
        return t.slowMoversDays;
      case 'garageStaleHours':
        return t.garageStaleHours;
      case 'garageStaleMinCount':
        return t.garageStaleMinCount;
      case 'activeGarageMinCount':
        return t.activeGarageMinCount;
      case 'debtorsMinCount':
        return t.debtorsMinCount;
      case 'installmentOverdueMinCount':
        return t.installmentOverdueMinCount;
      case 'installmentDueTodayMinCount':
        return t.installmentDueTodayMinCount;
      default:
        return 1;
    }
  }

  static OwnerAlertThresholds writeThresholdValue(
    OwnerAlertThresholds t,
    String key,
    int value,
  ) {
    final v = value.clamp(1, 9999);
    switch (key) {
      case 'stockShortageMinCount':
        return t.copyWith(stockShortageMinCount: v);
      case 'variantShortageMinCount':
        return t.copyWith(variantShortageMinCount: v);
      case 'slowMoversMinCount':
        return t.copyWith(slowMoversMinCount: v);
      case 'slowMoversDays':
        return t.copyWith(slowMoversDays: v.clamp(7, 180));
      case 'garageStaleHours':
        return t.copyWith(garageStaleHours: v.clamp(1, 24));
      case 'garageStaleMinCount':
        return t.copyWith(garageStaleMinCount: v);
      case 'activeGarageMinCount':
        return t.copyWith(activeGarageMinCount: v);
      case 'debtorsMinCount':
        return t.copyWith(debtorsMinCount: v);
      case 'installmentOverdueMinCount':
        return t.copyWith(installmentOverdueMinCount: v);
      case 'installmentDueTodayMinCount':
        return t.copyWith(installmentDueTodayMinCount: v);
      default:
        return t;
    }
  }

  static String alertTitleAr(String alertId) {
    switch (alertId) {
      case OwnerActionAlertIds.oilGarageStale:
        return 'سيارات متأخرة';
      case OwnerActionAlertIds.oilActiveGarage:
        return 'سيارات في الورشة';
      case OwnerActionAlertIds.oilStockShortage:
        return 'نواقص زيوت وفلاتر';
      case OwnerActionAlertIds.retailStockShortage:
        return 'نواقص الرفوف';
      case OwnerActionAlertIds.clothingVariantShortage:
        return 'نواقص المقاسات';
      case OwnerActionAlertIds.clothingSlowMovers:
        return 'أرصدة راكدة';
      case OwnerActionAlertIds.installmentOverdue:
        return 'أقساط متأخرة';
      case OwnerActionAlertIds.installmentDueToday:
        return 'أقساط اليوم';
      case OwnerActionAlertIds.debtCustomers:
        return 'ديون العملاء';
      default:
        return alertId;
    }
  }
}
