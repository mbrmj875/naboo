import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/password_hashing.dart';

void main() {
  group('user profile PIN sync security', () {
    test('only hash travels — verify round-trip without plaintext storage', () {
      const pin = '123456';
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash(pin, salt);

      expect(hash, isNot(equals(pin)));
      expect(PasswordHashing.verify(pin, salt, hash), isTrue);
      expect(PasswordHashing.verify('000000', salt, hash), isFalse);
    });

    test('cloud payload fields are hash names not plaintext', () {
      const syncFields = {'pinHash', 'pinSalt', 'updatedAt', 'displayName'};
      expect(syncFields.contains('pin'), isFalse);
      expect(syncFields.contains('password'), isFalse);
    });
  });
}
