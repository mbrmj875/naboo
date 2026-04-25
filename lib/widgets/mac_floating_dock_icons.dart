import 'package:flutter/material.dart';

import '../navigation/content_navigation.dart';

/// أيقونة البلاطة السفلية لكل مسار عائم (تظهر عند التصغير بالزر الأصفر).
IconData macFloatingDockIconForRoute(String routeId) {
  switch (routeId) {
    case AppContentRoutes.settings:
      return Icons.settings_rounded;
    case AppContentRoutes.cash:
      return Icons.account_balance_wallet_rounded;
    case AppContentRoutes.installments:
      return Icons.calendar_today_rounded;
    case AppContentRoutes.installmentSettings:
      return Icons.tune_rounded;
    case AppContentRoutes.invoices:
      return Icons.receipt_long_rounded;
    case AppContentRoutes.addInvoice:
      return Icons.point_of_sale_rounded;
    case AppContentRoutes.parkedSales:
      return Icons.pause_circle_outline_rounded;
    case AppContentRoutes.salePosSettings:
      return Icons.storefront_rounded;
    case AppContentRoutes.users:
      return Icons.manage_accounts_rounded;
    case AppContentRoutes.staffShiftsWeek:
      return Icons.date_range_rounded;
    case AppContentRoutes.employeeIdentity:
      return Icons.badge_rounded;
    case AppContentRoutes.printing:
      return Icons.print_rounded;
    case AppContentRoutes.loyaltySettings:
      return Icons.card_giftcard_rounded;
    case AppContentRoutes.loyaltyLedger:
      return Icons.stars_rounded;
    case AppContentRoutes.debts:
      return Icons.account_balance_rounded;
    case AppContentRoutes.debtSettings:
      return Icons.tune_rounded;
    default:
      return Icons.layers_rounded;
  }
}
