import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:naboo/services/license/trusted_time_service.dart';
import 'package:naboo/services/license/license_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('checkLocalClock sets lastKnownTime when missing', () async {
    final prefs = await SharedPreferences.getInstance();
    final svc = TrustedTimeService(prefs: prefs);
    final r = await svc.checkLocalClock();
    expect(r.isTampered, false);
    expect(prefs.getInt(LicensePrefsKeys.lastKnownTime), isNotNull);
  });

  test('checkLocalClock detects backward jump > 10 minutes', () async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    await prefs.setInt(
      LicensePrefsKeys.lastKnownTime,
      now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    );
    final svc = TrustedTimeService(prefs: prefs);
    final r = await svc.checkLocalClock(
      backJumpTolerance: const Duration(minutes: 10),
    );
    expect(r.isTampered, true);
  });
}

