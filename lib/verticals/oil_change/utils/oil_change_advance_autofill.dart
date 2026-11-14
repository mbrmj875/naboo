/// قرارات تعبئة «المبلغ المستلم» تلقائياً من إجمالي البطاقة.
///
/// منفصلة عن الشاشة لتُختبر وحدها: خطأ هنا يعني تسجيل دين وهمي على الزبون
/// أو إلغاء دين حقيقي، وكلاهما خطأ مالي.
class OilChangeAdvanceAutofill {
  const OilChangeAdvanceAutofill._();

  /// هل تُكتب قيمة الإجمالي في حقل المبلغ المستلم الآن؟
  ///
  /// [lastSyncedTotalFils] يمنع حلقة لا نهائية حين لا يعود المبلغ كما هو بعد
  /// التنسيق بخانتين عشريتين (كسور أقل من الدينار).
  static bool shouldSync({
    required bool manuallyEdited,
    required int currentAdvanceFils,
    required int totalFils,
    required int? lastSyncedTotalFils,
  }) {
    if (manuallyEdited) return false;
    if (currentAdvanceFils == totalFils) return false;
    if (lastSyncedTotalFils == totalFils) return false;
    return true;
  }

  /// عند فتح بطاقة محفوظة: هل المبلغ المخزّن اختيار صريح من المستخدم؟
  ///
  /// بطاقة إجماليها 500 والمستلم 0 تعني ديناً مقصوداً، فلا يجوز أن تحوّله
  /// التعبئة التلقائية إلى «مدفوعة بالكامل».
  static bool isManualOnHydration({
    required int? agreedFils,
    required int advanceFils,
  }) {
    final agreed = agreedFils ?? 0;
    if (agreed <= 0) return false;
    return advanceFils != agreed;
  }
}
