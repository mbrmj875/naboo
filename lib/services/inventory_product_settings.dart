import 'app_settings_repository.dart';
import 'tenant_context_service.dart';

/// مفاتيح إعدادات المنتجات والمخزون (جدول [app_settings]).
abstract class InventoryProductSettingsKeys {
  // —— تهيئة المنتجات
  static const prodNextSku = 'inv.prod.next_sku';
  static const prodSkuPrefix = 'inv.prod.sku_prefix';

  /// `numeric` | `alpha` | `alnum`
  static const prodSkuFormat = 'inv.prod.sku_format';
  static const prodSkuDigitWidth = 'inv.prod.sku_digit_width';
  static const prodSkuUnique = 'inv.prod.sku_unique';
  static const prodSkuPrefixEnabled = 'inv.prod.prefix_enabled';
  static const prodAdvancedPricing = 'inv.prod.advanced_pricing';
  /// هامش % على سعر الشراء لاقتراح سعر البيع (عند تفعيل [prodAdvancedPricing]).
  static const prodSuggestedMarginPercent = 'inv.prod.suggested_margin_percent';
  /// أقل سعر بيع = نسبة من سعر البيع المقترح (1–100).
  static const prodMinSellPercentOfSell = 'inv.prod.min_sell_percent_of_sell';
  static const prodMultiUnit = 'inv.prod.multi_unit';
  static const prodDefaultUnitView = 'inv.prod.default_unit_view';
  static const prodBundles = 'inv.prod.bundles';

  // —— تتبع المنتجات
  static const trackSerialBatch = 'inv.track.serial_batch_expiry';
  static const trackNegativeMode = 'inv.track.negative_mode';
  static const trackShowTotalAvailable = 'inv.track.show_total_available';

  // —— الأذون المخزنية
  static const vchRequests = 'inv.voucher.requests_enabled';
  static const vchNextTransferNo = 'inv.voucher.next_transfer_no';
  static const vchTransferPrefix = 'inv.voucher.transfer_prefix';
  static const vchSalesPerm = 'inv.voucher.sales_perm';
  static const vchPurchasePerm = 'inv.voucher.purchase_perm';

  // —— القيم الافتراضية
  static const defSubAccount = 'inv.defaults.sub_account';
  static const defWarehouseId = 'inv.defaults.warehouse_id';
  static const defPriceListId = 'inv.defaults.price_list_id';
  static const defTax1 = 'inv.defaults.tax1';
  static const defTax2 = 'inv.defaults.tax2';
  static const defReturnCost = 'inv.defaults.return_cost_method';
  static const defBusinessNature = 'inv.defaults.business_nature';

  // —— إعدادات شاشة إضافة المنتج
  static const addShowAdvancedPricing = 'inv.add_product.show_advanced_pricing';
  static const addShowTaxField = 'inv.add_product.show_tax_field';
  static const addShowDiscountFields = 'inv.add_product.show_discount_fields';
  static const addShowImageField = 'inv.add_product.show_image_field';
  static const addShowBarcodeField = 'inv.add_product.show_barcode_field';
  static const addShowExtraFields = 'inv.add_product.show_extra_fields';
  static const addRequireBarcode = 'inv.add_product.require_barcode';
  static const addRequireSupplier = 'inv.add_product.require_supplier';
  static const addRequireWarehouse = 'inv.add_product.require_warehouse';
  static const addRequireImage = 'inv.add_product.require_image';
  static const addDefaultTrackInventory =
      'inv.add_product.default_track_inventory';
}

