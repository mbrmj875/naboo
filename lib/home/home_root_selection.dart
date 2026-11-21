import '../services/business_setup_settings.dart';

enum EmployeeHomeRoot { loading, oilChangeStandalone, shared }

/// الغلاف الزيتي مغلق حتى يُجرَّب على جهاز حقيقي بحساب موظف.
const bool kOilChangeStandaloneHomeEnabled = false;

/// قرار جذر الرئيسية للموظف فقط؛ يبقى قرار المالك خارج هذا العقد.
EmployeeHomeRoot resolveEmployeeHomeRoot({
  required bool featuresLoaded,
  required BusinessSetupSettingsData features,
  bool standaloneEnabled = kOilChangeStandaloneHomeEnabled,
}) {
  if (!featuresLoaded) return EmployeeHomeRoot.loading;
  if (standaloneEnabled &&
      features.routingVertical == BusinessVertical.oilChange) {
    return EmployeeHomeRoot.oilChangeStandalone;
  }
  return EmployeeHomeRoot.shared;
}
