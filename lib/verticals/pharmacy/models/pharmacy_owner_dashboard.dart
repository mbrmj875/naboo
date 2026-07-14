import '../../_contract/vertical_manifest.dart';

/// لقطة KPIs لوحة المالك — 12 مؤشراً.
class PharmacyOwnerDashboard implements VerticalPharmacyOwnerDashboardSnapshot {
  const PharmacyOwnerDashboard({
    required this.expiringSoonCount,
    required this.outOfStockCount,
    required this.topDrugs,
    required this.originatorQty,
    required this.genericQty,
    required this.inventoryValueFils,
    required this.dailyProfitFils,
    required this.monthlyProfitFils,
    required this.topCustomers,
    required this.bestSupplierMatches,
    required this.inventoryTurnover,
    required this.avgTicketFils,
    required this.totalReceivableFils,
    required this.totalPayableFils,
    required this.calculatedAt,
  });

  final int expiringSoonCount;
  final int outOfStockCount;
  final List<PharmacyTopDrugRow> topDrugs;
  final double originatorQty;
  final double genericQty;
  final int inventoryValueFils;
  final int dailyProfitFils;
  final int monthlyProfitFils;
  final List<PharmacyTopCustomerRow> topCustomers;
  final int bestSupplierMatches;
  final double inventoryTurnover;
  final int avgTicketFils;
  final int totalReceivableFils;
  final int totalPayableFils;
  final DateTime calculatedAt;

  int get totalDebtExposureFils => totalReceivableFils + totalPayableFils;

  @override
  List<VerticalPharmacyKpiEntry> get kpiEntries => [
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.expiringSoon,
          titleAr: 'أدوية تنتهي قريباً',
          valueText: '$expiringSoonCount',
          subtitleAr: 'خلال 30 يوماً',
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.outOfStock,
          titleAr: 'أدوية نفدت',
          valueText: '$outOfStockCount',
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.topDrugs,
          titleAr: 'أكثر الأدوية مبيعاً',
          valueText: topDrugs.isEmpty
              ? '—'
              : topDrugs.take(3).map((e) => e.productName).join(' · '),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.originGenericRatio,
          titleAr: 'نسبة أصلي/جنيس',
          valueText: _ratioText(originatorQty, genericQty),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.inventoryValue,
          titleAr: 'قيمة المخزون',
          valueText: _formatFils(inventoryValueFils),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.dailyProfit,
          titleAr: 'الربح اليومي',
          valueText: _formatFils(dailyProfitFils),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.monthlyProfit,
          titleAr: 'الربح الشهري',
          valueText: _formatFils(monthlyProfitFils),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.topCustomers,
          titleAr: 'أفضل العملاء',
          valueText: topCustomers.isEmpty
              ? '—'
              : topCustomers.take(3).map((e) => e.customerName).join(' · '),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.bestSuppliers,
          titleAr: 'أفضل الموردين',
          valueText: '$bestSupplierMatches',
          subtitleAr: 'مطابقة أقل سعر',
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.inventoryTurnover,
          titleAr: 'معدل دوران المخزون',
          valueText: inventoryTurnover.toStringAsFixed(2),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.avgTicket,
          titleAr: 'متوسط قيمة الفاتورة',
          valueText: _formatFils(avgTicketFils),
        ),
        VerticalPharmacyKpiEntry(
          id: PharmacyKpiIds.totalDebt,
          titleAr: 'المديونية الشاملة',
          valueText: _formatFils(totalDebtExposureFils),
          subtitleAr: 'ذمم + موردين',
        ),
      ];

  static String _formatFils(int fils) {
    final dinars = fils / 1000.0;
    return '${dinars.toStringAsFixed(0)} د.ع';
  }

  static String _ratioText(double originator, double generic) {
    if (originator <= 0 && generic <= 0) return '—';
    if (generic <= 0) return '100% أصلي';
    if (originator <= 0) return '100% جنيس';
    final total = originator + generic;
    final oPct = (originator / total * 100).round();
    return '$oPct% أصلي · ${100 - oPct}% جنيس';
  }
}

class PharmacyTopDrugRow {
  const PharmacyTopDrugRow({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.revenueFils,
  });

  final int productId;
  final String productName;
  final double qty;
  final int revenueFils;
}

class PharmacyTopCustomerRow {
  const PharmacyTopCustomerRow({
    required this.customerId,
    required this.customerName,
    required this.invoiceCount,
    required this.totalFils,
  });

  final int customerId;
  final String customerName;
  final int invoiceCount;
  final int totalFils;
}

abstract final class PharmacyKpiIds {
  PharmacyKpiIds._();
  static const expiringSoon = 'pharmacy_expiring_soon';
  static const outOfStock = 'pharmacy_out_of_stock';
  static const topDrugs = 'pharmacy_top_drugs';
  static const originGenericRatio = 'pharmacy_origin_generic';
  static const inventoryValue = 'pharmacy_inventory_value';
  static const dailyProfit = 'pharmacy_daily_profit';
  static const monthlyProfit = 'pharmacy_monthly_profit';
  static const topCustomers = 'pharmacy_top_customers';
  static const bestSuppliers = 'pharmacy_best_suppliers';
  static const inventoryTurnover = 'pharmacy_inventory_turnover';
  static const avgTicket = 'pharmacy_avg_ticket';
  static const totalDebt = 'pharmacy_total_debt';
}
