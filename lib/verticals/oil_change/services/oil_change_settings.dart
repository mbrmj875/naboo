import 'package:flutter/material.dart';

import '../../../services/app_settings_repository.dart';

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
  /// سعر تبديل الزيت الأساسي (فلس) — يُضاف دائماً لمجموع البطاقة.
  static const baseOilChangePriceFils = 'biz.oil.base_price_fils';
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
}

class OilChangeSettings {
  OilChangeSettings._();

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

  /// `true` افتراضياً — نفس سلوك الزيت.
  static Future<bool> hydraulicStockFromWarehouseEnabled() async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getForTenant(
      OilChangeSettingsKeys.hydraulicStockFromWarehouse,
      tenantId: tenantId,
    );
    return raw == null || raw == '1';
  }

  static Future<void> setHydraulicStockFromWarehouse(bool enabled) async {
    final repo = AppSettingsRepository.instance;
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      OilChangeSettingsKeys.hydraulicStockFromWarehouse,
      enabled ? '1' : '0',
      tenantId: tenantId,
    );
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
