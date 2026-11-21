import 'package:flutter/material.dart';

import '../../../services/app_settings_repository.dart';
import '../models/oil_card_required_fields.dart';

/// أقسام «إضافات عند الحاجة» التي يمكن إظهارها/إخفاؤها من إعدادات المحل.
enum OilOptionalExtraKind {
  products,
  filters,
  hydraulicGear,
  hydraulicPower,
  services,
}

extension OilOptionalExtraKindUi on OilOptionalExtraKind {
  String get settingsKey => switch (this) {
        OilOptionalExtraKind.products =>
          OilChangeSettingsKeys.optionalExtrasProducts,
        OilOptionalExtraKind.filters =>
          OilChangeSettingsKeys.optionalExtrasFilters,
        OilOptionalExtraKind.hydraulicGear =>
          OilChangeSettingsKeys.optionalExtrasHydraulicGear,
        OilOptionalExtraKind.hydraulicPower =>
          OilChangeSettingsKeys.optionalExtrasHydraulicPower,
        OilOptionalExtraKind.services =>
          OilChangeSettingsKeys.optionalExtrasServices,
      };

  String get titleAr => switch (this) {
        OilOptionalExtraKind.products => 'المنتجات في البطاقة',
        OilOptionalExtraKind.filters => 'الفلاتر في البطاقة',
        OilOptionalExtraKind.hydraulicGear => 'هيدروليك الكير في البطاقة',
        OilOptionalExtraKind.hydraulicPower => 'هيدروليك الباور في البطاقة',
        OilOptionalExtraKind.services => 'الخدمات الإضافية في البطاقة',
      };

  String get subtitleOn => switch (this) {
        OilOptionalExtraKind.products =>
          'زر المنتجات يظهر ضمن إضافات بطاقة الغيار',
        OilOptionalExtraKind.filters =>
          'زر الفلاتر يظهر ضمن إضافات بطاقة الغيار',
        OilOptionalExtraKind.hydraulicGear =>
          'زر هيدروليك الكير يظهر ضمن إضافات بطاقة الغيار',
        OilOptionalExtraKind.hydraulicPower =>
          'زر هيدروليك الباور يظهر ضمن إضافات بطاقة الغيار',
        OilOptionalExtraKind.services =>
          'زر الخدمات الإضافية يظهر ضمن إضافات بطاقة الغيار',
      };

  String get subtitleOff => switch (this) {
        OilOptionalExtraKind.products => 'إخفاء قسم المنتجات من البطاقة',
        OilOptionalExtraKind.filters => 'إخفاء قسم الفلاتر من البطاقة',
        OilOptionalExtraKind.hydraulicGear =>
          'إخفاء قسم هيدروليك الكير من البطاقة',
        OilOptionalExtraKind.hydraulicPower =>
          'إخفاء قسم هيدروليك الباور من البطاقة',
        OilOptionalExtraKind.services =>
          'إخفاء قسم الخدمات الإضافية من البطاقة',
      };

  IconData get icon => switch (this) {
        OilOptionalExtraKind.products => Icons.inventory_2_outlined,
        OilOptionalExtraKind.filters => Icons.filter_alt_outlined,
        OilOptionalExtraKind.hydraulicGear => Icons.water_drop_outlined,
        OilOptionalExtraKind.hydraulicPower => Icons.water_drop_outlined,
        OilOptionalExtraKind.services => Icons.checklist_rounded,
      };
}