/// قيم محمّلة من التخزين مع افتراضات آمنة.
class InventoryProductSettingsData {
  const InventoryProductSettingsData({
    required this.nextSkuText,
    required this.skuPrefix,
    required this.skuNumberFormat,
    required this.skuDigitWidth,
    required this.skuUniqueSequential,
    required this.skuPrefixEnabled,
    required this.advancedPricing,
    required this.suggestedMarginPercent,
    required this.minSellPercentOfSell,
    required this.multiUnitPerItem,
    required this.defaultUnitView,
    required this.bundlesEnabled,
    required this.trackSerialBatchExpiry,
    required this.negativeStockMode,
    required this.showTotalAndAvailable,
    required this.inventoryRequestsEnabled,
    required this.nextTransferNo,
    required this.transferPrefix,
    required this.salesVoucherPerm,
    required this.purchaseVoucherPerm,
    required this.subAccountLabel,
    required this.defaultWarehouseId,
    required this.defaultPriceListId,
    required this.defaultTax1,
    required this.defaultTax2,
    required this.returnCostMethod,
    required this.businessNature,
    required this.addShowAdvancedPricing,
    required this.addShowTaxField,
    required this.addShowDiscountFields,
    required this.addShowImageField,
    required this.addShowBarcodeField,
    required this.addShowExtraFields,
    required this.addRequireBarcode,
    required this.addRequireSupplier,
    required this.addRequireWarehouse,
    required this.addRequireImage,
    required this.addDefaultTrackInventory,
  });

  final String nextSkuText;
  final String skuPrefix;

  /// `numeric` | `alpha` | `alnum`
  final String skuNumberFormat;

  /// عدد الخانات مع أصفار يسارية
  final String skuDigitWidth;
  final bool skuUniqueSequential;
  final bool skuPrefixEnabled;
  final bool advancedPricing;
  /// هامش على التكلفة كنسبة مئوية (مثلاً 25 يعني سعر بيع ≈ تكلفة × 1.25).
  final double suggestedMarginPercent;
  /// أقل سعر بيع كنسبة من سعر البيع (100 = مساوٍ لسعر البيع).
  final double minSellPercentOfSell;
  final bool multiUnitPerItem;

  /// `base` | `sale` | `purchase`
  final String defaultUnitView;
  final bool bundlesEnabled;

  final bool trackSerialBatchExpiry;

  /// `stop_all` | `tracked_only`
  final String negativeStockMode;
  final bool showTotalAndAvailable;

  final bool inventoryRequestsEnabled;
  final String nextTransferNo;
  final String transferPrefix;
  final bool salesVoucherPerm;
  final bool purchaseVoucherPerm;

  final String subAccountLabel;
  final int? defaultWarehouseId;
  final int? defaultPriceListId;

  /// مفاتيح ضريبة مطابقة لنمط إضافة المنتج: معفى | 5 | 10 | 15 | مخصص
  final String defaultTax1;
  final String defaultTax2;

  /// `sell_price` | `last_avg`
  final String returnCostMethod;

  /// `products` | `services` | `both`
  final String businessNature;

  // إعدادات شاشة إضافة المنتج
  final bool addShowAdvancedPricing;
  final bool addShowTaxField;
  final bool addShowDiscountFields;
  final bool addShowImageField;
  final bool addShowBarcodeField;
  final bool addShowExtraFields;
  final bool addRequireBarcode;
  final bool addRequireSupplier;
  final bool addRequireWarehouse;
  final bool addRequireImage;
  final bool addDefaultTrackInventory;

