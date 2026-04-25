import 'app_settings_repository.dart';
import 'tenant_context_service.dart';

abstract class InventoryPolicyKeys {
  // ── وحدات المخزون الأساسية ──────────────────────────────────────────────
  static const enableProducts       = 'inv.policy.products';
  static const enableAddProduct     = 'inv.policy.add_product';
  static const enableVouchers       = 'inv.policy.vouchers';
  static const enablePriceLists     = 'inv.policy.price_lists';
  static const enableWarehouses     = 'inv.policy.warehouses';
  static const enableStocktaking    = 'inv.policy.stocktaking';
  static const enableSettings       = 'inv.policy.settings';

  // ── سياسات السندات ──────────────────────────────────────────────────────
  static const requireSourceOnInbound = 'inv.policy.vouchers.require_source';

  // ── نوع النشاط التجاري ──────────────────────────────────────────────────
  static const businessProfile = 'inv.policy.business_profile';

  // ── خصائص بطاقة المنتج ──────────────────────────────────────────────────
  static const enableExpiryTracking  = 'inv.policy.product.expiry_tracking';
  static const enableBatchTracking   = 'inv.policy.product.batch_tracking';
  static const enableProductGrade    = 'inv.policy.product.grade';
  static const enableLowStockAlerts  = 'inv.policy.product.low_stock_alerts';
  static const enableProductImages   = 'inv.policy.product.images';
  static const enableProductVariants = 'inv.policy.product.variants';

  // ── المشتريات والموردون ──────────────────────────────────────────────────
  static const enablePurchaseOrders  = 'inv.policy.purchasing.po';

  // ── التحليلات ────────────────────────────────────────────────────────────
  static const enableStockAnalytics  = 'inv.policy.analytics';
}

// ── نوع النشاط التجاري ──────────────────────────────────────────────────────

enum BusinessProfile {
  smallShop    ('small_shop',    'محل صغير'),
  retail       ('retail',        'متجر تجزئة'),
  pharmacy     ('pharmacy',      'صيدلية'),
  clothing     ('clothing',      'محل ملابس'),
  construction ('construction',  'محل إنشائي'),
  warehouse    ('warehouse',     'مستودع / جملة');

  const BusinessProfile(this.key, this.label);
  final String key;
  final String label;

  static BusinessProfile fromKey(String? key) =>
      BusinessProfile.values.firstWhere(
        (p) => p.key == key,
        orElse: () => BusinessProfile.retail,
      );
}

// ── إعدادات بطاقة المنتج الافتراضية حسب نوع النشاط ──────────────────────────

class _ProfileDefaults {
  const _ProfileDefaults({
    required this.expiryTracking,
    required this.batchTracking,
    required this.productGrade,
    required this.lowStockAlerts,
    required this.productImages,
    required this.productVariants,
    required this.purchaseOrders,
    required this.stockAnalytics,
  });

  final bool expiryTracking;
  final bool batchTracking;
  final bool productGrade;
  final bool lowStockAlerts;
  final bool productImages;
  final bool productVariants;
  final bool purchaseOrders;
  final bool stockAnalytics;

