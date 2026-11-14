import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../navigation/content_navigation.dart';
import '../../owner/specs/owner_dashboard_profile.dart';
import '../../owner/specs/owner_kpi_catalog.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import '../../services/business_setup_settings.dart';
import '../_contract/vertical_manifest.dart';
import 'screens/floor_map_screen.dart';
import 'screens/kds_screen.dart';
import 'screens/menu_builder_screen.dart';
import 'screens/menu_theme_editor_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/restaurant_cashier_screen.dart';

/// سياسة باركود stub — Scan-to-table لاحقاً.
final class RestaurantBarcodeScanPolicyStub extends BarcodeScanPolicy {
  const RestaurantBarcodeScanPolicyStub();

  @override
  BarcodeScanDisposition handleScan(BarcodeScanContext context) {
    return BarcodeScanDisposition.passThrough;
  }
}

/// manifest تخصص المطاعم — المرحلة 2 (منيو + طاولات + وصفات + ثيم).
final class RestaurantVerticalManifest extends VerticalManifest {
  const RestaurantVerticalManifest();

  static const _navColor = Color(0xFFB45309);
  static const _gold = Color(0xFFB8960C);
  static const _blue = Color(0xFF2563EB);
  static const _orange = Color(0xFFF59E0B);
  static const _green = Color(0xFF059669);
  static const _purple = Color(0xFF7C3AED);

  @override
  String get id => BusinessVertical.restaurantCafe;

  @override
  List<NavModuleSpec> get navModules => const [
        NavModuleSpec(
          icon: Icons.table_restaurant_rounded,
          title: 'ترتيب القاعة',
          iconColor: _gold,
          routeId: AppContentRoutes.restaurantFloor,
          breadcrumbTitle: 'ترتيب القاعة',
        ),
        NavModuleSpec(
          icon: Icons.menu_book_rounded,
          title: 'المنيو',
          iconColor: _navColor,
          routeId: AppContentRoutes.restaurantMenu,
          subItems: [
            NavSubItemSpec(
              title: 'الأصناف',
              routeId: AppContentRoutes.restaurantMenu,
            ),
            NavSubItemSpec(
              title: 'الوصفات',
              routeId: AppContentRoutes.restaurantRecipes,
            ),
            NavSubItemSpec(
              title: 'تصميم المنيو العام',
              routeId: AppContentRoutes.restaurantMenuTheme,
            ),
          ],
        ),
        NavModuleSpec(
          icon: Icons.soup_kitchen_rounded,
          title: 'المطبخ',
          iconColor: _orange,
          routeId: AppContentRoutes.restaurantKds,
        ),
      ];

  @override
  Map<String, WidgetBuilder> get routes => {
        AppContentRoutes.restaurantFloor: (_) => const FloorMapScreen(),
        AppContentRoutes.restaurantMenu: (_) => const MenuBuilderScreen(),
        AppContentRoutes.restaurantRecipes: (_) => const RecipesScreen(),
        AppContentRoutes.restaurantKds: (_) => const KdsScreen(),
        AppContentRoutes.restaurantCashier: (_) =>
            const RestaurantCashierScreen(),
        AppContentRoutes.restaurantMenuTheme: (_) =>
            const MenuThemeEditorScreen(),
      };

  @override
  List<String> get routeGuardExact => const [
        AppContentRoutes.restaurantFloor,
        AppContentRoutes.restaurantMenu,
        AppContentRoutes.restaurantRecipes,
        AppContentRoutes.restaurantKds,
        AppContentRoutes.restaurantCashier,
        AppContentRoutes.restaurantMenuTheme,
      ];

