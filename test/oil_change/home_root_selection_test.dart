import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_root_selection.dart';
import 'package:naboo/services/app_remote_config_service.dart';
import 'package:naboo/services/business_setup_settings.dart';

void main() {
  group('اختيار جذر الرئيسية', () {
    test('يعرض انتظاراً حتى تحميل خصائص النشاط', () {
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: false,
          features: BusinessSetupSettingsData.defaults(),
        ),
        EmployeeHomeRoot.loading,
      );
    });

    test('قطاع الزيت ينتقل إلى الغلاف الزيتي عند تفعيله', () {
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: true,
          features: BusinessSetupSettingsData.createForVertical(
            BusinessVertical.oilChange,
          ),
          standaloneEnabled: true,
        ),
        EmployeeHomeRoot.oilChangeStandalone,
      );
    });

    test('مفتاح الرجوع يقرأ من الإعدادات عن بُعد وافتراضه الغلاف يعمل', () {
      expect(AppRemoteConfigData.fallback.oilShellDisabled, isFalse);
      expect(
        AppRemoteConfigData.fromJson(const {
          'oil_shell_disabled': true,
        }).oilShellDisabled,
        isTrue,
      );
      expect(
        resolveEmployeeHomeRoot(
          featuresLoaded: true,
          features: BusinessSetupSettingsData.createForVertical(
            BusinessVertical.oilChange,
          ),
          standaloneEnabled: false,
        ),
        EmployeeHomeRoot.shared,
      );
    });

    test('القطاعات الأخرى تبقى على الرئيسية المشتركة', () {
      for (final vertical in [
        BusinessVertical.generalRetail,
        BusinessVertical.pharmacy,
        BusinessVertical.restaurantCafe,
        BusinessVertical.supermarket,
        BusinessVertical.clothingStore,
      ]) {
        expect(
          resolveEmployeeHomeRoot(
            featuresLoaded: true,
            features: BusinessSetupSettingsData.createForVertical(vertical),
          ),
          EmployeeHomeRoot.shared,
          reason: vertical,
        );
      }
    });
  });
}
