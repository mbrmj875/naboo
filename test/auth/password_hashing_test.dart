import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/password_hashing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasswordHashing PBKDF2 (modern)', () {
    test('hashPin produces versioned pbkdf2 format', () async {
      final salt = PasswordHashing.generateSalt();
      final h = await PasswordHashing.hashPin('1234', salt);
      expect(h.startsWith('pbkdf2\$'), isTrue);
      expect(PasswordHashing.isModernHash(h), isTrue);
      expect(PasswordHashing.needsRehash(h), isFalse);
    });

    test('verifyPin accepts modern hash and rejects wrong', () async {
      final salt = PasswordHashing.generateSalt();
      final h = await PasswordHashing.hashPin('1234', salt);
      expect(await PasswordHashing.verifyPin('1234', salt, h), isTrue);
      expect(await PasswordHashing.verifyPin('4321', salt, h), isFalse);
    });

    test('verifyPin still accepts legacy SHA-256 hash', () async {
      final salt = PasswordHashing.generateSalt();
      final legacy = PasswordHashing.hash('1234', salt);
      expect(PasswordHashing.needsRehash(legacy), isTrue);
      expect(await PasswordHashing.verifyPin('1234', salt, legacy), isTrue);
      expect(await PasswordHashing.verifyPin('9999', salt, legacy), isFalse);
    });

    test('modern hash of same pin+salt is deterministic', () async {
      final salt = PasswordHashing.generateSalt();
      final a = await PasswordHashing.hashPin('1234', salt);
      final b = await PasswordHashing.hashPin('1234', salt);
      expect(a, equals(b));
    });
  });

  group('PasswordHashing', () {
    test('verify accepts correct pin and rejects wrong', () {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      expect(PasswordHashing.verify('1234', salt, hash), isTrue);
      expect(PasswordHashing.verify('4321', salt, hash), isFalse);
    });

    test('verify rejects empty salt or hash', () {
      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash('1234', salt);
      expect(PasswordHashing.verify('1234', '', hash), isFalse);
      expect(PasswordHashing.verify('1234', salt, ''), isFalse);
    });

    test('same pin with different salt yields different hash', () {
      final s1 = PasswordHashing.generateSalt();
      final s2 = PasswordHashing.generateSalt();
      expect(s1, isNot(equals(s2)));
      expect(
        PasswordHashing.hash('1234', s1),
        isNot(equals(PasswordHashing.hash('1234', s2))),
      );
    });

    group('constantTimeEquals', () {
      test('equal strings', () {
        expect(PasswordHashing.constantTimeEquals('abc123', 'abc123'), isTrue);
      });

      test('different content of same length', () {
        expect(PasswordHashing.constantTimeEquals('abc123', 'abc124'), isFalse);
      });

      test('different length', () {
        expect(PasswordHashing.constantTimeEquals('abc', 'abcd'), isFalse);
        expect(PasswordHashing.constantTimeEquals('', 'a'), isFalse);
      });

      test('both empty', () {
        expect(PasswordHashing.constantTimeEquals('', ''), isTrue);
      });
    });
  });
}