/// إعدادات محل غيار الزيت — مفاتيح ضمن نطاق التينانت.
abstract class OilChangeSettingsKeys {
  /// إرسال تلقائي عبر Evolution/n8n بعد حفظ بطاقة جديدة.
  static const whatsappAutoAfterSave = 'biz.oil.whatsapp_after_save';
  /// فتح تطبيق واتساب يدوياً برسالة جاهزة بعد الحفظ.
  static const whatsappManualAfterSave = 'biz.oil.whatsapp_manual_after_save';
  /// صرف زيت المحل من أصناف المخزون (لتر) عند حفظ البطاقة.
  static const stockFromWarehouse = 'biz.oil.stock_from_warehouse';
  /// صرف هيدروليك المحل من عائلات المخزون عند حفظ البطاقة.
  static const hydraulicStockFromWarehouse =
      'biz.oil.hydraulic_stock_from_warehouse';
  /// مصدر هيدروليك الكير وحده. غير مضبوط = يتبع المفتاح القديم المشترك.
  static const hydraulicGearStockFromWarehouse =
      'biz.oil.hydraulic_gear_stock_from_warehouse';
  /// مصدر هيدروليك الباور وحده. غير مضبوط = يتبع المفتاح القديم المشترك.
  static const hydraulicPowerStockFromWarehouse =
      'biz.oil.hydraulic_power_stock_from_warehouse';
  /// مصدر الفلاتر: «1» = من أصناف المخزون حسب حقل الصنف، وإلا أسماء وأسعار فقط.
  static const filtersStockFromWarehouse = 'biz.oil.filters_stock_from_warehouse';
  /// كمية الفلتر: «1» = قابلة للتعديل، وإلا قطعة واحدة دائماً.
  static const filterQuantityEditable = 'biz.oil.filter_quantity_editable';
  /// سعر تبديل الزيت الأساسي (فلس) — يُضاف دائماً لمجموع البطاقة.
  static const baseOilChangePriceFils = 'biz.oil.base_price_fils';
  /// محافظة المحل: تُوضع في لوحة كل بطاقة جديدة ما لم يغيّرها الموظف.
  static const defaultPlateProvince = 'biz.oil.default_plate_province';
  /// إلحاق دعوة تقييم (1–10 / ملاحظة) في نهاية رسالة واتساب بعد الحفظ.
  static const whatsappAskRatingAfterSave = 'biz.oil.whatsapp_ask_rating';
  /// (قديم) إظهار كل أقسام الإضافات دفعة واحدة — احتياط إن لم تُضبط المفاتيح المفردة.
  static const optionalExtrasOnCard = 'biz.oil.optional_extras_on_card';
  static const optionalExtrasProducts = 'biz.oil.optional_extras.products';
  static const optionalExtrasFilters = 'biz.oil.optional_extras.filters';
  static const optionalExtrasHydraulicGear =
      'biz.oil.optional_extras.hydraulic_gear';
  static const optionalExtrasHydraulicPower =
      'biz.oil.optional_extras.hydraulic_power';
  static const optionalExtrasServices = 'biz.oil.optional_extras.services';

  /// أجرة اليد حين يُحضر العميل الصنف (فلس). الزيت: فارغ = السعر الأساسي.
  static const customerLaborOil = 'biz.oil.customer_labor.oil';
  static const customerLaborHydraulicGear =
      'biz.oil.customer_labor.hydraulic_gear';
  static const customerLaborHydraulicPower =
      'biz.oil.customer_labor.hydraulic_power';
  static const customerLaborFilter = 'biz.oil.customer_labor.filter';
}

/// أجور اليد للأصناف التي يُحضرها العميل.
class OilCustomerLaborSettings {
  const OilCustomerLaborSettings({
    this.oilFils,
    this.hydraulicGearFils = 0,
    this.hydraulicPowerFils = 0,
    this.filterFils = 0,
  });

  /// null = تُستعمل أجرة التبديل الأساسية.
  final int? oilFils;
  final int hydraulicGearFils;
  final int hydraulicPowerFils;
  final int filterFils;

  static int? _parse(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    return v == null || v < 0 ? null : v;
  }

  factory OilCustomerLaborSettings.fromRaw(Map<String, String> raw) =>
      OilCustomerLaborSettings(
        oilFils: _parse(raw[OilChangeSettingsKeys.customerLaborOil]),
        hydraulicGearFils:
            _parse(raw[OilChangeSettingsKeys.customerLaborHydraulicGear]) ?? 0,
        hydraulicPowerFils:
            _parse(raw[OilChangeSettingsKeys.customerLaborHydraulicPower]) ?? 0,
        filterFils: _parse(raw[OilChangeSettingsKeys.customerLaborFilter]) ?? 0,
      );

