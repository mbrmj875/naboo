import 'owner_kpi_models.dart';
import 'owner_section_result.dart';

/// لقطة مجزّأة — كل قسم ينجح أو يفشل منفرداً.
class OwnerCommandCenterSnapshot {
  const OwnerCommandCenterSnapshot({
    this.staffUsers = const OwnerSectionResult.idle(),
    this.sales = const OwnerSectionResult.idle(),
    this.openShifts = const OwnerSectionResult.idle(),
    this.debts,
    this.installments,
    this.inventoryShortages,
    this.inventoryValue,
    this.cash,
    this.salesSparkline = const OwnerSectionResult.idle(),
    this.oilActiveCars,
    this.oilChangesCount,
    this.carWashCount,
    this.oilStockShortages,
    this.oilAvgTicket,
    this.hybridRevenueSplit,
    this.retailTopSellers,
    this.clothingVariantShortages,
    this.clothingSlowMovers,
  });

  final OwnerSectionResult<StaffUsersData> staffUsers;
  final OwnerSectionResult<SalesKpi> sales;
  final OwnerSectionResult<OpenShiftsKpi> openShifts;
  final OwnerSectionResult<DebtSummary>? debts;
  final OwnerSectionResult<InstallmentAlert>? installments;
  final OwnerSectionResult<InventoryAlert>? inventoryShortages;
  final OwnerSectionResult<InventoryValueKpi>? inventoryValue;
  final OwnerSectionResult<CashSummary>? cash;
  final OwnerSectionResult<List<int>>? salesSparkline;
  final OwnerSectionResult<OilActiveCarsKpi>? oilActiveCars;
  final OwnerSectionResult<OilChangesKpi>? oilChangesCount;
  final OwnerSectionResult<OilChangesKpi>? carWashCount;
  final OwnerSectionResult<InventoryAlert>? oilStockShortages;
  final OwnerSectionResult<OilAvgTicketKpi>? oilAvgTicket;
  final OwnerSectionResult<HybridRevenueKpi>? hybridRevenueSplit;
  final OwnerSectionResult<RetailTopSellersKpi>? retailTopSellers;
  final OwnerSectionResult<ClothingVariantShortagesKpi>? clothingVariantShortages;
  final OwnerSectionResult<ClothingSlowMoversKpi>? clothingSlowMovers;

  static const initial = OwnerCommandCenterSnapshot();

  Iterable<OwnerSectionResult<dynamic>> get activeSections sync* {
    yield staffUsers;
    yield sales;
    yield openShifts;
    if (debts != null) yield debts!;
    if (installments != null) yield installments!;
    if (inventoryShortages != null) yield inventoryShortages!;
    if (inventoryValue != null) yield inventoryValue!;
    if (cash != null) yield cash!;
    if (salesSparkline != null) yield salesSparkline!;
    if (oilActiveCars != null) yield oilActiveCars!;
    if (oilChangesCount != null) yield oilChangesCount!;
    if (carWashCount != null) yield carWashCount!;
    if (oilStockShortages != null) yield oilStockShortages!;
    if (oilAvgTicket != null) yield oilAvgTicket!;
    if (hybridRevenueSplit != null) yield hybridRevenueSplit!;
    if (retailTopSellers != null) yield retailTopSellers!;
    if (clothingVariantShortages != null) yield clothingVariantShortages!;
    if (clothingSlowMovers != null) yield clothingSlowMovers!;
  }

  CommandCenterScreenStatus get screenStatus {
    final sections = activeSections.toList();
    if (sections.isEmpty) return CommandCenterScreenStatus.idle;

    final anyLoading = sections.any((s) => s.isLoading);
    final anySuccess = sections.any((s) => s.isSuccess || s.isStale);
    final anyError = sections.any((s) => s.isError);
    final anyStale = sections.any((s) => s.isStale);

    if (anyLoading && !anySuccess) return CommandCenterScreenStatus.loading;
    if (anyError && anySuccess) return CommandCenterScreenStatus.partial;
    if (anyStale && anySuccess) return CommandCenterScreenStatus.offlineStale;
    if (anyError && !anySuccess) return CommandCenterScreenStatus.partial;
    if (anySuccess) return CommandCenterScreenStatus.ready;
    return CommandCenterScreenStatus.idle;
  }

