import '../../services/business_setup_settings.dart';
import 'models/owner_action_alert.dart';
import 'models/owner_alert_settings.dart';
import 'models/owner_command_center_snapshot.dart';
import 'models/owner_kpi_models.dart';
import 'models/owner_section_result.dart';
import 'specs/owner_dashboard_profile.dart';

/// يبني قائمة تنبيهات Action Rail من لقطة KPIs — query-driven، بدون dismiss.
abstract final class OwnerActionAlertResolver {
  OwnerActionAlertResolver._();

  static const maxVisibleAlerts = 5;

  static List<OwnerActionAlert> resolve({
    required OwnerDashboardProfile profile,
    required BusinessSetupSettingsData features,
    required OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds = OwnerAlertThresholds.defaults,
    OwnerAlertChannelPrefs channels = OwnerAlertChannelPrefs.defaults,
  }) {
    final alerts = <OwnerActionAlert>[];

    switch (profile) {
      case OwnerDashboardProfile.oilChangeService:
      case OwnerDashboardProfile.oilChangeHybrid:
        _appendOilAlerts(alerts, snapshot, thresholds);
      case OwnerDashboardProfile.supermarket:
        _appendRetailShortageAlerts(alerts, snapshot, thresholds);
      case OwnerDashboardProfile.clothingStore:
        _appendClothingAlerts(alerts, snapshot, thresholds);
      case OwnerDashboardProfile.generalRetail:
      case OwnerDashboardProfile.pharmacy:
        _appendRetailShortageAlerts(alerts, snapshot, thresholds);
    }

    if (features.enableInstallments) {
      _appendInstallmentAlerts(alerts, snapshot, thresholds);
    }
    if (features.enableDebts) {
      _appendDebtAlerts(alerts, snapshot, thresholds);
    }

    final filtered = alerts
        .where((a) => channels.forAlert(a.id).showInActionRail)
        .toList(growable: false);
    filtered.sort((a, b) => a.compareTo(b));
    if (filtered.length <= maxVisibleAlerts) return filtered;
    return filtered.sublist(0, maxVisibleAlerts);
  }

  static void _appendOilAlerts(
    List<OwnerActionAlert> out,
    OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds,
  ) {
    final cars = _data<OilActiveCarsKpi>(snapshot.oilActiveCars);
    if (cars != null) {
      if (thresholds.meetsMin(cars.staleWaitingCount, thresholds.garageStaleMinCount)) {
        final hours = thresholds.garageStaleHours;
        out.add(
          OwnerActionAlert(
            id: OwnerActionAlertIds.oilGarageStale,
            priority: OwnerAlertPriority.critical,
            titleAr: 'سيارات متأخرة',
            messageAr: _countLabel(
              cars.staleWaitingCount,
              one: 'سيارة بانتظار منذ $hours ساعة أو أكثر',
              many:
                  '${cars.staleWaitingCount} سيارات بانتظار منذ $hours ساعة أو أكثر',
            ),
            ctaLabelAr: 'سجل الغيارات',
            actionKind: OwnerActionKind.openOilLog,
          ),
        );
      } else if (thresholds.meetsMin(cars.activeCount, thresholds.activeGarageMinCount)) {
        out.add(
          OwnerActionAlert(
            id: OwnerActionAlertIds.oilActiveGarage,
            priority: OwnerAlertPriority.high,
            titleAr: 'سيارات في الورشة',
            messageAr: _countLabel(
              cars.activeCount,
              one: 'سيارة واحدة قيد العمل',
              many: '${cars.activeCount} سيارات قيد العمل',
            ),
            ctaLabelAr: 'سجل الغيارات',
            actionKind: OwnerActionKind.openOilLog,
          ),
        );
      }
    }

    final shortages = _data<InventoryAlert>(snapshot.oilStockShortages);
    if (shortages != null &&
        thresholds.meetsMin(
          shortages.shortageCount,
          thresholds.stockShortageMinCount,
        )) {
      out.add(
        OwnerActionAlert(
          id: OwnerActionAlertIds.oilStockShortage,
          priority: OwnerAlertPriority.medium,
          titleAr: 'نواقص زيوت وفلاتر',
          messageAr: _countLabel(
            shortages.shortageCount,
            one: 'صنف واحد ناقص',
            many: '${shortages.shortageCount} أصناف ناقصة',
          ),
          ctaLabelAr: 'PDF طلبية',
          actionKind: OwnerActionKind.purchasePdf,
        ),
      );
    }
  }

  static void _appendRetailShortageAlerts(
    List<OwnerActionAlert> out,
    OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds,
  ) {
    final shortages = _data<InventoryAlert>(snapshot.inventoryShortages);
    if (shortages == null ||
        !thresholds.meetsMin(
          shortages.shortageCount,
          thresholds.stockShortageMinCount,
        )) {
      return;
    }
    out.add(
      OwnerActionAlert(
        id: OwnerActionAlertIds.retailStockShortage,
        priority: OwnerAlertPriority.medium,
        titleAr: 'نواقص الرفوف',
        messageAr: _countLabel(
          shortages.shortageCount,
          one: 'صنف واحد ناقص على الرف',
          many: '${shortages.shortageCount} أصناف ناقصة على الرف',
        ),
        ctaLabelAr: 'PDF طلبية',
        actionKind: OwnerActionKind.purchasePdf,
      ),
    );
  }

