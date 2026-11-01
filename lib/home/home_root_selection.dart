import '../services/business_setup_settings.dart';

enum EmployeeHomeRoot { loading, oilChangeStandalone, shared }

/// قرار جذر الرئيسية للموظف فقط؛ يبقى قرار المالك خارج هذا العقد.
EmployeeHomeRoot resolveEmployeeHomeRoot({
  required bool featuresLoaded,
  required BusinessSetupSettingsData features,
}) {
  if (!featuresLoaded) return EmployeeHomeRoot.loading;
  if (features.routingVertical == BusinessVertical.oilChange) {
    return EmployeeHomeRoot.oilChangeStandalone;
  }
  return EmployeeHomeRoot.shared;
}
