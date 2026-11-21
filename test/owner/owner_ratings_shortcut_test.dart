import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/owner/widgets/owner_dashboard_summary_section.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';

/// «تقييمات الفنيين» انتقل من شريط سجل الغيارات إلى لوحة صاحب العمل.
void main() {
  late BusinessSetupSettingsData oil;
  late BusinessSetupSettingsData retail;
  late OwnerDashboardAccessContext fullAccess;

  setUp(() {
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
    oil = BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
    );
    retail = BusinessSetupSettingsData.createForVertical(
      BusinessVertical.supermarket,
    );
    fullAccess = OwnerDashboardAccessContext.fullAccess(tenantId: 7);
  });

  List<String> resolvedIds(BusinessSetupSettingsData features) {
    return OwnerDashboardSummarySection.resolveShortcuts(
      shortcutIds: const [],
      features: features,
      access: fullAccess,
    ).map((e) => e.id).toList(growable: false);
  }

  test('اختصار التقييمات يظهر لصاحب محل غيار الزيت', () {
    expect(resolvedIds(oil), contains(OwnerShortcutIds.oilRatings));
  });

  test('اختصار التقييمات يأتي بعد إدارة المستخدمين', () {
    final ids = resolvedIds(oil);
    expect(
      ids.indexOf(OwnerShortcutIds.oilRatings),
      greaterThan(ids.indexOf(OwnerShortcutIds.users)),
    );
  });

  test('لا يظهر لأنشطة غير غيار الزيت', () {
    expect(resolvedIds(retail), isNot(contains(OwnerShortcutIds.oilRatings)));
  });

  test('اختصار التقييمات يفتح شاشة التقييمات', () {
    final entry = OwnerKpiCatalog.shortcutsFor(
      features: oil,
      access: fullAccess,
    ).firstWhere((e) => e.id == OwnerShortcutIds.oilRatings);
    expect(entry.routeId, 'oil_change_ratings');
  });

  test('يختفي عند إطفاء ميزة غيار الزيت', () {
    final noOil = BusinessSetupSettingsData(
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
      enableOilChange: false,
      enableRepairServices: false,
      enablePos: true,
      enableServices: true,
    );
    expect(resolvedIds(noOil), isNot(contains(OwnerShortcutIds.oilRatings)));
  });
}
