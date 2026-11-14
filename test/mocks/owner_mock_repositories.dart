import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_trend.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_load_context.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/owner_command_center_repository.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';

/// مستودع وهمي — يسجّل الأقسام المحمّلة ويفشل حسب التكوين.
class FakeOwnerCommandCenterRepository extends OwnerCommandCenterRepository {
  FakeOwnerCommandCenterRepository({
    this.tenantId = 1,
    Set<String>? failOn,
  }) : failOn = failOn ?? <String>{};

  final int tenantId;
  final Set<String> failOn;
  final List<String> loadedSections = [];

  void _track(String sectionId) {
    loadedSections.add(sectionId);
    if (failOn.contains(sectionId)) {
      throw StateError('mock fail: $sectionId');
    }
  }

  @override
  Future<int> requireTenantId() async => tenantId;

  @override
  Future<StaffUsersData> loadStaffUsers() async {
    _track(OwnerSectionIds.staffUsers);
    return const StaffUsersData(users: [
      StaffUserRow(id: 1, displayName: 'موظف', username: 'staff'),
    ]);
  }

  @override
  Future<SalesKpi> loadSales({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.sales);
    return SalesKpi(salesFils: 7500000, range: range);
  }

  @override
  Future<List<int>> loadSalesSparkline({
    required int tenantId,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.salesSparkline);
    return const [1, 2, 3, 4, 5, 6, 7];
  }

  @override
  Future<OpenShiftsKpi> loadOpenShifts({required int tenantId}) async {
    _track(OwnerSectionIds.openShifts);
    return const OpenShiftsKpi(items: []);
  }

  @override
  Future<DebtSummary> loadDebtSummary({
    required int tenantId,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.debts);
    return debtSummary;
  }

  /// قابل للتغيير في اختبارات المزامنة.
  DebtSummary debtSummary = const DebtSummary(
    totalReceivableFils: 1000000,
    indebtedCustomerCount: 2,
  );

  @override
  Future<InstallmentAlert> loadInstallmentAlert({required int tenantId}) async {
    _track(OwnerSectionIds.installments);
    return const InstallmentAlert(overdueCount: 0, dueTodayCount: 0);
  }

  @override
  Future<InventoryAlert> loadInventoryShortages({required int tenantId}) async {
    _track(OwnerSectionIds.inventoryShortages);
    return const InventoryAlert(shortageCount: 3);
  }

  bool retailShortagesLoaded = false;

  @override
  Future<InventoryAlert> loadRetailStockShortages({required int tenantId}) async {
    _track(OwnerSectionIds.inventoryShortages);
    retailShortagesLoaded = true;
    return const InventoryAlert(shortageCount: 12);
  }

  @override
  Future<InventoryValueKpi> loadInventoryValue({required int tenantId}) async {
    _track(OwnerSectionIds.inventoryValue);
    return const InventoryValueKpi(totalCostFils: 50000000, productCount: 10);
  }

  @override
  Future<CashSummary> loadCashSummary({
    required int tenantId,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.cash);
    return const CashSummary(
      balanceFils: 2000000,
      todayInFils: 100000,
      todayOutFils: 50000,
    );
  }

  @override
  Future<OilActiveCarsKpi> loadOilActiveCars({
    required int tenantId,
    int garageStaleHours = 2,
  }) async {
    _track(OwnerSectionIds.oilActiveCars);
    return const OilActiveCarsKpi(activeCount: 2);
  }

  @override
  Future<OilChangesKpi> loadOilChangesCount({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.oilChangesCount);
    return OilChangesKpi(changeCount: 5, revenueFils: 500000, range: range);
  }

  @override
  Future<OilAvgTicketKpi> loadOilAvgTicket({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.oilAvgTicket);
    return OilAvgTicketKpi(avgTicketFils: 100000, changeCount: 5, range: range);
  }

  @override
  Future<InventoryAlert> loadOilStockShortages({required int tenantId}) async {
    _track(OwnerSectionIds.oilStockShortages);
    return const InventoryAlert(shortageCount: 1);
  }

  @override
  Future<HybridRevenueKpi> loadHybridRevenueSplit({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    _track(OwnerSectionIds.hybridRevenueSplit);
    return HybridRevenueKpi(
      serviceFils: 3000000,
      posRetailFils: 4500000,
      range: range,
    );
  }

  OwnerKpiTrend? oilChangesTrendResult;
  OwnerKpiTrend? oilAvgTicketTrendResult;

  @override
  Future<OwnerKpiTrend?> loadOilChangesTrendWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    return oilChangesTrendResult;
  }

  @override
  Future<OwnerKpiTrend?> loadOilAvgTicketTrendWoW({
    required int tenantId,
    required OwnerDateRange range,
    String? staffName,
  }) async {
    return oilAvgTicketTrendResult;
  }
}

/// يوجّه تحميل أقسام الزيت في الاختبارات إلى [FakeOwnerCommandCenterRepository].
OilOwnerSectionLoader oilOwnerSectionLoaderFrom(
  FakeOwnerCommandCenterRepository repo,
) {
  return (String sectionId, OwnerSectionLoadContext context,
      {required bool trend}) async {
    final range = context.range ?? const OwnerDateRange.today();
    if (trend) {
      switch (sectionId) {
        case OwnerSectionIds.oilChangesCount:
          return repo.loadOilChangesTrendWoW(
            tenantId: context.tenantId,
            range: range,
            staffName: context.staffName,
          );
        case OwnerSectionIds.oilAvgTicket:
          return repo.loadOilAvgTicketTrendWoW(
            tenantId: context.tenantId,
            range: range,
            staffName: context.staffName,
          );
        default:
          return null;
      }
    }
    switch (sectionId) {
      case OwnerSectionIds.oilActiveCars:
        return repo.loadOilActiveCars(
          tenantId: context.tenantId,
          garageStaleHours: context.garageStaleHours,
        );
      case OwnerSectionIds.oilChangesCount:
        return repo.loadOilChangesCount(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      case OwnerSectionIds.oilStockShortages:
        return repo.loadOilStockShortages(tenantId: context.tenantId);
      case OwnerSectionIds.oilAvgTicket:
        return repo.loadOilAvgTicket(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      default:
        return null;
    }
  };
}
