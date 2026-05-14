import 'package:flutter/foundation.dart';

import 'app_settings_repository.dart';

/// إعدادات "التخصص" الأولي للتطبيق — تُحفظ في جدول `app_settings` ضمن نطاق التينانت.
abstract class BusinessSetupKeys {
  static const onboardingCompleted = 'biz.onboarding.completed';
  static const enableDebts = 'biz.feature.debts';
  static const enableInstallments = 'biz.feature.installments';
  static const enableWeightSales = 'biz.feature.weight_sales';
  static const enableCustomers = 'biz.feature.customers';
  static const enableLoyalty = 'biz.feature.loyalty';
  static const enableTaxOnSale = 'biz.feature.sale_tax';
  static const enableInvoiceDiscount = 'biz.feature.sale_discount';
  static const enableClothingVariants = 'biz.feature.clothing_variants';
  static const enableServices = 'biz.feature.services';
}

class BusinessSetupSettingsData {
  const BusinessSetupSettingsData({
    required this.onboardingCompleted,
    required this.enableDebts,
    required this.enableInstallments,
    required this.enableWeightSales,
    required this.enableCustomers,
    required this.enableLoyalty,
    required this.enableTaxOnSale,
    required this.enableInvoiceDiscount,
    required this.enableClothingVariants,
    required this.enableServices,
  });

  final bool onboardingCompleted;
  final bool enableDebts;
  final bool enableInstallments;
  final bool enableWeightSales;
  final bool enableCustomers;
  final bool enableLoyalty;
  final bool enableTaxOnSale;
  final bool enableInvoiceDiscount;
  final bool enableClothingVariants;
  final bool enableServices;

  static BusinessSetupSettingsData defaults() => const BusinessSetupSettingsData(
        onboardingCompleted: false,
        enableDebts: false,
        enableInstallments: false,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableServices: true,
      );

  static Future<BusinessSetupSettingsData> load(AppSettingsRepository repo) async {
    final tenantId = await repo.getActiveTenantId();
    final raw = await repo.getKeys([
      't:$tenantId:${BusinessSetupKeys.onboardingCompleted}',
      't:$tenantId:${BusinessSetupKeys.enableDebts}',
      't:$tenantId:${BusinessSetupKeys.enableInstallments}',
      't:$tenantId:${BusinessSetupKeys.enableWeightSales}',
      't:$tenantId:${BusinessSetupKeys.enableCustomers}',
      't:$tenantId:${BusinessSetupKeys.enableLoyalty}',
      't:$tenantId:${BusinessSetupKeys.enableTaxOnSale}',
      't:$tenantId:${BusinessSetupKeys.enableInvoiceDiscount}',
      't:$tenantId:${BusinessSetupKeys.enableClothingVariants}',
      't:$tenantId:${BusinessSetupKeys.enableServices}',
    ]);
    bool b(String key) => (raw[key] ?? '0') == '1';
    return BusinessSetupSettingsData(
      onboardingCompleted: b('t:$tenantId:${BusinessSetupKeys.onboardingCompleted}'),
      enableDebts: b('t:$tenantId:${BusinessSetupKeys.enableDebts}'),
      enableInstallments: b('t:$tenantId:${BusinessSetupKeys.enableInstallments}'),
      enableWeightSales: b('t:$tenantId:${BusinessSetupKeys.enableWeightSales}'),
      enableCustomers: (raw['t:$tenantId:${BusinessSetupKeys.enableCustomers}'] ??
              (defaults().enableCustomers ? '1' : '0')) ==
          '1',
      enableLoyalty: b('t:$tenantId:${BusinessSetupKeys.enableLoyalty}'),
      enableTaxOnSale: b('t:$tenantId:${BusinessSetupKeys.enableTaxOnSale}'),
      enableInvoiceDiscount:
          (raw['t:$tenantId:${BusinessSetupKeys.enableInvoiceDiscount}'] ??
                  (defaults().enableInvoiceDiscount ? '1' : '0')) ==
              '1',
      enableClothingVariants: b('t:$tenantId:${BusinessSetupKeys.enableClothingVariants}'),
      enableServices: (raw['t:$tenantId:${BusinessSetupKeys.enableServices}'] ??
              (defaults().enableServices ? '1' : '0')) ==
          '1',
    );
  }

  static Future<bool> isCompleted(AppSettingsRepository repo) async {
    final tenantId = await repo.getActiveTenantId();
    final v = await repo.getForTenant(BusinessSetupKeys.onboardingCompleted, tenantId: tenantId);
    return (v ?? '0') == '1';
  }

  Future<void> save(AppSettingsRepository repo) async {
    final tenantId = await repo.getActiveTenantId();
    await repo.setForTenant(
      BusinessSetupKeys.onboardingCompleted,
      onboardingCompleted ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableDebts,
      enableDebts ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableInstallments,
      enableInstallments ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableWeightSales,
      enableWeightSales ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableCustomers,
      enableCustomers ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableLoyalty,
      enableLoyalty ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableTaxOnSale,
      enableTaxOnSale ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableInvoiceDiscount,
      enableInvoiceDiscount ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableClothingVariants,
      enableClothingVariants ? '1' : '0',
      tenantId: tenantId,
    );
    await repo.setForTenant(
      BusinessSetupKeys.enableServices,
      enableServices ? '1' : '0',
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

