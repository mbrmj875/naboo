import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/car_wash_user_preference.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseHelper();
    await db.closeAndDeleteDatabaseFile();
    await TenantContextService.instance.load();
    await AppSettingsRepository.instance.setActiveTenantId(1);
  });

  group('CarWashUserPreference', () {
    test('storageKey is scoped per tenant and user', () {
      expect(
        CarWashUserPreference.storageKey(tenantId: 1, userId: 10),
        't:1:u:10:biz.feature.car_wash',
      );
      expect(
        CarWashUserPreference.storageKey(tenantId: 1, userId: 11),
        isNot(CarWashUserPreference.storageKey(tenantId: 1, userId: 10)),
      );
    });

    test('enabling for one user does not enable another', () async {
      final repo = AppSettingsRepository.instance;
      const washStaff = 101;
      const oilOnlyStaff = 202;

      await CarWashUserPreference.setEnabledForUser(
        repo,
        userId: washStaff,
        enabled: true,
        tenantId: 1,
      );

      expect(
        await CarWashUserPreference.isEnabledForUser(
          repo,
          userId: washStaff,
          tenantId: 1,
        ),
        isTrue,
      );
      expect(
        await CarWashUserPreference.isEnabledForUser(
          repo,
          userId: oilOnlyStaff,
          tenantId: 1,
        ),
        isFalse,
      );
    });

    test('preference survives reload for the same user', () async {
      final repo = AppSettingsRepository.instance;
      const staffId = 303;

      await CarWashUserPreference.setEnabledForUser(
        repo,
        userId: staffId,
        enabled: true,
        tenantId: 1,
      );

      // محاكاة إعادة فتح التطبيق / إعادة قراءة الإعداد.
      expect(
        await CarWashUserPreference.isEnabledForUser(
          repo,
          userId: staffId,
          tenantId: 1,
        ),
        isTrue,
      );
    });
  });

  group('BusinessFeaturesProvider per-user car wash', () {
    test('switch staff switches car wash visibility', () async {
      await BusinessSetupSettingsData.createForVertical(
        BusinessVertical.oilChange,
      ).save(AppSettingsRepository.instance);

      final features = BusinessFeaturesProvider();
      await features.refresh();

      features.onActiveStaffChanged(11);
      await features.refresh();
      expect(features.data.enableCarWash, isFalse);

      await features.setCarWashEnabledForActiveUser(true);
      expect(features.data.enableCarWash, isTrue);

      // موظف آخر — لا يرى الغسل.
      features.onActiveStaffChanged(22);
      await features.refresh();
      expect(features.data.enableCarWash, isFalse);

      // العودة للأول — يبقى مفعّلاً.
      features.onActiveStaffChanged(11);
      await features.refresh();
      expect(features.data.enableCarWash, isTrue);

      features.dispose();
    });
  });
}
