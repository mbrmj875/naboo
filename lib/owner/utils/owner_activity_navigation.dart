import 'package:flutter/material.dart';

import '../../models/recent_activity_entry.dart';
import '../../navigation/content_navigation.dart';
import '../../screens/cash/cash_screen.dart';
import '../../screens/customers/customers_screen.dart';
import '../../screens/debts/debts_screen.dart';
import '../../screens/inventory/inventory_hub_screen.dart';
import '../../screens/inventory/inventory_products_screen.dart';
import '../../screens/invoices/invoices_screen.dart';
import '../../screens/loyalty/loyalty_ledger_screen.dart';
import '../../screens/invoices/parked_sales_screen.dart';
import '../../screens/users/staff_shifts_week_screen.dart';
import '../../screens/users/users_screen.dart';
import '../../services/database_helper.dart';
import '../../widgets/invoice_detail_sheet.dart';
import '../models/business_audit_event.dart';

/// تنقل من بطاقات نشاط الموظفين / التعديلات الحساسة في لوحة المالك.
abstract final class OwnerActivityNavigation {
  OwnerActivityNavigation._();

  static Future<void> openRecentActivity(
    BuildContext context,
    RecentActivityEntry entry,
  ) async {
    switch (entry.kind) {
      case RecentActivityKind.invoice:
        final id = entry.invoiceId;
        if (id != null) {
          await showInvoiceDetailSheet(context, DatabaseHelper(), id);
        } else {
          await _push(
            context,
            route: AppContentRoutes.invoices,
            builder: (_) => const InvoicesScreen(),
          );
        }
      case RecentActivityKind.cashMovement:
        final link = entry.linkedInvoiceId;
        if (link != null) {
          await showInvoiceDetailSheet(context, DatabaseHelper(), link);
        } else {
          await _push(
            context,
            route: AppContentRoutes.cash,
            builder: (_) => const CashScreen(),
          );
        }
      case RecentActivityKind.parkedSale:
        await _push(
          context,
          route: AppContentRoutes.parkedSales,
          builder: (_) => const ParkedSalesScreen(),
        );
      case RecentActivityKind.loyalty:
        final inv = entry.linkedInvoiceId;
        if (inv != null) {
          await showInvoiceDetailSheet(context, DatabaseHelper(), inv);
        } else {
          await _push(
            context,
            route: AppContentRoutes.loyaltyLedger,
            builder: (_) => const LoyaltyLedgerScreen(),
          );
        }
      case RecentActivityKind.stockVoucher:
        await _push(
          context,
          route: AppContentRoutes.inventory,
          builder: (_) => const InventoryHubScreen(),
        );
      case RecentActivityKind.customerCreated:
        await _push(
          context,
          route: AppContentRoutes.customers,
          builder: (_) => const CustomersScreen(),
        );
      case RecentActivityKind.productCreated:
        await _push(
          context,
          route: AppContentRoutes.inventoryProducts,
          builder: (_) => const InventoryProductsScreen(),
        );
      case RecentActivityKind.workShift:
        await _push(
          context,
          route: AppContentRoutes.staffShiftsWeek,
          builder: (_) => const StaffShiftsWeekScreen(),
        );
    }
  }

  static Future<void> openAuditEvent(
    BuildContext context,
    BusinessAuditEvent event,
  ) async {
    switch (event.category) {
      case BusinessAuditCategory.price:
      case BusinessAuditCategory.product:
        await _push(
          context,
          route: AppContentRoutes.inventoryProducts,
          builder: (_) => const InventoryProductsScreen(),
        );
      case BusinessAuditCategory.stock:
        await _push(
          context,
          route: AppContentRoutes.inventory,
          builder: (_) => const InventoryHubScreen(),
        );
      case BusinessAuditCategory.debt:
        await _push(
          context,
          route: AppContentRoutes.debts,
          builder: (_) => const DebtsScreen(),
        );
      case BusinessAuditCategory.security:
        await _push(
          context,
          route: AppContentRoutes.users,
          builder: (_) => const UsersScreen(),
        );
      case BusinessAuditCategory.other:
        await _push(
          context,
          route: AppContentRoutes.cash,
          builder: (_) => const CashScreen(),
        );
    }
  }

  static Future<void> _push(
    BuildContext context, {
    required String route,
    required WidgetBuilder builder,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: route),
        builder: builder,
      ),
    );
  }
}
