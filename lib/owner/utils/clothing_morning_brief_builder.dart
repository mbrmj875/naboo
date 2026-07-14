import '../models/owner_command_center_snapshot.dart';
import '../specs/owner_dashboard_l10n_keys.dart';

/// ملخص صباحي — محل ملابس v3.1.
abstract final class ClothingMorningBriefBuilder {
  ClothingMorningBriefBuilder._();

  static String build(OwnerCommandCenterSnapshot snapshot) {
    final parts = <String>[];

    final sales = snapshot.sales;
    if (sales != null && sales.hasData && sales.data != null) {
      parts.add('مبيعات الفترة جاهزة');
    }

    final shortages = snapshot.clothingVariantShortages;
    if (shortages != null && shortages.hasData && shortages.data != null) {
      final n = shortages.data!.shortageCount;
      if (n <= 0) {
        parts.add('لا نواقص مقاسات');
      } else if (n == 1) {
        parts.add('نقص مقاس واحد');
      } else {
        parts.add('$n نواقص مقاسات');
      }
    }

    final slow = snapshot.clothingSlowMovers;
    if (slow != null && slow.hasData && slow.data != null) {
      final n = slow.data!.slowCount;
      if (n > 0) {
        parts.add(n == 1 ? 'رصيد راكد واحد' : '$n أرصدة راكدة');
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
      return ownerDashboardL10n(OwnerDashboardL10nKeys.morningBriefClothing);
    }
    return parts.join(' · ');
  }
}
