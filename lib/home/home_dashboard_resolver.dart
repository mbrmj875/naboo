import '../services/business_setup_settings.dart';
import '../verticals/_contract/vertical_registry.dart';
import 'specs/home_dashboard_spec.dart';

/// يبني [HomeDashboardSpec] من النشاط التجاري وأعلام الميزات.
abstract final class HomeDashboardResolver {
  HomeDashboardResolver._();

  static HomeDashboardSpec resolve(BusinessSetupSettingsData features) {
    final manifest =
        VerticalRegistry.instance.manifestFor(BusinessVertical.oilChange);
    if (manifest != null && features.enableOilChange) {
      return manifest.resolveHome(features);
    }

    return const HomeDashboardSpec(
      profile: HomeDashboardProfile.retail,
      greetingSubtitle: 'إليك ملخص أعمال اليوم',
      greetingEmoji: '👋',
    );
  }
}