  static InventoryProductSettingsData fromRaw(Map<String, String?> raw) {
    String g(String k, String d) => raw[k] ?? d;
    bool b(String k, bool d) => (raw[k] ?? (d ? '1' : '0')) == '1';

    return InventoryProductSettingsData(
      nextSkuText: g(InventoryProductSettingsKeys.prodNextSku, ''),
      skuPrefix: g(InventoryProductSettingsKeys.prodSkuPrefix, ''),
      skuNumberFormat: g(InventoryProductSettingsKeys.prodSkuFormat, 'numeric'),
      skuDigitWidth: g(InventoryProductSettingsKeys.prodSkuDigitWidth, '1'),
      skuUniqueSequential: b(InventoryProductSettingsKeys.prodSkuUnique, true),
      skuPrefixEnabled: b(
        InventoryProductSettingsKeys.prodSkuPrefixEnabled,
        false,
      ),
      advancedPricing: b(
        InventoryProductSettingsKeys.prodAdvancedPricing,
        false,
      ),
      suggestedMarginPercent: () {
        final v = double.tryParse(
              g(InventoryProductSettingsKeys.prodSuggestedMarginPercent, '25')
                  .replaceAll(',', '.')) ??
            25.0;
        return v.clamp(0.0, 500.0);
      }(),
      minSellPercentOfSell: () {
        final v = double.tryParse(
              g(InventoryProductSettingsKeys.prodMinSellPercentOfSell, '100')
                  .replaceAll(',', '.')) ??
            100.0;
        return v.clamp(1.0, 100.0);
      }(),
      multiUnitPerItem: b(InventoryProductSettingsKeys.prodMultiUnit, false),
      defaultUnitView: g(
        InventoryProductSettingsKeys.prodDefaultUnitView,
        'base',
      ),
      bundlesEnabled: b(InventoryProductSettingsKeys.prodBundles, false),
      trackSerialBatchExpiry: b(
        InventoryProductSettingsKeys.trackSerialBatch,
        false,
      ),
      negativeStockMode: g(
        InventoryProductSettingsKeys.trackNegativeMode,
        'tracked_only',
      ),
      showTotalAndAvailable: b(
        InventoryProductSettingsKeys.trackShowTotalAvailable,
        false,
      ),
      inventoryRequestsEnabled: b(
        InventoryProductSettingsKeys.vchRequests,
        false,
      ),
      nextTransferNo: g(
        InventoryProductSettingsKeys.vchNextTransferNo,
        '000001',
      ),
      transferPrefix: g(InventoryProductSettingsKeys.vchTransferPrefix, ''),
      salesVoucherPerm: b(InventoryProductSettingsKeys.vchSalesPerm, false),
      purchaseVoucherPerm: b(
        InventoryProductSettingsKeys.vchPurchasePerm,
        false,
      ),
      subAccountLabel: g(InventoryProductSettingsKeys.defSubAccount, ''),
      defaultWarehouseId: int.tryParse(
        raw[InventoryProductSettingsKeys.defWarehouseId] ?? '',
      ),
      defaultPriceListId: int.tryParse(
        raw[InventoryProductSettingsKeys.defPriceListId] ?? '',
      ),
      defaultTax1: g(InventoryProductSettingsKeys.defTax1, 'معفى'),
      defaultTax2: g(InventoryProductSettingsKeys.defTax2, 'معفى'),
      returnCostMethod: g(
        InventoryProductSettingsKeys.defReturnCost,
        'sell_price',
      ),
      businessNature: g(
        InventoryProductSettingsKeys.defBusinessNature,
        'products',
      ),
      addShowAdvancedPricing: b(
        InventoryProductSettingsKeys.addShowAdvancedPricing,
        true,
      ),
      addShowTaxField: b(InventoryProductSettingsKeys.addShowTaxField, true),
      addShowDiscountFields: b(
        InventoryProductSettingsKeys.addShowDiscountFields,
        true,
      ),
      addShowImageField: b(
        InventoryProductSettingsKeys.addShowImageField,
        true,
      ),
      addShowBarcodeField: b(
        InventoryProductSettingsKeys.addShowBarcodeField,
        true,
      ),
      addShowExtraFields: b(
        InventoryProductSettingsKeys.addShowExtraFields,
        true,
      ),
      addRequireBarcode: b(
        InventoryProductSettingsKeys.addRequireBarcode,
        false,
      ),
      addRequireSupplier: b(
        InventoryProductSettingsKeys.addRequireSupplier,
        false,
      ),
      addRequireWarehouse: b(
        InventoryProductSettingsKeys.addRequireWarehouse,
        false,
      ),
      addRequireImage: b(InventoryProductSettingsKeys.addRequireImage, false),
      addDefaultTrackInventory: b(
        InventoryProductSettingsKeys.addDefaultTrackInventory,
        true,
      ),
    );
  }

