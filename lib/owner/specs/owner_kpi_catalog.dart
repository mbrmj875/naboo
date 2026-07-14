import '../../models/recent_activity_entry.dart';
import '../../services/business_setup_settings.dart';
import '../../services/permission_service.dart';
import '../models/owner_dashboard_access_context.dart';
import '../models/owner_section_ttl.dart';
import 'owner_dashboard_l10n_keys.dart';
import 'owner_kpi_catalog_entry.dart';

/// مصدر الحقيقة لبطاقات واختصارات لوحة المالk v3.
abstract final class OwnerKpiCatalog {
  OwnerKpiCatalog._();

  static const _oilVerticals = {BusinessVertical.oilChange};
  static const _retailVerticals = {
    BusinessVertical.supermarket,
    BusinessVertical.generalRetail,
  };
  static const _clothingVerticals = {BusinessVertical.clothingStore};
  static const _allVerticals = {
    BusinessVertical.oilChange,
    BusinessVertical.supermarket,
    BusinessVertical.generalRetail,
    BusinessVertical.clothingStore,
  };

  static final List<OwnerKpiCatalogEntry> allKpiEntries = [
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.oilActiveCars,
      titleKey: OwnerDashboardL10nKeys.oilActiveCarsTitle,
      sectionId: OwnerSectionIds.oilActiveCars,
      verticalAllowList: _oilVerticals,
      requiredFeatures: [OwnerFeatureRequirement.oilChange],
      requiredPermissionKey: PermissionKeys.ownerKpiOperations,
      loadPriority: OwnerCardLoadPriority.critical,
      heroEligible: true,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.oilChangesPeriod,
      titleKey: OwnerDashboardL10nKeys.oilChangesPeriodTitle,
      sectionId: OwnerSectionIds.oilChangesCount,
      verticalAllowList: _oilVerticals,
      requiredFeatures: [OwnerFeatureRequirement.oilChange],
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      supportsTrend: true,
      heroEligible: true,
      childSectionIds: [OwnerSectionIds.salesSparkline],
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.hybridRevenueSplit,
      titleKey: OwnerDashboardL10nKeys.hybridRevenueSplitTitle,
      sectionId: OwnerSectionIds.hybridRevenueSplit,
      verticalAllowList: _oilVerticals,
      requiredFeatures: [
        OwnerFeatureRequirement.oilChange,
        OwnerFeatureRequirement.pos,
      ],
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      supportsTrend: true,
      heroEligible: true,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.oilStockShortages,
      titleKey: OwnerDashboardL10nKeys.oilStockShortagesTitle,
      sectionId: OwnerSectionIds.oilStockShortages,
      verticalAllowList: _oilVerticals,
      requiredFeatures: [OwnerFeatureRequirement.oilChange],
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      supportsExport: true,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.debtsSummary,
      titleKey: OwnerDashboardL10nKeys.debtsSummaryTitle,
      sectionId: OwnerSectionIds.debts,
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiDebts,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.openShifts,
      titleKey: OwnerDashboardL10nKeys.openShiftsTitle,
      sectionId: OwnerSectionIds.openShifts,
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiOperations,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.cashSummary,
      titleKey: OwnerDashboardL10nKeys.cashSummaryTitle,
      sectionId: OwnerSectionIds.cash,
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.oilAvgTicket,
      titleKey: OwnerDashboardL10nKeys.oilAvgTicketTitle,
      sectionId: OwnerSectionIds.oilAvgTicket,
      verticalAllowList: _oilVerticals,
      requiredFeatures: [OwnerFeatureRequirement.oilChange],
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      supportsTrend: true,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.inventoryValue,
      titleKey: OwnerDashboardL10nKeys.inventoryValueTitle,
      sectionId: OwnerSectionIds.inventoryValue,
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      loadPriority: OwnerCardLoadPriority.heavy,
    ),
    // ── v3.1 supermarket ──
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailStockShortages,
      titleKey: OwnerDashboardL10nKeys.retailStockShortagesTitle,
      sectionId: OwnerSectionIds.inventoryShortages,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      supportsExport: true,
      heroEligible: true,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailSalesPeriod,
      titleKey: OwnerDashboardL10nKeys.retailSalesPeriodTitle,
      sectionId: OwnerSectionIds.sales,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      supportsTrend: true,
      heroEligible: true,
      childSectionIds: [OwnerSectionIds.salesSparkline],
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailTopSellers,
      titleKey: OwnerDashboardL10nKeys.retailTopSellersTitle,
      sectionId: OwnerSectionIds.retailTopSellers,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailDebtsSummary,
      titleKey: OwnerDashboardL10nKeys.debtsSummaryTitle,
      sectionId: OwnerSectionIds.debts,
      verticalAllowList: _retailVerticals,
      requiredFeatures: [OwnerFeatureRequirement.debts],
      requiredPermissionKey: PermissionKeys.ownerKpiDebts,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailOpenShifts,
      titleKey: OwnerDashboardL10nKeys.openShiftsTitle,
      sectionId: OwnerSectionIds.openShifts,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiOperations,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailCashSummary,
      titleKey: OwnerDashboardL10nKeys.cashSummaryTitle,
      sectionId: OwnerSectionIds.cash,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.retailInventoryValue,
      titleKey: OwnerDashboardL10nKeys.inventoryValueTitle,
      sectionId: OwnerSectionIds.inventoryValue,
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      loadPriority: OwnerCardLoadPriority.heavy,
    ),
    // ── v3.1 clothing ──
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingVariantShortages,
      titleKey: OwnerDashboardL10nKeys.clothingVariantShortagesTitle,
      sectionId: OwnerSectionIds.clothingVariantShortages,
      verticalAllowList: _clothingVerticals,
      requiredFeatures: [OwnerFeatureRequirement.clothingVariants],
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      supportsExport: true,
      heroEligible: true,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingSlowMovers,
      titleKey: OwnerDashboardL10nKeys.clothingSlowMoversTitle,
      sectionId: OwnerSectionIds.clothingSlowMovers,
      verticalAllowList: _clothingVerticals,
      requiredFeatures: [OwnerFeatureRequirement.clothingVariants],
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      heroEligible: true,
      loadPriority: OwnerCardLoadPriority.heavy,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingSalesPeriod,
      titleKey: OwnerDashboardL10nKeys.clothingSalesPeriodTitle,
      sectionId: OwnerSectionIds.sales,
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      supportsTrend: true,
      heroEligible: true,
      childSectionIds: [OwnerSectionIds.salesSparkline],
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingTopSellers,
      titleKey: OwnerDashboardL10nKeys.clothingTopSellersTitle,
      sectionId: OwnerSectionIds.retailTopSellers,
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingDebtsSummary,
      titleKey: OwnerDashboardL10nKeys.debtsSummaryTitle,
      sectionId: OwnerSectionIds.debts,
      verticalAllowList: _clothingVerticals,
      requiredFeatures: [OwnerFeatureRequirement.debts],
      requiredPermissionKey: PermissionKeys.ownerKpiDebts,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingOpenShifts,
      titleKey: OwnerDashboardL10nKeys.openShiftsTitle,
      sectionId: OwnerSectionIds.openShifts,
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiOperations,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingCashSummary,
      titleKey: OwnerDashboardL10nKeys.cashSummaryTitle,
      sectionId: OwnerSectionIds.cash,
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
      loadPriority: OwnerCardLoadPriority.critical,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.clothingInventoryValue,
      titleKey: OwnerDashboardL10nKeys.inventoryValueTitle,
      sectionId: OwnerSectionIds.inventoryValue,
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
      loadPriority: OwnerCardLoadPriority.heavy,
    ),
    OwnerKpiCatalogEntry(
      id: OwnerCatalogIds.installmentsSummary,
      titleKey: OwnerDashboardL10nKeys.installmentsSummaryTitle,
      sectionId: OwnerSectionIds.installments,
      verticalAllowList: _allVerticals,
      requiredFeatures: [OwnerFeatureRequirement.installments],
      requiredPermissionKey: PermissionKeys.ownerKpiDebts,
    ),
  ];

  static final List<OwnerShortcutCatalogEntry> allShortcutEntries = [
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.oilReport,
      titleKey: OwnerDashboardL10nKeys.scOilReport,
      routeId: 'reports',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.reportsAccess,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.purchasePdf,
      titleKey: OwnerDashboardL10nKeys.scPurchasePdf,
      routeId: 'owner_purchase_pdf',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.oilLog,
      titleKey: OwnerDashboardL10nKeys.scOilLog,
      routeId: 'oil_services_log',
      verticalAllowList: _oilVerticals,
      requiredFeatures: [OwnerFeatureRequirement.oilChange],
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.customers,
      titleKey: OwnerDashboardL10nKeys.scCustomers,
      routeId: 'customers',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.customersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.inventory,
      titleKey: OwnerDashboardL10nKeys.scInventory,
      routeId: 'inventory',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.inventoryView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.cash,
      titleKey: OwnerDashboardL10nKeys.scCash,
      routeId: 'cash',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.cashView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.users,
      titleKey: OwnerDashboardL10nKeys.scUsers,
      routeId: 'users',
      verticalAllowList: _oilVerticals,
      requiredPermissionKey: PermissionKeys.usersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.purchasePdf,
      titleKey: OwnerDashboardL10nKeys.scPurchasePdf,
      routeId: 'owner_purchase_pdf',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.scReports,
      titleKey: OwnerDashboardL10nKeys.scReports,
      routeId: 'reports',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.reportsAccess,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.customers,
      titleKey: OwnerDashboardL10nKeys.scCustomers,
      routeId: 'customers',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.customersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.inventory,
      titleKey: OwnerDashboardL10nKeys.scInventory,
      routeId: 'inventory',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.inventoryView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.cash,
      titleKey: OwnerDashboardL10nKeys.scCash,
      routeId: 'cash',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.cashView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.users,
      titleKey: OwnerDashboardL10nKeys.scUsers,
      routeId: 'users',
      verticalAllowList: _retailVerticals,
      requiredPermissionKey: PermissionKeys.usersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.addInvoice,
      titleKey: OwnerDashboardL10nKeys.scAddInvoice,
      routeId: 'add_invoice',
      verticalAllowList: _retailVerticals,
      requiredFeatures: [OwnerFeatureRequirement.pos],
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.purchasePdf,
      titleKey: OwnerDashboardL10nKeys.scPurchasePdf,
      routeId: 'owner_purchase_pdf',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.ownerKpiInventory,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.scReports,
      titleKey: OwnerDashboardL10nKeys.scReports,
      routeId: 'reports',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.reportsAccess,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.customers,
      titleKey: OwnerDashboardL10nKeys.scCustomers,
      routeId: 'customers',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.customersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.inventory,
      titleKey: OwnerDashboardL10nKeys.scInventory,
      routeId: 'inventory',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.inventoryView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.cash,
      titleKey: OwnerDashboardL10nKeys.scCash,
      routeId: 'cash',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.cashView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.users,
      titleKey: OwnerDashboardL10nKeys.scUsers,
      routeId: 'users',
      verticalAllowList: _clothingVerticals,
      requiredPermissionKey: PermissionKeys.usersView,
    ),
    OwnerShortcutCatalogEntry(
      id: OwnerShortcutIds.addInvoice,
      titleKey: OwnerDashboardL10nKeys.scAddInvoice,
      routeId: 'add_invoice',
      verticalAllowList: _clothingVerticals,
      requiredFeatures: [OwnerFeatureRequirement.pos],
      requiredPermissionKey: PermissionKeys.ownerKpiFinancial,
    ),
  ];

  static OwnerKpiCatalogEntry? kpiById(String catalogId) {
    for (final e in allKpiEntries) {
      if (e.id == catalogId) return e;
    }
    return null;
  }

  static OwnerShortcutCatalogEntry? shortcutById(String shortcutId) {
    for (final e in allShortcutEntries) {
      if (e.id == shortcutId) return e;
    }
    return null;
  }

  /// `Vertical ∩ Gate ∩ RBAC`.
  static List<OwnerKpiCatalogEntry> entriesFor({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    final vertical = features.routingVertical;
    return allKpiEntries
        .where(
          (e) =>
              e.verticalAllowList.contains(vertical) &&
              _featuresSatisfied(e.requiredFeatures, features) &&
              access.isGranted(e.requiredPermissionKey),
        )
        .toList(growable: false);
  }

  static List<OwnerShortcutCatalogEntry> shortcutsFor({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
  }) {
    final vertical = features.routingVertical;
    return allShortcutEntries
        .where(
          (e) =>
              e.verticalAllowList.contains(vertical) &&
              _featuresSatisfied(e.requiredFeatures, features) &&
              access.isGranted(e.requiredPermissionKey),
        )
        .toList(growable: false);
  }

  /// sectionIds للـ Provider — tenantId يُمرَّر صراحةً في loadSection.
  static List<String> sectionIdsFor({
    required BusinessSetupSettingsData features,
    required OwnerDashboardAccessContext access,
    required List<String> catalogOrder,
  }) {
    final allowed = {for (final e in entriesFor(features: features, access: access)) e.id};
    final out = <String>[];
    for (final catalogId in catalogOrder) {
      if (!allowed.contains(catalogId)) continue;
      final entry = kpiById(catalogId);
      if (entry == null) continue;
      if (!out.contains(entry.sectionId)) out.add(entry.sectionId);
      for (final child in entry.childSectionIds) {
        if (!out.contains(child)) out.add(child);
      }
    }
    return out;
  }

  static bool _featuresSatisfied(
    List<OwnerFeatureRequirement> requirements,
    BusinessSetupSettingsData features,
  ) {
    for (final req in requirements) {
      if (!_featureEnabled(req, features)) return false;
    }
    return true;
  }

  static bool _featureEnabled(
    OwnerFeatureRequirement req,
    BusinessSetupSettingsData features,
  ) {
    switch (req) {
      case OwnerFeatureRequirement.debts:
        return features.enableDebts;
      case OwnerFeatureRequirement.installments:
        return features.enableInstallments;
      case OwnerFeatureRequirement.pos:
        return features.enablePos;
      case OwnerFeatureRequirement.oilChange:
        return features.enableOilChange;
      case OwnerFeatureRequirement.loyalty:
        return features.enableLoyalty;
      case OwnerFeatureRequirement.weightSales:
        return features.enableWeightSales;
      case OwnerFeatureRequirement.clothingVariants:
        return features.enableClothingVariants;
    }
  }
}

