import 'package:flutter/material.dart';

import '../../../home/employee_access_policy.dart';
import '../../../navigation/content_navigation.dart';
import '../../../navigation/shell/shell_nav_item.dart';
import '../../../screens/cash/cash_screen.dart';
import '../../../screens/customers/customer_contacts_screen.dart';
import '../../../screens/customers/customer_form_screen.dart';
import '../../../screens/customers/customers_screen.dart';
import '../../../screens/debts/debt_settings_screen.dart';
import '../../../screens/debts/debts_screen.dart';
import '../../../screens/expenses/expenses_screen.dart';
import '../../../screens/inventory/add_product_screen.dart';
import '../../../screens/inventory/barcode_labels_screen.dart';
import '../../../screens/inventory/inventory_hub_screen.dart';
import '../../../screens/inventory/inventory_management_screen.dart';
import '../../../screens/inventory/inventory_products_screen.dart';
import '../../../screens/inventory/inventory_settings_screen.dart';
import '../../../screens/inventory/purchase_orders_screen.dart';
import '../../../screens/inventory/quick_product_update_screen.dart';
import '../../../screens/inventory/stock_analytics_screen.dart';
import '../../../screens/inventory/stocktaking_screen.dart';
import '../../../screens/inventory/warehouses_screen.dart';
import '../../../printing/printing_center_screen.dart';
import '../../../screens/reports/reports_screen.dart';
import '../../../screens/settings/settings_screen.dart';
import '../../../screens/users/employee_identity_screen.dart';
import '../../../screens/users/staff_shifts_week_screen.dart';
import '../../../screens/users/users_screen.dart';
import '../../car_wash/screens/car_wash_services_screen.dart';
import '../screens/oil_change_direct_sale_screen.dart';
import '../screens/oil_change_hub_screen.dart';
import '../screens/oil_change_invoices_screen.dart';
import '../screens/oil_change_services_screen.dart';

const _oilColor = Color(0xFF0EA5E9);