  static Future<InventoryProductSettingsData> load(
    AppSettingsRepository repo,
  ) async {
    const keys = [
      InventoryProductSettingsKeys.prodNextSku,
      InventoryProductSettingsKeys.prodSkuPrefix,
      InventoryProductSettingsKeys.prodSkuFormat,
      InventoryProductSettingsKeys.prodSkuDigitWidth,
      InventoryProductSettingsKeys.prodSkuUnique,
      InventoryProductSettingsKeys.prodSkuPrefixEnabled,
      InventoryProductSettingsKeys.prodAdvancedPricing,
      InventoryProductSettingsKeys.prodSuggestedMarginPercent,
      InventoryProductSettingsKeys.prodMinSellPercentOfSell,
      InventoryProductSettingsKeys.prodMultiUnit,
      InventoryProductSettingsKeys.prodDefaultUnitView,
      InventoryProductSettingsKeys.prodBundles,
      InventoryProductSettingsKeys.trackSerialBatch,
      InventoryProductSettingsKeys.trackNegativeMode,
      InventoryProductSettingsKeys.trackShowTotalAvailable,
      InventoryProductSettingsKeys.vchRequests,
      InventoryProductSettingsKeys.vchNextTransferNo,
      InventoryProductSettingsKeys.vchTransferPrefix,
      InventoryProductSettingsKeys.vchSalesPerm,
      InventoryProductSettingsKeys.vchPurchasePerm,
      InventoryProductSettingsKeys.defSubAccount,
      InventoryProductSettingsKeys.defWarehouseId,
      InventoryProductSettingsKeys.defPriceListId,
      InventoryProductSettingsKeys.defTax1,
      InventoryProductSettingsKeys.defTax2,
      InventoryProductSettingsKeys.defReturnCost,
      InventoryProductSettingsKeys.defBusinessNature,
      InventoryProductSettingsKeys.addShowAdvancedPricing,
      InventoryProductSettingsKeys.addShowTaxField,
      InventoryProductSettingsKeys.addShowDiscountFields,
      InventoryProductSettingsKeys.addShowImageField,
      InventoryProductSettingsKeys.addShowBarcodeField,
      InventoryProductSettingsKeys.addShowExtraFields,
      InventoryProductSettingsKeys.addRequireBarcode,
      InventoryProductSettingsKeys.addRequireSupplier,
      InventoryProductSettingsKeys.addRequireWarehouse,
      InventoryProductSettingsKeys.addRequireImage,
      InventoryProductSettingsKeys.addDefaultTrackInventory,
    ];
    final raw = <String, String?>{};
    final tenantId = TenantContextService.instance.activeTenantId;
    for (final k in keys) {
      raw[k] = await repo.getForTenant(k, tenantId: tenantId);
    }
    return fromRaw(raw);
  }

