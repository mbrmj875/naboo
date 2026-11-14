import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../navigation/content_navigation.dart';
import '../../owner/specs/owner_dashboard_profile.dart';
import '../../owner/specs/owner_kpi_catalog.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import '../../services/business_setup_settings.dart';
import '../../services/reports_repository.dart';
import '../_contract/vertical_manifest.dart';
import 'inventory/pharmacy_product_editor.dart';
import 'models/pharmacy_report_models.dart';
import 'screens/pharmacy_customer_detail_sheet.dart';
import 'screens/pharmacy_invoices_screen.dart';
import 'screens/pharmacy_owner_dashboard_panel.dart';
import 'screens/pharmacy_pos_drug_panel.dart';
import 'services/drug_catalog_repository.dart';
import 'services/pharmacy_alert_resolver.dart';
import 'services/pharmacy_customer_repository.dart';
import 'services/pharmacy_kpi_calculator.dart';
import 'services/pharmacy_reports_repository.dart';
import 'widgets/pharmacy_report_panels.dart';

/// سياسة باركود stub — Scan-to-drug panel في مرحلة لاحقة.
final class PharmacyBarcodeScanPolicyStub extends BarcodeScanPolicy {
  const PharmacyBarcodeScanPolicyStub();

  @override
  BarcodeScanDisposition handleScan(BarcodeScanContext context) {
    return BarcodeScanDisposition.passThrough;
  }
}

/// manifest تخصص الصيدلية — المرحلة 2 (تسجيل + stubs، بدون GUI كامل).
final class PharmacyVerticalManifest extends VerticalManifest {
  const PharmacyVerticalManifest();

  static const _productEditor = PharmacyProductEditor();
  static const _pharmacyNavColor = Color(0xFF059669);
  static const _pharmacyReportsSectionId = 9;

  static final PharmacyReportsRepository _reportsRepository =
      PharmacyReportsRepository();
  static final PharmacyKpiCalculator _kpiCalculator = PharmacyKpiCalculator(
    reportsRepo: _reportsRepository,
  );

  @override
  String get id => BusinessVertical.pharmacy;

  @override
  List<NavModuleSpec> get navModules => const [
        NavModuleSpec(
          icon: Icons.medication_liquid_rounded,
          title: 'فواتير الصيدلية',
          iconColor: _pharmacyNavColor,
          routeId: AppContentRoutes.pharmacyInvoices,
        ),
      ];

  @override
  Map<String, WidgetBuilder> get routes => {
        AppContentRoutes.pharmacyInvoices: (_) =>
            const PharmacyInvoicesScreen(),
      };

  @override
  List<String> get routeGuardExact => const [
        AppContentRoutes.pharmacyInvoices,
      ];

  @override
  List<String> get routeGuardPrefixes => const [
        AppContentRoutes.pharmacyInvoiceDetailPrefix,
      ];

  @override
  HomeDashboardSpec resolveHome(BusinessSetupSettingsData features) {
    return HomeDashboardSpec(
      profile: HomeDashboardProfile.retail,
      searchConfig: const HomeSearchConfig(
        placeholder: 'ابحث باسم الدواء أو الباركود…',
        shortPlaceholder: 'بحث: دواء، باركود…',
      ),
      greetingSubtitle: 'إليك ملخص الصيدلية اليوم',
      greetingEmoji: '💊',
      showPinnedProducts: features.enablePos,
    );
  }

  @override
  OwnerDashboardProfileSpec? resolveOwner(BusinessSetupSettingsData features) {
    return _pharmacyStoreSpec(features);
  }

