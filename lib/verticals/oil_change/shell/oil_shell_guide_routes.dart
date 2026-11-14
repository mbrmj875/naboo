import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../screens/inventory/add_product_screen.dart';
import '../../../screens/inventory/inventory_products_screen.dart';
import '../../../screens/settings/dashboard_layout_settings_screen.dart';
import '../../../screens/users/employee_identity_screen.dart';
import '../../../screens/users/staff_shifts_week_screen.dart';
import '../../../screens/users/user_form_screen.dart';
import '../../../screens/users/users_screen.dart';
import '../../car_wash/screens/car_wash_form_screen.dart';
import '../screens/oil_change_form_screen.dart';
import '../screens/oil_change_hub_screen.dart';
import '../screens/oil_change_services_screen.dart';
import '../screens/oil_change_whatsapp_connect_screen.dart';

/// مسار تحتاجه الجولات الإرشادية؛ [parentRouteId] يُفتح أولاً ليعود إليه الرجوع.
class OilGuideRoute {
  const OilGuideRoute(this.builder, {this.parentRouteId});

  final WidgetBuilder builder;
  final String? parentRouteId;
}

/// كل مسار تطلبه جولات الزيت والمخزون والموظفين.
final Map<String, OilGuideRoute> oilGuideRoutes = {
  AppContentRoutes.oilServicesLog: OilGuideRoute(
    (_) => const OilChangeHubScreen(),
  ),
  AppContentRoutes.oilChangeCreate: OilGuideRoute(
    (_) => const OilChangeFormScreen(),
  ),
  AppContentRoutes.oilChangeServices: OilGuideRoute(
    (_) => const OilChangeServicesScreen(),
  ),
  AppContentRoutes.oilWhatsappConnect: OilGuideRoute(
    (_) => const OilChangeWhatsappConnectScreen(),
    parentRouteId: AppContentRoutes.oilServicesLog,
  ),
  AppContentRoutes.carWashCreate: OilGuideRoute(
    (_) => const CarWashFormScreen(),
  ),
  AppContentRoutes.settingsDashboardLayout: OilGuideRoute(
    (_) => const DashboardLayoutSettingsScreen(),
  ),
  AppContentRoutes.inventoryProducts: OilGuideRoute(
    (_) => const InventoryProductsScreen(),
  ),
  AppContentRoutes.addProduct: OilGuideRoute(
    (_) => const AddProductScreen(),
    parentRouteId: AppContentRoutes.inventoryProducts,
  ),
  AppContentRoutes.users: OilGuideRoute((_) => const UsersScreen()),
  AppContentRoutes.userForm: OilGuideRoute(
    (_) => const UserFormScreen(),
    parentRouteId: AppContentRoutes.users,
  ),
  AppContentRoutes.staffShiftsWeek: OilGuideRoute(
    (_) => const StaffShiftsWeekScreen(),
  ),
  AppContentRoutes.employeeIdentity: OilGuideRoute(
    (_) => const EmployeeIdentityScreen(),
  ),
};
