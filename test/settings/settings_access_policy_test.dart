import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/employee_access_policy.dart';
import 'package:naboo/home/home_dashboard_resolver.dart';
import 'package:naboo/screens/settings/settings_registry.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/general_retail/manifest.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:naboo/verticals/pharmacy/manifest.dart';
import 'package:naboo/verticals/restaurant/manifest.dart';

/// المرحلة 3: بنود الإعدادات تتبع صلاحيات الموظف والتخصص عبر
/// `EmployeeAccessPolicy` الحقيقية، لا عبر دالة مزيفة.
Set<String> _visible({
  required bool owner,
  required BusinessSetupSettingsData features,
  Set<String> granted = const {},
}) {
  final policy = EmployeeAccessPolicy(
    can: (k) => owner || granted.contains(k),
    features: features,
    restricted: false,
    hiddenRouteIds: HomeDashboardResolver.resolve(features).hideNavRouteIds,
  );
  return visibleSettingsEntries(
    SettingsAccess(
      isOwner: owner,
      features: features,
      canSeeRoute: policy.isVisible,
    ),
  ).map((e) => e.id).toSet();
}

BusinessSetupSettingsData _retail() =>
    BusinessSetupSettingsData.createForVertical(
      BusinessVertical.generalRetail,
    ).copyWith(enableDebts: true, enableInstallments: true, enablePos: true);

const _staffDefault = {
  PermissionKeys.appDashboard,
  PermissionKeys.customersView,
  PermissionKeys.salesPos,
  PermissionKeys.cashView,
  PermissionKeys.inventoryView,
  PermissionKeys.debtsPanel,
  PermissionKeys.installmentsPlans,
};

void main() {
  setUpAll(() {
    final r = VerticalRegistry.instance;
    r.register(const GeneralRetailVerticalManifest());
    r.register(const OilChangeVerticalManifest());
    r.register(const PharmacyVerticalManifest());
    r.register(const RestaurantVerticalManifest());
  });

  test('الموظف بالصلاحيات الافتراضية لا يرى إعدادات المحل', () {
    final ids = _visible(
      owner: false,
      features: _retail(),
      granted: _staffDefault,
    );
    for (final id in [
      SettingsEntryIds.salePos,
      SettingsEntryIds.debtSettings,
      SettingsEntryIds.installmentSettings,
      SettingsEntryIds.inventorySettings,
      SettingsEntryIds.businessFeatures,
      SettingsEntryIds.subscription,
      SettingsEntryIds.printing,
      SettingsEntryIds.dashboardLayout,
      SettingsEntryIds.import,
    ]) {
      expect(ids, isNot(contains(id)), reason: id);
    }
    // بنود الجهاز تبقى له.
    expect(
      ids,
      containsAll([
        SettingsEntryIds.branchInfo,
        SettingsEntryIds.themeToggle,
        SettingsEntryIds.notifications,
        SettingsEntryIds.help,
        SettingsEntryIds.about,
      ]),
    );
  });

  test('صلاحية إعدادات الدين وحدها تُظهر إعدادات الدين فقط', () {
    final ids = _visible(
      owner: false,
      features: _retail(),
      granted: {..._staffDefault, PermissionKeys.debtsSettings},
    );
    expect(ids, contains(SettingsEntryIds.debtSettings));
    expect(ids, isNot(contains(SettingsEntryIds.installmentSettings)));
  });

  test('صلاحية التقسيط تحتاج لوحة التقسيط أيضاً', () {
    final ids = _visible(
      owner: false,
      features: _retail(),
      granted: {PermissionKeys.installmentsSettings},
    );
    expect(ids, isNot(contains(SettingsEntryIds.installmentSettings)));
  });

  test('صلاحية إعدادات التطبيق تُظهر نقطة البيع وميزات المتجر', () {
    final ids = _visible(
      owner: false,
      features: _retail(),
      granted: {..._staffDefault, PermissionKeys.settingsApp},
    );
    expect(
      ids,
      containsAll([
        SettingsEntryIds.salePos,
        SettingsEntryIds.businessFeatures,
        SettingsEntryIds.subscription,
        SettingsEntryIds.dashboardLayout,
      ]),
    );
  });

  test('موظف محل الزيت بلا صلاحية إعدادات التطبيق لا يرى لوحة غيار الزيت', () {
    final oil = BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
    );
    expect(
      _visible(owner: false, features: oil, granted: _staffDefault),
      isNot(contains(SettingsEntryIds.oilHub)),
    );
    expect(
      _visible(
        owner: false,
        features: oil,
        granted: {..._staffDefault, PermissionKeys.settingsApp},
      ),
      contains(SettingsEntryIds.oilHub),
    );
    expect(
      _visible(owner: true, features: oil),
      contains(SettingsEntryIds.oilHub),
    );
  });

  test('المالك يرى كل بنود تخصصه', () {
    final ids = _visible(owner: true, features: _retail());
    expect(
      ids,
      containsAll([
        SettingsEntryIds.salePos,
        SettingsEntryIds.debtSettings,
        SettingsEntryIds.installmentSettings,
        SettingsEntryIds.inventorySettings,
        SettingsEntryIds.businessFeatures,
        SettingsEntryIds.printing,
        SettingsEntryIds.import,
      ]),
    );
  });

  group('التخصص', () {
    test('المطعم لا يرى نقطة البيع ولا إعدادات المخزون', () {
      final r = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.restaurantCafe,
      );
      final ids = _visible(owner: true, features: r);
      expect(ids, isNot(contains(SettingsEntryIds.salePos)));
      expect(ids, isNot(contains(SettingsEntryIds.inventorySettings)));
      expect(ids, isNot(contains(SettingsEntryIds.oilHub)));
    });

    test('محل الزيت لا يرى الاستلام من Market', () {
      final oil = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      );
      final ids = _visible(owner: true, features: oil);
      expect(ids, isNot(contains(SettingsEntryIds.marketPickup)));
      expect(
        ids,
        containsAll([SettingsEntryIds.oilHub, SettingsEntryIds.washOffers]),
      );
    });

    test('التجزئة لا ترى بنود محل الزيت', () {
      final ids = _visible(owner: true, features: _retail());
      expect(ids, isNot(contains(SettingsEntryIds.oilHub)));
      expect(ids, isNot(contains(SettingsEntryIds.washOffers)));
    });
  });
}
