import '../navigation/content_navigation.dart';
import '../services/business_setup_settings.dart';
import '../services/license/restricted_mode_policy.dart';
import '../services/permission_service.dart';

/// قرار وصول الموظف إلى مسار — مكان واحد للصلاحيات والميزات والوضع المقيّد،
/// فلا يعتمد الأمان على تذكّر كل شاشة أو قائمة تطبيق هذه الشروط.
class EmployeeAccessPolicy {
  const EmployeeAccessPolicy({
    required this.can,
    required this.features,
    required this.restricted,
    this.hiddenRouteIds = const {},
  });

  final bool Function(String key) can;
  final BusinessSetupSettingsData features;
  final bool restricted;

  /// مسارات يخفيها التخصص من التنقل (`HomeDashboardSpec.hideNavRouteIds`).
  final Set<String> hiddenRouteIds;

  static String? permissionKeyForRoute(String routeId) {
    if (routeId.startsWith(AppContentRoutes.reportsPrefix)) {
      return PermissionKeys.reportsAccess;
    }
    switch (routeId) {
      case AppContentRoutes.invoices:
        return PermissionKeys.salesPos;
      case AppContentRoutes.customers:
        return PermissionKeys.customersView;
      case AppContentRoutes.loyaltySettings:
        return PermissionKeys.loyaltyAccess;
      case AppContentRoutes.installments:
        return PermissionKeys.installmentsPlans;
      case AppContentRoutes.debts:
        return PermissionKeys.debtsPanel;
      case AppContentRoutes.inventory:
        return PermissionKeys.inventoryView;
      case AppContentRoutes.cash:
        return PermissionKeys.cashView;
      case AppContentRoutes.printing:
        return PermissionKeys.printingAccess;
      default:
        return null;
    }
  }

  bool blockedByRestrictedMode(String routeId) =>
      restricted && !RestrictedModePolicy.isRouteAllowed(routeId);

  bool canOpen(String routeId) {
    if (hiddenRouteIds.contains(routeId)) return false;
    if (isContentRouteBlocked(routeId, features)) return false;
    if (blockedByRestrictedMode(routeId)) return false;
    final key = permissionKeyForRoute(routeId);
    return key == null || can(key);
  }
}
