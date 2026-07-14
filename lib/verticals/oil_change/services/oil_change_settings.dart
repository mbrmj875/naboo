import '../../../services/app_settings_repository.dart';

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
}
