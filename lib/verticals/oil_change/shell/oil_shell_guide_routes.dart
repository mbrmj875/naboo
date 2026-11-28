import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../notifications/ui/push_recipients_screen.dart';
import '../../../notifications/ui/push_settings_screen.dart';
import '../../../screens/debts/customer_debt_linking_screen.dart';
import '../../../screens/inventory/add_purchase_order_screen.dart';
import '../../../screens/inventory/barcode_settings_screen.dart';
import '../../../screens/inventory/brands_settings_screen.dart';
import '../../../screens/inventory/categories_settings_screen.dart';
import '../../../screens/inventory/inventory_policy_center_screen.dart';
import '../../../screens/inventory/inventory_settings_screen.dart';
import '../../../screens/inventory/product_settings_screen.dart';
import '../../../screens/inventory/stock_voucher_screen.dart';
import '../../../screens/inventory/unit_templates_settings_screen.dart';
import '../../../screens/settings/cash_ledger_audit_screen.dart';
import '../../../screens/shift/open_shift_screen.dart';
import '../../../screens/shift/work_shifts_calendar_screen.dart';
import '../../../screens/installments/installments_screen.dart';
import '../../../screens/inventory/inventory_products_screen.dart';
import '../../../screens/inventory/price_lists_screen.dart';
import '../../../screens/invoices/add_invoice_screen.dart';
import '../../../screens/invoices/invoices_screen.dart';
import '../../../screens/invoices/parked_sales_screen.dart';
import '../../../screens/invoices/sale_pos_settings_screen.dart';
import '../../../screens/license/subscription_plans_screen.dart';
import '../../../screens/loyalty/loyalty_ledger_screen.dart';
import '../../../screens/online_orders/online_orders_screen.dart';
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
  // ك2: شاشات يفتحها المساعد بمعرّفها. ظهورها يبقى بشرط الميزات والصلاحيات
  // نفسه (canOpenRoute)، فمحل بلا نقطة بيع لا تُفتح له الفواتير.
  AppContentRoutes.invoices: OilGuideRoute((_) => const InvoicesScreen()),
  AppContentRoutes.addInvoice: OilGuideRoute((_) => const AddInvoiceScreen(), parentRouteId: AppContentRoutes.invoices),
  AppContentRoutes.parkedSales: OilGuideRoute((_) => const ParkedSalesScreen(), parentRouteId: AppContentRoutes.invoices),
  AppContentRoutes.salePosSettings: OilGuideRoute((_) => const SalePosSettingsScreen(), parentRouteId: AppContentRoutes.settings),
  AppContentRoutes.onlineOrders: OilGuideRoute((_) => const OnlineOrdersScreen()),
  AppContentRoutes.loyaltyLedger: OilGuideRoute((_) => const LoyaltyLedgerScreen()),
  AppContentRoutes.installments: OilGuideRoute((_) => const InstallmentsScreen()),
  AppContentRoutes.inventoryPriceLists: OilGuideRoute((_) => const PriceListsScreen()),
  AppContentRoutes.subscriptionPlans: OilGuideRoute((_) => const SubscriptionPlansScreen(), parentRouteId: AppContentRoutes.settings),
  // ك2-ب: الشاشات الداخلية التي كانت تُفتح من داخل شاشة أخرى فقط.
  AppContentRoutes.inventorySettings: OilGuideRoute((_) => const InventorySettingsScreen(), parentRouteId: AppContentRoutes.inventory),
  AppContentRoutes.inventoryStockVoucher: OilGuideRoute((_) => const StockVoucherScreen(), parentRouteId: AppContentRoutes.inventoryManagement),
  AppContentRoutes.inventoryCategories: OilGuideRoute((_) => const CategoriesSettingsScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryBrands: OilGuideRoute((_) => const BrandsSettingsScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryBarcodeSettings: OilGuideRoute((_) => const BarcodeSettingsScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryUnitTemplates: OilGuideRoute((_) => const UnitTemplatesSettingsScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryProductSettings: OilGuideRoute((_) => const ProductSettingsScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryPolicyCenter: OilGuideRoute((_) => const InventoryPolicyCenterScreen(), parentRouteId: AppContentRoutes.inventorySettings),
  AppContentRoutes.inventoryPurchaseOrderNew: OilGuideRoute((_) => const AddPurchaseOrderScreen(), parentRouteId: AppContentRoutes.inventoryPurchaseOrders),
  AppContentRoutes.shiftOpen: OilGuideRoute((_) => const OpenShiftScreen()),
  AppContentRoutes.workShiftsCalendar: OilGuideRoute((_) => const WorkShiftsCalendarScreen(), parentRouteId: AppContentRoutes.staffShiftsWeek),
  AppContentRoutes.cashLedgerAudit: OilGuideRoute((_) => const CashLedgerAuditScreen(), parentRouteId: AppContentRoutes.settings),
  AppContentRoutes.debtLinking: OilGuideRoute((_) => const CustomerDebtLinkingScreen(), parentRouteId: AppContentRoutes.debts),
  AppContentRoutes.pushSettings: OilGuideRoute((_) => const PushSettingsScreen(), parentRouteId: AppContentRoutes.settings),
  AppContentRoutes.pushRecipients: OilGuideRoute((_) => const PushRecipientsScreen(), parentRouteId: AppContentRoutes.pushSettings),
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
