import 'package:uuid/uuid.dart';

/// إصلاحات هوية الصفوف بين الأجهزة، ويمكن إطفاؤها كلها معاً.
class SyncSafety {
  static bool enabled = true;

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
