import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// تجزئة رموز/كلمات المرور محلياً.
///
/// **الصيغة الحديثة (المفضّلة):** PBKDF2-HMAC-SHA256 بعدد تكرارات عالٍ،
/// مخزَّنة كسلسلة مُصدَّرة: `pbkdf2$<iterations>$<hashBase64>`. الحساب يجري في
/// isolate عبر [compute] حتى لا يُجمّد الواجهة (قاعدة 16ms).
///
/// **الصيغة القديمة:** SHA-256 خام (سلسلة hex بطول 64). تبقى **مقروءة للأبد**
/// عبر [verifyPin]؛ وتُرقّى تلقائياً إلى PBKDF2 عند أول تحقق ناجح (rehash
/// انتهازي) — لا يوجد سيناريو «مستخدم محبوس».
abstract class PasswordHashing {
  /// عدد تكرارات PBKDF2 للصيغة الجديدة (توازن بين الأمان وزمن ~200–300ms).
  static const int pbkdf2Iterations = 150000;
  static const int _keyLengthBytes = 32;
  static const String _pbkdf2Prefix = 'pbkdf2';

  static String generateSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// SHA-256 القديم — يبقى فقط للتوافق ولاكتشاف الصيغة أثناء [verifyPin].
  static String hash(String password, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:${password.trim()}'));
    return digest.toString();
  }

  /// تحقق متزامن للصيغة القديمة فقط (SHA-256). يُبقى للتوافق مع الاستدعاءات
  /// القديمة؛ الاستدعاءات الجديدة يجب أن تستعمل [verifyPin] الذي يدعم الصيغتين.
  static bool verify(String password, String salt, String storedHash) {
    if (storedHash.isEmpty || salt.isEmpty) return false;
    return constantTimeEquals(hash(password, salt), storedHash);
  }

  /// ينتج hash بالصيغة الحديثة (PBKDF2) — يُستخدم عند إنشاء/تغيير الرمز.
  static Future<String> hashPin(String password, String salt) async {
    final derived = await compute(
      _pbkdf2Derive,
      _Pbkdf2Request(password.trim(), salt, pbkdf2Iterations),
    );
    return '$_pbkdf2Prefix\$$pbkdf2Iterations\$$derived';
  }

  /// تحقق يدعم الصيغتين (PBKDF2 الحديثة + SHA-256 القديمة).
  static Future<bool> verifyPin(
    String password,
    String salt,
    String storedHash,
  ) async {
    if (storedHash.isEmpty || salt.isEmpty) return false;
    if (isModernHash(storedHash)) {
      final parts = storedHash.split(r'$');
      if (parts.length != 3) return false;
      final iterations = int.tryParse(parts[1]) ?? pbkdf2Iterations;
      final derived = await compute(
        _pbkdf2Derive,
        _Pbkdf2Request(password.trim(), salt, iterations),
      );
      return constantTimeEquals(derived, parts[2]);
    }
    // الصيغة القديمة SHA-256.
    return constantTimeEquals(hash(password, salt), storedHash);
  }

  /// هل الـ hash بالصيغة الحديثة؟ (لتقرير الحاجة لإعادة التجزئة).
  static bool isModernHash(String storedHash) =>
      storedHash.startsWith('$_pbkdf2Prefix\$');

  /// هل يحتاج هذا الـ hash إلى ترقية (كان بالصيغة القديمة)؟
  static bool needsRehash(String storedHash) =>
      storedHash.isNotEmpty && !isModernHash(storedHash);

  /// مقارنة نصّين بزمن ثابت لا يعتمد على موضع أول اختلاف — يمنع كشف الـ hash
  /// عبر قياس زمن الاستجابة (timing side-channel).
  static bool constantTimeEquals(String a, String b) {
    final ba = utf8.encode(a);
    final bb = utf8.encode(b);
    // نخلط الطول ضمن نتيجة الـ XOR بدل الرجوع المبكر حتى لا يتسرّب فرق الطول.
    var diff = ba.length ^ bb.length;
    final max = ba.length > bb.length ? ba.length : bb.length;
    for (var i = 0; i < max; i++) {
      final x = i < ba.length ? ba[i] : 0;
      final y = i < bb.length ? bb[i] : 0;
      diff |= x ^ y;
    }
    return diff == 0;
  }
}

/// وسيطة PBKDF2 القابلة للتمرير إلى [compute] (isolate).
class _Pbkdf2Request {
  const _Pbkdf2Request(this.password, this.salt, this.iterations);
  final String password;
  final String salt;
  final int iterations;
}

/// يُنفَّذ داخل isolate — لا يلمس أي حالة مشتركة.
String _pbkdf2Derive(_Pbkdf2Request req) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(
      Uint8List.fromList(utf8.encode(req.salt)),
      req.iterations,
      PasswordHashing._keyLengthBytes,
    ));
  final key = derivator.process(Uint8List.fromList(utf8.encode(req.password)));
  return base64UrlEncode(key);
}