  static _ProfileDefaults forProfile(BusinessProfile p) {
    switch (p) {
      case BusinessProfile.pharmacy:
        return const _ProfileDefaults(
          expiryTracking:  true,
          batchTracking:   true,
          productGrade:    true,
          lowStockAlerts:  true,
          productImages:   false,
          productVariants: false,
          purchaseOrders:  true,
          stockAnalytics:  true,
        );
      case BusinessProfile.clothing:
        return const _ProfileDefaults(
          expiryTracking:  false,
          batchTracking:   false,
          productGrade:    true,
          lowStockAlerts:  true,
          productImages:   true,
          productVariants: true,
          purchaseOrders:  false,
          stockAnalytics:  true,
        );
      case BusinessProfile.construction:
        return const _ProfileDefaults(
          expiryTracking:  false,
          batchTracking:   false,
          productGrade:    true,
          lowStockAlerts:  true,
          productImages:   false,
          productVariants: false,
          purchaseOrders:  true,
          stockAnalytics:  true,
        );
      case BusinessProfile.warehouse:
        return const _ProfileDefaults(
          expiryTracking:  true,
          batchTracking:   true,
          productGrade:    true,
          lowStockAlerts:  true,
          productImages:   false,
          productVariants: false,
          purchaseOrders:  true,
          stockAnalytics:  true,
        );
      case BusinessProfile.smallShop:
        return const _ProfileDefaults(
          expiryTracking:  false,
          batchTracking:   false,
          productGrade:    false,
          lowStockAlerts:  true,
          productImages:   true,
          productVariants: false,
          purchaseOrders:  false,
          stockAnalytics:  false,
        );
      case BusinessProfile.retail:
        return const _ProfileDefaults(
          expiryTracking:  false,
          batchTracking:   false,
          productGrade:    false,
          lowStockAlerts:  true,
          productImages:   true,
          productVariants: false,
          purchaseOrders:  false,
          stockAnalytics:  false,
        );
    }
  }
}

// ── نموذج البيانات ────────────────────────────────────────────────────────────

class InventoryPolicySettingsData {
  const InventoryPolicySettingsData({
    required this.enableProducts,
    required this.enableAddProduct,
    required this.enableVouchers,
    required this.enablePriceLists,
    required this.enableWarehouses,
    required this.enableStocktaking,
    required this.enableSettings,
    required this.requireSourceOnInbound,
    required this.businessProfile,
    // خصائص بطاقة المنتج
    required this.enableExpiryTracking,
    required this.enableBatchTracking,
    required this.enableProductGrade,
    required this.enableLowStockAlerts,
    required this.enableProductImages,
    required this.enableProductVariants,
    // المشتريات
    required this.enablePurchaseOrders,
    // التحليلات
    required this.enableStockAnalytics,
  });

  final bool enableProducts;
  final bool enableAddProduct;
  final bool enableVouchers;
  final bool enablePriceLists;
  final bool enableWarehouses;
  final bool enableStocktaking;
  final bool enableSettings;
  final bool requireSourceOnInbound;
  final String businessProfile;

  // خصائص بطاقة المنتج
  final bool enableExpiryTracking;
  final bool enableBatchTracking;
  final bool enableProductGrade;
  final bool enableLowStockAlerts;
  final bool enableProductImages;
  final bool enableProductVariants;

  // المشتريات والموردون
  final bool enablePurchaseOrders;

  // التحليلات
  final bool enableStockAnalytics;

  // ── الافتراضيات العامة ──────────────────────────────────────────────────

  static InventoryPolicySettingsData defaults() =>
      const InventoryPolicySettingsData(
        enableProducts:           true,
        enableAddProduct:         true,
        enableVouchers:           true,
        enablePriceLists:         true,
        enableWarehouses:         true,
        enableStocktaking:        true,
        enableSettings:           true,
        requireSourceOnInbound:   true,
        businessProfile:          'retail',
        enableExpiryTracking:     false,
        enableBatchTracking:      false,
        enableProductGrade:       false,
        enableLowStockAlerts:     true,
        enableProductImages:      true,
        enableProductVariants:    false,
        enablePurchaseOrders:     false,
        enableStockAnalytics:     false,
      );

  // ── إنشاء إعدادات افتراضية بناء على نوع النشاط ────────────────────────────

  /// يُعيد نسخة جديدة مع الإعدادات الافتراضية المناسبة لنوع النشاط.
  /// الوحدات الأساسية (products, vouchers…) تبقى كما هي ولا تُغيَّر.
  InventoryPolicySettingsData applyProfileDefaults(BusinessProfile profile) {
    final d = _ProfileDefaults.forProfile(profile);
    return copyWith(
      businessProfile:       profile.key,
      enableExpiryTracking:  d.expiryTracking,
      enableBatchTracking:   d.batchTracking,
      enableProductGrade:    d.productGrade,
      enableLowStockAlerts:  d.lowStockAlerts,
      enableProductImages:   d.productImages,
      enableProductVariants: d.productVariants,
      enablePurchaseOrders:  d.purchaseOrders,
      enableStockAnalytics:  d.stockAnalytics,
    );
  }

