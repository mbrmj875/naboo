/// تعريف جولة إرشادية وخطواتها.
library;

class GuideStep {
  const GuideStep({
    required this.anchorId,
    required this.title,
    required this.body,
    this.speakText,
    this.ensureRouteId,
    this.action,
    this.awaitTap = false,
    this.allowInteract = false,
  });

  /// معرّف [GuideAnchor] المستهدف.
  final String anchorId;

  final String title;
  final String body;

  /// نص المتحدث الأوفلاين — إن فارغ يُقرأ العنوان + الشرح.
  final String? speakText;

  /// إن وُجد: يُطلب من المضيف الانتقال لهذا المسار قبل عرض الخطوة.
  final String? ensureRouteId;

  /// إجراء مخصص للمضيف (مثل `oil.select_pending_tab`).
  final String? action;

  /// إن true: المستخدم يضغط الهدف مباشرة ولا يظهر زر «التالي».
  final bool awaitTap;

  /// إن true: الفتحة تسمح باللمس/الكتابة على الحقل مع إبقاء زر «التالي».
  final bool allowInteract;

  String get narration {
    final custom = speakText?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return '$title. $body';
  }
}

class GuideTour {
  const GuideTour({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
  });

  final String id;
  final String title;
  final String description;
  final List<GuideStep> steps;
}

/// كتالوج الجولات المسموحة (يُمرَّر أيضاً لـ DeepSeek).
abstract final class GuideTourIds {
  static const oilFirstRun = 'oil_first_run';
  static const oilWhatsapp = 'oil_whatsapp';
  static const oilPendingTab = 'oil_pending_tab';
  static const oilPlateAutofill = 'oil_plate_autofill';
  static const oilHubSettings = 'oil_hub_settings';
  static const oilCatalogOil = 'oil_catalog_oil';
  static const oilCatalogFilter = 'oil_catalog_filter';
  static const oilCatalogHydraulic = 'oil_catalog_hydraulic';
  static const oilServicesBase = 'oil_services_base';
  static const carWashHome = 'car_wash_home';
  static const carWashVisibility = 'car_wash_visibility';
  static const carWashCreate = 'car_wash_create';

  /// جولات وحدة المستخدمين / الموظفين.
  static const usersAddStaff = 'users_add_staff';
  static const usersModuleOverview = 'users_module_overview';
  static const usersIdentity = 'users_identity';
  static const usersShifts = 'users_shifts';

  /// جولات إضافة منتج / أنواع المخزون.
  static const productAddOverview = 'product_add_overview';
  static const productStockCount = 'product_stock_count';
  static const productStockVolume = 'product_stock_volume';
  static const productStockHydraulic = 'product_stock_hydraulic';
  static const productStockOil = 'product_stock_oil';
  static const productPricingInventory = 'product_pricing_inventory';

  static const none = 'none';

  static const allowlist = <String>{
    oilFirstRun,
    oilWhatsapp,
    oilPendingTab,
    oilPlateAutofill,
    oilHubSettings,
    oilCatalogOil,
    oilCatalogFilter,
    oilCatalogHydraulic,
    oilServicesBase,
    carWashHome,
    carWashVisibility,
    carWashCreate,
    usersAddStaff,
    usersModuleOverview,
    usersIdentity,
    usersShifts,
    productAddOverview,
    productStockCount,
    productStockVolume,
    productStockHydraulic,
    productStockOil,
    productPricingInventory,
    none,
  };
}