List<ShellNavItem> _catalog() => [
  ShellNavItem(
    icon: Icons.home_rounded,
    title: 'الرئيسية',
    iconColor: Colors.amber,
    routeId: AppContentRoutes.home,
    destination: (_) => const SizedBox.shrink(),
  ),
  ShellNavItem(
    icon: Icons.opacity_rounded,
    title: 'سجل غيارات الزيت',
    iconColor: _oilColor,
    routeId: AppContentRoutes.oilServicesLog,
    destination: (_) => const OilChangeHubScreen(),
    subItems: [
      ShellNavSubItem(
        title: 'سجل الغيارات',
        routeId: AppContentRoutes.oilServicesLog,
        breadcrumbTitle: 'سجل غيارات الزيت',
        destination: (_) => const OilChangeHubScreen(),
      ),
      ShellNavSubItem(
        title: 'الفواتير',
        routeId: AppContentRoutes.oilInvoices,
        destination: (_) => const OilChangeInvoicesScreen(),
      ),
      ShellNavSubItem(
        title: 'بيع مباشر',
        routeId: AppContentRoutes.oilDirectSale,
        destination: (_) => const OilChangeDirectSaleScreen(),
      ),
      ShellNavSubItem(
        title: 'الخدمات وأسعارها',
        routeId: AppContentRoutes.oilChangeServices,
        destination: (_) => const OilChangeServicesScreen(),
      ),
      ShellNavSubItem(
        title: 'أنواع الغسيل وأسعارها',
        routeId: AppContentRoutes.carWashServices,
        destination: (_) => const CarWashServicesScreen(),
      ),
    ],
  ),
  ShellNavItem(
    icon: Icons.person_outline,
    title: 'العملاء',
    iconColor: Colors.teal,
    routeId: AppContentRoutes.customers,
    destination: (_) => const CustomersScreen(),
    subItems: [
      ShellNavSubItem(
        title: 'إدارة العملاء',
        routeId: AppContentRoutes.customers,
        destination: (_) => const CustomersScreen(),
      ),
      ShellNavSubItem(
        title: 'إضافة عميل جديد',
        routeId: AppContentRoutes.customersAdd,
        destination: (_) => const CustomerFormScreen(),
      ),
      ShellNavSubItem(
        title: 'قائمة الاتصال',
        routeId: AppContentRoutes.customerContacts,
        destination: (_) => const CustomerContactsScreen(),
      ),
    ],
  ),
  ShellNavItem(
    icon: Icons.balance_outlined,
    title: 'الديون',
    iconColor: Colors.amber,
    routeId: AppContentRoutes.debts,
    destination: (_) => const DebtsScreen(),
    subItems: [
      ShellNavSubItem(
        title: 'لوحة الديون (آجل)',
        routeId: AppContentRoutes.debts,
        destination: (_) => const DebtsScreen(),
      ),
      ShellNavSubItem(
        title: 'إعدادات الدين',
        routeId: AppContentRoutes.debtSettings,
        destination: (_) => const DebtSettingsScreen(),
      ),
    ],
  ),
  ShellNavItem(
    icon: Icons.inventory_2,
    title: 'المخزون',
    iconColor: Colors.orange,
    routeId: AppContentRoutes.inventory,
    destination: (_) => const InventoryHubScreen(),
    subItems: [
      ShellNavSubItem(
        title: 'قائمة المنتجات',
        routeId: AppContentRoutes.inventoryProducts,
        destination: (_) => const InventoryProductsScreen(),
      ),
      ShellNavSubItem(
        title: 'إضافة منتج جديد',
        routeId: AppContentRoutes.addProduct,
        destination: (_) => const AddProductScreen(),
      ),
      ShellNavSubItem(
        title: 'تحديث منتج موجود',
        routeId: AppContentRoutes.quickUpdateProducts,
        destination: (_) => const QuickProductUpdateScreen(),
      ),
      ShellNavSubItem(
        title: 'طباعة ملصقات باركود',
        routeId: AppContentRoutes.inventoryBarcodeLabels,
        destination: (_) => const BarcodeLabelsScreen(),
      ),
      ShellNavSubItem(
        title: 'حركات المخزون',
        routeId: AppContentRoutes.inventoryManagement,
        destination: (_) => const InventoryManagementScreen(),
      ),
      ShellNavSubItem(
        title: 'المستودعات',
        routeId: AppContentRoutes.inventoryWarehouses,
        destination: (_) => const WarehousesScreen(),
      ),
      ShellNavSubItem(
        title: 'الجرد الدوري',
        routeId: AppContentRoutes.inventoryStocktaking,
        destination: (_) => const StocktakingScreen(),
      ),
      ShellNavSubItem(
        title: 'أوامر الشراء',
        routeId: AppContentRoutes.inventoryPurchaseOrders,
        destination: (_) => const PurchaseOrdersScreen(),
      ),
      ShellNavSubItem(
        title: 'تحليلات المخزون',
        routeId: AppContentRoutes.inventoryAnalytics,
        destination: (_) => const StockAnalyticsScreen(),
      ),
      ShellNavSubItem(
        title: 'إعدادات المخزون',
        routeId: AppContentRoutes.inventorySettings,
        destination: (_) => const InventorySettingsScreen(),
      ),
    ],
  ),
  ShellNavItem(
    icon: Icons.account_balance_wallet,
    title: 'الصندوق',
    iconColor: Colors.purple,
    routeId: AppContentRoutes.cash,
    destination: (_) => const CashScreen(),
  ),
  ShellNavItem(
    icon: Icons.payments_outlined,
    title: 'المصروفات',
    iconColor: Colors.teal,
    routeId: AppContentRoutes.expenses,
    destination: (_) => const ExpensesScreen(),
  ),
  ShellNavItem(
    icon: Icons.bar_chart,
    title: 'التقارير',
    iconColor: Colors.red,
    routeId: AppContentRoutes.reports(0),
    destination: (_) => const ReportsScreen(initialSection: 0),
  ),
  ShellNavItem(
    icon: Icons.people_alt,
    title: 'المستخدمين',
    iconColor: Colors.indigo,
    routeId: AppContentRoutes.users,
    destination: (_) => const UsersScreen(),
    subItems: [
      ShellNavSubItem(
        title: 'إدارة المستخدمين',
        icon: Icons.manage_accounts_outlined,
        routeId: AppContentRoutes.users,
        destination: (_) => const UsersScreen(),
      ),
      ShellNavSubItem(
        title: 'ورديات الموظفين (أسبوع)',
        icon: Icons.date_range_rounded,
        routeId: AppContentRoutes.staffShiftsWeek,
        destination: (_) => const StaffShiftsWeekScreen(),
      ),
      ShellNavSubItem(
        title: 'هويات الموظفين',
        icon: Icons.badge_outlined,
        routeId: AppContentRoutes.employeeIdentity,
        destination: (_) => const EmployeeIdentityScreen(),
      ),
    ],
  ),
  ShellNavItem(
    icon: Icons.print,
    title: 'الطباعة',
    iconColor: Colors.blueGrey,
    routeId: AppContentRoutes.printing,
    destination: (_) => const PrintingCenterScreen(),
  ),
  ShellNavItem(
    icon: Icons.settings_rounded,
    title: 'الإعدادات',
    iconColor: Colors.blueGrey,
    routeId: AppContentRoutes.settings,
    destination: (_) => const SettingsScreen(),
  ),
];

