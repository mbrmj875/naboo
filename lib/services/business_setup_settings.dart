import 'package:flutter/foundation.dart';

import 'app_settings_repository.dart';

/// معرّفات نشاط المتجر (vertical) — تُخزَّن في [BusinessSetupKeys.businessVertical].
abstract class BusinessVertical {
  static const oilChange = 'oil_change';
  static const supermarket = 'supermarket';
  static const clothingStore = 'clothing_store';
  static const generalRetail = 'general_retail';
  static const pharmacy = 'pharmacy';
  static const restaurantCafe = 'restaurant_cafe';

  /// العرض في onboarding — [oilChange].
  static const oilChangeDisplayNameAr = 'محل زيت وصيانة سيارات';

  static const all = <String>[
    oilChange,
    supermarket,
    clothingStore,
    generalRetail,
    pharmacy,
    restaurantCafe,
  ];

  static bool isKnown(String? value) {
    final v = value?.trim() ?? '';
    return v.isNotEmpty && all.contains(v);
  }
}

/// إعدادات "التخصص" الأولي للتطبيق — تُحفظ في جدول `app_settings` ضمن نطاق التينانت.
abstract class BusinessSetupKeys {
  static const onboardingCompleted = 'biz.onboarding.completed';
  static const businessVertical = 'biz.vertical';
  /// يُفعَّل بعد أول اختيار للتخصص — يمنع تغيير [businessVertical] لاحقاً.
  static const verticalLocked = 'biz.vertical.locked';
  static const migrationFeatureGateV1 = 'biz.migration.feature_gate_v1';

  static const enableDebts = 'biz.feature.debts';
  static const enableInstallments = 'biz.feature.installments';
  static const enableWeightSales = 'biz.feature.weight_sales';
  static const enableCustomers = 'biz.feature.customers';
  static const enableLoyalty = 'biz.feature.loyalty';
  static const enableTaxOnSale = 'biz.feature.sale_tax';
  static const enableInvoiceDiscount = 'biz.feature.sale_discount';
  static const enableClothingVariants = 'biz.feature.clothing_variants';

  /// مفتاح قديم — للقراءة في الترحيل فقط (v1.0.2). يُزامَن عند الحفظ مع oil+repair.
  static const enableServices = 'biz.feature.services';

  static const enableOilChange = 'biz.feature.oil_change';
  static const enableRepairServices = 'biz.feature.repair_services';
  static const enablePos = 'biz.feature.pos';
}

class BusinessSetupSettingsData {
  const BusinessSetupSettingsData({
    required this.onboardingCompleted,
    required this.businessVertical,
    required this.enableDebts,
    required this.enableInstallments,
    required this.enableWeightSales,
    required this.enableCustomers,
    required this.enableLoyalty,
    required this.enableTaxOnSale,
    required this.enableInvoiceDiscount,
    required this.enableClothingVariants,
    required this.enableOilChange,
    required this.enableRepairServices,
    required this.enablePos,
    required this.enableServices,
  });

  final bool onboardingCompleted;
  final String businessVertical;
  final bool enableDebts;
  final bool enableInstallments;
  final bool enableWeightSales;
  final bool enableCustomers;
  final bool enableLoyalty;
  final bool enableTaxOnSale;
  final bool enableInvoiceDiscount;
  final bool enableClothingVariants;
  final bool enableOilChange;
  final bool enableRepairServices;
  final bool enablePos;

  /// مرآة للمفتاح القديم `biz.feature.services` — يُحفظ كـ (oil ∨ repair).
  final bool enableServices;

  /// غيار زيت + صيانة (للتوافق مع القراءات القديمة قبل المرحلة 1).
  bool get enableAnyLegacyServicesBundle => enableOilChange || enableRepairServices;

  /// التخصص الفعلي للواجهة — يُصلّح الحسابات القديمة حيث `biz.vertical`
  /// = [BusinessVertical.generalRetail] لكن أعلام الورشة (مثل [enableOilChange]) مفعّلة.
  String get effectiveVertical {
    final stored = businessVertical.trim();
    if (onboardingCompleted &&
        enableOilChange &&
        (stored == BusinessVertical.generalRetail ||
            !BusinessVertical.isKnown(stored))) {
      return BusinessVertical.oilChange;
    }
    if (onboardingCompleted &&
        enableClothingVariants &&
        stored == BusinessVertical.generalRetail) {
      return BusinessVertical.clothingStore;
    }
    if (onboardingCompleted &&
        enableWeightSales &&
        enablePos &&
        !enableOilChange &&
        stored == BusinessVertical.generalRetail) {
      return BusinessVertical.supermarket;
    }
    return BusinessVertical.isKnown(stored)
        ? stored
        : BusinessVertical.generalRetail;
  }

