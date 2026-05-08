import '../models/invoice.dart';

/// نتيجة فحص توازن الفاتورة. عند [isValid] = `false` تحتوي [errorMessage]
/// رسالة عربية مختصرة جاهزة للعرض.
class ValidationResult {
  const ValidationResult._({required this.isValid, this.errorMessage});

  /// فاتورة متوازنة — لا توجد رسالة خطأ.
  factory ValidationResult.valid() => const ValidationResult._(isValid: true);

  /// فاتورة غير متوازنة — [message] يصف السبب باختصار للمستخدم.
  factory ValidationResult.invalid(String message) =>
      ValidationResult._(isValid: false, errorMessage: message);

  final bool isValid;
  final String? errorMessage;

  @override
  String toString() => isValid
      ? 'ValidationResult.valid()'
      : 'ValidationResult.invalid("$errorMessage")';
}

/// يُرفَع من طبقات الحفظ (provider/DAO) عندما تفشل [validateInvoiceBalance]
/// كحاجز ثاني (defense-in-depth) خلف فحص الواجهة.
class InvoiceValidationException implements Exception {
  InvoiceValidationException(this.message);
  final String message;
  @override
  String toString() => 'InvoiceValidationException: $message';
}

/// السماحية الافتراضية لاختلاف الـ floating point — 1 فلس = 0.01.
const double kInvoiceBalanceTolerance = 0.01;

/// يتحقق من توازن الفاتورة قبل الحفظ.
///
/// الفحوص (بترتيب التنفيذ):
///   1) لا أصناف بكمية أو سعر أو إجمالي سالب.
///   2) الضريبة والخصم وخصم الولاء أرقام غير سالبة.
///   3) (للبيع فقط) مجموع الخصومات لا يتجاوز إجمالي البنود.
///   4) (للبيع فقط) `total == sumItems + tax - discount - loyaltyDiscount`
///      ضمن السماحية.
///   5) `total >= 0`.
///   6) `advancePayment >= 0`.
///   7) `advancePayment <= total` ضمن السماحية.
///
/// لأنواع التحصيلات/الدفعات (`debtCollection`, `installmentCollection`,
/// `supplierPayment`) نتخطّى الفحوص (3) و (4) لأنّ هذه الفواتير لا تحتوي
/// أصنافاً ويُمثّل [Invoice.total] فيها مبلغ التحصيل/الدفع مباشرةً.
ValidationResult validateInvoiceBalance(
  Invoice inv, {
  double tolerance = kInvoiceBalanceTolerance,
}) {
  // ---- 1) لا أصناف سالبة. -------------------------------------------------
  for (final item in inv.items) {
    if (item.quantity.isNaN || item.price.isNaN || item.total.isNaN) {
      return ValidationResult.invalid(
        'بند يحتوي قيمة غير صالحة (NaN): ${item.productName}',
      );
    }
    if (item.quantity < 0) {
      return ValidationResult.invalid(
        'الكمية سالبة في بند: ${item.productName}',
      );
    }
    if (item.price < 0) {
      return ValidationResult.invalid(
        'سعر البند سالب: ${item.productName}',
      );
    }
    if (item.total < 0) {
      return ValidationResult.invalid(
        'إجمالي البند سالب: ${item.productName}',
      );
    }
  }

  // ---- 2) ضريبة/خصم غير سالبَيْن. -----------------------------------------
  if (inv.tax.isNaN || inv.discount.isNaN || inv.loyaltyDiscount.isNaN) {
    return ValidationResult.invalid('الفاتورة تحتوي قيمة غير صالحة (NaN)');
  }
  if (inv.tax < 0) {
    return ValidationResult.invalid('الضريبة سالبة');
  }
  if (inv.discount < 0) {
    return ValidationResult.invalid('الخصم سالب');
  }
  if (inv.loyaltyDiscount < 0) {
    return ValidationResult.invalid('خصم الولاء سالب');
  }

  final isCollection = inv.type == InvoiceType.debtCollection ||
      inv.type == InvoiceType.installmentCollection ||
      inv.type == InvoiceType.supplierPayment;

  if (!isCollection) {
    final subtotal = inv.items.fold<double>(0.0, (s, i) => s + i.total);
    final totalDiscount = inv.discount + inv.loyaltyDiscount;

    // ---- 3) الخصم لا يتجاوز إجمالي البنود. -------------------------------
    if (totalDiscount > subtotal + tolerance) {
      return ValidationResult.invalid(
        'الخصم (${_fmt(totalDiscount)}) أكبر من إجمالي البنود '
        '(${_fmt(subtotal)})',
      );
    }

    // ---- 4) معادلة الإجمالي. ----------------------------------------------
    final expectedTotal =
        subtotal + inv.tax - inv.discount - inv.loyaltyDiscount;
    if ((inv.total - expectedTotal).abs() > tolerance) {
      return ValidationResult.invalid(
        'إجمالي الفاتورة (${_fmt(inv.total)}) لا يطابق المعادلة: '
        'مجموع البنود (${_fmt(subtotal)}) + الضريبة (${_fmt(inv.tax)}) '
        '- الخصم الكلي (${_fmt(totalDiscount)}) = ${_fmt(expectedTotal)}',
      );
    }
  }

  // ---- 5) total >= 0. -----------------------------------------------------
  if (inv.total.isNaN) {
    return ValidationResult.invalid('إجمالي الفاتورة قيمة غير صالحة (NaN)');
  }
  if (inv.total < -tolerance) {
    return ValidationResult.invalid('إجمالي الفاتورة سالب');
  }

  // ---- 6) advancePayment >= 0. -------------------------------------------
  if (inv.advancePayment.isNaN) {
    return ValidationResult.invalid('المبلغ المدفوع قيمة غير صالحة (NaN)');
  }
  if (inv.advancePayment < 0) {
    return ValidationResult.invalid('المبلغ المدفوع سالب');
  }

  // ---- 7) advancePayment <= total. ---------------------------------------
  if (inv.advancePayment > inv.total + tolerance) {
    return ValidationResult.invalid(
      'المبلغ المدفوع (${_fmt(inv.advancePayment)}) أكبر من إجمالي '
      'الفاتورة (${_fmt(inv.total)})',
    );
  }

  return ValidationResult.valid();
}

/// قراءة آمنة لعدد صحيح من نصّ غير موثوق (إدخال مستخدم، حقل JSON قادم من
/// السيرفر، …). تعيد [fallback] عند الفشل بدلاً من رمي `FormatException`.
///
/// مثال:
/// ```dart
/// final qty = safeParseInt(controller.text); // 0 عند الإدخال الفارغ.
/// ```
int safeParseInt(String? raw, {int fallback = 0}) {
  if (raw == null) return fallback;
  return int.tryParse(raw.trim()) ?? fallback;
}

/// قراءة آمنة لعدد عشري من نصّ غير موثوق. تعيد [fallback] عند الفشل أو
/// عندما يُنتج التحليل قيمة غير منتهية (`NaN` أو `±Infinity`) — هذه قيم
/// تُسمَّم أيّ حساب مالي لاحق فنرفضها كقيم مدخَلَة فاسدة.
double safeParseDouble(String? raw, {double fallback = 0.0}) {
  if (raw == null) return fallback;
  final result = double.tryParse(raw.trim());
  if (result == null) return fallback;
  if (result.isNaN || result.isInfinite) return fallback;
  return result;
}

String _fmt(double v) {
  if (!v.isFinite) return v.toString();
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}