/// قائمة تنقل موظف الزيت بعد الصلاحيات والميزات، بالترتيب المحفوظ.
List<ShellNavItem> buildOilShellNav(
  EmployeeAccessPolicy policy, {
  List<String> savedOrder = const [],
}) {
  final visible = <ShellNavItem>[];
  for (final item in _catalog()) {
    final subs = item.subItems
        ?.where((sub) => policy.isVisible(sub.routeId))
        .map(
          (sub) => ShellNavSubItem(
            title: sub.title,
            routeId: sub.routeId,
            destination: sub.destination,
            icon: sub.icon,
            breadcrumbTitle: sub.breadcrumbTitle,
            disabled: policy.blockedByRestrictedMode(sub.routeId),
          ),
        )
        .toList();
    if (subs != null && subs.isEmpty) continue;
    if (subs == null && !policy.isVisible(item.routeId)) continue;
    // وحدة بفروع تُغلق بصلاحية مسارها الرئيسي إلا إن بقي فرع مسموح.
    final moduleVisible = policy.isVisible(item.routeId);
    if (!moduleVisible && item.routeId != AppContentRoutes.users) continue;
    visible.add(
      ShellNavItem(
        icon: item.icon,
        title: item.title,
        iconColor: item.iconColor,
        routeId: item.routeId,
        destination: item.destination,
        breadcrumbTitle: item.breadcrumbTitle,
        subItems: subs,
        disabled:
            item.routeId != AppContentRoutes.home &&
            policy.blockedByRestrictedMode(item.routeId),
      ),
    );
  }
  return applySavedNavOrder(visible, savedOrder);
}

/// يطبّق ترتيب المستخدم؛ البنود الجديدة تبقى في مكانها بعد المحفوظة.
List<ShellNavItem> applySavedNavOrder(
  List<ShellNavItem> items,
  List<String> savedOrder,
) {
  if (savedOrder.isEmpty) return items;
  final byRoute = {for (final item in items) item.routeId: item};
  final ordered = <ShellNavItem>[
    for (final routeId in savedOrder)
      if (byRoute.containsKey(routeId)) byRoute[routeId]!,
  ];
  ordered.addAll(items.where((item) => !savedOrder.contains(item.routeId)));
  return ordered;
}
