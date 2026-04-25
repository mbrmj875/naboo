import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// تجزئة كلمات المرور محلياً (SHA-256 + ملح عشوائي) — مناسبة للتخزين المحلي فقط.
abstract class PasswordHashing {
  static String generateSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String hash(String password, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:${password.trim()}'));
    return digest.toString();
  }

  static bool verify(String password, String salt, String storedHash) {
    if (storedHash.isEmpty || salt.isEmpty) return false;
    return hash(password, salt) == storedHash;
  }
}
