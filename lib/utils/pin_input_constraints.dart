import 'package:flutter/services.dart';

import 'auth_validators.dart';

/// قيود موحّدة لحقول رمز PIN (4 أرقام) في كل الشاشات.
abstract final class PinInputConstraints {
  static const int length = 4;
  static const String hint = '••••';
  static const String requiredMessage = 'هذا الحقل مطلوب';
  static const String invalidMessage = 'رمز PIN يجب أن يكون 4 أرقام';
  static const String mismatchMessage = 'تأكيد رمز PIN غير مطابق';
  static const String weakMessage = 'هذا الرمز سهل التخمين — اختر رمزاً آخر';
  static const String staffSubtitle =
      'رمز رقمي من 4 أرقام يستخدمه الموظف لتسجيل الدخول.';

  static List<TextInputFormatter> get formatters => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ];

  /// تحقق عند الحقل مطلوب (إنشاء حساب / كاشير جديد). يرفض الرموز الضعيفة.
  static String? validateRequired(String? value) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return requiredMessage;
    if (!AuthValidators.isValidPin(t)) return invalidMessage;
    if (isWeak(t)) return weakMessage;
    return null;
  }

  /// تحقق عند الحقل اختياري (تعديل مستخدم — PIN جديد). يرفض الرموز الضعيفة.
  static String? validateOptional(String? value) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return null;
    if (!AuthValidators.isValidPin(t)) return invalidMessage;
    if (isWeak(t)) return weakMessage;
    return null;
  }

  static bool isValid(String value) => AuthValidators.isValidPin(value.trim());

  /// رمز ضعيف يسهل تخمينه: كل الأرقام متطابقة (0000) أو تسلسل صاعد/هابط
  /// (1234 / 4321 / 0123 / 3210…). يُطبَّق عند **الإنشاء/التغيير فقط**.
  static bool isWeak(String value) {
    final t = value.trim();
    if (t.length != length) return false;
    // كل الأرقام متطابقة.
    if (t.split('').toSet().length == 1) return true;
    final digits = t.split('').map(int.parse).toList();
    var ascending = true;
    var descending = true;
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] != digits[i - 1] + 1) ascending = false;
      if (digits[i] != digits[i - 1] - 1) descending = false;
    }
    return ascending || descending;
  }

  static bool matches(String pin, String confirm) =>
      pin.trim() == confirm.trim() && isValid(pin);
}
