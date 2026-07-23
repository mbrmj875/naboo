import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/owner_action_alert_resolver.dart';
import 'package:naboo/owner/models/owner_action_alert.dart';
import 'package:naboo/owner/models/owner_alert_settings.dart';
import 'package:naboo/owner/owner_dashboard_profile_resolver.dart';
import 'package:naboo/owner/owner_dashboard_studio_resolver.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/owner/providers/owner_dashboard_studio_provider.dart';
import 'package:naboo/owner/services/owner_dashboard_studio_store.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/owner/widgets/owner_dashboard_v3_panel.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';

import '../mocks/owner_mock_repositories.dart';

const _oilCatalogIds = [
  OwnerCatalogIds.oilActiveCars,
  OwnerCatalogIds.oilChangesPeriod,
  OwnerCatalogIds.oilStockShortages,
  OwnerCatalogIds.oilAvgTicket,
  OwnerCatalogIds.hybridRevenueSplit,
  OwnerCatalogIds.debtsSummary,
  OwnerCatalogIds.openShifts,
  OwnerCatalogIds.cashSummary,
  OwnerCatalogIds.inventoryValue,
];

void main() {
  group('S6 regression — vertical isolation', () {
    late OwnerDashboardAccessContext fullAccess;

    setUp(() {
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 1);
    });

    test('supermarket catalog never exposes oil workshop cards', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
        enableDebtsCustom: true,
      );
      final ids = OwnerKpiCatalog.entriesFor(
        features: features,
        access: fullAccess,
      ).map((e) => e.id).toList();
      expect(ids, isNotEmpty);
      for (final oilId in _oilCatalogIds) {
        expect(ids, isNot(contains(oilId)));
      }
    });

    test('clothing store catalog never exposes oil workshop cards', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.clothingStore,
      );
      final ids = OwnerKpiCatalog.entriesFor(
        features: features,
        access: fullAccess,
      ).map((e) => e.id).toList();
      expect(ids, isNotEmpty);
      for (final oilId in _oilCatalogIds) {
        expect(ids, isNot(contains(oilId)));
      }
      expect(ids, isNot(contains(OwnerCatalogIds.retailStockShortages)));
    });

    test('studio resolver strips invalid saved oil prefs on non-oil vertical', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
      );
      final preset = OwnerDashboardProfileSpec(
        profile: OwnerDashboardProfile.supermarket,
        defaultCardOrder: const [OwnerCatalogIds.oilActiveCars],
        defaultHeroCatalogId: OwnerCatalogIds.oilActiveCars,
        defaultShortcutIds: const [OwnerShortcutIds.oilReport],
        activityFeedFilter: const {},
        morningBriefBuilderId: '',
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(
          heroCatalogId: OwnerCatalogIds.oilActiveCars,
          shortcutIds: [OwnerShortcutIds.oilReport],
          catalogCardOrder: [OwnerCatalogIds.oilActiveCars],
        ),
        input: OwnerDashboardResolveInput(features: features, access: fullAccess),
      );
      expect(effective.cardOrder, isEmpty);
      expect(effective.shortcutIds, isEmpty);
    });
  });

  group('S6 regression — v2 / beta isolation', () {
    late FakeOwnerCommandCenterRepository repo;
    late OwnerCommandCenterProvider center;

    setUp(() {
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      repo = FakeOwnerCommandCenterRepository();
      center = OwnerCommandCenterProvider(repository: repo);
    });

    tearDown(() {
      center.dispose();
    });

    test('v3 resolves oil_change preset regardless of saved beta flag', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      final access = OwnerDashboardAccessContext.fullAccess(tenantId: 3);
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: features, access: access),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(v3Beta: false),
        input: OwnerDashboardResolveInput(features: features, access: access),
      );
      expect(preset.profile, OwnerDashboardProfile.oilChangeService);
      expect(effective.cardOrder, isNotEmpty);
      expect(effective.heroCatalogId, OwnerCatalogIds.oilActiveCars);
    });

    test('v3 guard resolves supermarket preset when beta on', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
        enableDebtsCustom: true,
      );
      final access = OwnerDashboardAccessContext.fullAccess(tenantId: 3);
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: features, access: access),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(v3Beta: true),
        input: OwnerDashboardResolveInput(features: features, access: access),
      );
      expect(preset.profile, OwnerDashboardProfile.supermarket);
      expect(effective.heroCatalogId, OwnerCatalogIds.retailStockShortages);
      expect(effective.cardOrder, contains(OwnerCatalogIds.retailTopSellers));
    });

    test('v3 guard resolves clothing preset when beta on', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.clothingStore,
        enableDebtsCustom: true,
      );
      final access = OwnerDashboardAccessContext.fullAccess(tenantId: 4);
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: features, access: access),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(v3Beta: true),
        input: OwnerDashboardResolveInput(features: features, access: access),
      );
      expect(preset.profile, OwnerDashboardProfile.clothingStore);
      expect(effective.heroCatalogId, OwnerCatalogIds.clothingVariantShortages);
      expect(effective.cardOrder, contains(OwnerCatalogIds.clothingSlowMovers));
      expect(effective.cardOrder, contains(OwnerCatalogIds.clothingTopSellers));
    });

    test('v3 guard resolves oil_change preset when beta on', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      final access = OwnerDashboardAccessContext.fullAccess(tenantId: 3);
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: features, access: access),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(v3Beta: true),
        input: OwnerDashboardResolveInput(features: features, access: access),
      );
      expect(preset.profile, OwnerDashboardProfile.oilChangeService);
      expect(effective.cardOrder, isNotEmpty);
      expect(effective.heroCatalogId, OwnerCatalogIds.oilActiveCars);
    });
  });

  group('S6 hybrid profile transition', () {
    late BusinessSetupSettingsData oilService;
    late BusinessSetupSettingsData oilHybrid;
    late OwnerDashboardAccessContext fullAccess;

    setUp(() {
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      oilService = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      oilHybrid = _copyWithPos(oilService, enablePos: true);
      fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 9);
    });

    test('detectProfile upgrades service to hybrid when POS enabled', () {
      expect(
        OwnerDashboardProfileResolver.detectProfile(oilService),
        OwnerDashboardProfile.oilChangeService,
      );
      expect(
        OwnerDashboardProfileResolver.detectProfile(oilHybrid),
        OwnerDashboardProfile.oilChangeHybrid,
      );
    });

    test('mergeCatalogOrder preserves saved order and prepends revenue split', () {
      const savedOrder = [
        OwnerCatalogIds.oilActiveCars,
        OwnerCatalogIds.oilChangesPeriod,
        OwnerCatalogIds.cashSummary,
      ];
      final hybridPreset = OwnerDashboardProfileResolver.resolve(
        OwnerDashboardResolveInput(features: oilHybrid, access: fullAccess),
      );

      final merged = OwnerDashboardProfileResolver.mergeCatalogOrderWithPreset(
        savedOrder: savedOrder,
        presetOrder: hybridPreset.defaultCardOrder,
        allowedIds: OwnerKpiCatalog.entriesFor(
          features: oilHybrid,
          access: fullAccess,
        ).map((e) => e.id).toSet(),
        layoutVisible: const {},
      );

      expect(merged.first, OwnerCatalogIds.hybridRevenueSplit);
      expect(merged.indexOf(OwnerCatalogIds.oilActiveCars), 1);
      expect(merged.indexOf(OwnerCatalogIds.oilChangesPeriod), 2);
      expect(merged.indexOf(OwnerCatalogIds.cashSummary), greaterThan(2));
    });

    test('saved hero kept when enabling POS if still eligible', () {
      final hybridPreset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilHybrid, access: fullAccess),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: hybridPreset,
        saved: const OwnerDashboardStudioRaw(
          heroCatalogId: OwnerCatalogIds.oilActiveCars,
          catalogCardOrder: [
            OwnerCatalogIds.oilActiveCars,
            OwnerCatalogIds.oilChangesPeriod,
          ],
        ),
        input: OwnerDashboardResolveInput(features: oilHybrid, access: fullAccess),
      );
      expect(effective.heroCatalogId, OwnerCatalogIds.oilActiveCars);
      expect(effective.cardOrder.first, OwnerCatalogIds.hybridRevenueSplit);
    });
  });

  group('S9 regression — Action Rail', () {
    test('oil stale garage alert is critical with openOilLog action', () {
      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.oilChangeService,
        features: BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
        ),
        snapshot: OwnerCommandCenterSnapshot(
          oilActiveCars: OwnerSectionResult.success(
            const OilActiveCarsKpi(activeCount: 2, staleWaitingCount: 1),
            DateTime(2026, 5, 28),
          ),
        ),
      );
      expect(alerts.first.priority, OwnerAlertPriority.critical);
      expect(alerts.first.actionKind, OwnerActionKind.openOilLog);
    });
  });

  group('S10 regression — thresholds and push payload', () {
    test('alert settings server payload includes push ids and thresholds', () {
      final settings = OwnerAlertSettings(
        thresholds: const OwnerAlertThresholds(stockShortageMinCount: 4),
        channels: OwnerAlertChannelPrefs(
          byAlertId: {
            OwnerActionAlertIds.retailStockShortage: OwnerAlertChannelPref(
              enablePush: true,
            ),
          },
        ),
      );
      final payload = settings.toServerSyncPayload(
        businessVertical: 'supermarket',
        enableDebts: true,
        enableInstallments: true,
      );
      expect(payload['thresholds'], isA<Map>());
      expect(payload['featureFlags'], isA<Map>());
      expect(
        (payload['pushAlertIds'] as List).cast<String>(),
        contains(OwnerActionAlertIds.retailStockShortage),
      );
    });

    test('high stock threshold suppresses retail shortage in Action Rail', () {
      final alerts = OwnerActionAlertResolver.resolve(
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
        thresholds: const OwnerAlertThresholds(stockShortageMinCount: 5),
      );
      expect(alerts, isEmpty);
    });
  });
}

BusinessSetupSettingsData _copyWithPos(
  BusinessSetupSettingsData base, {
  required bool enablePos,
}) {
  return BusinessSetupSettingsData(
    onboardingCompleted: base.onboardingCompleted,
    businessVertical: base.businessVertical,
    enableDebts: base.enableDebts,
    enableInstallments: base.enableInstallments,
    enableWeightSales: base.enableWeightSales,
    enableCustomers: base.enableCustomers,
    enableLoyalty: base.enableLoyalty,
    enableTaxOnSale: base.enableTaxOnSale,
    enableInvoiceDiscount: base.enableInvoiceDiscount,
    enableClothingVariants: base.enableClothingVariants,
    enableOilChange: base.enableOilChange,
    enableRepairServices: base.enableRepairServices,
    enablePos: enablePos,
      enableCarWash: false,
    enableServices: base.enableServices,
  );
}

class _StudioStub extends OwnerDashboardStudioProvider {
  _StudioStub({
    required this.beta,
    required this.loaded,
    int tenantId = 1,
  }) : super(tenantId: tenantId);

  final bool beta;
  @override
  final bool loaded;

  @override
  bool get v3BetaEnabled => beta;
}
