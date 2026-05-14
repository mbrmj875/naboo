/// ذمم دائنة (Accounts Payable) — ما على المتجر للموردين.
///
/// يُمثّل [SupplierBill] «وصل المورد» الخارجي (مرجعهم + مبلغ + صورة اختيارية).
/// [SupplierPayout] دفعة من الصندوق (أو تسجيل دفع خارجي دون صندوق).
class Supplier {
  const Supplier({
    required this.id,
    this.globalId,
    required this.name,
    this.phone,
    this.notes,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String? globalId;
  final String name;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
}


/// ملخص رصيد مورد: مجموع وصولاتهم − مجموع ما دفعناه.
class SupplierApSummary {
  const SupplierApSummary({
    required this.supplier,
    required this.totalBilled,
    required this.totalPaid,
  });

  final Supplier supplier;
  final double totalBilled;
  final double totalPaid;

  double get openPayable => totalBilled - totalPaid;
}

class SupplierBill {
  const SupplierBill({
    required this.id,
    this.globalId,
    required this.supplierId,
    this.theirReference,
    this.theirBillDate,
    required this.amount,
    this.note,
    this.imagePath,
    required this.createdAt,
    this.updatedAt,
    this.createdByUserName,
    this.linkedStockVoucherId,
    this.linkedVoucherNo,
  });

  final int id;
  final String? globalId;
  final int supplierId;
  final String? theirReference;
  final DateTime? theirBillDate;
  final double amount;
  final String? note;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdByUserName;


  /// إذن مخزوني وارد مرتبط بهذا الوصل (إن وُجد).
  final int? linkedStockVoucherId;
  final String? linkedVoucherNo;
}

class SupplierPayout {
  const SupplierPayout({
    required this.id,
    this.globalId,
    required this.supplierId,
    required this.amount,
    this.note,
    required this.createdAt,
    this.updatedAt,
    this.createdByUserName,
    required this.affectsCash,
    this.receiptInvoiceId,
  });

  final int id;
  final String? globalId;
  final int supplierId;
  final double amount;
  final String? note;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdByUserName;
  final bool affectsCash;


  /// سند الفاتورة المرتبط (قائمة الفواتير) إن وُجد.
  final int? receiptInvoiceId;
}

class SupplierPayoutResult {
  const SupplierPayoutResult({
    required this.payoutId,
    required this.receiptInvoiceId,
    this.cashLedgerId,
  });

  final int payoutId;
  final int receiptInvoiceId;
  final int? cashLedgerId;
}