  @override
  HomeDashboardSpec resolveHome(BusinessSetupSettingsData features) {
    return const HomeDashboardSpec(
      profile: HomeDashboardProfile.retail,
      searchConfig: HomeSearchConfig(
        placeholder: 'ابحث عن طبق أو طاولة…',
        shortPlaceholder: 'بحث: طبق، طاولة…',
      ),
      greetingSubtitle: 'منصة ضيافة — القاعة منفصلة عن المنيو',
      greetingEmoji: '',
      showPinnedProducts: false,
      showRestaurantPosHome: true,
      primaryCta: HomeDashboardAction(
        id: 'restaurant_cashier',
        title: 'كاشير المطعم',
        subtitle: 'طلب على طاولة أو استلام',
        icon: Icons.point_of_sale_rounded,
        routeId: AppContentRoutes.restaurantCashier,
        accentColor: _gold,
        isPrimary: true,
      ),
      secondaryTiles: [
        HomeDashboardAction(
          id: 'restaurant_floor',
          title: 'ترتيب القاعة',
          subtitle: 'ضع الطاولات كما في المطعم',
          icon: Icons.table_restaurant_rounded,
          routeId: AppContentRoutes.restaurantFloor,
          accentColor: _blue,
        ),
        HomeDashboardAction(
          id: 'restaurant_kds',
          title: 'المطبخ',
          subtitle: 'طلبات التجهيز',
          icon: Icons.soup_kitchen_rounded,
          routeId: AppContentRoutes.restaurantKds,
          accentColor: _orange,
        ),
        HomeDashboardAction(
          id: 'restaurant_menu',
          title: 'المنيو',
          subtitle: 'أصناف وأسعار',
          icon: Icons.menu_book_rounded,
          routeId: AppContentRoutes.restaurantMenu,
          accentColor: _green,
        ),
        HomeDashboardAction(
          id: 'restaurant_theme',
          title: 'تصميم المنيو',
          subtitle: 'ثيم وشعار',
          icon: Icons.palette_rounded,
          routeId: AppContentRoutes.restaurantMenuTheme,
          accentColor: _purple,
        ),
      ],
      hideGlanceIds: {
        'sale',
        'stock',
        'parked',
        'orders',
        'reports',
        'cash',
      },
      // إخفاء بيع رف / مخزون رف / ديون / معلّقات / طلبات أونلاين
      hideNavRouteIds: {
        AppContentRoutes.addInvoice,
        AppContentRoutes.parkedSales,
        AppContentRoutes.onlineOrders,
        AppContentRoutes.inventory,
        AppContentRoutes.inventoryProducts,
        AppContentRoutes.inventoryBarcodeLabels,
        AppContentRoutes.inventoryManagement,
        AppContentRoutes.inventoryWarehouses,
        AppContentRoutes.inventoryPriceLists,
        AppContentRoutes.inventoryStocktaking,
        AppContentRoutes.inventoryPurchaseOrders,
        AppContentRoutes.inventoryAnalytics,
        AppContentRoutes.inventorySettings,
        AppContentRoutes.quickUpdateProducts,
        AppContentRoutes.debts,
        AppContentRoutes.salePosSettings,
      },
    );
  }

  @override
  OwnerDashboardProfileSpec? resolveOwner(BusinessSetupSettingsData features) {
    if (features.effectiveVertical != BusinessVertical.restaurantCafe) {
      return null;
    }
    return OwnerDashboardProfileSpec(
      profile: OwnerDashboardProfile.restaurantCafe,
      defaultCardOrder: [
        if (features.enableInstallments) OwnerCatalogIds.installmentsSummary,
        OwnerCatalogIds.retailOpenShifts,
        OwnerCatalogIds.retailTopSellers,
        OwnerCatalogIds.retailSalesPeriod,
        OwnerCatalogIds.retailCashSummary,
      ],
      defaultHeroCatalogId: OwnerCatalogIds.retailSalesPeriod,
      defaultShortcutIds: const [
        OwnerShortcutIds.customers,
        OwnerShortcutIds.cash,
        OwnerShortcutIds.scReports,
      ],
      activityFeedFilter: supermarketActivityFeedFilter(features),
      morningBriefBuilderId: 'restaurant_morning_brief',
    );
  }

  @override
  BarcodeScanPolicy get barcodePolicy =>
      const RestaurantBarcodeScanPolicyStub();

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
      VerticalDefaultFeatures.forVertical(BusinessVertical.restaurantCafe);
}
