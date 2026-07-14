/// حالات بطاقة غيار الزيت في [service_orders.status].
abstract class OilChangeOrderStatus {
  static const suspended = 'suspended';
  static const completed = 'completed';

  static bool isSuspended(Map<String, dynamic> row) =>
      (row['status'] ?? '').toString().trim() == suspended;

  static bool isActiveLogRow(Map<String, dynamic> row) => !isSuspended(row);
}

/// فلتر تبويبات سجل غيار الزيت.
enum OilChangeLogStatusFilter {
  /// كل البطاقات ما عدا المعلّقة.
  active,

  /// البطاقات المعلّقة فقط.
  suspended,
}
