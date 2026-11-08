import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/business_setup_settings.dart';

BusinessSetupSettingsData _shop(
  String vertical, {
  bool oil = false,
  bool pos = false,
}) => BusinessSetupSettingsData(
  onboardingCompleted: true,
  businessVertical: vertical,
  enableDebts: true,
  enableInstallments: false,
  enableWeightSales: false,
  enableCustomers: true,
  enableLoyalty: false,
  enableTaxOnSale: false,
  enableInvoiceDiscount: true,
  enableClothingVariants: false,
  enableOilChange: oil,
  enableRepairServices: false,
  enablePos: pos,
  enableServices: oil,
);

void main() {
  group('فصل التخصصات', () {
    test('شاشة الاسترجاع تفتح في محل الزيت بلا نقطة بيع (بيع مباشر)', () {
      final oilNoPos = _shop(BusinessVertical.oilChange, oil: true);
      expect(
        isContentRouteBlocked(AppContentRoutes.processReturn(514), oilNoPos),
        isFalse,
      );
    });

    test('عروض الغسيل لمحل الزيت فقط', () {
      final oil = _shop(BusinessVertical.oilChange, oil: true);
      expect(
        isContentRouteBlocked(AppContentRoutes.settingsWashOffers, oil),
        isFalse,
      );
      for (final v in [
        BusinessVertical.pharmacy,
        BusinessVertical.generalRetail,
        BusinessVertical.restaurantCafe,
        BusinessVertical.supermarket,
        BusinessVertical.clothingStore,
      ]) {
        expect(
          isContentRouteBlocked(
            AppContentRoutes.settingsWashOffers,
            _shop(v, pos: true),
          ),
          isTrue,
          reason: v,
        );
      }
    });

    test('سياسة الاسترجاع متاحة لكل التخصصات', () {
      for (final v in [
        BusinessVertical.oilChange,
        BusinessVertical.pharmacy,
        BusinessVertical.generalRetail,
      ]) {
        expect(
          isContentRouteBlocked(
            AppContentRoutes.settingsReturnPolicy,
            _shop(v, oil: v == BusinessVertical.oilChange, pos: true),
          ),
          isFalse,
          reason: v,
        );
      }
    });
  });
}
