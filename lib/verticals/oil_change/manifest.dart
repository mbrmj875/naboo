import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../navigation/content_navigation.dart';
import '../../owner/models/owner_section_load_context.dart';
import '../../owner/models/owner_section_ttl.dart';
import '../../owner/owner_trend_repository.dart';
import '../../owner/specs/owner_dashboard_profile.dart';
import '../../owner/specs/owner_kpi_catalog.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import 'owner/owner_oil_dashboard_repository.dart';
import 'screens/oil_change_form_screen.dart';
import 'screens/oil_change_hub_screen.dart';
import 'screens/oil_change_invoices_screen.dart';
import 'screens/oil_change_service_form_screen.dart';
import 'screens/oil_change_services_screen.dart';
import '../../services/business_setup_settings.dart';
import '../../services/reports_repository.dart';
import '../_contract/vertical_manifest.dart';
import 'inventory/oil_change_fluid_inventory_editor.dart';
import 'reports/oil_change_reports_panel.dart';
import 'services/oil_change_reports_repository.dart';

/// سياسة باركود stub — يُستبدَل بـ Scan-to-Card في مرحلة لاحقة.
final class OilChangeBarcodeScanPolicyStub extends BarcodeScanPolicy {
  const OilChangeBarcodeScanPolicyStub();

  @override
  BarcodeScanDisposition handleScan(BarcodeScanContext context) {
    return BarcodeScanDisposition.passThrough;
  }
}

/// manifest تخصص غيار الزيت — المرحلة 1 (تسجيل فقط، بدون ربط shell).
final class OilChangeVerticalManifest extends VerticalManifest {
  const OilChangeVerticalManifest();

  static const _oilNavColor = Color(0xFF0EA5E9);
  static const _oilReportsSectionId = 8;
  static const _fluidInventoryEditor = OilChangeFluidInventoryEditor();
  static const _gold = Color(0xFFB8960C);
  static const _blue = Color(0xFF2563EB);
  static const _orange = Color(0xFFF59E0B);
  static const _red = Color(0xFFDC2626);
  static const _green = Color(0xFF059669);
  static const _purple = Color(0xFF7C3AED);

  @override
  String get id => BusinessVertical.oilChange;

  @override
  List<NavModuleSpec> get navModules => const [
        NavModuleSpec(
          icon: Icons.opacity_rounded,
          title: 'سجل غيارات الزيت',
          iconColor: _oilNavColor,
          routeId: AppContentRoutes.oilServicesLog,
          subItems: [
            NavSubItemSpec(
              title: 'سجل الغيارات',
              routeId: AppContentRoutes.oilServicesLog,
            ),
            NavSubItemSpec(
              title: 'الفواتير',
              routeId: AppContentRoutes.oilInvoices,
            ),
            NavSubItemSpec(
              title: 'الخدمات وأسعارها',
              routeId: AppContentRoutes.oilChangeServices,
            ),
          ],
        ),
      ];

  @override
  Map<String, WidgetBuilder> get routes => {
        AppContentRoutes.oilServicesLog: (_) => const OilChangeHubScreen(),
        AppContentRoutes.oilChangeHub: (_) => const OilChangeHubScreen(),
        AppContentRoutes.oilChangeServices: (_) =>
            const OilChangeServicesScreen(),
        AppContentRoutes.oilChangeCreate: (_) => const OilChangeFormScreen(),
        AppContentRoutes.oilChangeServiceCreate: (_) =>
            const OilChangeServiceFormScreen(),
        AppContentRoutes.oilInvoices: (_) => const OilChangeInvoicesScreen(),
      };

