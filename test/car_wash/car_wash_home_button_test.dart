import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/providers/dashboard_layout_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/verticals/oil_change/manifest.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// زر «غسيل السيارات» تحت الزر الذهبي + مفتاح إخفائه من تخصيص الرئيسية.
void main() {
  const manifest = OilChangeVerticalManifest();

  group('وصفة الرئيسية', () {
    test('الزر الثاني هو غسيل السيارات ويفتح بطاقة الغسيل', () {
      final spec = manifest.resolveHome(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );
      final wash = spec.secondaryCta;
      expect(wash, isNotNull);
      expect(wash!.title, 'غسيل السيارات');
      expect(wash.routeId, 'car_wash_create');
    });

    test('الزر الثاني موجود في الوضع الهجين أيضاً', () {
      final hybrid = BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      );
      final spec = manifest.resolveHome(hybrid);
      expect(spec.secondaryCta?.routeId, 'car_wash_create');
      expect(spec.primaryCta?.routeId, 'oil_change_create');
    });

    test('الزر الأساسي لم يتغيّر', () {
      final spec = manifest.resolveHome(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      );
      expect(spec.primaryCta?.title, 'غيار زيت جديد');
      expect(spec.primaryCta?.subtitle, 'تسجيل سيارة وعداد');
    });
  });

  group('مسارات بطاقة الغسيل', () {
    test('المسارات مسجّلة في وصفة النشاط', () {
      expect(manifest.routes[AppContentRoutes.carWashCreate], isNotNull);
      expect(manifest.routes[AppContentRoutes.carWashServices], isNotNull);
    });

    test('المسارات محميّة ببوابة غيار الزيت', () {
      expect(
        manifest.routeGuardExact,
        containsAll([
          AppContentRoutes.carWashCreate,
          AppContentRoutes.carWashServices,
        ]),
      );
      expect(
        featureRouteMapping[FeatureGateId.oilChange],
        contains(AppContentRoutes.carWashCreate),
      );
    });

    test('عنوان المسار عربي وواضح', () {
      expect(
        breadcrumbFallbackTitleForRouteId(AppContentRoutes.carWashCreate),
        'بطاقة غسيل سيارة',
      );
      expect(
        breadcrumbFallbackTitleForRouteId(AppContentRoutes.carWashServices),
        'أنواع الغسيل وأسعارها',
      );
    });
  });

  group('مفتاح إظهار الزر', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ظاهر افتراضياً', () async {
      final layout = DashboardLayoutProvider();
      await Future<void>.delayed(Duration.zero);
      expect(layout.carWashButtonVisible, isTrue);
    });

    test('الإخفاء يُحفظ ويُقرأ بعد إعادة التشغيل', () async {
      final layout = DashboardLayoutProvider();
      await Future<void>.delayed(Duration.zero);
      await layout.setCarWashButtonVisible(false);
      expect(layout.carWashButtonVisible, isFalse);

      final reopened = DashboardLayoutProvider();
      await Future<void>.delayed(Duration.zero);
      expect(reopened.carWashButtonVisible, isFalse);
    });

    test('استعادة الافتراضي تُعيد الزر', () async {
      final layout = DashboardLayoutProvider();
      await Future<void>.delayed(Duration.zero);
      await layout.setCarWashButtonVisible(false);
      await layout.resetToDefaults();
      expect(layout.carWashButtonVisible, isTrue);
    });

    test('المفتاح لا يمسّ ترتيب الأقسام ولا إظهارها', () async {
      final layout = DashboardLayoutProvider();
      await Future<void>.delayed(Duration.zero);
      final orderBefore = layout.order;
      await layout.setCarWashButtonVisible(false);
      expect(layout.order, orderBefore);
      for (final id in DashboardLayoutProvider.sectionIds) {
        expect(layout.isVisible(id), isTrue, reason: id);
      }
    });

    test('أقسام التخصيص بقيت أربعة كما هي', () {
      expect(
        DashboardLayoutProvider.sectionIds,
        ['header', 'orbit', 'pinned', 'charts'],
      );
    });
  });
}