  static const keys = [
    OilChangeSettingsKeys.customerLaborOil,
    OilChangeSettingsKeys.customerLaborHydraulicGear,
    OilChangeSettingsKeys.customerLaborHydraulicPower,
    OilChangeSettingsKeys.customerLaborFilter,
  ];
}

/// كل إعدادات بطاقة الغيار المقروءة عند فتحها، باستعلام واحد.
class OilChangeCardSettings {
  const OilChangeCardSettings({
    required this.stockFromWarehouse,
    required this.hydraulicStockFromWarehouse,
    bool? hydraulicGearStockFromWarehouse,
    bool? hydraulicPowerStockFromWarehouse,
    this.filtersStockFromWarehouse = false,
    this.filterQuantityEditable = false,
    required this.optionalExtras,
    required this.baseOilChangePriceFils,
    required this.whatsappAutoAfterSave,
    required this.whatsappManualAfterSave,
    required this.whatsappAskRatingAfterSave,
    required this.requiredFields,
    this.customerLabor = const OilCustomerLaborSettings(),
  })  : hydraulicGearStockFromWarehouse =
            hydraulicGearStockFromWarehouse ?? hydraulicStockFromWarehouse,
        hydraulicPowerStockFromWarehouse =
            hydraulicPowerStockFromWarehouse ?? hydraulicStockFromWarehouse;

  final bool stockFromWarehouse;

  /// المفتاح القديم المشترك (قبل فصل الكير عن الباور).
  final bool hydraulicStockFromWarehouse;
  final bool hydraulicGearStockFromWarehouse;
  final bool hydraulicPowerStockFromWarehouse;

  /// أي قسم هيدروليك مرتبط بالمخزون (لتحميل أصناف المخزون).
  bool get anyHydraulicStockFromWarehouse =>
      hydraulicGearStockFromWarehouse || hydraulicPowerStockFromWarehouse;
  final bool filtersStockFromWarehouse;
  final bool filterQuantityEditable;
  final Map<OilOptionalExtraKind, bool> optionalExtras;
  final int baseOilChangePriceFils;
  final bool whatsappAutoAfterSave;
  final bool whatsappManualAfterSave;
  final bool whatsappAskRatingAfterSave;
  final OilCardRequiredFields requiredFields;
  final OilCustomerLaborSettings customerLabor;

  /// نفس القيم الافتراضية التي تطبّقها دوال [OilChangeSettings] المفردة.
  factory OilChangeCardSettings.fromRaw(Map<String, String> raw) {
    bool onByDefault(String key) {
      final v = raw[key];
      return v == null || v == '1';
    }

    final legacyDefault = onByDefault(OilChangeSettingsKeys.optionalExtrasOnCard);
    final legacyHydraulic =
        onByDefault(OilChangeSettingsKeys.hydraulicStockFromWarehouse);
    bool hydraulicSlot(String key) {
      final v = raw[key]?.trim() ?? '';
      return v.isEmpty ? legacyHydraulic : v == '1';
    }

    final baseRaw = raw[OilChangeSettingsKeys.baseOilChangePriceFils]?.trim();
    return OilChangeCardSettings(
      stockFromWarehouse: onByDefault(OilChangeSettingsKeys.stockFromWarehouse),
      hydraulicStockFromWarehouse: legacyHydraulic,
      hydraulicGearStockFromWarehouse:
          hydraulicSlot(OilChangeSettingsKeys.hydraulicGearStockFromWarehouse),
      hydraulicPowerStockFromWarehouse:
          hydraulicSlot(OilChangeSettingsKeys.hydraulicPowerStockFromWarehouse),
      filtersStockFromWarehouse:
          raw[OilChangeSettingsKeys.filtersStockFromWarehouse] == '1',
      filterQuantityEditable:
          raw[OilChangeSettingsKeys.filterQuantityEditable] == '1',
      optionalExtras: {
        for (final kind in OilOptionalExtraKind.values)
          kind: raw[kind.settingsKey] == null
              ? legacyDefault
              : raw[kind.settingsKey] == '1',
      },
      baseOilChangePriceFils:
          baseRaw == null || baseRaw.isEmpty ? 0 : int.tryParse(baseRaw) ?? 0,
      whatsappAutoAfterSave:
          raw[OilChangeSettingsKeys.whatsappAutoAfterSave] == '1',
      whatsappManualAfterSave:
          raw[OilChangeSettingsKeys.whatsappManualAfterSave] == '1',
      whatsappAskRatingAfterSave:
          onByDefault(OilChangeSettingsKeys.whatsappAskRatingAfterSave),
      requiredFields: OilCardRequiredFields.fromRaw(raw),
      customerLabor: OilCustomerLaborSettings.fromRaw(raw),
    );
  }

