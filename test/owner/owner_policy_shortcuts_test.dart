import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_dashboard_access_context.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/owner/widgets/owner_dashboard_summary_section.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/_contract/vertical_registry.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';

/// المالك يدخل لوحته لا إعدادات المحل، فزرّا «سياسة الاسترجاع» و«عروض الغسيل»
/// يجب أن يكونا في لوحته، وعروض الغسيل لمحل الزيت فقط.
void main() {
  setUp(() {
    VerticalRegistry.instance.register(const OilChangeVerticalManifest());
  });

  List<String> ids(String vertical) {
    return OwnerDashboardSummarySection.resolveShortcuts(
      shortcutIds: const [],
      features: BusinessSetupSettingsData.createForVertical(vertical),
      access: OwnerDashboardAccessContext.fullAccess(tenantId: 7),
    ).map((e) => e.id).toList(growable: false);
  }

  test('محل الزيت: الزرّان موجودان', () {
    final oil = ids(BusinessVertical.oilChange);
    expect(oil, contains(OwnerShortcutIds.returnPolicy));
    expect(oil, contains(OwnerShortcutIds.washOffers));
  });

  test('بقية التخصصات: سياسة الاسترجاع فقط بلا عروض الغسيل', () {
    for (final v in [
      BusinessVertical.supermarket,
      BusinessVertical.generalRetail,
      BusinessVertical.clothingStore,
      BusinessVertical.restaurantCafe,
      BusinessVertical.pharmacy,
    ]) {
      final got = ids(v);
      expect(got, contains(OwnerShortcutIds.returnPolicy), reason: v);
      expect(got, isNot(contains(OwnerShortcutIds.washOffers)), reason: v);
    }
  });
}
