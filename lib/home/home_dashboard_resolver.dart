import '../services/business_setup_settings.dart';
import '../verticals/_contract/vertical_registry.dart';
import 'specs/home_dashboard_spec.dart';

/// يبني [HomeDashboardSpec] من النشاط التجاري وأعلام الميزات.
abstract final class HomeDashboardResolver {
  HomeDashboardResolver._();

  static HomeDashboardSpec resolve(BusinessSetupSettingsData features) {
    // عقد VerticalManifest: اللوحة من الـmanifest النشط (oil / pharmacy / restaurant / …).
    VerticalRegistry.instance.syncActiveVertical(features);
    return VerticalRegistry.instance.activeManifest.resolveHome(features);
  }
}