  static List<String> get keys => [
        OilChangeSettingsKeys.stockFromWarehouse,
        OilChangeSettingsKeys.hydraulicStockFromWarehouse,
        OilChangeSettingsKeys.hydraulicGearStockFromWarehouse,
        OilChangeSettingsKeys.hydraulicPowerStockFromWarehouse,
        OilChangeSettingsKeys.filtersStockFromWarehouse,
        OilChangeSettingsKeys.filterQuantityEditable,
        OilChangeSettingsKeys.optionalExtrasOnCard,
        for (final kind in OilOptionalExtraKind.values) kind.settingsKey,
        OilChangeSettingsKeys.baseOilChangePriceFils,
        OilChangeSettingsKeys.whatsappAutoAfterSave,
        OilChangeSettingsKeys.whatsappManualAfterSave,
        OilChangeSettingsKeys.whatsappAskRatingAfterSave,
        ...OilCardRequiredFields.keys,
        ...OilCustomerLaborSettings.keys,
      ];
}

class OilChangeSettings {
  OilChangeSettings._();

  /// قراءة واحدة لكل إعدادات البطاقة (بدل نحو 17 قراءة متتالية).
  ///
  /// الطلبات المتزامنة أثناء فتح البطاقة تتشارك نفس القراءة.
  static Future<OilChangeCardSettings> loadCardSettings() {
    final pending = _cardSettingsInFlight;
    if (pending != null) return pending;
    final f = _readCardSettings();
    _cardSettingsInFlight = f;
    f.whenComplete(() {
      if (identical(_cardSettingsInFlight, f)) _cardSettingsInFlight = null;
    }).ignore();
    return f;
  }

  static Future<OilChangeCardSettings>? _cardSettingsInFlight;

