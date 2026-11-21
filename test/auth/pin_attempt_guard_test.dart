import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/pin_attempt_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PinAttemptGuard.now = DateTime.now;
  });

  tearDown(() {
    PinAttemptGuard.now = DateTime.now;
  });

  group('PinAttemptGuard', () {
    const scope = 'user_1';

    test('no lock initially', () async {
      expect(await PinAttemptGuard.remainingLock(scope), isNull);
      expect(await PinAttemptGuard.failureCount(scope), 0);
    });

    test('first 5 failures are free, 6th applies 30s lock', () async {
      for (var i = 0; i < PinAttemptGuard.freeAttempts - 1; i++) {
        expect(await PinAttemptGuard.recordFailure(scope), isNull);
      }
      // المحاولة رقم 5 تبلغ الحد وتطبّق أول قفل.
      final lock = await PinAttemptGuard.recordFailure(scope);
      expect(lock, const Duration(seconds: 30));

      final remaining = await PinAttemptGuard.remainingLock(scope);
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(25));
    });

    test('lock escalates 30s -> 60s -> 5m -> 15m', () async {
      for (var i = 0; i < PinAttemptGuard.freeAttempts; i++) {
        await PinAttemptGuard.recordFailure(scope);
      }
      // نتجاوز القفل الأول زمنياً ثم نُخطئ مجدداً لنصعّد.
      Duration? last;
      var fake = DateTime(2026, 1, 1, 12);
      PinAttemptGuard.now = () => fake;

      for (final expected in const [
        Duration(seconds: 60),
        Duration(minutes: 5),
        Duration(minutes: 15),
        Duration(minutes: 15), // السقف يتكرر
      ]) {
        fake = fake.add(const Duration(hours: 1)); // تجاوز أي قفل سابق
        last = await PinAttemptGuard.recordFailure(scope);
        expect(last, expected);
      }
    });

    test('recordSuccess clears counter and lock', () async {
      for (var i = 0; i < PinAttemptGuard.freeAttempts; i++) {
        await PinAttemptGuard.recordFailure(scope);
      }
      expect(await PinAttemptGuard.remainingLock(scope), isNotNull);

      await PinAttemptGuard.recordSuccess(scope);
      expect(await PinAttemptGuard.remainingLock(scope), isNull);
      expect(await PinAttemptGuard.failureCount(scope), 0);
    });

    test('lock expires after its duration passes', () async {
      var fake = DateTime(2026, 1, 1, 12);
      PinAttemptGuard.now = () => fake;
      for (var i = 0; i < PinAttemptGuard.freeAttempts; i++) {
        await PinAttemptGuard.recordFailure(scope);
      }
      expect(await PinAttemptGuard.remainingLock(scope), isNotNull);

      fake = fake.add(const Duration(seconds: 31));
      expect(await PinAttemptGuard.remainingLock(scope), isNull);
    });

    test('scopes are isolated', () async {
      for (var i = 0; i < PinAttemptGuard.freeAttempts; i++) {
        await PinAttemptGuard.recordFailure('user_1');
      }
      expect(await PinAttemptGuard.remainingLock('user_1'), isNotNull);
      expect(await PinAttemptGuard.remainingLock('user_2'), isNull);
    });

    test('formatRemaining renders m:ss', () {
      expect(
        PinAttemptGuard.formatRemaining(const Duration(seconds: 27)),
        '0:27',
      );
      expect(
        PinAttemptGuard.formatRemaining(const Duration(seconds: 65)),
        '1:05',
      );
    });
  });
}
