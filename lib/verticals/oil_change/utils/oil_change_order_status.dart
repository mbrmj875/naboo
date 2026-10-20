/// حالات بطاقة غيار الزيت في [service_orders.status].
abstract class OilChangeOrderStatus {
  static const suspended = 'suspended';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const delivered = 'delivered';

  static bool isSuspended(Map<String, dynamic> row) =>
      (row['status'] ?? '').toString().trim() == suspended;

  static bool isCancelled(Map<String, dynamic> row) =>
      (row['status'] ?? '').toString().trim() == cancelled;

  /// صف يظهر في تبويب «السجل» (عمل حقيقي — ليس معلّقاً ولا ملغىً).
  static bool isActiveLogRow(Map<String, dynamic> row) =>
      !isSuspended(row) && !isCancelled(row);
}

/// فلتر تبويبات سجل غيار الزيت.
enum OilChangeLogStatusFilter {
  /// السجل الحقيقي: مكتمل/مسلّم/… — بلا معلّقة ولا ملغاة.
  active,

  /// البطاقات المعلّقة فقط.
  suspended,
}
