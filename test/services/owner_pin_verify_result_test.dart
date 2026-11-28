import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/auth_user_messages.dart';
import 'package:naboo/services/auth/owner_auth_cloud_service.dart';

void main() {
  group('OwnerPinVerifyResult.fromBody', () {
    test('ok carries the phone', () {
      final r = OwnerPinVerifyResult.fromBody({'ok': true, 'phone': ' 07701234567 '});
      expect(r.verdict, OwnerPinVerdict.ok);
      expect(r.phone, '07701234567');
      expect(r.isDefinitive, isTrue);
    });

    test('wrong carries remaining tries', () {
      final r = OwnerPinVerifyResult.fromBody(
        {'ok': false, 'reason': 'wrong_pin', 'remaining': 2, 'locked_until': null},
      );
      expect(r.verdict, OwnerPinVerdict.wrong);
      expect(r.remaining, 2);
      expect(r.isDefinitive, isTrue);
    });

    test('locked from body or bare 429', () {
      final r = OwnerPinVerifyResult.fromBody(
        {'ok': false, 'reason': 'locked', 'locked_until': '2026-11-27T20:00:00Z'},
        status: 429,
      );
      expect(r.verdict, OwnerPinVerdict.locked);
      expect(r.lockedUntil, DateTime.utc(2026, 11, 27, 20).toLocal());
      expect(OwnerPinVerifyResult.fromBody('nope', status: 429).verdict, OwnerPinVerdict.locked);
    });

    test('server errors are not a verdict on the PIN', () {
      for (final body in [null, 'x', {'ok': false, 'reason': 'server_error'}]) {
        final r = OwnerPinVerifyResult.fromBody(body, status: 500);
        expect(r.verdict, OwnerPinVerdict.unavailable);
        expect(r.isDefinitive, isFalse);
      }
      expect(
        OwnerPinVerifyResult.fromBody({'ok': false, 'reason': 'no_secret'}).verdict,
        OwnerPinVerdict.noSecret,
      );
    });
  });

  group('OwnerAuthCloudSecret', () {
    test('complete with has_pin even without the hash', () {
      final s = OwnerAuthCloudSecret.fromJson({'phone': '07701234567', 'has_pin': true});
      expect(s.isComplete, isTrue);
      expect(s.hasHashMaterial, isFalse);
    });

    test('incomplete without hash or has_pin', () {
      expect(OwnerAuthCloudSecret.fromJson({'phone': '07701234567'}).isComplete, isFalse);
    });
  });

  group('messages', () {
    test('remaining tries wording', () {
      expect(AuthUserMessages.wrongPinRemaining(null), AuthUserMessages.wrongPin);
      expect(AuthUserMessages.wrongPinRemaining(4), AuthUserMessages.wrongPin);
      expect(AuthUserMessages.wrongPinRemaining(2), contains('محاولتان'));
      expect(AuthUserMessages.wrongPinRemaining(1), contains('محاولة واحدة'));
      expect(AuthUserMessages.wrongPinRemaining(0), contains('أُقفل'));
    });

    test('lock duration wording', () {
      final now = DateTime(2026, 11, 27, 12);
      expect(
        AuthUserMessages.pinLocked(now.add(const Duration(minutes: 14, seconds: 30)), now: now),
        contains('15 دقيقة'),
      );
      expect(AuthUserMessages.pinLocked(now.add(const Duration(minutes: 1)), now: now), contains('دقيقتين'));
      expect(AuthUserMessages.pinLocked(now.add(const Duration(hours: 2)), now: now), contains('ساعتين'));
      expect(AuthUserMessages.pinLocked(now.add(const Duration(hours: 5, minutes: 10)), now: now), contains('6 ساعات'));
      expect(AuthUserMessages.pinLocked(null), contains('حاول لاحقاً'));
    });
  });
}