  // ── تحميل من قاعدة البيانات ────────────────────────────────────────────────

  static bool _asBool(String? v, bool fallback) {
    if (v == null) return fallback;
    return v == '1';
  }

  static Future<InventoryPolicySettingsData> load(
    AppSettingsRepository repo,
  ) async {
    final d = defaults();
    final tenantId = TenantContextService.instance.activeTenantId;
    final keys = [
      InventoryPolicyKeys.enableProducts,
      InventoryPolicyKeys.enableAddProduct,
      InventoryPolicyKeys.enableVouchers,
      InventoryPolicyKeys.enablePriceLists,
      InventoryPolicyKeys.enableWarehouses,
      InventoryPolicyKeys.enableStocktaking,
      InventoryPolicyKeys.enableSettings,
      InventoryPolicyKeys.requireSourceOnInbound,
      InventoryPolicyKeys.businessProfile,
      InventoryPolicyKeys.enableExpiryTracking,
      InventoryPolicyKeys.enableBatchTracking,
      InventoryPolicyKeys.enableProductGrade,
      InventoryPolicyKeys.enableLowStockAlerts,
      InventoryPolicyKeys.enableProductImages,
      InventoryPolicyKeys.enableProductVariants,
      InventoryPolicyKeys.enablePurchaseOrders,
      InventoryPolicyKeys.enableStockAnalytics,
    ];
    final values = <String, String?>{};
    for (final k in keys) {
      values[k] = await repo.getForTenant(k, tenantId: tenantId);
    }
    return InventoryPolicySettingsData(
      enableProducts:     _asBool(values[InventoryPolicyKeys.enableProducts],     d.enableProducts),
      enableAddProduct:   _asBool(values[InventoryPolicyKeys.enableAddProduct],   d.enableAddProduct),
      enableVouchers:     _asBool(values[InventoryPolicyKeys.enableVouchers],     d.enableVouchers),
      enablePriceLists:   _asBool(values[InventoryPolicyKeys.enablePriceLists],   d.enablePriceLists),
      enableWarehouses:   _asBool(values[InventoryPolicyKeys.enableWarehouses],   d.enableWarehouses),
      enableStocktaking:  _asBool(values[InventoryPolicyKeys.enableStocktaking],  d.enableStocktaking),
      enableSettings:     _asBool(values[InventoryPolicyKeys.enableSettings],     d.enableSettings),
      requireSourceOnInbound: _asBool(
        values[InventoryPolicyKeys.requireSourceOnInbound],
        d.requireSourceOnInbound,
      ),
      businessProfile:       values[InventoryPolicyKeys.businessProfile] ?? d.businessProfile,
      enableExpiryTracking:  _asBool(values[InventoryPolicyKeys.enableExpiryTracking],  d.enableExpiryTracking),
      enableBatchTracking:   _asBool(values[InventoryPolicyKeys.enableBatchTracking],   d.enableBatchTracking),
      enableProductGrade:    _asBool(values[InventoryPolicyKeys.enableProductGrade],    d.enableProductGrade),
      enableLowStockAlerts:  _asBool(values[InventoryPolicyKeys.enableLowStockAlerts],  d.enableLowStockAlerts),
      enableProductImages:   _asBool(values[InventoryPolicyKeys.enableProductImages],   d.enableProductImages),
      enableProductVariants: _asBool(values[InventoryPolicyKeys.enableProductVariants], d.enableProductVariants),
      enablePurchaseOrders:  _asBool(values[InventoryPolicyKeys.enablePurchaseOrders],  d.enablePurchaseOrders),
      enableStockAnalytics:  _asBool(values[InventoryPolicyKeys.enableStockAnalytics],  d.enableStockAnalytics),
    );
  }

  // ── حفظ في قاعدة البيانات ──────────────────────────────────────────────────