  @override
  HomeDashboardSpec resolveHome(BusinessSetupSettingsData features) {
    final isHybrid = features.enablePos;
    final profile = isHybrid
        ? HomeDashboardProfile.oilChangeHybrid
        : HomeDashboardProfile.oilChangeService;

    final primary = HomeDashboardAction(
      id: 'oil_new',
      title: 'غيار زيت جديد',
      subtitle: 'تسجيل سيارة وعداد',
      icon: Icons.add_rounded,
      routeId: 'oil_change_create',
      accentColor: _gold,
      isPrimary: true,
    );

    final tiles = <HomeDashboardAction>[
      const HomeDashboardAction(
        id: 'oil_log',
        title: 'سجل الغيارات',
        subtitle: 'آخر العمليات',
        icon: Icons.history_rounded,
        routeId: 'oil_services_log',
        accentColor: _blue,
      ),
      const HomeDashboardAction(
        id: 'oil_garage',
        title: 'السيارات الحالية',
        subtitle: 'في الورشة',
        icon: Icons.directions_car_filled_rounded,
        routeId: 'oil_services_log',
        accentColor: _orange,
        hint: 'قيد الانتظار أو العمل',
      ),
      const HomeDashboardAction(
        id: 'oil_stock',
        title: 'المخزون',
        subtitle: 'زيوت وفلاتر',
        icon: Icons.inventory_2_rounded,
        routeId: 'inventory',
        accentColor: _red,
      ),
      const HomeDashboardAction(
        id: 'oil_cash',
        title: 'صندوق اليوم',
        subtitle: 'المقبوض في الوردية',
        icon: Icons.payments_rounded,
        routeId: 'cash',
        accentColor: _green,
      ),
      if (isHybrid)
        const HomeDashboardAction(
          id: 'hybrid_sale',
          title: 'بيع سريع',
          subtitle: 'فاتورة قطع غيار',
          icon: Icons.add_shopping_cart_rounded,
          routeId: 'add_invoice',
          accentColor: _purple,
        ),
    ];

    final hide = <String>{
      'sale',
      'orders',
      'parked',
      if (!isHybrid) 'stock',
      if (!isHybrid) 'reports',
    };

    return HomeDashboardSpec(
      profile: profile,
      searchConfig: const HomeSearchConfig(
        placeholder: 'ابحث برقم السيارة، رقم الهاتف، أو اسم العميل…',
        shortPlaceholder: 'بحث: لوحة، هاتف، عميل…',
        routeToOilHub: true,
      ),
      primaryCta: primary,
      secondaryTiles: tiles,
      hideGlanceIds: hide,
      hideNavRouteIds: const {
        AppContentRoutes.onlineOrders,
      },
      greetingSubtitle: 'إليك ملخص ورشتك اليوم',
      greetingEmoji: '🛠️',
      showPinnedProducts: isHybrid,
      showOilKpiGrid: true,
      extraHybridGlanceIds: const {},
    );
  }

  @override
  OwnerDashboardProfileSpec? resolveOwner(BusinessSetupSettingsData features) {
    if (!features.enableOilChange) return null;
    if (features.enablePos) {
      return _oilChangeHybridSpec(features);
    }
    return _oilChangeServiceSpec(features);
  }

