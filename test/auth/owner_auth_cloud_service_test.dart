import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/owner_auth_cloud_service.dart';

void main() {
  group('OwnerAuthCloudSecret', () {
    test('isComplete requires valid Iraqi phone and hash material', () {
      const ok = OwnerAuthCloudSecret(
        phone: '07701234567',
        pinHash: 'abc123',
        pinSalt: 'salt',
      );
      expect(ok.isComplete, isTrue);

      const badPhone = OwnerAuthCloudSecret(
        phone: '123',
        pinHash: 'abc',
        pinSalt: 'salt',
      );
      expect(badPhone.isComplete, isFalse);

      const badHash = OwnerAuthCloudSecret(
        phone: '07701234567',
        pinHash: '',
        pinSalt: 'salt',
      );
      expect(badHash.isComplete, isFalse);
    });

    test('fromJson accepts snake_case RPC keys', () {
      final secret = OwnerAuthCloudSecret.fromJson({
        'phone': '07709998888',
        'pin_hash': 'hash',
        'pin_salt': 'salt',
      });
      expect(secret.phone, '07709998888');
      expect(secret.pinHash, 'hash');
      expect(secret.pinSalt, 'salt');
      expect(secret.isComplete, isTrue);
    });
  });
}
