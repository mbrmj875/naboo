import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_dashboard_resolver.dart';
import 'package:naboo/home/specs/home_dashboard_spec.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/general_retail/manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';

/// مصفوفة سلوك التخصصات — مبنية على الكود الفعلي (manifest + registry).
///
/// لا تختبر شاشات كاملة هنا؛ تختبر «عقد» التخصص الذي تستهلكه الشاشات المشتركة.
void main() {
  setUp(() {
    VerticalRegistry.instance.register(const GeneralRetailVerticalManifest());
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
    VerticalRegistry.instance.register(const PharmacyVerticalManifest());
  });

  BusinessSetupSettingsData settings(String vertical) =>
      BusinessSetupSettingsData.createForVertical(vertical);

  void sync(String vertical) =>
      VerticalRegistry.instance.syncActiveVertical(settings(vertical));

  group('manifest contracts — pharmacy', () {
    const manifest = PharmacyVerticalManifest();

    test('has pharmacy product editor hook', () {
      expect(manifest.pharmacyProductEditor, isNotNull);
    });

    test('has no fluid inventory editor', () {
      expect(manifest.fluidInventoryEditor, isNull);
    });

    test('nav adds pharmacy invoices module', () {
      expect(manifest.navModules, hasLength(1));
      expect(manifest.navModules.single.title, 'فواتير الصيدلية');
    });

    test('reports section 9 only for pharmacy vertical', () {
      expect(manifest.reportSections.single.sectionId, 9);
      expect(manifest.pharmacyReportSections, hasLength(4));
    });

    test('owner panel and pharmacy profile', () {
      final spec = manifest.resolveOwner(settings(BusinessVertical.pharmacy));
      expect(spec?.profile, OwnerDashboardProfile.pharmacy);
      expect(manifest.buildOwnerVerticalDashboardPanel(), isNotNull);
    });

    test('inventory policy key is pharmacy', () {
      expect(manifest.inventoryPolicy.businessProfileKey, 'pharmacy');
    });

    test('default features: POS on, oil off', () {
      final f = manifest.defaultFeatures.settings;
      expect(f.enablePos, isTrue);
      expect(f.enableOilChange, isFalse);
    });
  });

  group('manifest contracts — oil_change', () {
    const manifest = OilChangeVerticalManifest();

    test('has fluid editor, no pharmacy editor', () {
      expect(manifest.fluidInventoryEditor, isNotNull);
      expect(manifest.pharmacyProductEditor, isNull);
    });

    test('nav module is oil services log with sub-items', () {
      expect(manifest.navModules.single.title, 'سجل غيارات الزيت');
      expect(manifest.navModules.single.subItems, isNotNull);
      expect(manifest.navModules.single.subItems!.length, greaterThanOrEqualTo(3));
    });

    test('reports section 8', () {
      expect(manifest.reportSections.single.sectionId, 8);
    });

    test('service-only home hides sale glance and POS tiles', () {
      final home = manifest.resolveHome(settings(BusinessVertical.oilChange));
      expect(home.profile, HomeDashboardProfile.oilChangeService);
      expect(home.showOilKpiGrid, isTrue);
      expect(home.hideGlanceIds, contains('sale'));
      expect(home.hideGlanceIds, contains('stock'));
      expect(home.hideNavRouteIds, contains(AppContentRoutes.onlineOrders));
      expect(home.showPinnedProducts, isFalse);
    });

    test('hybrid home shows quick sale when enablePos', () {
      final hybrid = settings(BusinessVertical.oilChange).copyWith(enablePos: true);
      final home = manifest.resolveHome(hybrid);
      expect(home.profile, HomeDashboardProfile.oilChangeHybrid);
      expect(home.showPinnedProducts, isTrue);
      expect(
        home.secondaryTiles.any((t) => t.id == 'hybrid_sale'),
        isTrue,
      );
    });

    test('owner service profile vs hybrid profile', () {
      final serviceSpec = manifest.resolveOwner(settings(BusinessVertical.oilChange));
      expect(serviceSpec?.profile, OwnerDashboardProfile.oilChangeService);

      final hybridSpec = manifest.resolveOwner(
        settings(BusinessVertical.oilChange).copyWith(enablePos: true),
      );
      expect(hybridSpec?.profile, OwnerDashboardProfile.oilChangeHybrid);
      expect(hybridSpec?.hybridRevenueSplit, isTrue);
    });
  });

  group('manifest contracts — general_retail', () {
    const manifest = GeneralRetailVerticalManifest();

    test('no vertical-specific nav, routes, editors, or reports', () {
      expect(manifest.navModules, isEmpty);
      expect(manifest.routes, isEmpty);
      expect(manifest.pharmacyProductEditor, isNull);
      expect(manifest.fluidInventoryEditor, isNull);
      expect(manifest.reportSections, isEmpty);
      expect(manifest.buildOwnerVerticalDashboardPanel(), isNull);
    });

    test('retail home profile with pinned products when POS enabled', () {
      final home = manifest.resolveHome(settings(BusinessVertical.generalRetail));
      expect(home.profile, HomeDashboardProfile.retail);
      expect(home.showOilKpiGrid, isFalse);
      expect(home.showPinnedProducts, isTrue);
    });

    test('owner uses generalRetail profile', () {
      final spec = manifest.resolveOwner(settings(BusinessVertical.generalRetail));
      expect(spec?.profile, OwnerDashboardProfile.generalRetail);
    });
  });

  group('VerticalRegistry active manifest', () {
    test('pharmacy active → pharmacy hooks available', () {
      sync(BusinessVertical.pharmacy);
      expect(VerticalRegistry.instance.activeManifest.id, BusinessVertical.pharmacy);
      expect(VerticalRegistry.instance.activeManifest.pharmacyProductEditor, isNotNull);
      expect(VerticalRegistry.instance.activeManifest.fluidInventoryEditor, isNull);
    });

    test('oil_change active → fluid editor via manifestFor (not activeManifest)', () {
      sync(BusinessVertical.oilChange);
      expect(VerticalRegistry.instance.activeManifest.pharmacyProductEditor, isNull);
      expect(
        VerticalRegistry.instance
            .manifestFor(BusinessVertical.oilChange)
            ?.fluidInventoryEditor,
        isNotNull,
      );
    });

    test('general_retail active → no vertical hooks', () {
      sync(BusinessVertical.generalRetail);
      final m = VerticalRegistry.instance.activeManifest;
      expect(m.pharmacyProductEditor, isNull);
    });
  });

  group('HomeDashboardResolver — actual runtime behavior', () {
    test('oil_change uses oil manifest home', () {
      final spec = HomeDashboardResolver.resolve(settings(BusinessVertical.oilChange));
      expect(spec.isOilProfile, isTrue);
      expect(spec.showOilKpiGrid, isTrue);
    });

    test('pharmacy currently falls through to generic retail home (known gap)', () {
      final spec = HomeDashboardResolver.resolve(settings(BusinessVertical.pharmacy));
      // PharmacyVerticalManifest.resolveHome has 💊 greeting but resolver ignores it today.
      expect(spec.isOilProfile, isFalse);
      expect(spec.greetingEmoji, '👋');
      expect(spec.greetingSubtitle, 'إليك ملخص أعمال اليوم');
    });

    test('general_retail uses generic retail home', () {
      final spec = HomeDashboardResolver.resolve(settings(BusinessVertical.generalRetail));
      expect(spec.isOilProfile, isFalse);
      expect(spec.showOilKpiGrid, isFalse);
    });
  });

  group('add_product vertical hooks (unit)', () {
    test('pharmacy active exposes pharmacy session hook', () {
      sync(BusinessVertical.pharmacy);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNotNull,
      );
    });

    test('retail active has no pharmacy editor on active manifest', () {
      sync(BusinessVertical.generalRetail);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNull,
      );
    });

    test('oil_change active has no pharmacy editor on active manifest', () {
      sync(BusinessVertical.oilChange);
      expect(
        VerticalRegistry.instance.activeManifest.pharmacyProductEditor,
        isNull,
      );
    });

    test('fluid editor always resolved from oil manifest (not active vertical)', () {
      sync(BusinessVertical.pharmacy);
      expect(
        VerticalRegistry.instance
            .manifestFor(BusinessVertical.oilChange)
            ?.fluidInventoryEditor,
        isNotNull,
      );
    });
  });
}