  Future<void> save(AppSettingsRepository repo) async {
    final tenantId = TenantContextService.instance.activeTenantId;

    Future<void> b(String key, bool value) =>
        repo.setForTenant(key, value ? '1' : '0', tenantId: tenantId);
    Future<void> s(String key, String value) =>
        repo.setForTenant(key, value, tenantId: tenantId);

    await b(InventoryPolicyKeys.enableProducts,           enableProducts);
    await b(InventoryPolicyKeys.enableAddProduct,         enableAddProduct);
    await b(InventoryPolicyKeys.enableVouchers,           enableVouchers);
    await b(InventoryPolicyKeys.enablePriceLists,         enablePriceLists);
    await b(InventoryPolicyKeys.enableWarehouses,         enableWarehouses);
    await b(InventoryPolicyKeys.enableStocktaking,        enableStocktaking);
    await b(InventoryPolicyKeys.enableSettings,           enableSettings);
    await b(InventoryPolicyKeys.requireSourceOnInbound,   requireSourceOnInbound);
    await s(InventoryPolicyKeys.businessProfile,          businessProfile);
    await b(InventoryPolicyKeys.enableExpiryTracking,     enableExpiryTracking);
    await b(InventoryPolicyKeys.enableBatchTracking,      enableBatchTracking);
    await b(InventoryPolicyKeys.enableProductGrade,       enableProductGrade);
    await b(InventoryPolicyKeys.enableLowStockAlerts,     enableLowStockAlerts);
    await b(InventoryPolicyKeys.enableProductImages,      enableProductImages);
    await b(InventoryPolicyKeys.enableProductVariants,    enableProductVariants);
    await b(InventoryPolicyKeys.enablePurchaseOrders,     enablePurchaseOrders);
    await b(InventoryPolicyKeys.enableStockAnalytics,     enableStockAnalytics);
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  InventoryPolicySettingsData copyWith({
    bool?   enableProducts,
    bool?   enableAddProduct,
    bool?   enableVouchers,
    bool?   enablePriceLists,
    bool?   enableWarehouses,
    bool?   enableStocktaking,
    bool?   enableSettings,
    bool?   requireSourceOnInbound,
    String? businessProfile,
    bool?   enableExpiryTracking,
    bool?   enableBatchTracking,
    bool?   enableProductGrade,
    bool?   enableLowStockAlerts,
    bool?   enableProductImages,
    bool?   enableProductVariants,
    bool?   enablePurchaseOrders,
    bool?   enableStockAnalytics,
  }) {
    return InventoryPolicySettingsData(
      enableProducts:           enableProducts           ?? this.enableProducts,
      enableAddProduct:         enableAddProduct         ?? this.enableAddProduct,
      enableVouchers:           enableVouchers           ?? this.enableVouchers,
      enablePriceLists:         enablePriceLists         ?? this.enablePriceLists,
      enableWarehouses:         enableWarehouses         ?? this.enableWarehouses,
      enableStocktaking:        enableStocktaking        ?? this.enableStocktaking,
      enableSettings:           enableSettings           ?? this.enableSettings,
      requireSourceOnInbound:   requireSourceOnInbound   ?? this.requireSourceOnInbound,
      businessProfile:          businessProfile          ?? this.businessProfile,
      enableExpiryTracking:     enableExpiryTracking     ?? this.enableExpiryTracking,
      enableBatchTracking:      enableBatchTracking      ?? this.enableBatchTracking,
      enableProductGrade:       enableProductGrade       ?? this.enableProductGrade,
      enableLowStockAlerts:     enableLowStockAlerts     ?? this.enableLowStockAlerts,
      enableProductImages:      enableProductImages      ?? this.enableProductImages,
      enableProductVariants:    enableProductVariants    ?? this.enableProductVariants,
      enablePurchaseOrders:     enablePurchaseOrders     ?? this.enablePurchaseOrders,
      enableStockAnalytics:     enableStockAnalytics     ?? this.enableStockAnalytics,
    );
  }
}
