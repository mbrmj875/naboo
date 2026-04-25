/// تجميع ديون «آجل» لعميل (مسجّل أو باسم فقط).
class CustomerDebtSummary {
  const CustomerDebtSummary({
    required this.customerId,
    required this.displayName,
    required this.openRemaining,
    required this.invoiceCount,
    this.oldestInvoiceDate,
  });

  /// null = عميل غير مربوط بجدول العملاء؛ التجميع بالاسم فقط.
  final int? customerId;
  final String displayName;
  final double openRemaining;
  final int invoiceCount;
  final DateTime? oldestInvoiceDate;
}

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