  static OwnerDashboardProfileSpec _pharmacyStoreSpec(
    BusinessSetupSettingsData features,
  ) {
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.pharmacy,
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
      defaultShortcutIds: const [
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.scReports,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.cash,
        OwnerShortcutIds.addInvoice,
      ],
      activityFeedFilter: supermarketActivityFeedFilter(features),
      morningBriefBuilderId: 'supermarket_morning_brief',
    );
  }

  @override
  BarcodeScanPolicy get barcodePolicy => const PharmacyBarcodeScanPolicyStub();

  @override
  List<ReportSectionSpec> get reportSections => const [
        ReportSectionSpec(
          sectionId: _pharmacyReportsSectionId,
          titleAr: 'تقارير الصيدلية',
          requiredFeatureKey: BusinessSetupKeys.enablePos,
        ),
      ];

  @override
  List<PharmacyReportSectionSpec> get pharmacyReportSections => const [
        PharmacyReportSectionSpec(
          section: 'inventory',
          titleAr: 'المخزون',
          reportsScreenId: _pharmacyReportsSectionId,
        ),
        PharmacyReportSectionSpec(
          section: 'sales',
          titleAr: 'المبيعات',
          reportsScreenId: _pharmacyReportsSectionId,
        ),
        PharmacyReportSectionSpec(
          section: 'finance',
          titleAr: 'مالي',
          reportsScreenId: _pharmacyReportsSectionId,
        ),
        PharmacyReportSectionSpec(
          section: 'suppliers',
          titleAr: 'الموردين',
          reportsScreenId: _pharmacyReportsSectionId,
        ),
      ];

  @override
  InventoryPolicy get inventoryPolicy => const InventoryPolicy(
        businessProfileKey: 'pharmacy',
      );

  @override
  List<KpiCatalogEntry> get kpiCatalogEntries => const [];

  @override
  VerticalDefaultFeatures get defaultFeatures =>
      VerticalDefaultFeatures.forVertical(BusinessVertical.pharmacy);

  @override
  VerticalPharmacyProductEditor? get pharmacyProductEditor => _productEditor;

  @override
  Widget? buildPosDrugPanel(BuildContext context, PosDrugPanelArgs args) {
    return PharmacyPosDrugPanelHost(args: args);
  }

  @override
  Future<List<PharmacyAlert>> evaluateSaleAlerts(
    SaleAlertContext context,
  ) async {
    return PharmacyAlertResolver(catalog: DrugCatalogRepository()).evaluate(
      context,
    );
  }

  @override
  Future<VerticalPharmacyCustomerExtSnapshot?> loadCustomerPharmacySnapshot({
    required int tenantId,
    required int customerId,
  }) async {
    final repo = PharmacyCustomerRepository();
    await repo.ensureSchema();
    final ext = await repo.getByCustomerId(
      tenantId: tenantId,
      customerId: customerId,
    );
    if (ext == null) return null;
    return VerticalPharmacyCustomerExtSnapshot(allergies: ext.allergies);
  }

  @override
  Widget? buildCustomerAllergiesBanner(List<String> allergies) {
    if (allergies.isEmpty) return null;
    return PharmacyCustomerAllergiesBanner(allergies: allergies);
  }

  @override
  Future<void> openCustomerPharmacyDetailSheet({
    required BuildContext context,
    required int tenantId,
    required int customerId,
    required String customerName,
    String? customerPhone,
    required VoidCallback onUpdated,
  }) async {
    await PharmacyCustomerDetailSheet.show(
      context: context,
      tenantId: tenantId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      onUpdated: onUpdated,
    );
  }

  @override
  Widget? buildCustomerExtensionSection({
    required BuildContext context,
    required int tenantId,
    required int customerId,
    required String customerName,
    String? customerPhone,
    required VoidCallback onUpdated,
  }) {
    if (customerId <= 0) return null;
    return PharmacyCustomerExtensionSection(
      tenantId: tenantId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      onUpdated: onUpdated,
    );
  }

  @override
  Future<void> recordPharmacySaleCustomerExt({
    required int tenantId,
    required int customerId,
    required List<int> productIds,
    required DateTime purchasedAt,
  }) async {
    final repo = PharmacyCustomerRepository();
    await repo.recordRefillsFromSale(
      tenantId: tenantId,
      customerId: customerId,
      productIds: productIds,
      purchasedAt: purchasedAt,
    );
  }

  @override
  Future<VerticalPharmacyOwnerDashboardSnapshot?> loadOwnerDashboard({
    required int tenantId,
  }) {
    return _kpiCalculator.calculateDashboard(tenantId: tenantId);
  }

  @override
  Future<Object?> loadReportSectionSnapshot(
    int sectionId,
    ReportDateRange range,
  ) async {
    if (sectionId != _pharmacyReportsSectionId) return null;
    return _reportsRepository.loadReportsBundle();
  }

  @override
  Widget? buildReportSectionPanel(int sectionId, Object? snapshot) {
    if (sectionId != _pharmacyReportsSectionId) return null;
    if (snapshot is! PharmacyReportsBundle) return null;
    return PharmacyReportsTabbedPanel(bundle: snapshot);
  }

  @override
  Widget? buildPharmacyReportPanel({
    required PharmacyReportSectionSpec section,
    required Object? snapshot,
  }) {
    if (snapshot is! PharmacyReportsBundle) return null;
    return switch (section.section) {
      'inventory' => PharmacyInventoryReportPanel(snapshot: snapshot.inventory),
      'sales' => PharmacySalesReportPanel(snapshot: snapshot.sales),
      'finance' => PharmacyFinanceReportPanel(snapshot: snapshot.finance),
      'suppliers' => PharmacySupplierReportPanel(snapshot: snapshot.suppliers),
      _ => null,
    };
  }

  @override
  Widget? buildOwnerVerticalDashboardPanel() =>
      const PharmacyOwnerDashboardPanel();

  @override
  void invalidateOwnerDashboardCache() {
    PharmacyReportsRepository.invalidateCache();
  }
}
