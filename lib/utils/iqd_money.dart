/// تطبيع مبالغ الدينار العراقي للتخزين: 1 دينار = 1000 فلس.
/// المشروع يخزّن عادةً `REAL` بالدينار؛ هذا المساعد يمنع سلاسل `double` غير المستقرة
/// عند المدخلات الحساسة (إضافة منتج، إلخ) دون هجرة أعمدة كاملة.
class IqdMoney {
  IqdMoney._();

  static int toFils(double dinars) {
    if (!dinars.isFinite || dinars < 0) return 0;
    return (dinars * 1000.0).round();
  }

  static double fromFils(int fils) => fils / 1000.0;

  /// جولة round-trip عبر الفلس لقيمة دينار واحدة (مناسب للتخزين في SQLite REAL).
  static double normalizeDinar(double dinars) {
    return fromFils(toFils(dinars));
  }
}
