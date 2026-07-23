import '../specs/owner_kpi_catalog_entry.dart';

/// TTL لكل قسم — انظر spec §5.
class OwnerSectionTtl {
  OwnerSectionTtl._();

  static const staffUsers = Duration(minutes: 5);
  static const sales = Duration(minutes: 2);
  static const openShifts = Duration(seconds: 30);
  static const debts = Duration(minutes: 5);
  static const installments = Duration(minutes: 5);
  static const inventoryShortages = Duration(minutes: 5);
  static const salesSparkline = Duration(minutes: 10);
  static const inventoryValue = Duration(minutes: 15);
  static const cash = Duration(minutes: 2);

  static Duration forId(String sectionId) {
    switch (sectionId) {
      case OwnerSectionIds.staffUsers:
        return staffUsers;
      case OwnerSectionIds.sales:
        return sales;
      case OwnerSectionIds.openShifts:
        return openShifts;
      case OwnerSectionIds.debts:
        return debts;
      case OwnerSectionIds.installments:
        return installments;
      case OwnerSectionIds.inventoryShortages:
        return inventoryShortages;
      case OwnerSectionIds.salesSparkline:
        return salesSparkline;
      case OwnerSectionIds.inventoryValue:
        return inventoryValue;
      case OwnerSectionIds.cash:
        return cash;
      case OwnerSectionIds.oilActiveCars:
        return openShifts;
      case OwnerSectionIds.oilChangesCount:
        return sales;
      case OwnerSectionIds.carWashCount:
        return sales;
      case OwnerSectionIds.oilStockShortages:
        return inventoryShortages;
      case OwnerSectionIds.oilAvgTicket:
        return sales;
      case OwnerSectionIds.hybridRevenueSplit:
        return sales;
      case OwnerSectionIds.retailTopSellers:
        return sales;
      case OwnerSectionIds.clothingVariantShortages:
        return inventoryShortages;
      case OwnerSectionIds.clothingSlowMovers:
        return inventoryValue;
      default:
        return const Duration(minutes: 2);
    }
  }

  static OwnerCardLoadPriority loadPriorityFor(String sectionId) {
    switch (sectionId) {
      case OwnerSectionIds.cash:
      case OwnerSectionIds.openShifts:
      case OwnerSectionIds.oilActiveCars:
        return OwnerCardLoadPriority.critical;
      case OwnerSectionIds.inventoryValue:
      case OwnerSectionIds.clothingSlowMovers:
        return OwnerCardLoadPriority.heavy;
      case OwnerSectionIds.clothingVariantShortages:
        return OwnerCardLoadPriority.critical;
      default:
        return OwnerCardLoadPriority.normal;
    }
  }

  static bool isFresh(String sectionId, DateTime? fetchedAt) {
    if (fetchedAt == null) return false;
    return DateTime.now().difference(fetchedAt) < forId(sectionId);
  }

  /// true إذا تجاوزت البيانات 3× TTL — يُعاد Skeleton (v1.1.2 §5).
  static bool isVeryStale(String sectionId, DateTime? fetchedAt) {
    if (fetchedAt == null) return true;
    final ttl = forId(sectionId);
    return DateTime.now().difference(fetchedAt) > ttl * 3;
  }
}

/// معرّفات أقسام لوحة المالك.
abstract class OwnerSectionIds {
  static const staffUsers = 'staffUsers';
  static const sales = 'sales';
  static const openShifts = 'openShifts';
  static const debts = 'debts';
  static const installments = 'installments';
  static const inventoryShortages = 'inventoryShortages';
  static const salesSparkline = 'salesSparkline';
  static const inventoryValue = 'inventoryValue';
  static const cash = 'cash';

  // ── v3 oil_change ──
  static const oilActiveCars = 'oilActiveCars';
  static const oilChangesCount = 'oilChangesCount';
  static const oilStockShortages = 'oilStockShortages';
  static const oilAvgTicket = 'oilAvgTicket';
  static const hybridRevenueSplit = 'hybridRevenueSplit';
  static const carWashCount = 'carWashCount';

  // ── v3.1 supermarket ──
  static const retailTopSellers = 'retailTopSellers';

  // ── v3.1 clothing ──
  static const clothingVariantShortages = 'clothingVariantShortages';
  static const clothingSlowMovers = 'clothingSlowMovers';
}
