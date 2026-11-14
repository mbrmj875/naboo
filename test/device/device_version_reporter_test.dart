import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/device_version_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  DeviceVersionReporter reporter({
    required List<String> sent,
    String version = '2.2.43+267',
    bool fail = false,
  }) {
    return DeviceVersionReporter(
      currentVersion: () async => version,
      send: (deviceId, v) async {
        if (fail) throw Exception('function not found');
        sent.add('$deviceId@$v');
      },
    );
  }

  test('الصيغة: النسخة مع رقم البناء', () {
    expect(formatDeviceAppVersion('2.2.43', '267'), '2.2.43+267');
    expect(formatDeviceAppVersion('2.2.43', ''), '2.2.43');
    expect(formatDeviceAppVersion('', '267'), '');
  });

  test('يُبلَّغ فقط عند تغيّر النسخة', () {
    expect(
      shouldReportDeviceVersion(lastReported: null, current: '2.2.43+267'),
      isTrue,
    );
    expect(
      shouldReportDeviceVersion(
        lastReported: '2.2.43+267',
        current: '2.2.43+267',
      ),
      isFalse,
    );
    expect(
      shouldReportDeviceVersion(
        lastReported: '2.2.42+266',
        current: '2.2.43+267',
      ),
      isTrue,
    );
    expect(shouldReportDeviceVersion(lastReported: null, current: ''), isFalse);
  });

  test('أول تشغيل يبلّغ مرة واحدة ويحفظ النسخة', () async {
    final sent = <String>[];
    final r = reporter(sent: sent);
    await r.reportIfNeeded(userId: 'u1', deviceId: 'd1');
    await r.reportIfNeeded(userId: 'u1', deviceId: 'd1');
    expect(sent, ['d1@2.2.43+267']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(DeviceVersionReporter.prefKey('u1', 'd1')),
      '2.2.43+267',
    );
  });

  test('تشغيل لاحق بالنسخة نفسها لا يرسل شيئاً', () async {
    SharedPreferences.setMockInitialValues({
      DeviceVersionReporter.prefKey('u1', 'd1'): '2.2.43+267',
    });
    final sent = <String>[];
    await reporter(sent: sent).reportIfNeeded(userId: 'u1', deviceId: 'd1');
    expect(sent, isEmpty);
  });

  test('بعد التحديث يبلّغ النسخة الجديدة', () async {
    SharedPreferences.setMockInitialValues({
      DeviceVersionReporter.prefKey('u1', 'd1'): '2.2.42+266',
    });
    final sent = <String>[];
    await reporter(sent: sent).reportIfNeeded(userId: 'u1', deviceId: 'd1');
    expect(sent, ['d1@2.2.43+267']);
  });

  test('فشل الخادم لا يرمي ولا يُحفظ، ولا يتكرر في التشغيل نفسه', () async {
    final sent = <String>[];
    final r = reporter(sent: sent, fail: true);
    await r.reportIfNeeded(userId: 'u1', deviceId: 'd1');
    await r.reportIfNeeded(userId: 'u1', deviceId: 'd1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceVersionReporter.prefKey('u1', 'd1')), isNull);
    expect(sent, isEmpty);
  });

  test('حساب آخر على الجهاز نفسه يبلّغ بمفتاحه', () async {
    SharedPreferences.setMockInitialValues({
      DeviceVersionReporter.prefKey('u1', 'd1'): '2.2.43+267',
    });
    final sent = <String>[];
    await reporter(sent: sent).reportIfNeeded(userId: 'u2', deviceId: 'd1');
    expect(sent, ['d1@2.2.43+267']);
  });
}
