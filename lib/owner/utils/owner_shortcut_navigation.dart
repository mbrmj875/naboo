import 'package:flutter/material.dart';

import '../../navigation/content_navigation.dart';
import '../../screens/cash/cash_screen.dart';
import '../../screens/customers/customers_screen.dart';
import '../../screens/inventory/inventory_products_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../verticals/oil_change/screens/oil_change_form_screen.dart';
import '../../screens/invoices/add_invoice_screen.dart';
import '../../verticals/oil_change/screens/oil_change_hub_screen.dart';
import '../../screens/users/users_screen.dart';
import '../specs/owner_kpi_catalog_entry.dart';

/// تنقل اختصارات catalog v3 من لوحة المالk.
abstract final class OwnerShortcutNavigation {
  OwnerShortcutNavigation._();

  static void open(
    BuildContext context,
    OwnerShortcutCatalogEntry entry, {
    VoidCallback? onPurchasePdf,
  }) {
    switch (entry.routeId) {
      case 'reports':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: AppContentRoutes.reports(0)),
            builder: (_) => const ReportsScreen(),
          ),
        );
      case 'owner_purchase_pdf':
        onPurchasePdf?.call();
      case 'oil_services_log':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.oilServicesLog),
            builder: (_) => const OilChangeHubScreen(),
          ),
        );
      case 'customers':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.customers),
            builder: (_) => const CustomersScreen(),
          ),
        );
      case 'inventory':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.inventoryProducts),
            builder: (_) => const InventoryProductsScreen(),
          ),
        );
      case 'cash':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.cash),
            builder: (_) => const CashScreen(),
          ),
        );
      case 'oil_change_create':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.oilChangeCreate),
            builder: (_) => const OilChangeFormScreen(),
          ),
        );
      case 'users':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.users),
            builder: (_) => const UsersScreen(),
          ),
        );
      case 'add_invoice':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.addInvoice),
            builder: (_) => const AddInvoiceScreen(),
          ),
        );
    }
  }
}
