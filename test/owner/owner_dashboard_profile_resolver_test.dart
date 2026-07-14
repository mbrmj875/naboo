import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/recent_activity_entry.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/owner_dashboard_profile_resolver.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';

void main() {
  group('OwnerDashboardProfileResolver', () {
    late BusinessSetupSettingsData oilService;
    late BusinessSetupSettingsData oilHybrid;
    late OwnerDashboardAccessContext fullAccess;

    setUp(() {
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      oilService = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      oilHybrid = BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.oilChange,
        enableDebts: true,
        enableInstallments: false,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: true,
        enableRepairServices: false,
        enablePos: true,
        enableServices: true,
      );
      fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 7);
    });

    OwnerDashboardResolveInput input(BusinessSetupSettingsData f) {
      return OwnerDashboardResolveInput(features: f, access: fullAccess);
    }

    test('misconfigured general_retail + oil flags resolves oil owner preset', () {
      final misconfigured = BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.generalRetail,
        enableDebts: true,
        enableInstallments: false,
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
      expect(misconfigured.routingVertical, BusinessVertical.oilChange);
      expect(
        OwnerDashboardProfileResolver.detectProfile(misconfigured),
        OwnerDashboardProfile.oilChangeService,
      );
      final spec = OwnerDashboardProfileResolver.resolve(input(misconfigured));
      expect(spec.profile, OwnerDashboardProfile.oilChangeService);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.oilActiveCars);
      final oilKpis = OwnerKpiCatalog.entriesFor(
        features: misconfigured,
        access: fullAccess,
      ).map((e) => e.id);
      expect(oilKpis, contains(OwnerCatalogIds.oilActiveCars));
      expect(oilKpis, isNot(contains(OwnerCatalogIds.retailStockShortages)));
    });

    test('detectProfile oil service vs hybrid', () {
      expect(
        OwnerDashboardProfileResolver.detectProfile(oilService),
        OwnerDashboardProfile.oilChangeService,
      );
      expect(
        OwnerDashboardProfileResolver.detectProfile(oilHybrid),
        OwnerDashboardProfile.oilChangeHybrid,
      );
    });

    test('oil service preset hero and card order', () {
      final spec = OwnerDashboardProfileResolver.resolve(input(oilService));
      expect(spec.profile, OwnerDashboardProfile.oilChangeService);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.oilActiveCars);
      expect(spec.defaultCardOrder.first, OwnerCatalogIds.oilActiveCars);
      expect(spec.defaultCardOrder, contains(OwnerCatalogIds.debtsSummary));
      expect(spec.hybridRevenueSplit, isFalse);
    });

    test('oil hybrid preset uses revenue split hero', () {
      final spec = OwnerDashboardProfileResolver.resolve(input(oilHybrid));
      expect(spec.profile, OwnerDashboardProfile.oilChangeHybrid);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.hybridRevenueSplit);
      expect(spec.defaultCardOrder.first, OwnerCatalogIds.hybridRevenueSplit);
      expect(spec.hybridRevenueSplit, isTrue);
    });

    test('supermarket preset uses stock shortages hero', () {
      final supermarket = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
        enableDebtsCustom: true,
      );
      final spec = OwnerDashboardProfileResolver.resolve(input(supermarket));
      expect(spec.profile, OwnerDashboardProfile.supermarket);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.retailStockShortages);
      expect(spec.defaultCardOrder.first, OwnerCatalogIds.retailStockShortages);
      expect(spec.defaultCardOrder, contains(OwnerCatalogIds.retailTopSellers));
      expect(spec.morningBriefBuilderId, 'supermarket_morning_brief');
    });

    test('general retail preset mirrors supermarket retail cards', () {
      final retail = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.generalRetail,
        enableDebtsCustom: true,
      );
      expect(
        OwnerDashboardProfileResolver.detectProfile(retail),
        OwnerDashboardProfile.generalRetail,
      );
      final spec = OwnerDashboardProfileResolver.resolve(input(retail));
      expect(spec.profile, OwnerDashboardProfile.generalRetail);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.retailStockShortages);
      expect(spec.defaultCardOrder.first, OwnerCatalogIds.retailStockShortages);
      expect(spec.defaultCardOrder, contains(OwnerCatalogIds.retailTopSellers));
      expect(spec.morningBriefBuilderId, 'supermarket_morning_brief');
      expect(
        OwnerKpiCatalog.entriesFor(features: retail, access: fullAccess)
            .map((e) => e.id),
        contains(OwnerCatalogIds.retailStockShortages),
      );
    });

    test('clothing preset uses variant shortages hero', () {
      final clothing = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.clothingStore,
        enableDebtsCustom: true,
      );
      final spec = OwnerDashboardProfileResolver.resolve(input(clothing));
      expect(spec.profile, OwnerDashboardProfile.clothingStore);
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.clothingVariantShortages);
      expect(spec.defaultCardOrder.first, OwnerCatalogIds.clothingVariantShortages);
      expect(spec.defaultCardOrder, contains(OwnerCatalogIds.clothingSlowMovers));
      expect(spec.defaultCardOrder, contains(OwnerCatalogIds.clothingTopSellers));
      expect(spec.morningBriefBuilderId, 'clothing_morning_brief');
    });

    test('mergeCatalogOrder inserts hybrid card without reordering saved cards', () {
      const saved = [
        OwnerCatalogIds.oilActiveCars,
        OwnerCatalogIds.cashSummary,
      ];
      final preset = OwnerDashboardProfileResolver.resolve(input(oilHybrid));
      final order = OwnerDashboardProfileResolver.mergeCatalogOrderWithPreset(
        savedOrder: saved,
        presetOrder: preset.defaultCardOrder,
        allowedIds: {
          for (final e in OwnerKpiCatalog.entriesFor(
            features: oilHybrid,
            access: fullAccess,
          ))
            e.id,
        },
        layoutVisible: const {},
      );
      expect(order.first, OwnerCatalogIds.hybridRevenueSplit);
      expect(order.indexOf(OwnerCatalogIds.oilActiveCars), 1);
    });

    test('resolveForAccess filters financial cards for GM', () {
      final gm = OwnerDashboardAccessContext(
        tenantId: 7,
        permissions: {
          PermissionKeys.ownerKpiOperations: true,
          PermissionKeys.ownerKpiInventory: true,
          PermissionKeys.ownerKpiDebts: true,
          PermissionKeys.ownerKpiFinancial: false,
        },
      );
      final spec = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilService, access: gm),
      );
      expect(spec.defaultCardOrder, isNot(contains(OwnerCatalogIds.cashSummary)));
      expect(
        spec.defaultCardOrder,
        isNot(contains(OwnerCatalogIds.oilChangesPeriod)),
      );
      expect(spec.defaultHeroCatalogId, OwnerCatalogIds.oilActiveCars);
    });

    test('activity feed excludes loyalty when gate off', () {
      final spec = OwnerDashboardProfileResolver.resolve(input(oilService));
      expect(spec.activityFeedFilter, contains(RecentActivityKind.workShift));
      expect(spec.activityFeedFilter, isNot(contains(RecentActivityKind.loyalty)));
    });

    test('effectiveCardOrder merges layout with RBAC', () {
      final preset = OwnerDashboardProfileResolver.resolve(input(oilService));
      final gm = OwnerDashboardAccessContext(
        tenantId: 7,
        permissions: {
          PermissionKeys.ownerKpiOperations: true,
          PermissionKeys.ownerKpiFinancial: false,
          PermissionKeys.ownerKpiInventory: true,
          PermissionKeys.ownerKpiDebts: true,
        },
      );
      final order = OwnerDashboardProfileResolver.effectiveCardOrder(
        preset: preset,
        layoutOrder: [
          OwnerCatalogIds.cashSummary,
          OwnerCatalogIds.oilActiveCars,
        ],
        layoutVisible: const {},
        input: OwnerDashboardResolveInput(features: oilService, access: gm),
      );
      expect(order.first, OwnerCatalogIds.oilActiveCars);
      expect(order, isNot(contains(OwnerCatalogIds.cashSummary)));
      expect(order, isNot(contains(OwnerCatalogIds.oilChangesPeriod)));
    });

    test('shortcuts filtered by permission in resolveForAccess', () {
      final limited = OwnerDashboardAccessContext(
        tenantId: 7,
        permissions: {
          PermissionKeys.ownerKpiOperations: true,
          PermissionKeys.ownerKpiFinancial: true,
          PermissionKeys.ownerKpiInventory: true,
          PermissionKeys.ownerKpiDebts: true,
          PermissionKeys.reportsAccess: false,
          PermissionKeys.customersView: true,
          PermissionKeys.inventoryView: true,
          PermissionKeys.cashView: true,
        },
      );
      final spec = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilService, access: limited),
      );
      expect(spec.defaultShortcutIds, isNot(contains(OwnerShortcutIds.oilReport)));
      expect(spec.defaultShortcutIds, contains(OwnerShortcutIds.customers));
    });
  });
}
