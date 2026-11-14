import 'package:uuid/uuid.dart';

/// إصلاحات هوية الصفوف بين الأجهزة، ويمكن إطفاؤها كلها معاً.
class SyncSafety {
  static bool enabled = true;

  /// المرحلة 2: دمج كتالوجات الزيوت والغسيل بالمعرّف العام بدل الرقم المحلي.
  /// مطفأ حتى تتحدث كل أجهزة المحل، ويُشغَّل ليلاً.
  static bool catalogIdentity = false;

  /// المرحلة 3: التقاط التعديلات في سجل محلي (وضع الظل، لا يرسل).
  /// يُقرأ عند فتح القاعدة، فتغييره يسري من الفتح التالي.
  static bool changeCapture = false;

  /// المرحلة 4: إرسال التعديلات الملتقطة واستلام تعديلات الأجهزة الأخرى،
  /// مع بقاء النسخة الكاملة كما هي. يحتاج [changeCapture]، والخادم يشغّله
  /// لكل حساب على حدة.
  static bool deltaSync = false;

  static int cashFils(Map<String, dynamic> row) {
    final fils = (row['amountFils'] as num?)?.toInt() ?? 0;
    if (fils != 0) return fils;
    return (((row['amount'] as num?)?.toDouble() ?? 0) * 1000).round();
  }

  /// بصمة القيد لا تستخدم أرقاماً محلية، لأنها تختلف بين الأجهزة.
  static String cashContentKey(Map<String, dynamic> row) =>
      '${row['createdAt']}|${row['transactionType']}|${cashFils(row)}';

  /// كل جهاز يحسب المعرف نفسه للقيد نفسه.
  static String cashGlobalId(Map<String, dynamic> row) =>
      const Uuid().v5(Namespace.url.value, 'naboo.cash|${cashContentKey(row)}');

  static Map<String, dynamic> newCashGlobalIdField() =>
      enabled ? {'global_id': const Uuid().v4()} : const {};
}
