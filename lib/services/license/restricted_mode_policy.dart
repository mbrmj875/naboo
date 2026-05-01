import '../../navigation/content_navigation.dart';

/// سياسة مركزية للوضع المقيّد (Restricted Mode).
///
/// الهدف: منع تشتّت "whitelist" بين الشاشات. أي UI يسأل هذه السياسة بدل
/// اتخاذ قرار محلي غير متسق.
class RestrictedModePolicy {
  const RestrictedModePolicy._();

  static bool isRouteAllowed(String routeId) {
    // مسارات البيع والمرتجع وملفات العميل والطباعة فقط.
    if (routeId == AppContentRoutes.invoices) return true;
    if (routeId == AppContentRoutes.addInvoice) return true;
    if (routeId == AppContentRoutes.parkedSales) return true;
    if (routeId.startsWith('app_process_return_')) return true;
    if (routeId == AppContentRoutes.customers) return true;
    if (routeId == AppContentRoutes.customerContacts) return true;
    if (routeId == AppContentRoutes.printing) return true;

    return false;
  }
}