  Future<void> save(AppSettingsRepository repo) async {
    final tenantId = TenantContextService.instance.activeTenantId;
    Future<void> s(String k, String v) =>
        repo.setForTenant(k, v, tenantId: tenantId);

    await s(InventoryProductSettingsKeys.prodNextSku, nextSkuText);
    await s(InventoryProductSettingsKeys.prodSkuPrefix, skuPrefix);
    await s(InventoryProductSettingsKeys.prodSkuFormat, skuNumberFormat);
    await s(InventoryProductSettingsKeys.prodSkuDigitWidth, skuDigitWidth);
    await s(
      InventoryProductSettingsKeys.prodSkuUnique,
      skuUniqueSequential ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.prodSkuPrefixEnabled,
      skuPrefixEnabled ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.prodAdvancedPricing,
      advancedPricing ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.prodSuggestedMarginPercent,
      suggestedMarginPercent.toString(),
    );
    await s(
      InventoryProductSettingsKeys.prodMinSellPercentOfSell,
      minSellPercentOfSell.toString(),
    );
    await s(
      InventoryProductSettingsKeys.prodMultiUnit,
      multiUnitPerItem ? '1' : '0',
    );
    await s(InventoryProductSettingsKeys.prodDefaultUnitView, defaultUnitView);
    await s(
      InventoryProductSettingsKeys.prodBundles,
      bundlesEnabled ? '1' : '0',
    );

    await s(
      InventoryProductSettingsKeys.trackSerialBatch,
      trackSerialBatchExpiry ? '1' : '0',
    );
    await s(InventoryProductSettingsKeys.trackNegativeMode, negativeStockMode);
    await s(
      InventoryProductSettingsKeys.trackShowTotalAvailable,
      showTotalAndAvailable ? '1' : '0',
    );

    await s(
      InventoryProductSettingsKeys.vchRequests,
      inventoryRequestsEnabled ? '1' : '0',
    );
    await s(InventoryProductSettingsKeys.vchNextTransferNo, nextTransferNo);
    await s(InventoryProductSettingsKeys.vchTransferPrefix, transferPrefix);
    await s(
      InventoryProductSettingsKeys.vchSalesPerm,
      salesVoucherPerm ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.vchPurchasePerm,
      purchaseVoucherPerm ? '1' : '0',
    );

    await s(InventoryProductSettingsKeys.defSubAccount, subAccountLabel);
    await s(
      InventoryProductSettingsKeys.defWarehouseId,
      defaultWarehouseId?.toString() ?? '',
    );
    await s(
      InventoryProductSettingsKeys.defPriceListId,
      defaultPriceListId?.toString() ?? '',
    );
    await s(InventoryProductSettingsKeys.defTax1, defaultTax1);
    await s(InventoryProductSettingsKeys.defTax2, defaultTax2);
    await s(InventoryProductSettingsKeys.defReturnCost, returnCostMethod);
    await s(InventoryProductSettingsKeys.defBusinessNature, businessNature);
    await s(
      InventoryProductSettingsKeys.addShowAdvancedPricing,
      addShowAdvancedPricing ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addShowTaxField,
      addShowTaxField ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addShowDiscountFields,
      addShowDiscountFields ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addShowImageField,
      addShowImageField ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addShowBarcodeField,
      addShowBarcodeField ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addShowExtraFields,
      addShowExtraFields ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addRequireBarcode,
      addRequireBarcode ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addRequireSupplier,
      addRequireSupplier ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addRequireWarehouse,
      addRequireWarehouse ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addRequireImage,
      addRequireImage ? '1' : '0',
    );
    await s(
      InventoryProductSettingsKeys.addDefaultTrackInventory,
      addDefaultTrackInventory ? '1' : '0',
    );
  }

