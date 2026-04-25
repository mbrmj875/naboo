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

  static String? optionalPhone(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final digits = RegExp(r'\d').allMatches(t).length;
    if (digits < 7) return 'رقم الهاتف يبدو غير مكتمل';
    if (t.length > 40) return 'رقم الهاتف طويل جداً';
    return null;
  }
}

/// رقم هاتف مُسجَّل لعميل آخر (يُعرض للمستخدم ولا يُكسر المزامنة).
class DuplicateCustomerPhoneException implements Exception {
  DuplicateCustomerPhoneException(this.message);
  final String message;

  @override
  String toString() => message;
}
