import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/services/inventory_policy_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_owner_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyVerticalManifest', () {
    const manifest = PharmacyVerticalManifest();

    test('id is pharmacy', () {
      expect(manifest.id, BusinessVertical.pharmacy);
    });

    test('inventoryPolicy uses pharmacy business profile key', () {
      expect(manifest.inventoryPolicy.businessProfileKey, 'pharmacy');
      final settings = manifest.inventoryPolicy.toSettingsDefaults();
      expect(settings.businessProfile, BusinessProfile.pharmacy.key);
    });

    test('defaultFeatures match pharmacy vertical', () {
      final features = manifest.defaultFeatures.settings;
      expect(features.businessVertical, BusinessVertical.pharmacy);
      expect(features.enablePos, isTrue);
      expect(features.enableOilChange, isFalse);
    });

    test('resolveHome returns pharmacy greeting', () {
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.pharmacy,
      );
      final home = manifest.resolveHome(features);
      expect(home.greetingEmoji, '💊');
      expect(home.greetingSubtitle, contains('الصيدلية'));
    });

    test('pharmacy editor session is available from manifest', () {
      final session = manifest.pharmacyProductEditor!.createSession();
      expect(session, isA<PharmacyProductEditorSession>());
      expect(session.validateForSave(), isNotNull);
      session.dispose();
    });

    test('oil manifest keeps pharmacy editor null', () {
      const oil = OilChangeVerticalManifest();
      expect(oil.pharmacyProductEditor, isNull);
    });

    test('registry resolves pharmacy manifest after register', () {
      VerticalRegistry.instance.register(const PharmacyVerticalManifest());
      final resolved =
          VerticalRegistry.instance.manifestFor(BusinessVertical.pharmacy);
      expect(resolved, isA<PharmacyVerticalManifest>());
    });

    test('resolveOwner returns pharmacy profile preset', () {
      const manifest = PharmacyVerticalManifest();
      final features = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.pharmacy,
      );
      final spec = manifest.resolveOwner(features);
      expect(spec, isNotNull);
      expect(spec!.profile, OwnerDashboardProfile.pharmacy);
      expect(spec.defaultCardOrder, isNotEmpty);
    });

    test('report sections include pharmacy section 9', () {
      const manifest = PharmacyVerticalManifest();
      expect(manifest.reportSections, hasLength(1));
      expect(manifest.reportSections.single.sectionId, 9);
      expect(manifest.pharmacyReportSections, hasLength(4));
    });

    test('buildOwnerVerticalDashboardPanel is non-null', () {
      const manifest = PharmacyVerticalManifest();
      expect(manifest.buildOwnerVerticalDashboardPanel(), isNotNull);
    });

    test('loadOwnerDashboard returns 12 KPI entries', () async {
      VerticalRegistry.instance.register(const PharmacyVerticalManifest());
      final dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      addTearDown(() async => dbHelper.closeAndDeleteDatabaseFile());
      final catalog = DrugCatalogRepository(db: dbHelper, scheduleSync: () {});
      await catalog.ensureSchema();

      const manifest = PharmacyVerticalManifest();
      final dash = await manifest.loadOwnerDashboard(tenantId: 1);
      expect(dash, isA<PharmacyOwnerDashboard>());
      expect(dash!.kpiEntries, hasLength(12));
    });
  });
}
