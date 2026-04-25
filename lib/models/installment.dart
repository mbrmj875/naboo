import 'dart:math' as math;

/// إزاحة [monthsDelta] شهراً تقويمياً (موجب للأمام، سالب للخلف) مع ضبط يوم الشهر.
DateTime installmentShiftCalendarMonths(DateTime d, int monthsDelta) {
  if (monthsDelta == 0) return d;
  var y = d.year;
  var m = d.month + monthsDelta;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  final lastDay = DateTime(y, m + 1, 0).day;
  final day = math.min(d.day, lastDay);
  return DateTime(y, m, day, d.hour, d.minute, d.second);
}

/// إضافة [months] إلى [d] مع ضبط يوم الشهر عند الحاجة (مثلاً 31 → آخر يوم في الشهر الهدف).
DateTime installmentAddCalendarMonths(DateTime d, int months) =>
    installmentShiftCalendarMonths(d, months);

class InstallmentPlan {
  int? id;
  int invoiceId;
  String customerName;

  /// ربط اختياري بجدول العملاء في قاعدة البيانات.
  int? customerId;
  double totalAmount;
  double paidAmount;
  int numberOfInstallments;
  List<Installment> installments;

  /// لقطة عند إنشاء الخطة من شاشة البيع (فائدة %، مبالغ، أشهر، قسط شهري مقترح).
  double interestPct;
  double interestAmount;
  double financedAtSale;
  double totalWithInterest;
  int plannedMonths;
  double suggestedMonthly;

  InstallmentPlan({
    this.id,
    required this.invoiceId,
    required this.customerName,
    this.customerId,
    required this.totalAmount,
    required this.paidAmount,
    required this.numberOfInstallments,
    required this.installments,
    this.interestPct = 0,
    this.interestAmount = 0,
    this.financedAtSale = 0,
    this.totalWithInterest = 0,
    this.plannedMonths = 0,
    this.suggestedMonthly = 0,
  });

  /// يوزّع المتبقي بعد المقدم على الأقساط مع تصحيح الفلس في القسط الأخير.
  ///
  /// [anchorDate]: مرجع أول استحقاق (غالباً تاريخ الفاتورة أو تاريخ اتفاق).
  /// القسط الأول يستحق بعد [paymentIntervalMonths] من المرجع، ثم كل
  /// [paymentIntervalMonths] شهراً (تقويم أو 30 يوماً حسب [useCalendarMonths]).
  void distributeInstallments(
    DateTime anchorDate, {
    int paymentIntervalMonths = 1,
    bool useCalendarMonths = true,
  }) {
    installments.clear();
    final remaining = totalAmount - paidAmount;
    if (numberOfInstallments <= 0 || remaining <= 0) return;

    final n = numberOfInstallments;
    final per = remaining / n;
    var allocated = 0.0;
    final step = paymentIntervalMonths.clamp(1, 24);
    for (var i = 0; i < n; i++) {
      final isLast = i == n - 1;
      // القسط الأخير يستوعب باقي الفلس حتى يصبح مجموع الأقساط = المتبقي بالضبط.
      final amt = isLast
          ? (remaining - allocated)
          : (per * 100).round() / 100;
      if (!isLast) allocated += amt;
      final int period = step * (i + 1);
      final DateTime due = useCalendarMonths
          ? installmentAddCalendarMonths(anchorDate, period)
          : anchorDate.add(Duration(days: 30 * period));
      installments.add(Installment(dueDate: due, amount: amt, paid: false));
    }
  }
}

class Installment {
  int? id;
  int? planId; // now nullable, will be set after insertion
  DateTime dueDate;
  double amount;
  bool paid;
  DateTime? paidDate;

  Installment({
    this.id,
    this.planId,
    required this.dueDate,
    required this.amount,
    this.paid = false,
    this.paidDate,
  });
}
