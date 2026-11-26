import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../screens/inventory/inventory_products_screen.dart';
import '../../../screens/settings/dashboard_layout_settings_screen.dart';
import '../../../screens/users/user_form_screen.dart';
import '../../../screens/users/users_screen.dart';
import '../../car_wash/screens/car_wash_form_screen.dart';
import '../screens/oil_change_card_settings_screen.dart';
import '../screens/oil_change_form_screen.dart';
import '../screens/oil_change_ratings_screen.dart';
import '../screens/oil_change_service_form_screen.dart';
import '../screens/oil_change_services_screen.dart';
import '../screens/oil_change_whatsapp_connect_screen.dart';
import '../screens/oil_change_whatsapp_messages_screen.dart';
import '../screens/whatsapp_customer_queue_screen.dart';
import '../screens/whatsapp_responder_page_screen.dart';
import '../screens/oil_change_whatsapp_wallet_screen.dart';
import '../screens/oil_technicians_screen.dart';
import '../../../screens/inventory/add_product_screen.dart';
import 'oil_shell_nav.dart';

/// مسار تحتاجه الجولات الإرشادية؛ [parentRouteId] يُفتح أولاً ليعود إليه الرجوع.
class OilGuideRoute {
  const OilGuideRoute(this.builder, {this.parentRouteId});

  final WidgetBuilder builder;
  final String? parentRouteId;
}

/// شاشات لا تظهر في القائمة لكن يفتحها الإرشاد بمعرّفها.
final Map<String, OilGuideRoute> _extras = {
  AppContentRoutes.oilChangeCreate: OilGuideRoute((_) => const OilChangeFormScreen()),
  AppContentRoutes.oilWhatsappConnect: OilGuideRoute(
    (_) => const OilChangeWhatsappConnectScreen(),
    parentRouteId: AppContentRoutes.oilServicesLog,
  ),
  AppContentRoutes.oilWhatsappMessages: OilGuideRoute(
    (_) => const OilChangeWhatsappMessagesScreen(),
    parentRouteId: AppContentRoutes.oilServicesLog,
  ),
  AppContentRoutes.oilWhatsappWallet: OilGuideRoute(
    (_) => const OilChangeWhatsappWalletScreen(),
    parentRouteId: AppContentRoutes.oilWhatsappConnect,
  ),
  AppContentRoutes.oilWhatsappResponder: OilGuideRoute(
    (_) => const WhatsappResponderPageScreen(),
    parentRouteId: AppContentRoutes.oilWhatsappMessages,
  ),
  AppContentRoutes.oilWhatsappQueue: OilGuideRoute(
    (_) => const WhatsappCustomerQueueScreen(),
    parentRouteId: AppContentRoutes.oilWhatsappMessages,
  ),
  AppContentRoutes.oilRatings: OilGuideRoute(
    (_) => const OilChangeRatingsScreen(),
    parentRouteId: AppContentRoutes.oilServicesLog,
  ),
  AppContentRoutes.oilCardSettings: OilGuideRoute(
    (_) => const OilChangeCardSettingsScreen(),
    parentRouteId: AppContentRoutes.oilServicesLog,
  ),
  AppContentRoutes.oilTechnicians: OilGuideRoute(
    (_) => const OilTechniciansScreen(),
    parentRouteId: AppContentRoutes.oilCardSettings,
  ),
  AppContentRoutes.oilChangeServiceCreate: OilGuideRoute(
    (_) => const OilChangeServiceFormScreen(),
    parentRouteId: AppContentRoutes.oilChangeServices,
  ),
  AppContentRoutes.carWashCreate: OilGuideRoute((_) => const CarWashFormScreen()),
  AppContentRoutes.settingsDashboardLayout: OilGuideRoute((_) => const DashboardLayoutSettingsScreen()),
  AppContentRoutes.addProduct: OilGuideRoute(
    (_) => const AddProductScreen(),
    parentRouteId: AppContentRoutes.inventoryProducts,
  ),
  AppContentRoutes.userForm: OilGuideRoute((_) => const UserFormScreen(), parentRouteId: AppContentRoutes.users),
};

/// كل مسار يفتحه الإرشاد: يُولَّد من كتالوج القائمة ثم الشاشات الإضافية (م3-6).
final Map<String, OilGuideRoute> oilGuideRoutes = _build();

Map<String, OilGuideRoute> _build() {
  final out = <String, OilGuideRoute>{};
  for (final item in oilShellCatalog()) {
    if (item.routeId != AppContentRoutes.home) out[item.routeId] = OilGuideRoute(item.destination);
    for (final sub in [...?item.subItems]) {
      out.putIfAbsent(sub.routeId, () => OilGuideRoute(sub.destination));
    }
  }
  out.addAll(_extras);
  // ضمان لمسارات الجولات القديمة حتى لو تغيّر الكتالوج.
  out.putIfAbsent(AppContentRoutes.inventoryProducts, () => OilGuideRoute((_) => const InventoryProductsScreen()));
  out.putIfAbsent(AppContentRoutes.oilChangeServices, () => OilGuideRoute((_) => const OilChangeServicesScreen()));
  out.putIfAbsent(AppContentRoutes.users, () => OilGuideRoute((_) => const UsersScreen()));
  return out;
}
