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
  });

  final int invoiceId;
  final String customerName;
  final int? customerId;
  final DateTime date;
  final double total;
  final double advancePayment;

  double get remaining =>
      math.max(0.0, total - advancePayment);

  bool get isSettled => remaining < 0.5;

  /// عدد الأيام منذ تاريخ الفاتورة (تقويمي).
  int daysSinceInvoice(DateTime now) {
    final a = DateTime(date.year, date.month, date.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays;
  }
}
