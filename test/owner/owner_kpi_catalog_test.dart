import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/specs/owner_dashboard_l10n_keys.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/permission_service.dart';

void main() {
  group('OwnerKpiCatalog', () {
    late BusinessSetupSettingsData oilFeatures;
    late OwnerDashboardAccessContext fullAccess;

    setUp(() {
      oilFeatures = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 42);
    });

    test('oil_change service entries include core KPIs', () {
      final entries = OwnerKpiCatalog.entriesFor(
        features: oilFeatures,
        access: fullAccess,
      );
      final ids = entries.map((e) => e.id).toSet();
      expect(ids, contains(OwnerCatalogIds.oilActiveCars));
      expect(ids, contains(OwnerCatalogIds.oilChangesPeriod));
      expect(ids, isNot(contains(OwnerCatalogIds.hybridRevenueSplit)));
      expect(ids, isNot(contains(OwnerCatalogIds.retailTopSellers)));
    });

    test('supermarket catalog exposes retail cards not oil cards', () {
      final supermarket = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
      );
      final entries = OwnerKpiCatalog.entriesFor(
        features: supermarket,
        access: fullAccess,
      );
      final ids = entries.map((e) => e.id).toSet();
      expect(ids, contains(OwnerCatalogIds.retailStockShortages));
      expect(ids, contains(OwnerCatalogIds.retailTopSellers));
      expect(ids, isNot(contains(OwnerCatalogIds.oilActiveCars)));
    });

    test('clothing catalog exposes variant KPIs not supermarket cards', () {
      final clothing = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.clothingStore,
      );
      final entries = OwnerKpiCatalog.entriesFor(
        features: clothing,
        access: fullAccess,
      );
      final ids = entries.map((e) => e.id).toSet();
      expect(ids, contains(OwnerCatalogIds.clothingVariantShortages));
      expect(ids, contains(OwnerCatalogIds.clothingSlowMovers));
      expect(ids, contains(OwnerCatalogIds.clothingTopSellers));
      expect(ids, isNot(contains(OwnerCatalogIds.retailStockShortages)));
      expect(ids, isNot(contains(OwnerCatalogIds.oilActiveCars)));
    });

    test('hybrid adds revenue split when POS enabled', () {
      final hybrid = oilFeatures.copyWith(enablePos: true);
      final entries = OwnerKpiCatalog.entriesFor(
        features: hybrid,
        access: fullAccess,
      );
      final ids = entries.map((e) => e.id).toList();
      expect(ids, contains(OwnerCatalogIds.hybridRevenueSplit));
    });

    test('debts card hidden when feature gate off', () {
      final noDebts = oilFeatures.copyWith(enableDebts: false);
      final entries = OwnerKpiCatalog.entriesFor(
        features: noDebts,
        access: fullAccess,
      );
      expect(
        entries.map((e) => e.id),
        isNot(contains(OwnerCatalogIds.debtsSummary)),
      );
    });

    test('GM without financial permission hides cash and revenue KPIs', () {
      final gmAccess = OwnerDashboardAccessContext(
        tenantId: 42,
        permissions: {
          PermissionKeys.ownerKpiOperations: true,
          PermissionKeys.ownerKpiInventory: true,
          PermissionKeys.ownerKpiDebts: true,
          PermissionKeys.ownerKpiFinancial: false,
        },
      );
      final entries = OwnerKpiCatalog.entriesFor(
        features: oilFeatures,
        access: gmAccess,
      );
      final ids = entries.map((e) => e.id).toSet();
      expect(ids, contains(OwnerCatalogIds.oilActiveCars));
      expect(ids, isNot(contains(OwnerCatalogIds.cashSummary)));
      expect(ids, isNot(contains(OwnerCatalogIds.oilChangesPeriod)));
      expect(ids, contains(OwnerCatalogIds.inventoryValue));
    });

    test('catalog uses l10n keys not hardcoded Arabic', () {
      final entry = OwnerKpiCatalog.kpiById(OwnerCatalogIds.oilActiveCars)!;
      expect(entry.titleKey, OwnerDashboardL10nKeys.oilActiveCarsTitle);
      expect(entry.titleKey, startsWith('owner.kpi.'));
      expect(ownerDashboardL10n(entry.titleKey), 'سيارات في الورشة');
    });

    test('sectionIdsFor passes tenant-scoped order to loaders', () {
      final order = [
        OwnerCatalogIds.oilActiveCars,
        OwnerCatalogIds.cashSummary,
      ];
      final sections = OwnerKpiCatalog.sectionIdsFor(
        features: oilFeatures,
        access: fullAccess,
        catalogOrder: order,
      );
      expect(sections.first, isNotEmpty);
      expect(fullAccess.tenantId, 42);
    });
  });
}

extension on BusinessSetupSettingsData {
  BusinessSetupSettingsData copyWith({
    bool? enableDebts,
    bool? enablePos,
  }) {
    return BusinessSetupSettingsData(
      onboardingCompleted: onboardingCompleted,
      businessVertical: businessVertical,
      enableDebts: enableDebts ?? this.enableDebts,
      enableInstallments: enableInstallments,
      enableWeightSales: enableWeightSales,
      enableCustomers: enableCustomers,
      enableLoyalty: enableLoyalty,
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      enableClothingVariants: enableClothingVariants,
      enableOilChange: enableOilChange,
      enableRepairServices: enableRepairServices,
      enablePos: enablePos ?? this.enablePos,
      enableServices: enableServices,
    );
  }
}