/// فلتر نشاطات oil_change — يُستخدم في ProfileSpec.
Set<RecentActivityKind> oilChangeActivityFeedFilter(
  BusinessSetupSettingsData features,
) {
  return {
    RecentActivityKind.workShift,
    RecentActivityKind.invoice,
    RecentActivityKind.productCreated,
    RecentActivityKind.stockVoucher,
    if (features.enablePos) RecentActivityKind.parkedSale,
    if (features.enableLoyalty) RecentActivityKind.loyalty,
  };
}

/// فلتر نشاطات supermarket — v3.1.
Set<RecentActivityKind> supermarketActivityFeedFilter(
  BusinessSetupSettingsData features,
) {
  return {
    RecentActivityKind.workShift,
    RecentActivityKind.invoice,
    RecentActivityKind.productCreated,
    RecentActivityKind.stockVoucher,
    if (features.enablePos) RecentActivityKind.parkedSale,
    if (features.enableLoyalty) RecentActivityKind.loyalty,
  };
}

/// فلتر نشاطات clothing — v3.1.
Set<RecentActivityKind> clothingActivityFeedFilter(
  BusinessSetupSettingsData features,
) {
  return {
    RecentActivityKind.workShift,
    RecentActivityKind.invoice,
    RecentActivityKind.productCreated,
    RecentActivityKind.stockVoucher,
    if (features.enablePos) RecentActivityKind.parkedSale,
    if (features.enableLoyalty) RecentActivityKind.loyalty,
  };
}
