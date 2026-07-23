import 'package:naboo/services/business_setup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessSetupSettingsData.createForVertical', () {
    test('oil_change locks installments and pos', () {
      final d = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      );
      expect(d.businessVertical, BusinessVertical.oilChange);
      expect(d.enableOilChange, isTrue);
      expect(d.enableRepairServices, isFalse);
      expect(d.enablePos, isFalse);
      expect(d.enableInstallments, isFalse);
      expect(d.enableCarWash, isFalse);
      expect(d.enableDebts, isTrue);
      expect(d.enableCustomers, isTrue);
    });

    test('supermarket enables weight pos loyalty not oil', () {
      final d = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.supermarket,
      );
      expect(d.enableWeightSales, isTrue);
      expect(d.enablePos, isTrue);
      expect(d.enableLoyalty, isTrue);
      expect(d.enableOilChange, isFalse);
      expect(d.enableInstallments, isFalse);
    });

    test('withVerticalGuardsApplied forces oil_change rules', () {
      final d = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      ).copyWith(
        enableInstallments: true,
        enablePos: true,
        enableRepairServices: true,
      );
      final guarded = d.withVerticalGuardsApplied();
      expect(guarded.enableInstallments, isFalse);
      expect(guarded.enablePos, isFalse);
      expect(guarded.enableRepairServices, isFalse);
      expect(guarded.enableOilChange, isTrue);
    });
  });

  group('BusinessSetupSettingsData.routingVertical', () {
    test('matches employee home — oil when enableOilChange even if key is retail', () {
      final d = BusinessSetupSettingsData(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.generalRetail,
        enableDebts: true,
        enableInstallments: false,
        enableWeightSales: false,
        enableCustomers: true,
        enableLoyalty: false,
        enableTaxOnSale: false,
        enableInvoiceDiscount: true,
        enableClothingVariants: false,
        enableOilChange: true,
        enableRepairServices: false,
        enablePos: false,
      enableCarWash: false,
        enableServices: true,
      );
      expect(d.routingVertical, BusinessVertical.oilChange);
    });
  });

  group('BusinessSetupSettingsData.effectiveVertical', () {
    test('infers oil_change when vertical key missing but oil enabled', () {
      final d = BusinessSetupSettingsData.defaults().copyWith(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.generalRetail,
        enableOilChange: true,
        enableRepairServices: false,
        enablePos: false,
      );
      expect(d.effectiveVertical, BusinessVertical.oilChange);
    });

    test('normalizedVerticalIfNeeded repairs stored vertical', () {
      final d = BusinessSetupSettingsData.defaults().copyWith(
        onboardingCompleted: true,
        businessVertical: BusinessVertical.generalRetail,
        enableOilChange: true,
        enableRepairServices: false,
        enablePos: false,
      );
      final fixed = d.normalizedVerticalIfNeeded();
      expect(fixed, isNotNull);
      expect(fixed!.businessVertical, BusinessVertical.oilChange);
    });
  });

  group('BusinessVertical', () {
    test('isKnown accepts spec ids', () {
      expect(BusinessVertical.isKnown('oil_change'), isTrue);
      expect(BusinessVertical.isKnown('clothing_store'), isTrue);
      expect(BusinessVertical.isKnown('pharmacy'), isTrue);
      expect(BusinessVertical.isKnown('restaurant_cafe'), isTrue);
      expect(BusinessVertical.all.length, 6);
      expect(BusinessVertical.isKnown('unknown'), isFalse);
    });
  });
}
