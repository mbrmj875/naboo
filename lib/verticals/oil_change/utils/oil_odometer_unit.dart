/// وحدة عداد السيارة في بطاقة الغيار: كيلومتر أو ميل.
///
/// تُحفظ في `service_orders.odometerUnit` ('km' أو 'mi')؛ الفارغ في البطاقات
/// القديمة = كيلومتر. لكل سيارة وحدتها، وتُنسخ من آخر زيارة لها.
abstract final class OilOdometerUnit {
  static const km = 'km';
  static const mi = 'mi';

  /// يقرأ الوحدة من قيمة خام؛ كل ما ليس ميلاً = كيلومتر.
  static String parse(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase() == mi ? mi : km;

  /// وحدة البطاقة من صفّها.
  static String of(Map<String, dynamic> row) => parse(row['odometerUnit']);

  /// الاسم المكتوب بعد الرقم: «كم» أو «ميل».
  static String label(String unit) => unit == mi ? 'ميل' : 'كم';

  /// اسم وحدة البطاقة من صفّها.
  static String labelOf(Map<String, dynamic> row) => label(of(row));
}
