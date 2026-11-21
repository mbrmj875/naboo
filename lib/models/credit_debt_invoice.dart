import 'dart:math' as math;

/// فاتورة «دين / آجل» مع المتبقي المحسوب من [total] و [advancePayment].
class CreditDebtInvoice {
  CreditDebtInvoice({
    required this.invoiceId,
    required this.customerName,
    required this.customerId,
    required this.date,
    required this.total,
    required this.advancePayment,
    this.totalFils,
    this.advancePaymentFils,
  });

  final int invoiceId;
  final String customerName;
  final int? customerId;
  final DateTime date;
  final double total;
  final double advancePayment;
  final int? totalFils;
  final int? advancePaymentFils;

  int get remainingFils {
    if (totalFils != null || advancePaymentFils != null) {
      final t = totalFils ?? 0;
      final a = advancePaymentFils ?? 0;
      return math.max(0, t - a);
    }
    return (math.max(0.0, total - advancePayment) * 1000).round();
  }

  double get remaining => remainingFils / 1000.0;

  bool get isSettled => remainingFils < 500;

  /// عدد الأيام منذ تاريخ الفاتورة (تقويمي).
  int daysSinceInvoice(DateTime now) {
    final a = DateTime(date.year, date.month, date.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays;
  }
}