  InventoryProductSettingsData copyWith({
    String? nextSkuText,
    String? skuPrefix,
    String? skuNumberFormat,
    String? skuDigitWidth,
    bool? skuUniqueSequential,
    bool? skuPrefixEnabled,
    bool? advancedPricing,
    double? suggestedMarginPercent,
    double? minSellPercentOfSell,
    bool? multiUnitPerItem,
    String? defaultUnitView,
    bool? bundlesEnabled,
    bool? trackSerialBatchExpiry,
    String? negativeStockMode,
    bool? showTotalAndAvailable,
    bool? inventoryRequestsEnabled,
    String? nextTransferNo,
    String? transferPrefix,
    bool? salesVoucherPerm,
    bool? purchaseVoucherPerm,
    String? subAccountLabel,
    int? defaultWarehouseId,
    int? defaultPriceListId,
    bool clearWarehouseId = false,
    bool clearPriceListId = false,
    String? defaultTax1,
    String? defaultTax2,
    String? returnCostMethod,
    String? businessNature,
    bool? addShowAdvancedPricing,
    bool? addShowTaxField,
    bool? addShowDiscountFields,
    bool? addShowImageField,
    bool? addShowBarcodeField,
    bool? addShowExtraFields,
    bool? addRequireBarcode,
    bool? addRequireSupplier,
    bool? addRequireWarehouse,
    bool? addRequireImage,
    bool? addDefaultTrackInventory,
  }) {
    return InventoryProductSettingsData(
      nextSkuText: nextSkuText ?? this.nextSkuText,
      skuPrefix: skuPrefix ?? this.skuPrefix,
      skuNumberFormat: skuNumberFormat ?? this.skuNumberFormat,
      skuDigitWidth: skuDigitWidth ?? this.skuDigitWidth,
      skuUniqueSequential: skuUniqueSequential ?? this.skuUniqueSequential,
      skuPrefixEnabled: skuPrefixEnabled ?? this.skuPrefixEnabled,
      advancedPricing: advancedPricing ?? this.advancedPricing,
      suggestedMarginPercent:
          suggestedMarginPercent ?? this.suggestedMarginPercent,
      minSellPercentOfSell:
          minSellPercentOfSell ?? this.minSellPercentOfSell,
      multiUnitPerItem: multiUnitPerItem ?? this.multiUnitPerItem,
      defaultUnitView: defaultUnitView ?? this.defaultUnitView,
      bundlesEnabled: bundlesEnabled ?? this.bundlesEnabled,
      trackSerialBatchExpiry:
          trackSerialBatchExpiry ?? this.trackSerialBatchExpiry,
      negativeStockMode: negativeStockMode ?? this.negativeStockMode,
      showTotalAndAvailable:
          showTotalAndAvailable ?? this.showTotalAndAvailable,
      inventoryRequestsEnabled:
          inventoryRequestsEnabled ?? this.inventoryRequestsEnabled,
      nextTransferNo: nextTransferNo ?? this.nextTransferNo,
      transferPrefix: transferPrefix ?? this.transferPrefix,
      salesVoucherPerm: salesVoucherPerm ?? this.salesVoucherPerm,
      purchaseVoucherPerm: purchaseVoucherPerm ?? this.purchaseVoucherPerm,
      subAccountLabel: subAccountLabel ?? this.subAccountLabel,
      defaultWarehouseId: clearWarehouseId
          ? null
          : (defaultWarehouseId ?? this.defaultWarehouseId),
      defaultPriceListId: clearPriceListId
          ? null
          : (defaultPriceListId ?? this.defaultPriceListId),
      defaultTax1: defaultTax1 ?? this.defaultTax1,
      defaultTax2: defaultTax2 ?? this.defaultTax2,
      returnCostMethod: returnCostMethod ?? this.returnCostMethod,
      businessNature: businessNature ?? this.businessNature,
      addShowAdvancedPricing:
          addShowAdvancedPricing ?? this.addShowAdvancedPricing,
      addShowTaxField: addShowTaxField ?? this.addShowTaxField,
      addShowDiscountFields:
          addShowDiscountFields ?? this.addShowDiscountFields,
      addShowImageField: addShowImageField ?? this.addShowImageField,
      addShowBarcodeField: addShowBarcodeField ?? this.addShowBarcodeField,
      addShowExtraFields: addShowExtraFields ?? this.addShowExtraFields,
      addRequireBarcode: addRequireBarcode ?? this.addRequireBarcode,
      addRequireSupplier: addRequireSupplier ?? this.addRequireSupplier,
      addRequireWarehouse: addRequireWarehouse ?? this.addRequireWarehouse,
      addRequireImage: addRequireImage ?? this.addRequireImage,
      addDefaultTrackInventory:
          addDefaultTrackInventory ?? this.addDefaultTrackInventory,
    );
  }
}
