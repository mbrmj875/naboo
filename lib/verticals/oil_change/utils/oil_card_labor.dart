/// أجور اليد في بطاقة الغيار — قاعدة واحدة للشاشة والفاتورة.
///
/// - الزيت: أجرة التبديل تُضاف دائماً. مع «زيت العميل» تحلّ أجرته الخاصة محل
///   الأساسية (لا تُجمع معها)، وإن لم تُضبط تُستعمل الأساسية.
/// - الهيدروليك والفلاتر: أجرة يد فقط حين يُحضر العميل الصنف.
/// - ما يكتبه الموظف في البطاقة [cardFils] يغلب الإعدادات لهذه البطاقة.
int effectiveOilLaborFils({
  required bool customerOil,
  required int baseFils,
  int? customerOilSettingFils,
  int? cardFils,
}) {
  if (cardFils != null && cardFils >= 0) return cardFils;
  if (customerOil) return customerOilSettingFils ?? baseFils;
  return baseFils;
}

int effectiveCustomerItemLaborFils({
  required bool customerProvided,
  required int settingFils,
  int? cardFils,
}) {
  if (!customerProvided) return 0;
  if (cardFils != null && cardFils >= 0) return cardFils;
  return settingFils < 0 ? 0 : settingFils;
}

/// اسم سطر أجرة التبديل في الفاتورة والإيصال.
String oilLaborLineName({required bool customerOil}) =>
    customerOil ? 'أجرة التبديل (زيت العميل)' : 'تبديل الزيت';
