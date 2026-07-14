/// أقسام تقارير الصيدلية.
enum PharmacyReportSection {
  inventory,
  sales,
  finance,
  suppliers,
}

/// صف دواء في تقرير.
class PharmacyReportDrugRow {
  const PharmacyReportDrugRow({
    required this.productId,
    required this.productName,
    this.batchNo,
    this.expiryDate,
    this.qty = 0,
    this.valueFils = 0,
    this.extra,
  });

  final int productId;
  final String productName;
  final String? batchNo;
  final DateTime? expiryDate;
  final double qty;
  final int valueFils;
  final String? extra;
}

/// صف عميل/مورد في تقرير.
class PharmacyReportEntityRow {
  const PharmacyReportEntityRow({
    required this.id,
    required this.name,
    required this.metricLabel,
    this.amountFils = 0,
  });

  final int id;
  final String name;
  final String metricLabel;
  final int amountFils;
}

class PharmacyInventoryReportSnapshot {
  const PharmacyInventoryReportSnapshot({
    required this.expiring30,
    required this.expiring60,
    required this.expiring90,
    required this.outOfStock,
    required this.slowMoving30,
    required this.slowMoving60,
    required this.slowMoving90,
    required this.inventoryValueFils,
    required this.previousMonthValueFils,
  });

  final List<PharmacyReportDrugRow> expiring30;
  final List<PharmacyReportDrugRow> expiring60;
  final List<PharmacyReportDrugRow> expiring90;
  final List<PharmacyReportDrugRow> outOfStock;
  final List<PharmacyReportDrugRow> slowMoving30;
  final List<PharmacyReportDrugRow> slowMoving60;
  final List<PharmacyReportDrugRow> slowMoving90;
  final int inventoryValueFils;
  final int previousMonthValueFils;
}

class PharmacySalesReportSnapshot {
  const PharmacySalesReportSnapshot({
    required this.dailySalesFils,
    required this.weeklySalesFils,
    required this.monthlySalesFils,
    required this.topByQty,
    required this.topByValue,
    required this.topCustomers,
    required this.rxQty,
    required this.otcQty,
    required this.originatorQty,
    required this.genericQty,
    required this.peakHours,
  });

  final int dailySalesFils;
  final int weeklySalesFils;
  final int monthlySalesFils;
  final List<PharmacyReportDrugRow> topByQty;
  final List<PharmacyReportDrugRow> topByValue;
  final List<PharmacyReportEntityRow> topCustomers;
  final double rxQty;
  final double otcQty;
  final double originatorQty;
  final double genericQty;
  final List<({int hour, int salesFils})> peakHours;
}

class PharmacyFinanceReportSnapshot {
  const PharmacyFinanceReportSnapshot({
    required this.topProfitDrugs,
    required this.avgMarginPct,
    required this.receivableFils,
    required this.payableFils,
    required this.currentMonthProfitFils,
    required this.previousMonthProfitFils,
    required this.inventoryCostFils,
    required this.expectedRetailFils,
  });

  final List<PharmacyReportDrugRow> topProfitDrugs;
  final double avgMarginPct;
  final int receivableFils;
  final int payableFils;
  final int currentMonthProfitFils;
  final int previousMonthProfitFils;
  final int inventoryCostFils;
  final int expectedRetailFils;
}

class PharmacySupplierReportSnapshot {
  const PharmacySupplierReportSnapshot({
    required this.bestPriceMatches,
    required this.lastSupplyRows,
    required this.purchaseInvoices,
    required this.supplierBalances,
  });

  final List<PharmacyReportDrugRow> bestPriceMatches;
  final List<PharmacyReportDrugRow> lastSupplyRows;
  final List<PharmacyReportEntityRow> purchaseInvoices;
  final List<PharmacyReportEntityRow> supplierBalances;
}

class PharmacyReportsBundle {
  const PharmacyReportsBundle({
    required this.inventory,
    required this.sales,
    required this.finance,
    required this.suppliers,
    required this.generatedAt,
  });

  final PharmacyInventoryReportSnapshot inventory;
  final PharmacySalesReportSnapshot sales;
  final PharmacyFinanceReportSnapshot finance;
  final PharmacySupplierReportSnapshot suppliers;
  final DateTime generatedAt;
}