  /// يُعيد نسخة مُصحّحة إن كان [businessVertical] لا يطابق [effectiveVertical].
  BusinessSetupSettingsData? normalizedVerticalIfNeeded() {
    if (!onboardingCompleted) return null;
    final effective = effectiveVertical;
    if (effective == businessVertical) return null;
    return copyWith(businessVertical: effective).withVerticalGuardsApplied();
  }

  /// تخصص توجيه الواجهات — يطابق [HomeDashboardResolver] (الموظف).
  /// عند تفعيل غيار الزيت تُعرض واجهة الورشة حتى لو كان المفتاح المحفوظ قديماً.
  String get routingVertical {
    if (enableOilChange) return BusinessVertical.oilChange;
    return effectiveVertical;
  }

  static BusinessSetupSettingsData defaults() => const BusinessSetupSettingsData(
        onboardingCompleted: false,
        businessVertical: BusinessVertical.generalRetail,
        enableDebts: false,
        enableInstallments: false,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: true,
        enableRepairServices: true,
        enablePos: true,
        enableServices: true,
      );

  /// افتراضيات نشاط جاهزة للحفظ بعد اختيار النشاط في onboarding (المرحلة 5).
  static BusinessSetupSettingsData createForVertical(
    String vertical, {
    bool onboardingCompleted = true,
    bool enableLoyaltyCustom = false,
    bool enableDebtsCustom = true,
  }) {
    final v = BusinessVertical.isKnown(vertical)
        ? vertical.trim()
        : BusinessVertical.generalRetail;

    switch (v) {
      case BusinessVertical.oilChange:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.oilChange,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: false,
          enableCustomers: true,
          enableLoyalty: enableLoyaltyCustom,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: false,
          enableOilChange: true,
          enableRepairServices: false,
          enablePos: false,
          enableServices: true,
        );
      case BusinessVertical.supermarket:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.supermarket,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: true,
          enableCustomers: true,
          enableLoyalty: true,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: false,
          enableOilChange: false,
          enableRepairServices: false,
          enablePos: true,
          enableServices: false,
        );
      case BusinessVertical.clothingStore:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.clothingStore,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: false,
          enableCustomers: true,
          enableLoyalty: true,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: true,
          enableOilChange: false,
          enableRepairServices: false,
          enablePos: true,
          enableServices: false,
        );
      case BusinessVertical.pharmacy:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.pharmacy,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: false,
          enableCustomers: true,
          enableLoyalty: true,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: false,
          enableOilChange: false,
          enableRepairServices: false,
          enablePos: true,
          enableServices: false,
        );
      case BusinessVertical.restaurantCafe:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.restaurantCafe,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: false,
          enableCustomers: true,
          enableLoyalty: true,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: false,
          enableOilChange: false,
          enableRepairServices: false,
          enablePos: true,
          enableServices: true,
        );
      case BusinessVertical.generalRetail:
      default:
        return BusinessSetupSettingsData(
          onboardingCompleted: onboardingCompleted,
          businessVertical: BusinessVertical.generalRetail,
          enableDebts: enableDebtsCustom,
          enableInstallments: false,
          enableWeightSales: false,
          enableCustomers: true,
          enableLoyalty: enableLoyaltyCustom,
          enableTaxOnSale: false,
          enableInvoiceDiscount: true,
          enableClothingVariants: false,
          enableOilChange: false,
          enableRepairServices: false,
          enablePos: true,
          enableServices: false,
        );
    }
  }

  /// قيود نشاط ورشة غيار الزيت (Spec v1.0.2).
  BusinessSetupSettingsData withVerticalGuardsApplied() {
    if (businessVertical != BusinessVertical.oilChange) return this;
    return copyWith(
      enableInstallments: false,
      enablePos: false,
      enableOilChange: true,
      enableRepairServices: false,
      enableCustomers: true,
      enableServices: true,
    );
  }

  BusinessSetupSettingsData copyWith({
    bool? onboardingCompleted,
    String? businessVertical,
    bool? enableDebts,
    bool? enableInstallments,
    bool? enableWeightSales,
    bool? enableCustomers,
    bool? enableLoyalty,
    bool? enableTaxOnSale,
    bool? enableInvoiceDiscount,
    bool? enableClothingVariants,
    bool? enableOilChange,
    bool? enableRepairServices,
    bool? enablePos,
    bool? enableServices,
  }) {
    final oil = enableOilChange ?? this.enableOilChange;
    final repair = enableRepairServices ?? this.enableRepairServices;
    return BusinessSetupSettingsData(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      businessVertical: businessVertical ?? this.businessVertical,
      enableDebts: enableDebts ?? this.enableDebts,
      enableInstallments: enableInstallments ?? this.enableInstallments,
      enableWeightSales: enableWeightSales ?? this.enableWeightSales,
      enableCustomers: enableCustomers ?? this.enableCustomers,
      enableLoyalty: enableLoyalty ?? this.enableLoyalty,
      enableTaxOnSale: enableTaxOnSale ?? this.enableTaxOnSale,
      enableInvoiceDiscount:
          enableInvoiceDiscount ?? this.enableInvoiceDiscount,
      enableClothingVariants:
          enableClothingVariants ?? this.enableClothingVariants,
      enableOilChange: oil,
      enableRepairServices: repair,
      enablePos: enablePos ?? this.enablePos,
      enableServices: enableServices ?? (oil || repair),
    );
  }

  /// ترحيل لمرة واحدة (Spec — [BusinessSetupKeys.migrationFeatureGateV1]).
  static Future<void> runFeatureGateMigrationIfNeeded(
    AppSettingsRepository repo,
  ) async {
    final tenantId = await repo.getActiveTenantId();
    final t = tenantId;

    final migrationDone = await repo.getForTenant(
          BusinessSetupKeys.migrationFeatureGateV1,
          tenantId: t,
        ) ==
        'done';
    if (migrationDone) return;

    final keys = _allTenantKeys(t);
    final raw = await repo.getKeys(keys);

    final verticalRaw = (raw['t:$t:${BusinessSetupKeys.businessVertical}'] ?? '')
        .toString()
        .trim();
    final hasKnownVertical = BusinessVertical.isKnown(verticalRaw);

    final legacyServicesOn =
        (raw['t:$t:${BusinessSetupKeys.enableServices}'] ?? '0') == '1';

    final hasOilKey = raw.containsKey('t:$t:${BusinessSetupKeys.enableOilChange}');
    final hasRepairKey =
        raw.containsKey('t:$t:${BusinessSetupKeys.enableRepairServices}');
    final hasPosKey = raw.containsKey('t:$t:${BusinessSetupKeys.enablePos}');

    BusinessSetupSettingsData next;

    if (hasKnownVertical) {
      next = _fromRaw(repo: repo, tenantId: t, raw: raw);
      if (!hasOilKey || !hasRepairKey || !hasPosKey) {
        final verticalDefaults = createForVertical(
          verticalRaw,
          onboardingCompleted: next.onboardingCompleted,
          enableLoyaltyCustom: next.enableLoyalty,
          enableDebtsCustom: next.enableDebts,
        );
        next = next.copyWith(
          enableOilChange:
              hasOilKey ? next.enableOilChange : verticalDefaults.enableOilChange,
          enableRepairServices: hasRepairKey
              ? next.enableRepairServices
              : verticalDefaults.enableRepairServices,
          enablePos: hasPosKey ? next.enablePos : verticalDefaults.enablePos,
        );
      }
    } else if (legacyServicesOn) {
      next = _fromRaw(repo: repo, tenantId: t, raw: raw).copyWith(
        businessVertical: BusinessVertical.oilChange,
        enableOilChange: true,
        enableRepairServices: true,
        enablePos: true,
        enableServices: true,
      );
    } else {
      next = _fromRaw(repo: repo, tenantId: t, raw: raw);
      if (!hasOilKey && !hasRepairKey) {
        final legacyBundle = legacyServicesOn;
        next = next.copyWith(
          businessVertical: next.businessVertical.isEmpty
              ? BusinessVertical.generalRetail
              : next.businessVertical,
          enableOilChange: legacyBundle,
          enableRepairServices: legacyBundle,
          enablePos: hasPosKey ? next.enablePos : true,
          enableServices: legacyBundle,
        );
      } else if (!BusinessVertical.isKnown(next.businessVertical)) {
        next = next.copyWith(businessVertical: BusinessVertical.generalRetail);
      }
    }

    next = next.withVerticalGuardsApplied();
    await next.save(repo);
    await repo.setForTenant(
      BusinessSetupKeys.migrationFeatureGateV1,
      'done',
      tenantId: t,
    );
  }

  static Future<BusinessSetupSettingsData> load(AppSettingsRepository repo) async {
    await runFeatureGateMigrationIfNeeded(repo);
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getKeys(_allTenantKeys(tenantId));
    var data = _fromRaw(repo: repo, tenantId: tenantId, raw: raw)
        .withVerticalGuardsApplied();
    final normalized = data.normalizedVerticalIfNeeded();
    if (normalized != null) {
      await normalized.save(repo, forceVerticalCorrection: true);
      await markVerticalLocked(repo);
      BusinessFeaturesRevision.bump();
      data = normalized;
    }
    return data;
  }

  static Future<bool> isCompleted(AppSettingsRepository repo) async {
    await runFeatureGateMigrationIfNeeded(repo);
    final tenantId = await repo.getActiveTenantId();
    final v = await repo.getForTenant(
      BusinessSetupKeys.onboardingCompleted,
      tenantId: tenantId,
    );
    if ((v ?? '0') == '1') return true;
    return repo.hasAnyScopedKeyValue(BusinessSetupKeys.onboardingCompleted, '1');
  }

  /// هل اختار هذا الحساب/المستأجر تخصصاً نهائياً (لا يُعاد السؤال).
  static Future<bool> isVerticalLocked(AppSettingsRepository repo) async {
    final tenantId = await repo.getActiveTenantId();
    final v = await repo.getForTenant(
      BusinessSetupKeys.verticalLocked,
      tenantId: tenantId,
    );
    if (v == '1') return true;
    return repo.hasAnyScopedKeyValue(BusinessSetupKeys.verticalLocked, '1');
  }

  static Future<void> markVerticalLocked(AppSettingsRepository repo) async {
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      BusinessSetupKeys.verticalLocked,
      '1',
      tenantId: tenantId,
    );
  }

  /// هل يوجد تخصص معروف محفوظ (محلي أو عبر أي tenant على الجهاز).
  static Future<bool> hasKnownVerticalSaved(AppSettingsRepository repo) async {
    if (await isVerticalLocked(repo)) return true;
    if (await isCompleted(repo)) return true;
    for (final v in BusinessVertical.all) {
      if (await repo.hasAnyScopedKeyValue(
        BusinessSetupKeys.businessVertical,
        v,
      )) {
        return true;
      }
    }
    final setup = await load(repo);
    return BusinessVertical.isKnown(setup.businessVertical);
  }

  static List<String> _allTenantKeys(int tenantId) {
    final t = tenantId;
    return [
      't:$t:${BusinessSetupKeys.onboardingCompleted}',
      't:$t:${BusinessSetupKeys.businessVertical}',
      't:$t:${BusinessSetupKeys.migrationFeatureGateV1}',
      't:$t:${BusinessSetupKeys.enableDebts}',
      't:$t:${BusinessSetupKeys.enableInstallments}',
      't:$t:${BusinessSetupKeys.enableWeightSales}',
      't:$t:${BusinessSetupKeys.enableCustomers}',
      't:$t:${BusinessSetupKeys.enableLoyalty}',
      't:$t:${BusinessSetupKeys.enableTaxOnSale}',
      't:$t:${BusinessSetupKeys.enableInvoiceDiscount}',
      't:$t:${BusinessSetupKeys.enableClothingVariants}',
      't:$t:${BusinessSetupKeys.enableServices}',
      't:$t:${BusinessSetupKeys.enableOilChange}',
      't:$t:${BusinessSetupKeys.enableRepairServices}',
      't:$t:${BusinessSetupKeys.enablePos}',
    ];
  }

  static BusinessSetupSettingsData _fromRaw({
    required AppSettingsRepository repo,
    required int tenantId,
    required Map<String, String?> raw,
  }) {
    final t = tenantId;
    bool b(String key) => (raw[key] ?? '0') == '1';

    final def = defaults();
    final legacyServices = (raw['t:$t:${BusinessSetupKeys.enableServices}'] ??
            (def.enableServices ? '1' : '0')) ==
        '1';

    final vertical = (raw['t:$t:${BusinessSetupKeys.businessVertical}'] ?? '')
        .toString()
        .trim();
    final resolvedVertical = BusinessVertical.isKnown(vertical)
        ? vertical
        : BusinessVertical.generalRetail;

    final hasOilKey = raw.containsKey('t:$t:${BusinessSetupKeys.enableOilChange}');
    final hasRepairKey =
        raw.containsKey('t:$t:${BusinessSetupKeys.enableRepairServices}');
    final hasPosKey = raw.containsKey('t:$t:${BusinessSetupKeys.enablePos}');

    final enableOilChange = hasOilKey
        ? b('t:$t:${BusinessSetupKeys.enableOilChange}')
        : legacyServices;
    final enableRepairServices = hasRepairKey
        ? b('t:$t:${BusinessSetupKeys.enableRepairServices}')
        : legacyServices;
    final enablePos = hasPosKey
        ? b('t:$t:${BusinessSetupKeys.enablePos}')
        : resolvedVertical != BusinessVertical.oilChange;

    return BusinessSetupSettingsData(
      onboardingCompleted:
          b('t:$t:${BusinessSetupKeys.onboardingCompleted}'),
      businessVertical: resolvedVertical,
      enableDebts: b('t:$t:${BusinessSetupKeys.enableDebts}'),
      enableInstallments: b('t:$t:${BusinessSetupKeys.enableInstallments}'),
      enableWeightSales: b('t:$t:${BusinessSetupKeys.enableWeightSales}'),
      enableCustomers: (raw['t:$t:${BusinessSetupKeys.enableCustomers}'] ??
              (def.enableCustomers ? '1' : '0')) ==
          '1',
      enableLoyalty: b('t:$t:${BusinessSetupKeys.enableLoyalty}'),
      enableTaxOnSale: b('t:$t:${BusinessSetupKeys.enableTaxOnSale}'),
      enableInvoiceDiscount:
          (raw['t:$t:${BusinessSetupKeys.enableInvoiceDiscount}'] ??
                  (def.enableInvoiceDiscount ? '1' : '0')) ==
              '1',
      enableClothingVariants:
          b('t:$t:${BusinessSetupKeys.enableClothingVariants}'),
      enableOilChange: enableOilChange,
      enableRepairServices: enableRepairServices,
      enablePos: enablePos,
      enableServices: enableOilChange || enableRepairServices,
    );
  }

  Future<void> save(
    AppSettingsRepository repo, {
    bool forceVerticalCorrection = false,
  }) async {
    var normalized = withVerticalGuardsApplied();
    final tenantId = await repo.getActiveTenantId();

    if (!forceVerticalCorrection &&
        await BusinessSetupSettingsData.isVerticalLocked(repo)) {
      final tenantIdForRead = tenantId;
      final raw = await repo.getKeys(_allTenantKeys(tenantIdForRead));
      final existing = _fromRaw(
        repo: repo,
        tenantId: tenantIdForRead,
        raw: raw,
      );
      if (existing.businessVertical != normalized.businessVertical) {
        normalized = normalized.copyWith(
          businessVertical: existing.businessVertical,
        );
      }
    }

    final legacyServices =
        normalized.enableOilChange || normalized.enableRepairServices;

    await repo.setForTenant(
      BusinessSetupKeys.onboardingCompleted,
      normalized.onboardingCompleted ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.businessVertical,
      normalized.businessVertical,
      tenantId: tenantId,
    );
    if (normalized.onboardingCompleted &&
        BusinessVertical.isKnown(normalized.businessVertical)) {
      await repo.setForTenant(
        BusinessSetupKeys.verticalLocked,
        '1',
        tenantId: tenantId,
      );
    }
    await repo.setForTenant(
      BusinessSetupKeys.enableDebts,
      normalized.enableDebts ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableInstallments,
      normalized.enableInstallments ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableWeightSales,
      normalized.enableWeightSales ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableCustomers,
      normalized.enableCustomers ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableLoyalty,
      normalized.enableLoyalty ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableTaxOnSale,
      normalized.enableTaxOnSale ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableInvoiceDiscount,
      normalized.enableInvoiceDiscount ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableClothingVariants,
      normalized.enableClothingVariants ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableOilChange,
      normalized.enableOilChange ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableRepairServices,
      normalized.enableRepairServices ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enablePos,
      normalized.enablePos ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableServices,
      legacyServices ? '1' : '0',
      tenantId: tenantId,
    );
  }
}

/// يُزاد بعد حفظ [BusinessSetupSettingsData] لتحديث القائمة الجانبية في [HomeScreen].
class BusinessFeaturesRevision {
  BusinessFeaturesRevision._();
  static final ValueNotifier<int> instance = ValueNotifier<int>(0);

  static void bump() {
    instance.value++;
  }
}
