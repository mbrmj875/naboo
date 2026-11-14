import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';

void main() {
  final t0 = DateTime(2026, 11, 10, 12);
  const every = Duration(minutes: 15);

  test('أول مزامنة بعد فتح التطبيق تفحص دائماً', () {
    expect(CloudSyncService.isAccessCheckDue(null, every, now: t0), isTrue);
  });

  test('لا فحص قبل انتهاء المدة', () {
    expect(
      CloudSyncService.isAccessCheckDue(
        t0,
        every,
        now: t0.add(const Duration(minutes: 14, seconds: 59)),
      ),
      isFalse,
    );
  });

  test('فحص عند انتهاء المدة', () {
    expect(
      CloudSyncService.isAccessCheckDue(t0, every, now: t0.add(every)),
      isTrue,
    );
  });

  test('ساعة الجهاز رجعت للخلف: يفحص', () {
    expect(
      CloudSyncService.isAccessCheckDue(
        t0,
        every,
        now: t0.subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });
}
