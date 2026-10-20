import 'oil_change_filter_format.dart';

/// سياسات «الإجمالي المتفق عليه» مقابل مجموع بنود البطاقة.
///
/// منفصلة عن الشاشة لتُختبر وحدها — خطأ هنا يعني نقص تحصيل (فلتر/زيت)
/// أو تجميد إجمالي قديم بعد إضافة بند.
class OilChangeAgreedTotal {
  const OilChangeAgreedTotal._();

  /// تسامح 1 د.ع بالفلس عند مقارنة المتفق عليه بمجموع البنود.
  static const int toleranceFils = 1000;

  /// عند فتح بطاقة محفوظة: هل المتفق عليه تعديل صريح من المستخدم؟
  ///
  /// - بلا متفق / صفر → تلقائي.
  /// - متفق أقل من مجموع البنود → قيمة قديمة مجمّدة (ليست خصماً) → تلقائي لإعادة الحساب.
  /// - متفق يساوي المجموع (ضمن التسامح) → تلقائي.
  /// - متفق أكبر من المجموع → زيادة/تعديل مقصود → يدوي.
  static bool isManualOnHydration({
    required int? agreedFils,
    required int cardGrandFils,
  }) {
    final agreed = agreedFils ?? 0;
    if (agreed <= 0) return false;
    if (cardGrandFils <= 0) return true;
    if (agreed + toleranceFils < cardGrandFils) return false;
    return (agreed - cardGrandFils).abs() > toleranceFils;
  }

  /// إجمالي الصندوق الأصفر / الدفع: يدوي فقط إن وُجد تعديل صريح.
  static int checkoutTotalFils({
    required int agreedFils,
    required int cardGrandFils,
    required bool manuallyEdited,
  }) {
    if (manuallyEdited && agreedFils > 0) return agreedFils;
    if (cardGrandFils > 0) return cardGrandFils;
    return agreedFils > 0 ? agreedFils : 0;
  }

  /// ما يُحفظ في `agreedPriceFils` عند التعليق/التحديث/البيع.
  static int agreedFilsForSave({
    required int agreedFils,
    required int cardGrandFils,
    required bool manuallyEdited,
  }) {
    if (!manuallyEdited || agreedFils <= 0) {
      if (cardGrandFils > 0) return cardGrandFils;
      return agreedFils > 0 ? agreedFils : 0;
    }
    return agreedFils;
  }

  /// هل تغيير بند (فلتر/زيت/…) يجب أن يلغي العلم اليدوي ويعيد الحساب؟
  ///
  /// دائماً نعم للبنود — الخصم اليدوي يُعاد عبر «إعادة حساب» ثم تعديل
  /// الحقل مجدداً إن لزم.
  static bool shouldClearManualOnComponentChange() => true;

  /// تقدير مجموع الفلاتر + مادة الزيت من صف محفوظ (لاختبارات round-trip).
  ///
  /// لا يشمل خدمات إضافية/هيدروليك/منتجات — كافٍ لكشف نقص الفلتر مقابل الزيت.
  static int estimateOilAndFiltersFilsFromRow(Map<String, dynamic> row) {
    var total = 0;
    final oilCustomer =
        ((row['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
    if (!oilCustomer) {
      final sell = (row['oilSellPerLiterFils'] as num?)?.toInt() ?? 0;
      final liters = (row['oilLitersUsed'] as num?)?.toDouble() ?? 0;
      if (sell > 0 && liters > 0) {
        total += (liters * sell).round();
      }
    }
    for (final line in oilFilterLinesDataFromRow(row)) {
      if (line.priceFils > 0) total += line.priceFils;
    }
    return total;
  }
}