  static OwnerDashboardProfileSpec _oilChangeServiceSpec(
    BusinessSetupSettingsData features,
  ) {
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.oilChangeService,
      defaultCardOrder: _oilServiceCardOrder(features),
      defaultHeroCatalogId: OwnerCatalogIds.oilActiveCars,
      defaultShortcutIds: const [
        OwnerShortcutIds.oilReport,
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.oilLog,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.cash,
      ],
      activityFeedFilter: oilChangeActivityFeedFilter(features),
      morningBriefBuilderId: 'oil_change_morning_brief',
    );
  }

  static OwnerDashboardProfileSpec _oilChangeHybridSpec(
    BusinessSetupSettingsData features,
  ) {
    final order = <String>[
      OwnerCatalogIds.hybridRevenueSplit,
      OwnerCatalogIds.oilActiveCars,
      OwnerCatalogIds.oilChangesPeriod,
      OwnerCatalogIds.oilStockShortages,
      OwnerCatalogIds.debtsSummary,
      if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
      OwnerCatalogIds.openShifts,
      OwnerCatalogIds.cashSummary,
      OwnerCatalogIds.oilAvgTicket,
      OwnerCatalogIds.inventoryValue,
    ];
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.oilChangeHybrid,
      defaultCardOrder: order,
      defaultHeroCatalogId: OwnerCatalogIds.hybridRevenueSplit,
      defaultShortcutIds: const [
        OwnerShortcutIds.oilReport,
        OwnerShortcutIds.purchasePdf,
        OwnerShortcutIds.oilLog,
        OwnerShortcutIds.customers,
        OwnerShortcutIds.inventory,
        OwnerShortcutIds.cash,
      ],
      activityFeedFilter: oilChangeActivityFeedFilter(features),
      morningBriefBuilderId: 'oil_change_morning_brief',
      hybridRevenueSplit: true,
    );
  }

  static List<String> _oilServiceCardOrder(BusinessSetupSettingsData features) {
    return [
      OwnerCatalogIds.oilActiveCars,
      OwnerCatalogIds.oilChangesPeriod,
      OwnerCatalogIds.oilStockShortages,
      OwnerCatalogIds.debtsSummary,
      if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
      OwnerCatalogIds.openShifts,
      OwnerCatalogIds.cashSummary,
      OwnerCatalogIds.oilAvgTicket,
      OwnerCatalogIds.inventoryValue,
    ];
  }

  @override
  BarcodeScanPolicy get barcodePolicy => const OilChangeBarcodeScanPolicyStub();

  @override
  List<ReportSectionSpec> get reportSections => const [
        ReportSectionSpec(
          sectionId: _oilReportsSectionId,
          titleAr: 'غيار الزيت',
          requiredFeatureKey: BusinessSetupKeys.enableOilChange,
        ),
      ];

  static final OwnerOilDashboardRepository _ownerOilRepo =
      OwnerOilDashboardRepository();
  static final OwnerTrendRepository _ownerOilTrends = OwnerTrendRepository(
    oilDashboard: _ownerOilRepo,
  );

  @override
  Future<Object?> loadOwnerSection(
    String sectionId,
    OwnerSectionLoadContext context,
  ) async {
    switch (sectionId) {
      case OwnerSectionIds.oilActiveCars:
        return _ownerOilRepo.loadActiveCars(
          tenantId: context.tenantId,
          garageStaleHours: context.garageStaleHours,
        );
      case OwnerSectionIds.oilChangesCount:
        final range = context.range;
        if (range == null) return null;
        return _ownerOilRepo.loadOilChangesInRange(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      case OwnerSectionIds.oilStockShortages:
        return _ownerOilRepo.loadOilFluidShortages(
          tenantId: context.tenantId,
        );
      case OwnerSectionIds.oilAvgTicket:
        final range = context.range;
        if (range == null) return null;
        return _ownerOilRepo.loadAvgTicket(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      default:
        return null;
    }
  }

  @override
  Future<Object?> loadOwnerSectionTrend(
    String sectionId,
    OwnerSectionLoadContext context,
  ) async {
    final range = context.range;
    if (range == null) return null;
    switch (sectionId) {
      case OwnerSectionIds.oilChangesCount:
        return _ownerOilTrends.compareOilChangesWoW(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      case OwnerSectionIds.oilAvgTicket:
        return _ownerOilTrends.compareOilAvgTicketWoW(
          tenantId: context.tenantId,
          range: range,
          staffName: context.staffName,
        );
      default:
        return null;
    }
  }

  @override
  Future<Object?> loadReportSectionSnapshot(
    int sectionId,
    ReportDateRange range,
  ) async {
    if (sectionId != _oilReportsSectionId) return null;
    return OilChangeReportsRepository.instance.loadSnapshot(range);
  }

  @override
  Widget? buildReportSectionPanel(int sectionId, Object? snapshot) {
    if (sectionId != _oilReportsSectionId) return null;
    if (snapshot is! OilChangeReportsSnapshot) return null;
    return OilChangeReportsPanel(data: snapshot);
  }

  @override
  VerticalFluidInventoryEditor? get fluidInventoryEditor =>
      _fluidInventoryEditor;

  @override
  InventoryPolicy get inventoryPolicy => const InventoryPolicy(
        businessProfileKey: 'retail',
        preferVolumeLiterProducts: true,
      );

  @override
  List<KpiCatalogEntry> get kpiCatalogEntries => const [];

  @override
  VerticalDefaultFeatures get defaultFeatures =>
      VerticalDefaultFeatures.forVertical(BusinessVertical.oilChange);

  @override
  List<String> get routeGuardPrefixes => const [
        AppContentRoutes.oilChangeEditPrefix,
        AppContentRoutes.oilChangeServiceEditPrefix,
      ];

  @override
  List<String> get routeGuardExact => const [
        AppContentRoutes.oilServicesLog,
        AppContentRoutes.oilChangeServices,
        AppContentRoutes.oilChangeHub,
        AppContentRoutes.oilChangeCreate,
        AppContentRoutes.oilChangeServiceCreate,
        AppContentRoutes.oilInvoices,
      ];
}
