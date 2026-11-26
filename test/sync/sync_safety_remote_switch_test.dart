import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/app_remote_config_service.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncSafety.enabled = true;
  });
  tearDown(() => SyncSafety.enabled = true);

  test('المفتاح غائب من الإعدادات: الإصلاح يعمل', () {
    final cfg = AppRemoteConfigData.fromJson({});
    expect(cfg.syncSafetyDisabled, isFalse);
  });

  test('المفتاح مفعّل في الخادم: يُقرأ', () {
    final cfg = AppRemoteConfigData.fromJson({'sync_safety_disabled': true});
    expect(cfg.syncSafetyDisabled, isTrue);
  });

  test('الإيقاف يطفئ الإصلاح ويُحفظ على الجهاز', () async {
    await AppRemoteConfigService.instance.applySyncSafetySwitch(disabled: true);
    expect(SyncSafety.enabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(AppRemoteConfigService.syncSafetyDisabledPrefKey),
      isTrue,
    );
  });

  test('رفع الإيقاف يعيد الإصلاح', () async {
    await AppRemoteConfigService.instance.applySyncSafetySwitch(disabled: true);
    await AppRemoteConfigService.instance.applySyncSafetySwitch(disabled: false);
    expect(SyncSafety.enabled, isTrue);
  });
}
