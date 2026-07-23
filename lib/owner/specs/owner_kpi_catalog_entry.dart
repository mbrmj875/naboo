import '../../models/recent_activity_entry.dart';
import '../../services/business_setup_settings.dart';
import '../models/owner_dashboard_access_context.dart';
import 'owner_dashboard_profile.dart';

/// معرّفات بطاقات catalog v3 (≠ sectionId دائماً).
abstract class OwnerCatalogIds {
  static const oilActiveCars = 'oil_active_cars';
  static const oilChangesPeriod = 'oil_changes_period';
  static const carWashPeriod = 'car_wash_period';
  static const oilStockShortages = 'oil_stock_shortages';
  static const oilAvgTicket = 'oil_avg_ticket';
  static const hybridRevenueSplit = 'hybrid_revenue_split';
  static const debtsSummary = 'debts_summary';
  static const openShifts = 'open_shifts';
  static const cashSummary = 'cash_summary';
  static const inventoryValue = 'inventory_value';
  static const installmentsSummary = 'installments_summary';

  // ── v3.1 supermarket ──
  static const retailStockShortages = 'retail_stock_shortages';
  static const retailSalesPeriod = 'retail_sales_period';
  static const retailTopSellers = 'retail_top_sellers';
  static const retailDebtsSummary = 'retail_debts_summary';
  static const retailOpenShifts = 'retail_open_shifts';
  static const retailCashSummary = 'retail_cash_summary';
  static const retailInventoryValue = 'retail_inventory_value';

  // ── v3.1 clothing ──
  static const clothingVariantShortages = 'clothing_variant_shortages';
  static const clothingSlowMovers = 'clothing_slow_movers';
  static const clothingSalesPeriod = 'clothing_sales_period';
  static const clothingTopSellers = 'clothing_top_sellers';
  static const clothingDebtsSummary = 'clothing_debts_summary';
  static const clothingOpenShifts = 'clothing_open_shifts';
  static const clothingCashSummary = 'clothing_cash_summary';
  static const clothingInventoryValue = 'clothing_inventory_value';
}

/// اختصارات catalog v3.
abstract class OwnerShortcutIds {
  static const oilReport = 'sc_oil_report';
  static const purchasePdf = 'sc_purchase_pdf';
  static const oilLog = 'sc_oil_log';
  static const customers = 'sc_customers';
  static const inventory = 'sc_inventory';
  static const cash = 'sc_cash';
  static const scReports = 'sc_reports';
  static const addInvoice = 'sc_add_invoice';
  static const users = 'sc_users';
}

/// متطلبات بوابة الميزات على مستوى البطاقة.
enum OwnerFeatureRequirement {
  debts,
  installments,
  pos,
  oilChange,
  carWash,
  loyalty,
  weightSales,
  clothingVariants,
}

/// أولوية تحميل البطاقة — lazy loading v3.
enum OwnerCardLoadPriority {
  critical,
  normal,
  heavy,
}

/// metadata بطاقة KPI واحدة في catalog.
class OwnerKpiCatalogEntry {
  const OwnerKpiCatalogEntry({
    required this.id,
    required this.titleKey,
    required this.sectionId,
    required this.verticalAllowList,
    this.requiredFeatures = const [],
    this.requiredPermissionKey,
    this.loadPriority = OwnerCardLoadPriority.normal,
    this.supportsTrend = false,
    this.supportsExport = false,
    this.defaultVisible = true,
    this.heroEligible = false,
    this.childSectionIds = const [],
  });

  final String id;
  final String titleKey;
  final String sectionId;
  final Set<String> verticalAllowList;
  final List<OwnerFeatureRequirement> requiredFeatures;
  final String? requiredPermissionKey;
  final OwnerCardLoadPriority loadPriority;
  final bool supportsTrend;
  final bool supportsExport;
  final bool defaultVisible;
  final bool heroEligible;
  final List<String> childSectionIds;
}

/// metadata اختصار سريع.
class OwnerShortcutCatalogEntry {
  const OwnerShortcutCatalogEntry({
    required this.id,
    required this.titleKey,
    required this.routeId,
    required this.verticalAllowList,
    this.requiredPermissionKey,
    this.requiredFeatures = const [],
  });

  final String id;
  final String titleKey;
  final String routeId;
  final Set<String> verticalAllowList;
  final String? requiredPermissionKey;
  final List<OwnerFeatureRequirement> requiredFeatures;
}

/// وصفة لوحة المالk لنشاط واحد.
class OwnerDashboardProfileSpec {
  const OwnerDashboardProfileSpec({
    required this.profile,
    required this.defaultCardOrder,
    required this.defaultHeroCatalogId,
    required this.defaultShortcutIds,
    required this.activityFeedFilter,
    required this.morningBriefBuilderId,
    this.hybridRevenueSplit = false,
  });

  final OwnerDashboardProfile profile;
  final List<String> defaultCardOrder;
  final String defaultHeroCatalogId;
  final List<String> defaultShortcutIds;
  final Set<RecentActivityKind> activityFeedFilter;
  final String morningBriefBuilderId;
  final bool hybridRevenueSplit;
}

/// مدخلات Resolver — features + tenant/RBAC صريح.
class OwnerDashboardResolveInput {
  const OwnerDashboardResolveInput({
    required this.features,
    required this.access,
  });

  final BusinessSetupSettingsData features;
  final OwnerDashboardAccessContext access;
}
