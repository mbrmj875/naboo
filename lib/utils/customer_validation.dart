import 'package:flutter/services.dart';

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

  /// صيغة E.164 عراقية موحّدة للتخزين والمقارنة (مثل +9647801112233).
  /// إن تعذّر التطبيع يُعاد null.
  static String? toE164IraqMobile(String? raw) {
    final digits = normalizePhoneDigits(raw);
    if (digits == null) return null;
    var d = digits;
    if (d.startsWith('00964')) {
      d = d.substring(2);
    }
    if (d.startsWith('964')) {
      // already country code
    } else if (d.startsWith('0') && d.length >= 10) {
      d = '964${d.substring(1)}';
    } else if (d.startsWith('7') && d.length == 10) {
      d = '964$d';
    } else {
      return null;
    }
    // +964 + 10 أرقام وطنية تقريباً
    if (d.length < 12 || d.length > 15) return null;
    return '+$d';
  }

  /// مفتاح مطابقة موحّد (أرقام E.164 بلا +) — يساوي بين 07 و+964 و964.
  static String? phoneMatchKey(String? raw) {
    final e164 = toE164IraqMobile(raw);
    if (e164 != null) return normalizePhoneDigits(e164);
    return normalizePhoneDigits(raw);
  }

  /// يفرض هاتفاً عراقياً محلياً: يبدأ بـ `07` وطوله الأقصى 11 رقماً.
  static String coerceIraqiMobileDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '07';
    // 9647XXXXXXXX → 07XXXXXXXX
    if (d.startsWith('964') && d.length >= 4) {
      d = '0${d.substring(3)}';
    }
    if (d.startsWith('7') && !d.startsWith('07')) {
      d = '0$d';
    }
    if (!d.startsWith('07')) {
      if (d.startsWith('0') && d.length > 1) {
        d = '07${d.substring(2)}';
      } else {
        d = '07$d';
      }
    }
    if (d.length > 11) d = d.substring(0, 11);
    return d.length < 2 ? '07' : d;
  }

  /// مُنسِّقات إدخال لحقل هاتف عراقي (07 + 9 أرقام = 11).
  static List<TextInputFormatter> iraqiMobileInputFormatters() => [
        _IraqiMobilePhoneTextInputFormatter(),
      ];

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

class _IraqiMobilePhoneTextInputFormatter extends TextInputFormatter {
  static const _prefix = '07';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    // مسح أو استبدال داخل «07» يُرفض: البادئة ثابتة.
    if (oldText.startsWith(_prefix) &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.extentOffset <= _prefix.length &&
        newValue.text.length < oldText.length) {
      return TextEditingValue(
        text: oldText,
        selection: const TextSelection.collapsed(offset: _prefix.length),
      );
    }

    final coerced = CustomerValidation.coerceIraqiMobileDigits(newValue.text);
    final rawDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final caret = newValue.selection.extentOffset.clamp(0, newValue.text.length);
    final digitsBefore = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp(r'\D'), '')
        .length;
    var offset = digitsBefore;
    if (coerced.startsWith(_prefix) && !rawDigits.startsWith(_prefix)) {
      final injected =
          (coerced.length - rawDigits.length).clamp(0, _prefix.length);
      offset = digitsBefore + injected;
    }
    if (coerced.startsWith(_prefix) && offset < _prefix.length) {
      offset = _prefix.length;
    }
    if (offset > coerced.length) offset = coerced.length;
    if (offset < 0) offset = 0;
    return TextEditingValue(
      text: coerced,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
