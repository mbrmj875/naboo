import 'package:flutter/material.dart';

import '../../navigation/content_navigation.dart';
import '../../screens/debts/debts_screen.dart';
import '../../screens/installments/installments_screen.dart';
import '../../screens/inventory/inventory_products_screen.dart';
import '../../verticals/oil_change/screens/oil_change_hub_screen.dart';
import '../../verticals/oil_change/screens/oil_change_whatsapp_connect_screen.dart';
import '../models/owner_action_alert.dart';

/// تنفيذ إجراءات Action Rail — one-click من لوحة المالك.
abstract final class OwnerActionNavigation {
  OwnerActionNavigation._();

  static void run(
    BuildContext context,
    OwnerActionKind kind, {
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
    VoidCallback? onOpenDebts,
  }) {
    switch (kind) {
      case OwnerActionKind.purchasePdf:
        onPurchasePdf?.call();
      case OwnerActionKind.debtReminders:
        onDebtReminders?.call();
      case OwnerActionKind.openDebts:
        if (onOpenDebts != null) {
          onOpenDebts();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DebtsScreen(),
            ),
          );
        }
      case OwnerActionKind.openInventory:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.inventoryProducts),
            builder: (_) => const InventoryProductsScreen(),
          ),
        );
      case OwnerActionKind.openOilLog:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppContentRoutes.oilServicesLog),
            builder: (_) => const OilChangeHubScreen(),
          ),
        );
      case OwnerActionKind.openInstallments:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const InstallmentsScreen(),
          ),
        );
      case OwnerActionKind.openWhatsappConnect:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OilChangeWhatsappConnectScreen(),
          ),
        );
    }
  }
}
