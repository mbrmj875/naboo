/// قواعد إدخال العملاء — متسقة مع حفظ SQLite (بدون تغيير مخطط الجداول).
class CustomerValidation {
  CustomerValidation._();

  /// مقارنة البحث ومنع تكرار الهاتف: الأرقام فقط (بدون مسافات أو + أو شرطات).
  /// إن كان فارغًا أو بلا أرقام يُعاد `null`.
  static String? normalizePhoneDigits(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits;
  }

  static final _email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static String? name(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'اسم العميل مطلوب';
    if (t.length < 2) return 'الاسم قصير جداً';
    if (t.length > 200) return 'الاسم طويل جداً';
    return null;
  }

  static String? optionalEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    if (!_email.hasMatch(t)) return 'صيغة البريد غير صحيحة';
    return null;
  }

  /// هاتف عراقي اختياري: 11 رقمًا ويبدأ بـ 07 (مثل 07701234567).
  static String? iraqiMobilePhone(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final digits = normalizePhoneDigits(t);
    if (digits == null) return 'أدخل أرقام الهاتف فقط';
    if (digits.length != 11) {
      return 'رقم الهاتف العراقي يجب أن يكون 11 رقمًا';
    }
    if (!digits.startsWith('07')) {
      return 'رقم الهاتف العراقي يبدأ بـ 07 (مثال: 07701234567)';
    }
    return null;
  }

  static String? optionalPhone(String? v) => iraqiMobilePhone(v);
}

/// رقم هاتف مُسجَّل لعميل آخر (يُعرض للمستخدم ولا يُكسر المزامنة).
class DuplicateCustomerPhoneException implements Exception {
  DuplicateCustomerPhoneException(this.message);
  final String message;

  @override
  String toString() => message;
}