  static void _appendClothingAlerts(
    List<OwnerActionAlert> out,
    OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds,
  ) {
    final variants = _data<ClothingVariantShortagesKpi>(
      snapshot.clothingVariantShortages,
    );
    if (variants != null &&
        thresholds.meetsMin(
          variants.shortageCount,
          thresholds.variantShortageMinCount,
        )) {
      out.add(
        OwnerActionAlert(
          id: OwnerActionAlertIds.clothingVariantShortage,
          priority: OwnerAlertPriority.high,
          titleAr: 'نواقص المقاسات',
          messageAr: _countLabel(
            variants.shortageCount,
            one: 'مقاس أو لون واحد نفد',
            many: '${variants.shortageCount} مقاسات/ألوان ناقصة',
          ),
          ctaLabelAr: 'PDF طلبية',
          actionKind: OwnerActionKind.purchasePdf,
        ),
      );
    }

    final slow = _data<ClothingSlowMoversKpi>(snapshot.clothingSlowMovers);
    if (slow != null &&
        thresholds.meetsMin(slow.slowCount, thresholds.slowMoversMinCount)) {
      out.add(
        OwnerActionAlert(
          id: OwnerActionAlertIds.clothingSlowMovers,
          priority: OwnerAlertPriority.medium,
          titleAr: 'أرصدة راكدة',
          messageAr: _countLabel(
            slow.slowCount,
            one: 'متغيّر واحد بدون مبيعات منذ ${slow.daysThreshold} يوماً',
            many:
                '${slow.slowCount} متغيّرات بدون مبيعات منذ ${slow.daysThreshold} يوماً',
          ),
          ctaLabelAr: 'المخzون',
          actionKind: OwnerActionKind.openInventory,
        ),
      );
    }
  }

  static void _appendInstallmentAlerts(
    List<OwnerActionAlert> out,
    OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds,
  ) {
    final inst = _data<InstallmentAlert>(snapshot.installments);
    if (inst == null) return;

    if (thresholds.meetsMin(
      inst.overdueCount,
      thresholds.installmentOverdueMinCount,
    )) {
      out.add(
        OwnerActionAlert(
          id: OwnerActionAlertIds.installmentOverdue,
          priority: OwnerAlertPriority.critical,
          titleAr: 'أقساط متأخرة',
          messageAr: _countLabel(
            inst.overdueCount,
            one: 'قسط واحد متأخر',
            many: '${inst.overdueCount} أقساط متأخرة',
          ),
          ctaLabelAr: 'الأقساط',
          actionKind: OwnerActionKind.openInstallments,
        ),
      );
    }

    if (thresholds.meetsMin(
      inst.dueTodayCount,
      thresholds.installmentDueTodayMinCount,
    )) {
      out.add(
        OwnerActionAlert(
          id: OwnerActionAlertIds.installmentDueToday,
          priority: OwnerAlertPriority.high,
          titleAr: 'أقساط اليوم',
          messageAr: _countLabel(
            inst.dueTodayCount,
            one: 'قسط واحد مستحق اليوم',
            many: '${inst.dueTodayCount} أقساط مستحقة اليوم',
          ),
          ctaLabelAr: 'الأقساط',
          actionKind: OwnerActionKind.openInstallments,
        ),
      );
    }
  }

  static void _appendDebtAlerts(
    List<OwnerActionAlert> out,
    OwnerCommandCenterSnapshot snapshot,
    OwnerAlertThresholds thresholds,
  ) {
    final debts = _data<DebtSummary>(snapshot.debts);
    if (debts == null ||
        !thresholds.meetsMin(
          debts.indebtedCustomerCount,
          thresholds.debtorsMinCount,
        )) {
      return;
    }
    out.add(
      OwnerActionAlert(
        id: OwnerActionAlertIds.debtCustomers,
        priority: OwnerAlertPriority.high,
        titleAr: 'ديون العملاء',
        messageAr: _countLabel(
          debts.indebtedCustomerCount,
          one: 'عميل واحد مدين',
          many: '${debts.indebtedCustomerCount} عملاء مدينون',
        ),
        ctaLabelAr: 'إرسال واتساب',
        actionKind: OwnerActionKind.debtReminders,
      ),
    );
  }

  static T? _data<T>(OwnerSectionResult<T>? section) {
    if (section == null || !section.hasData) return null;
    return section.data;
  }

  static String _countLabel(
    int n, {
    required String one,
    required String many,
  }) {
    return n == 1 ? one : many;
  }
}
