import 'package:flutter/foundation.dart';

/// AppLogger — قناة التسجيل الموحَّدة للتطبيق.
///
/// الفلسفة:
///   * `print()` و `debugPrint()` المباشرة ممنوعة في الكود الإنتاجي. لكلّ ما
///     يحتاج لوغ، استعمل [AppLogger.info] / [AppLogger.warn] / [AppLogger.error]
///     لتمرّ كل الرسائل عبر [redact] أوّلاً.
///   * أيّ سرّ يُلتقَط عرضياً (JWT، كلمة مرور، OTP، مفاتيح ترخيص أو anon)
///     يُستبدَل بعلامة `[REDACTED:*]` قبل أن يصل إلى الـ console.
///   * في وضع الإصدار (`!kDebugMode`) لا تُطبَع شيئاً، حتى لو نسي المطوّر
///     غلاف `if (kDebugMode)` في موقع الاستدعاء.
///
/// التصميم خالٍ من أيّ تبعيات لكي يبقى آمناً للاستيراد من أيّ مكان (بما فيه
/// طبقة الـ DAO ومسارات الإقلاع).
class AppLogger {
  AppLogger._();

  // ---------------------------------------------------------------------------
  // Test hooks (visible for testing only).
  // ---------------------------------------------------------------------------

  /// تجاوز [kDebugMode] في الاختبارات. عند `null` يُستعمَل [kDebugMode] الحقيقي.
  @visibleForTesting
  static bool? debugOverride;

  /// مُستقبِل للاختبارات. عند `null` يُستعمَل [debugPrint] الحقيقي.
  @visibleForTesting
  static void Function(String message)? sink;

  /// إعادة كل الـ overrides للقيم الافتراضية (يُستعمَل في `tearDown`).
  @visibleForTesting
  static void resetForTesting() {
    debugOverride = null;
    sink = null;
  }

  static bool get _enabled => debugOverride ?? kDebugMode;

  static void _emit(String level, String tag, String message) {
    if (!_enabled) return;
    final out = '[$level][$tag] ${_redact(message)}';
    final s = sink;
    if (s != null) {
      s(out);
    } else {
      debugPrint(out);
    }
  }

  // ---------------------------------------------------------------------------
  // Public API.
  // ---------------------------------------------------------------------------

  /// لوغ معلوماتي عام. يُهمَل في الإصدار.
  static void info(String tag, String message) =>
      _emit('INFO', tag, message);

  /// تحذير غير قاتل. يُهمَل في الإصدار.
  static void warn(String tag, String message) =>
      _emit('WARN', tag, message);

  /// خطأ مع stack trace اختياري. يُطبَع في خانتين: السطر الرئيسي ثم
  /// `[ERROR][tag][stack] ...` لتسهيل البحث في السجلّ.
  static void error(
    String tag,
    String message, [
    Object? err,
    StackTrace? st,
  ]) {
    if (!_enabled) return;
    final redactedMsg = _redact(message);
    final errStr = err == null ? '' : ' :: ${_redact(err.toString())}';
    final out = '[ERROR][$tag] $redactedMsg$errStr';
    final s = sink;
    if (s != null) {
      s(out);
      if (st != null) s('[ERROR][$tag][stack] $st');
    } else {
      debugPrint(out);
      if (st != null) debugPrint('[ERROR][$tag][stack] $st');
    }
  }

  /// متاحة للاختبارات للتأكّد من تنقيح القيم الحسّاسة.
  @visibleForTesting
  static String redact(String input) => _redact(input);

  // ---------------------------------------------------------------------------
  // Redaction engine.
  // ---------------------------------------------------------------------------

  /// يطبّق سلسلة من القواعد لإخفاء القيم الحسّاسة قبل الطباعة.
  ///
  /// الترتيب مقصود: الحقول المعنونة (`password`/`license_key`/`anon_key`)
  /// أوّلاً حتى لا يأكل JWT pattern قيمتها كاملة، ثمّ JWT المنفرد، ثمّ OTP.
  static String _redact(String input) {
    if (input.isEmpty) return input;

    var out = input;

    // 1) الحقول المعنونة — value مأخوذ بعد ":" أو "=".
    out = out.replaceAllMapped(
      _passwordPattern,
      (m) => '${m.group(1)}[REDACTED:PASSWORD]',
    );
    out = out.replaceAllMapped(
      _licenseKeyPattern,
      (m) => '${m.group(1)}[REDACTED:LICENSE_KEY]',
    );
    out = out.replaceAllMapped(
      _anonKeyPattern,
      (m) => '${m.group(1)}[REDACTED:ANON_KEY]',
    );

    // 2) JWT منفرد: `eyJxxx.yyy.zzz` بدون اسم حقل قبله.
    out = out.replaceAll(_jwtPattern, '[REDACTED:JWT]');

    // 3) OTP: 4-8 أرقام قريبة من كلمة "otp".
    out = out.replaceAllMapped(
      _otpPattern,
      (m) => '${m.group(1)}[REDACTED:OTP]',
    );

    return out;
  }

  // ---------------------------------------------------------------------------
  // Patterns (compiled once).
  // ---------------------------------------------------------------------------

  /// JWT بثلاثة أجزاء معزولة بنقطة. الجزء الأوّل يبدأ بـ `eyJ` (header) والثاني
  /// أيضاً بـ `eyJ` (payload). الـ minimum 5 أحرف لكل جزء يتجنّب false positives.
  static final RegExp _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_\-]{5,}\.eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}',
  );

  /// `password=value` أو `"password": "value"` أو `password : value`.
  /// نلتقط البادئة في group 1 لنعيد بناء الناتج بشكل قابل للقراءة.
  static final RegExp _passwordPattern = RegExp(
    r'''(["']?password["']?\s*[:=]\s*["']?)[^"'\s,;}]+''',
    caseSensitive: false,
  );

  /// `license_key=value` أو `"license_key": "value"`.
  static final RegExp _licenseKeyPattern = RegExp(
    r'''(["']?license_key["']?\s*[:=]\s*["']?)[^"'\s,;}]+''',
    caseSensitive: false,
  );

  /// `anonKey=value` أو `anon_key=value` أو `"anonKey": "value"`.
  static final RegExp _anonKeyPattern = RegExp(
    r'''(["']?anon[_]?key["']?\s*[:=]\s*["']?)[^"'\s,;}]+''',
    caseSensitive: false,
  );

  /// 4-8 أرقام قريبة من كلمة "otp" (خلال 30 رمز غير-رقمي قبلها).
  static final RegExp _otpPattern = RegExp(
    r'(otp[^0-9\n]{0,30})\d{4,8}',
    caseSensitive: false,
  );
}
