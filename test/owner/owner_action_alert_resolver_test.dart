import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_action_alert.dart';
import 'package:naboo/owner/models/owner_alert_settings.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/owner_action_alert_resolver.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/services/business_setup_settings.dart';

void main() {
  group('OwnerActionAlertResolver', () {
    test('sorts critical before medium for oil_change', () {
      final snapshot = OwnerCommandCenterSnapshot(
        oilActiveCars: OwnerSectionResult.success(
          const OilActiveCarsKpi(activeCount: 2, staleWaitingCount: 1),
          DateTime(2026, 5, 28),
        ),
        oilStockShortages: OwnerSectionResult.success(
          const InventoryAlert(shortageCount: 4),
          DateTime(2026, 5, 28),
        ),
      );
      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.oilChangeService,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
        ),
        snapshot: snapshot,
      );

      expect(alerts, isNotEmpty);
      expect(alerts.first.id, OwnerActionAlertIds.oilGarageStale);
      expect(alerts.first.priority, OwnerAlertPriority.critical);
      expect(alerts.last.priority, OwnerAlertPriority.medium);
      expect(alerts.every((a) => a.ctaLabelAr.isNotEmpty), isTrue);
    });

    test('supermarket retail shortage alert disappears when count zero', () {
      final empty = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
        snapshot: OwnerCommandCenterSnapshot(
          inventoryShortages: OwnerSectionResult.success(
            const InventoryAlert(shortageCount: 0),
            DateTime(2026, 5, 28),
          ),
        ),
      );
      expect(empty, isEmpty);

      final active = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
        snapshot: OwnerCommandCenterSnapshot(
          inventoryShortages: OwnerSectionResult.success(
            const InventoryAlert(shortageCount: 2),
            DateTime(2026, 5, 28),
          ),
        ),
      );
      expect(active, hasLength(1));
      expect(active.single.id, OwnerActionAlertIds.retailStockShortage);
    });

    test('installment overdue outranks due today and debts', () {
      final features = BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.supermarket,
        enableDebts: true,
        enableInstallments: true,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: false,
        enableRepairServices: false,
        enablePos: true,
        enableServices: true,
      );
      final snapshot = OwnerCommandCenterSnapshot(
        installments: OwnerSectionResult.success(
          const InstallmentAlert(overdueCount: 2, dueTodayCount: 3),
          DateTime(2026, 5, 28),
        ),
        debts: OwnerSectionResult.success(
          const DebtSummary(totalReceivableFils: 1000000, indebtedCustomerCount: 4),
          DateTime(2026, 5, 28),
        ),
      );

      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: features,
        snapshot: snapshot,
      );

      expect(alerts.first.id, OwnerActionAlertIds.installmentOverdue);
      expect(alerts.first.priority, OwnerAlertPriority.critical);
      expect(
        alerts.map((a) => a.id),
        containsAll([
          OwnerActionAlertIds.installmentDueToday,
          OwnerActionAlertIds.debtCustomers,
        ]),
      );
    });

    test('limits visible alerts to maxVisibleAlerts', () {
      final features = BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.oilChange,
        enableDebts: true,
        enableInstallments: true,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: true,
        enableRepairServices: false,
        enablePos: false,
        enableServices: true,
      );
      final snapshot = OwnerCommandCenterSnapshot(
        oilActiveCars: OwnerSectionResult.success(
          const OilActiveCarsKpi(activeCount: 2, staleWaitingCount: 1),
          DateTime(2026, 5, 28),
        ),
        oilStockShortages: OwnerSectionResult.success(
          const InventoryAlert(shortageCount: 3),
          DateTime(2026, 5, 28),
        ),
        installments: OwnerSectionResult.success(
          const InstallmentAlert(overdueCount: 1, dueTodayCount: 1),
          DateTime(2026, 5, 28),
        ),
        debts: OwnerSectionResult.success(
          const DebtSummary(totalReceivableFils: 1, indebtedCustomerCount: 1),
          DateTime(2026, 5, 28),
        ),
      );

      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.oilChangeService,
        features: features,
        snapshot: snapshot,
      );

      expect(alerts.length, OwnerActionAlertResolver.maxVisibleAlerts);
    });

    test('clothing variant shortage uses purchase PDF action', () {
      final snapshot = OwnerCommandCenterSnapshot(
        clothingVariantShortages: OwnerSectionResult.success(
          const ClothingVariantShortagesKpi(shortageCount: 5),
          DateTime(2026, 5, 28),
        ),
      );
      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.clothingStore,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.clothingStore,
        ),
        snapshot: snapshot,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.id, OwnerActionAlertIds.clothingVariantShortage);
      expect(alerts.single.actionKind, OwnerActionKind.purchasePdf);
      expect(alerts.single.messageAr, contains('5'));
    });

    test('threshold suppresses alert below owner minimum', () {
      final snapshot = OwnerCommandCenterSnapshot(
        inventoryShortages: OwnerSectionResult.success(
          const InventoryAlert(shortageCount: 2),
          DateTime(2026, 5, 28),
        ),
      );
      const highThreshold = OwnerAlertThresholds(stockShortageMinCount: 5);
      final suppressed = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
        snapshot: snapshot,
        thresholds: highThreshold,
      );
      expect(suppressed, isEmpty);

      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
        snapshot: snapshot,
        thresholds: const OwnerAlertThresholds(stockShortageMinCount: 2),
      );
      expect(alerts, hasLength(1));
    });

    test('channel prefs hide alert from Action Rail', () {
      final snapshot = OwnerCommandCenterSnapshot(
        inventoryShortages: OwnerSectionResult.success(
          const InventoryAlert(shortageCount: 3),
          DateTime(2026, 5, 28),
        ),
      );
      final hidden = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.supermarket,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
        snapshot: snapshot,
        channels: OwnerAlertChannelPrefs(
          byAlertId: {
            OwnerActionAlertIds.retailStockShortage: OwnerAlertChannelPref(
              showInActionRail: false,
            ),
          },
        ),
      );
      expect(hidden, isEmpty);
    });
  });
}