  /// [fils] = null يمسح القيمة (للزيت: يعود للسعر الأساسي، ولغيره: صفر).
  static Future<void> setCustomerLaborFils(String key, int? fils) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      key,
      fils == null || fils < 0 ? '' : '$fils',
      tenantId: tenantId,
    );
  }

  /// إعداد تشغيل/إيقاف عام لبطاقة الغيار ('1' / '0').
  static Future<void> setCardFlag(String key, bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(key, enabled ? '1' : '0', tenantId: tenantId);
  }

  static Future<void> setFieldRequired(OilCardField field, bool required) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      field.settingsKey,
      required ? '1' : '0',
      tenantId: tenantId,
    );
  }

  static Future<OilChangeCardSettings> _readCardSettings() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getKeysForTenant(
      OilChangeCardSettings.keys,
      tenantId: tenantId,
    );
    return OilChangeCardSettings.fromRaw(raw);
  }

  static Future<bool> whatsappAutoAfterSaveEnabled() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.whatsappAutoAfterSave,
      tenantId: tenantId,
    );
    return raw == '1';
  }

  static Future<void> setWhatsappAutoAfterSave(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.whatsappAutoAfterSave,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
    if (enabled) {
      await repo.setForTenant(
        OilChangeSettingsKeys.whatsappManualAfterSave,
        '0',
        tenantId: tenantId,
      );
    }
  }

  static Future<bool> whatsappManualAfterSaveEnabled() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.whatsappManualAfterSave,
      tenantId: tenantId,
    );
    return raw == '1';
  }

  static Future<void> setWhatsappManualAfterSave(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.whatsappManualAfterSave,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
    if (enabled) {
      await repo.setForTenant(
        OilChangeSettingsKeys.whatsappAutoAfterSave,
        '0',
        tenantId: tenantId,
      );
    }
  }

  /// `true` افتراضياً عند عدم وجود إعداد — يحافظ على سلوك المخزون السابق.
  static Future<bool> stockFromWarehouseEnabled() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.stockFromWarehouse,
      tenantId: tenantId,
    );
    return raw == null || raw == '1';
  }

  static Future<void> setStockFromWarehouse(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.stockFromWarehouse,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
  }

  /// `true` إن كان أي من الكير أو الباور مرتبطاً بالمخزون.
  static Future<bool> hydraulicStockFromWarehouseEnabled() async =>
      (await loadCardSettings()).anyHydraulicStockFromWarehouse;

  /// المفتاح المشترك القديم: يضبط الكير والباور معاً.
  static Future<void> setHydraulicStockFromWarehouse(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    for (final key in [
      OilChangeSettingsKeys.hydraulicStockFromWarehouse,
      OilChangeSettingsKeys.hydraulicGearStockFromWarehouse,
      OilChangeSettingsKeys.hydraulicPowerStockFromWarehouse,
    ]) {
      await repo.setForTenant(key, enabled ? '1' : '0', tenantId: tenantId);
    }
  }

  static Future<int> getBaseOilChangePriceFils() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.baseOilChangePriceFils,
      tenantId: tenantId,
    );
    if (raw == null || raw.trim().isEmpty) return 0;
    return int.tryParse(raw.trim()) ?? 0;
  }

  /// محافظة المحل للوحات الجديدة، أو null (بلا محافظة).
  static Future<String?> getDefaultPlateProvince() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.defaultPlateProvince,
      tenantId: tenantId,
    );
    final v = (raw ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> setDefaultPlateProvince(String? province) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.defaultPlateProvince,
      (province ?? '').trim(),
      tenantId: tenantId,
    );
  }

  static Future<void> setBaseOilChangePriceFils(int fils) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final safe = fils < 0 ? 0 : fils;
    await repo.setForTenant(
      OilChangeSettingsKeys.baseOilChangePriceFils,
      '$safe',
      tenantId: tenantId,
    );
  }

  /// `true` افتراضياً — دعوة التقييم في نهاية رسالة واتساب بعد الحفظ.
  static Future<bool> whatsappAskRatingAfterSaveEnabled() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.whatsappAskRatingAfterSave,
      tenantId: tenantId,
    );
    return raw == null || raw == '1';
  }

  static Future<void> setWhatsappAskRatingAfterSave(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.whatsappAskRatingAfterSave,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
  }

  /// هل يظهر أي قسم إضافات؟ (للتوافق مع الاستدعاءات القديمة).
  static Future<bool> optionalExtrasOnCardEnabled() async {
    final flags = await loadOptionalExtraFlags();
    return flags.values.any((v) => v);
  }

  static Future<void> setOptionalExtrasOnCard(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.optionalExtrasOnCard,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
    for (final kind in OilOptionalExtraKind.values) {
      await repo.setForTenant(
        kind.settingsKey,
        enabled ? '1' : '0',
        tenantId: tenantId,
      );
    }
  }

  /// يحمّل إظهار كل قسم على حدة. إن لم يُضبط المفتاح المفرد:
  /// يتبع المفتاح القديم `optional_extras_on_card` (افتراضياً يظهر).
  static Future<Map<OilOptionalExtraKind, bool>> loadOptionalExtraFlags() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final legacyRaw = await repo.getForTenant(
      OilChangeSettingsKeys.optionalExtrasOnCard,
      tenantId: tenantId,
    );
    final legacyDefault = legacyRaw == null || legacyRaw == '1';

    final out = <OilOptionalExtraKind, bool>{};
    for (final kind in OilOptionalExtraKind.values) {
      final raw = await repo.getForTenant(
        kind.settingsKey,
        tenantId: tenantId,
      );
      if (raw == null) {
        out[kind] = legacyDefault;
      } else {
        out[kind] = raw == '1';
      }
    }
    return out;
  }

  static Future<bool> optionalExtraEnabled(OilOptionalExtraKind kind) async {
    final flags = await loadOptionalExtraFlags();
    return flags[kind] ?? true;
  }

  static Future<void> setOptionalExtra(
    OilOptionalExtraKind kind,
    bool enabled,
  ) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      kind.settingsKey,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
  }
}
