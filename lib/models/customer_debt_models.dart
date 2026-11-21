/// تجميع ديون «آجل» لعميل (مسجّل أو باسم فقط).
class CustomerDebtSummary {
  const CustomerDebtSummary({
    required this.customerId,
    required this.displayName,
    required this.openRemaining,
    required this.invoiceCount,
    this.oldestInvoiceDate,
    this.overdueFils = 0,
    this.daysLate = 0,
    this.periodDays = 0,
    this.cashOnly = false,
    this.searchText = '',
  });

  /// null = عميل غير مربوط بجدول العملاء؛ التجميع بالاسم فقط.
  final int? customerId;
  final String displayName;
  final double openRemaining;
  final int invoiceCount;
  final DateTime? oldestInvoiceDate;

  /// متبقي الفواتير الأقدم من فترة التسديد (فترته الخاصة أو العامة).
  final int overdueFils;

  /// أيام التأخر بعد انتهاء الفترة لأقدم دين متأخر؛ 0 = غير متأخر.
  final int daysLate;

  /// الفترة المطبَّقة عليه؛ 0 = بلا فترة.
  final int periodDays;
  final bool cashOnly;

  /// هواتفه ولوحات سياراته (للبحث)، بأحرف صغيرة.
  final String searchText;

  bool get isOverdue => daysLate > 0 && overdueFils > 0;
}

/// متأخرون أولاً، ثم الأكبر ديناً (في كل مجموعة).
int compareCustomerDebtOverdueFirst(CustomerDebtSummary a, CustomerDebtSummary b) {
  if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
  return b.openRemaining.compareTo(a.openRemaining);
}

/// فاتورة متأخرة: مفتوحة وعمرها أكثر من [periodDays] (0 = بلا فترة).
bool creditInvoiceIsOverdue({
  required DateTime date,
  required int remainingFils,
  required int periodDays,
  required DateTime now,
}) =>
    periodDays > 0 &&
    remainingFils >= 500 &&
    now.difference(date).inDays > periodDays;

/// بند منتج ضمن ديون العميل (من فواتير آجل).
class CustomerDebtLineItem {
  const CustomerDebtLineItem({
    required this.invoiceId,
    required this.invoiceDate,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.sellerName,
  });

  final int invoiceId;
  final DateTime invoiceDate;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String? sellerName;
}

/// نتيجة تسديد دفعة على ديون آجل (FIFO على الفواتير).
class CustomerDebtPaymentResult {
  const CustomerDebtPaymentResult({
    required this.amountApplied,
    required this.debtBefore,
    required this.debtAfter,
    required this.paymentRowId,
    this.receiptInvoiceId,
  });

  final double amountApplied;
  final double debtBefore;
  final double debtAfter;
  final int paymentRowId;

  /// فاتورة السند المُنشأة (قائمة الفواتير + الصندوق).
  final int? receiptInvoiceId;
}

/// مفتاح تجميع العميل في الاستعلامات.
class CustomerDebtParty {
  const CustomerDebtParty({
    required this.customerId,
    required this.displayName,
    required this.normalizedName,
  });

  final int? customerId;
  final String displayName;

  /// للمطابقة عندما [customerId] null.
  final String normalizedName;

  bool get isRegistered => customerId != null;
}

extension CustomerDebtPartyFromSummary on CustomerDebtSummary {
  CustomerDebtParty toParty() {
    final n = displayName.trim().toLowerCase();
    return CustomerDebtParty(
      customerId: customerId,
      displayName: displayName.trim().isEmpty ? 'عميل' : displayName.trim(),
      normalizedName: n,
    );
  }
}

/// فاتورة دين آجل مفتوحة غير مربوطة ببطاقة عميل (`customerId` فارغ).
class UnlinkedCreditDebtInvoice {
  const UnlinkedCreditDebtInvoice({
    required this.invoiceId,
    required this.customerName,
    required this.remaining,
    required this.date,
    required this.normalizedName,
  });

  final int invoiceId;
  final String customerName;
  final double remaining;
  final DateTime date;
  final String normalizedName;
}

/// عميل مرشّح عند تكرار الاسم في جدول العملاء.
class AmbiguousDebtCustomerMatch {
  const AmbiguousDebtCustomerMatch({
    required this.customerId,
    required this.name,
  });

  final int customerId;
  final String name;
}

/// اسم يطابق أكثر من عميل مسجّل — لا يُسمح بالربط التلقائي.
class AmbiguousDebtCustomerName {
  const AmbiguousDebtCustomerName({
    required this.normalizedName,
    required this.sampleName,
    required this.matchingCustomerCount,
    required this.openInvoiceCount,
    this.matchingCustomers = const [],
  });

  final String normalizedName;
  final String sampleName;
  final int matchingCustomerCount;
  final int openInvoiceCount;
  final List<AmbiguousDebtCustomerMatch> matchingCustomers;
}

/// استثناء العميل من إعدادات الدين العامة (من صفحته).
class CustomerDebtException {
  const CustomerDebtException({
    this.periodDays,
    this.capFils,
    this.cashOnly = false,
  });

  /// فترة تسديد خاصة بالأيام؛ `null` = الفترة العامة، و0 = بلا فترة له.
  final int? periodDays;

  /// سقف دين خاص بالفلس؛ `null` = السقف العام، و0 = بلا سقف له.
  final int? capFils;

  /// «نقداً فقط»: لا دين جديد إلا برمز المالك.
  final bool cashOnly;

  static const none = CustomerDebtException();

  bool get isNone => periodDays == null && capFils == null && !cashOnly;

  factory CustomerDebtException.fromRow(Map<String, dynamic>? r) {
    if (r == null) return none;
    return CustomerDebtException(
      periodDays: (r['debtPeriodDays'] as num?)?.toInt(),
      capFils: (r['debtCapFils'] as num?)?.toInt(),
      cashOnly: ((r['cashOnly'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
