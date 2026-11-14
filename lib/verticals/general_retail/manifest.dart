import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../owner/specs/owner_dashboard_profile.dart';
import '../../owner/specs/owner_kpi_catalog.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import '../../services/business_setup_settings.dart';
import '../_contract/vertical_manifest.dart';

/// سياسة باركود افتراضية — لا سلوك خاص للتجزئة العامة.
final class GeneralRetailBarcodeScanPolicy extends BarcodeScanPolicy {
  const GeneralRetailBarcodeScanPolicy();

  @override
  BarcodeScanDisposition handleScan(BarcodeScanContext context) {
    return BarcodeScanDisposition.passThrough;
  }
}

/// manifest افتراضي للتجزئة العامة — fallback لـ [VerticalRegistry.activeManifest].
final class GeneralRetailVerticalManifest extends VerticalManifest {
  const GeneralRetailVerticalManifest();

  @override
  String get id => BusinessVertical.generalRetail;

  @override
  List<NavModuleSpec> get navModules => const [];

  @override
  Map<String, WidgetBuilder> get routes => const {};

  @override
  HomeDashboardSpec resolveHome(BusinessSetupSettingsData features) {
    return HomeDashboardSpec(
      profile: HomeDashboardProfile.retail,
      searchConfig: const HomeSearchConfig(
        placeholder: 'ابحث باسم المنتج أو الباركود…',
        shortPlaceholder: 'بحث: منتج، باركود…',
      ),
      greetingSubtitle: 'إليك ملخص أعمال اليوم',
      greetingEmoji: '👋',
      showPinnedProducts: features.enablePos,
    );
  }

  @override
  OwnerDashboardProfileSpec? resolveOwner(BusinessSetupSettingsData features) {
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.generalRetail,
      defaultCardOrder: [
        if (features.enableDebts) OwnerCatalogIds.retailDebtsSummary,
        if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
        OwnerCatalogIds.retailInventoryValue,
        OwnerCatalogIds.retailStockShortages,
        OwnerCatalogIds.retailOpenShifts,
        OwnerCatalogIds.retailTopSellers,
        OwnerCatalogIds.retailSalesPeriod,
        OwnerCatalogIds.retailCashSummary,
      ],
      defaultHeroCatalogId: OwnerCatalogIds.retailStockShortages,
      defaultShortcutIds: [
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.scReports,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.cash,
        if (features.enablePos) OwnerShortcutIds.addInvoice,
      ],
      activityFeedFilter: supermarketActivityFeedFilter(features),
      morningBriefBuilderId: 'supermarket_morning_brief',
    );
  }

  @override
  BarcodeScanPolicy get barcodePolicy => const GeneralRetailBarcodeScanPolicy();

  @override
  List<ReportSectionSpec> get reportSections => const [];

  @override
  InventoryPolicy get inventoryPolicy => const InventoryPolicy(
        businessProfileKey: 'retail',
      );

  @override
  List<KpiCatalogEntry> get kpiCatalogEntries => const [];

  @override
  VerticalDefaultFeatures get defaultFeatures =>
      VerticalDefaultFeatures.forVertical(BusinessVertical.generalRetail);
}
