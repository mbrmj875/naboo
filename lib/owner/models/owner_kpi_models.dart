import 'owner_date_range.dart';

class StaffUserRow {
  const StaffUserRow({
    required this.id,
    required this.displayName,
    required this.username,
  });

  final int id;
  final String displayName;
  final String username;

  String get label =>
      displayName.trim().isNotEmpty ? displayName.trim() : username.trim();
}

class StaffUsersData {
  const StaffUsersData({required this.users});

  final List<StaffUserRow> users;

  List<String> get displayNames =>
      users.map((u) => u.label).where((n) => n.isNotEmpty).toList();
}

class SalesKpi {
  const SalesKpi({required this.salesFils, required this.range});

  final int salesFils;
  final OwnerDateRange range;
}

class OpenShiftRow {
  const OpenShiftRow({
    required this.id,
    required this.staffName,
    required this.openedAt,
  });

  final int id;
  final String staffName;
  final String openedAt;
}

class OpenShiftsKpi {
  const OpenShiftsKpi({required this.items});

  final List<OpenShiftRow> items;
}

class DebtSummary {
  const DebtSummary({
    required this.totalReceivableFils,
    required this.indebtedCustomerCount,
  });

  final int totalReceivableFils;
  final int indebtedCustomerCount;
}

class InstallmentAlert {
  const InstallmentAlert({
    required this.overdueCount,
    required this.dueTodayCount,
  });

  final int overdueCount;
  final int dueTodayCount;
}

class InventoryAlert {
  const InventoryAlert({required this.shortageCount});

  final int shortageCount;
}

class InventoryValueKpi {
  const InventoryValueKpi({required this.totalCostFils, required this.productCount});

  final int totalCostFils;
  final int productCount;
}

class CashSummary {
  const CashSummary({
    required this.balanceFils,
    required this.todayInFils,
    required this.todayOutFils,
  });

  final int balanceFils;
  final int todayInFils;
  final int todayOutFils;
}

class ShortageProductRow {
  const ShortageProductRow({
    required this.id,
    required this.name,
    required this.qty,
    required this.lowStockThreshold,
  });

  final int id;
  final String name;
  final double qty;
  final double lowStockThreshold;
}

class DebtorRow {
  const DebtorRow({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceFils,
  });

  final int id;
  final String name;
  final String? phone;
  final int balanceFils;
}

/// v3 — سيارات في الورشة (pending / in_progress).
class OilActiveCarsKpi {
  const OilActiveCarsKpi({
    required this.activeCount,
    this.staleWaitingCount = 0,
  });

  final int activeCount;

  /// طلبات في الورشة منذ ≥ ساعتين — Action Rail critical.
  final int staleWaitingCount;
}

/// v3 — غيارات مسجّلة في الفترة.
class OilChangesKpi {
  const OilChangesKpi({
    required this.changeCount,
    required this.revenueFils,
    required this.range,
  });

  final int changeCount;
  final int revenueFils;
  final OwnerDateRange range;
}

/// v3 — متوسط قيمة الغيار (fils).
class OilAvgTicketKpi {
  const OilAvgTicketKpi({
    required this.avgTicketFils,
    required this.changeCount,
    required this.range,
  });

  final int avgTicketFils;
  final int changeCount;
  final OwnerDateRange range;
}

/// v3 hybrid — إيراد خدمة غيار vs POS.
class HybridRevenueKpi {
  const HybridRevenueKpi({
    required this.serviceFils,
    required this.posRetailFils,
    required this.range,
  });

  final int serviceFils;
  final int posRetailFils;
  final OwnerDateRange range;

  int get totalFils => serviceFils + posRetailFils;
}

/// صف منتج ضمن أعلى المبيعات — v3.1 supermarket.
class TopSellerRow {
  const TopSellerRow({
    required this.productName,
    required this.revenueFils,
    required this.qtySold,
  });

  final String productName;
  final int revenueFils;
  final double qtySold;
}

/// أعلى 5 أصناف مبيعاً — تجميع SQL.
class RetailTopSellersKpi {
  const RetailTopSellersKpi({
    required this.items,
    required this.range,
  });

  final List<TopSellerRow> items;
  final OwnerDateRange range;
}

/// نواقص متغيّرات ملابس (SKU) — v3.1 clothing.
class ClothingVariantShortagesKpi {
  const ClothingVariantShortagesKpi({required this.shortageCount});

  final int shortageCount;
}

class ClothingVariantShortageRow {
  const ClothingVariantShortageRow({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.colorName,
    required this.size,
    required this.quantity,
    required this.lowStockThreshold,
  });

  final int variantId;
  final int productId;
  final String productName;
  final String colorName;
  final String size;
  final int quantity;
  final double lowStockThreshold;

  String get displayLabel {
    final parts = <String>[productName];
    if (colorName.isNotEmpty) parts.add(colorName);
    if (size.isNotEmpty) parts.add(size);
    return parts.join(' — ');
  }
}

/// أرصدة بطيئة الحركة — متغيّرات بمخzون دون مبيعات حديثة.
class ClothingSlowMoversKpi {
  const ClothingSlowMoversKpi({
    required this.slowCount,
    required this.daysThreshold,
    required this.items,
  });

  final int slowCount;
  final int daysThreshold;
  final List<ClothingSlowMoverRow> items;
}

class ClothingSlowMoverRow {
  const ClothingSlowMoverRow({
    required this.productName,
    required this.colorName,
    required this.size,
    required this.quantity,
    required this.daysWithoutSale,
  });

  final String productName;
  final String colorName;
  final String size;
  final int quantity;
  final int daysWithoutSale;

  String get displayLabel {
    final parts = <String>[productName];
    if (colorName.isNotEmpty) parts.add(colorName);
    if (size.isNotEmpty) parts.add(size);
    return parts.join(' — ');
  }
}
