import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/owner_dashboard_studio_resolver.dart';
import 'package:naboo/owner/owner_dashboard_profile_resolver.dart';
import 'package:naboo/owner/services/owner_dashboard_studio_store.dart';
import 'package:naboo/owner/models/owner_alert_settings.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OwnerDashboardStudioResolver', () {
    late BusinessSetupSettingsData oilService;
    late OwnerDashboardAccessContext fullAccess;

    setUp(() {
      VerticalRegistry.instance.register(const OilChangeVerticalManifest());
      oilService = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
        enableDebtsCustom: true,
      );
      fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 1);
    });

    test('falls back to preset hero when saved hero is not allowed', () {
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilService, access: fullAccess),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(
          heroCatalogId: 'invalid_hero',
          shortcutIds: const ['sc_oil_report'],
        ),
        input: OwnerDashboardResolveInput(features: oilService, access: fullAccess),
      );
      expect(effective.heroCatalogId, OwnerCatalogIds.oilActiveCars);
      expect(effective.shortcutIds, contains(OwnerShortcutIds.oilReport));
    });

    test('filters shortcuts by RBAC', () {
      final gmAccess = OwnerDashboardAccessContext(
        tenantId: 1,
        permissions: {
          PermissionKeys.ownerKpiOperations: true,
          PermissionKeys.ownerKpiFinancial: false,
          PermissionKeys.reportsAccess: false,
        },
      );
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilService, access: gmAccess),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: OwnerDashboardStudioRaw(
          shortcutIds: [
            OwnerShortcutIds.oilReport,
            OwnerShortcutIds.cash,
          ],
        ),
        input: OwnerDashboardResolveInput(features: oilService, access: gmAccess),
      );
      expect(effective.shortcutIds, isNot(contains(OwnerShortcutIds.oilReport)));
    });

    test('reset card order when saved order has only invalid ids', () {
      final preset = OwnerDashboardProfileResolver.resolveForAccess(
        OwnerDashboardResolveInput(features: oilService, access: fullAccess),
      );
      final effective = OwnerDashboardStudioResolver.resolve(
        preset: preset,
        saved: const OwnerDashboardStudioRaw(
          catalogCardOrder: ['bogus_card'],
          catalogCardVisible: {'bogus_card': true},
        ),
        input: OwnerDashboardResolveInput(features: oilService, access: fullAccess),
      );
      expect(effective.cardOrder, isNotEmpty);
      expect(effective.cardOrder.first, OwnerCatalogIds.oilActiveCars);
    });
  });

  group('OwnerDashboardStudioStore', () {
    test('persists v3 beta in app_settings per tenant', () async {
      final dh = DatabaseHelper();
      await dh.closeAndDeleteDatabaseFile();
      final store = OwnerDashboardStudioStore();
      await store.save(
        tenantId: 3,
        raw: const OwnerDashboardStudioRaw(v3Beta: true, heroCatalogId: 'oil_active_cars'),
      );
      final loaded = await store.load(tenantId: 3);
      expect(loaded.v3Beta, isTrue);
      expect(loaded.heroCatalogId, 'oil_active_cars');

      final repo = AppSettingsRepository.instance;
      final raw = await repo.getForTenant(
        OwnerDashboardStudioKeys.v3Beta,
        tenantId: 3,
      );
      expect(raw, '1');
      await dh.closeAndDeleteDatabaseFile();
    });

    test('persists alert settings JSON per tenant', () async {
      final dh = DatabaseHelper();
      await dh.closeAndDeleteDatabaseFile();
      final store = OwnerDashboardStudioStore();
      await store.save(
        tenantId: 9,
        raw: OwnerDashboardStudioRaw(
          alertSettings: OwnerAlertSettings(
            thresholds: const OwnerAlertThresholds(stockShortageMinCount: 4),
          ),
        ),
      );
      final loaded = await store.load(tenantId: 9);
      expect(loaded.alertSettings.thresholds.stockShortageMinCount, 4);
      await dh.closeAndDeleteDatabaseFile();
    });
  });
}
