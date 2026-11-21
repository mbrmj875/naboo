import '../models/owner_command_center_snapshot.dart';
import '../models/owner_section_result.dart';
import '../specs/owner_dashboard_l10n_keys.dart';

/// ملخص صباحي — سوبرماركت v3.1.
abstract final class SupermarketMorningBriefBuilder {
  SupermarketMorningBriefBuilder._();

  static String build(OwnerCommandCenterSnapshot snapshot) {
    final parts = <String>[];

    final sales = snapshot.sales;
    if (sales != null && sales.hasData && sales.data != null) {
      parts.add('مبيعات الفترة جاهزة');
    }

    final shortages = snapshot.inventoryShortages;
    if (shortages != null && shortages.hasData && shortages.data != null) {
      final n = shortages.data!.shortageCount;
      if (n <= 0) {
        parts.add('لا نواقص');
      } else if (n == 1) {
        parts.add('نقص واحد');
      } else {
        parts.add('$n نواقص');
      }
    }

    final top = snapshot.retailTopSellers;
    if (top != null && top.hasData && top.data != null) {
      final count = top.data!.items.length;
      if (count > 0) {
        parts.add('أعلى $count أصناف');
      }
    }

    if (parts.isEmpty) {
      return ownerDashboardL10n(OwnerDashboardL10nKeys.morningBriefSupermarket);
    }
    return parts.join(' · ');
  }
}