  /// تشخيص الأقسام الفاشلة لعرضها للمستخدم في banner الحالة الجزئية.
  /// يُرجع قائمة `(الاسم العربي للقسم, رسالة الخطأ)`.
  List<({String label, String? error})> get failedSectionDiagnostics {
    final entries = <({String label, String? error})>[];
    void add(String label, OwnerSectionResult<dynamic>? r) {
      if (r != null && r.isError) {
        entries.add((label: label, error: r.errorMessage));
      }
    }

    add('الموظفون', staffUsers);
    add('المبيعات', sales);
    add('الورديات المفتوحة', openShifts);
    add('الديون', debts);
    add('الأقساط', installments);
    add('نواقص المخزون', inventoryShortages);
    add('قيمة المخزون', inventoryValue);
    add('الصندوق', cash);
    add('مخطط المبيعات', salesSparkline);
    add('سيارات قيد الخدمة', oilActiveCars);
    add('تغييرات الزيت', oilChangesCount);
    add('غسل السيارات', carWashCount);
    add('مخزون مواد الزيت', oilStockShortages);
    add('متوسط الفاتورة (زيت)', oilAvgTicket);
    add('توزيع الإيرادات الهجين', hybridRevenueSplit);
    add('الأكثر مبيعاً', retailTopSellers);
    add('نواقص متغيرات الملابس', clothingVariantShortages);
    add('بضائع راكدة (ملابس)', clothingSlowMovers);
    return entries;
  }

  OwnerCommandCenterSnapshot copyWith({
    OwnerSectionResult<StaffUsersData>? staffUsers,
    OwnerSectionResult<SalesKpi>? sales,
    OwnerSectionResult<OpenShiftsKpi>? openShifts,
    OwnerSectionResult<DebtSummary>? debts,
    OwnerSectionResult<InstallmentAlert>? installments,
    OwnerSectionResult<InventoryAlert>? inventoryShortages,
    OwnerSectionResult<InventoryValueKpi>? inventoryValue,
    OwnerSectionResult<CashSummary>? cash,
    OwnerSectionResult<List<int>>? salesSparkline,
    OwnerSectionResult<OilActiveCarsKpi>? oilActiveCars,
    OwnerSectionResult<OilChangesKpi>? oilChangesCount,
    OwnerSectionResult<OilChangesKpi>? carWashCount,
    OwnerSectionResult<InventoryAlert>? oilStockShortages,
    OwnerSectionResult<OilAvgTicketKpi>? oilAvgTicket,
    OwnerSectionResult<HybridRevenueKpi>? hybridRevenueSplit,
    OwnerSectionResult<RetailTopSellersKpi>? retailTopSellers,
    OwnerSectionResult<ClothingVariantShortagesKpi>? clothingVariantShortages,
    OwnerSectionResult<ClothingSlowMoversKpi>? clothingSlowMovers,
    bool clearDebts = false,
    bool clearInstallments = false,
    bool clearInventory = false,
    bool clearCash = false,
    bool clearOilV3 = false,
    bool clearV3Catalog = false,
  }) {
    final clearCatalog = clearOilV3 || clearV3Catalog;
    return OwnerCommandCenterSnapshot(
      staffUsers: staffUsers ?? this.staffUsers,
      sales: sales ?? this.sales,
      openShifts: openShifts ?? this.openShifts,
      debts: clearDebts ? null : (debts ?? this.debts),
      installments: clearInstallments ? null : (installments ?? this.installments),
      inventoryShortages:
          clearInventory ? null : (inventoryShortages ?? this.inventoryShortages),
      inventoryValue: clearInventory ? null : (inventoryValue ?? this.inventoryValue),
      cash: clearCash ? null : (cash ?? this.cash),
      salesSparkline: salesSparkline ?? this.salesSparkline,
      oilActiveCars: clearCatalog ? null : (oilActiveCars ?? this.oilActiveCars),
      oilChangesCount:
          clearCatalog ? null : (oilChangesCount ?? this.oilChangesCount),
      carWashCount: clearCatalog ? null : (carWashCount ?? this.carWashCount),
      oilStockShortages:
          clearCatalog ? null : (oilStockShortages ?? this.oilStockShortages),
      oilAvgTicket: clearCatalog ? null : (oilAvgTicket ?? this.oilAvgTicket),
      hybridRevenueSplit:
          clearCatalog ? null : (hybridRevenueSplit ?? this.hybridRevenueSplit),
      retailTopSellers:
          clearCatalog ? null : (retailTopSellers ?? this.retailTopSellers),
      clothingVariantShortages: clearCatalog
          ? null
          : (clothingVariantShortages ?? this.clothingVariantShortages),
      clothingSlowMovers:
          clearCatalog ? null : (clothingSlowMovers ?? this.clothingSlowMovers),
    );
  }
}
