import 'package:flutter/foundation.dart';

import 'invoice.dart';
import '../utils/iraqi_currency_format.dart';

/// نوع سطر في خلاصة «آخر النشاط» على لوحة التحكم.
enum RecentActivityKind {
  /// فاتورة مسجّلة في [invoices].
  invoice,

  /// حركة من [cash_ledger].
  cashMovement,

  /// بيع مؤجّل في [parked_sales].
  parkedSale,

  /// سطر من [loyalty_ledger].
  loyalty,

  /// سند مخزون من [stock_vouchers].
  stockVoucher,

  /// عميل جديد في [customers].
  customerCreated,

  /// صنف جديد في [products].
  productCreated,

  /// فتح أو إغلاق وردية في [work_shifts].
  workShift,
}

/// سطر واحد في تغذية النشاط الأخير — يُبنى من [DatabaseHelper.getRecentActivityFeed].
@immutable
class RecentActivityEntry {
  const RecentActivityEntry({
    required this.kind,
    required this.at,
    required this.title,
    required this.subtitle,
    this.amountIqd,
    this.invoiceId,
    this.cashLedgerId,
    this.linkedInvoiceId,
    this.parkedSaleId,
    this.loyaltyLedgerId,
    this.stockVoucherId,
    this.customerId,
    this.productId,
    this.workShiftId,
  });

  final RecentActivityKind kind;
  final DateTime at;
  final String title;
  final String subtitle;

  /// للعرض (فاتورة إجمالي، صندوق المبلغ الموقّع).
  final double? amountIqd;

  /// للانتقال إلى تفاصيل الفاتورة.
  final int? invoiceId;

  final int? cashLedgerId;

  /// قيد صندوق مرتبط بفاتورة (اختياري).
  final int? linkedInvoiceId;

  final int? parkedSaleId;
  final int? loyaltyLedgerId;
  final int? stockVoucherId;

  /// عميل مرتبط (ولاء أو تسجيل عميل جديد).
  final int? customerId;
  final int? productId;
  final int? workShiftId;

  /// أنواع لا تُصنَّف ضمن «فواتير» أو «صندوق» في شريط التصفية.
  static bool kindIsOtherThanInvoiceOrCash(RecentActivityKind k) {
    return k != RecentActivityKind.invoice &&
        k != RecentActivityKind.cashMovement;
  }

  String get amountLabel => amountIqd == null
      ? ''
      : IraqiCurrencyFormat.formatIqd(amountIqd!);

  String get timeLabel {
    final now = DateTime.now();
    final d = DateTime(at.year, at.month, at.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) {
      final h = at.hour.toString().padLeft(2, '0');
      final m = at.minute.toString().padLeft(2, '0');
      return 'اليوم $h:$m';
    }
    if (diff == 1) return 'أمس';
    return '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}';
  }

  factory RecentActivityEntry.fromInvoiceRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final type = invoiceTypeFromDb(r['type']);
    final isRet = (r['isReturned'] as int? ?? 0) != 0;
    final name = r['customerName']?.toString().trim();
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final rawDate = r['date']?.toString();
    final date = DateTime.tryParse(rawDate ?? '') ?? DateTime.now();
    final typeLabel = _invoiceTypeLabelAr(type);
    final title = isRet ? 'مرتجع #$id' : 'فاتورة $typeLabel · #$id';
    final sub = (name != null && name.isNotEmpty) ? name : 'بدون اسم عميل';
    final by = r['createdByUserName']?.toString().trim();
    final sub2 = (by != null && by.isNotEmpty) ? '$sub · $by' : sub;
    return RecentActivityEntry(
      kind: RecentActivityKind.invoice,
      at: date,
      title: title,
      subtitle: sub2,
      amountIqd: total,
      invoiceId: id,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: null,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromCashRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final amt = (r['amount'] as num).toDouble();
    final tt = r['transactionType']?.toString() ?? '';
    final desc = r['description']?.toString().trim() ?? '';
    final invId = r['invoiceId'] as int?;
    final raw = r['createdAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    final typeLabel = ledgerTransactionTypeLabelAr(tt);
    String sub;
    if (desc.isNotEmpty) {
      sub = desc;
    } else if (invId != null) {
      sub = 'مرتبط بفاتورة #$invId';
    } else {
      sub = 'صندوق';
    }
    return RecentActivityEntry(
      kind: RecentActivityKind.cashMovement,
      at: date,
      title: typeLabel,
      subtitle: sub,
      amountIqd: amt,
      invoiceId: null,
      cashLedgerId: id,
      linkedInvoiceId: invId,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: null,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromParkedRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final title = r['title']?.toString().trim();
    final raw = r['updatedAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    final label = (title != null && title.isNotEmpty) ? title : 'بيع مؤجّل';
    return RecentActivityEntry(
      kind: RecentActivityKind.parkedSale,
      at: date,
      title: 'مؤجّل · #$id',
      subtitle: label,
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: id,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: null,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromLoyaltyRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final cid = r['customerId'] as int;
    final kind = r['kind']?.toString() ?? '';
    final pts = (r['points'] as num?)?.toInt() ?? 0;
    final name = r['customerName']?.toString().trim();
    final sub = (name != null && name.isNotEmpty) ? name : 'عميل #$cid';
    final raw = r['createdAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    final typeLabel = loyaltyKindLabelAr(kind);
    return RecentActivityEntry(
      kind: RecentActivityKind.loyalty,
      at: date,
      title: '$typeLabel · ${pts >= 0 ? '+' : ''}$pts نقطة',
      subtitle: sub,
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: r['invoiceId'] as int?,
      parkedSaleId: null,
      loyaltyLedgerId: id,
      stockVoucherId: null,
      customerId: cid,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromStockVoucherRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final no = r['voucherNo']?.toString() ?? '#$id';
    final vType = r['voucherType']?.toString() ?? '';
    final raw = r['createdAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    final typeLabel = stockVoucherTypeLabelAr(vType);
    final note = r['notes']?.toString().trim();
    return RecentActivityEntry(
      kind: RecentActivityKind.stockVoucher,
      at: date,
      title: 'سند مخزون $typeLabel · $no',
      subtitle: (note != null && note.isNotEmpty) ? note : 'مخزون',
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: id,
      customerId: null,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromCustomerCreatedRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final name = r['name']?.toString().trim() ?? 'عميل #$id';
    final raw = r['createdAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    return RecentActivityEntry(
      kind: RecentActivityKind.customerCreated,
      at: date,
      title: 'عميل جديد · #$id',
      subtitle: name,
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: id,
      productId: null,
      workShiftId: null,
    );
  }

  factory RecentActivityEntry.fromProductCreatedRow(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final name = r['name']?.toString().trim() ?? 'صنف #$id';
    final raw = r['createdAt']?.toString();
    final date = DateTime.tryParse(raw ?? '') ?? DateTime.now();
    return RecentActivityEntry(
      kind: RecentActivityKind.productCreated,
      at: date,
      title: 'صنف جديد · #$id',
      subtitle: name,
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: null,
      productId: id,
      workShiftId: null,
    );
  }

  /// [isClose] يحدد إن كان الحدث إغلاق الوردية (وإلا فتح).
  factory RecentActivityEntry.fromWorkShiftRow(
    Map<String, dynamic> r, {
    required bool isClose,
  }) {
    final id = r['id'] as int;
    final name = r['shiftStaffName']?.toString().trim() ?? '';
    final rawAt = isClose
        ? r['closedAt']?.toString()
        : r['openedAt']?.toString();
    final date = DateTime.tryParse(rawAt ?? '') ?? DateTime.now();
    final title = isClose ? 'إغلاق وردية' : 'فتح وردية';
    final sub = name.isNotEmpty ? name : 'وردية #$id';
    return RecentActivityEntry(
      kind: RecentActivityKind.workShift,
      at: date,
      title: title,
      subtitle: sub,
      amountIqd: null,
      invoiceId: null,
      cashLedgerId: null,
      linkedInvoiceId: null,
      parkedSaleId: null,
      loyaltyLedgerId: null,
      stockVoucherId: null,
      customerId: null,
      productId: null,
      workShiftId: id,
    );
  }
}

String _invoiceTypeLabelAr(InvoiceType t) {
  switch (t) {
    case InvoiceType.cash:
      return 'نقدي';
    case InvoiceType.credit:
      return 'آجل';
    case InvoiceType.installment:
      return 'تقسيط';
    case InvoiceType.delivery:
      return 'توصيل';
    case InvoiceType.debtCollection:
      return 'تحصيل دين';
    case InvoiceType.installmentCollection:
      return 'تسديد قسط';
    case InvoiceType.supplierPayment:
      return 'دفع مورد';
  }
}

/// يطابق تسميات [cash_screen] لحركات [cash_ledger].
String ledgerTransactionTypeLabelAr(String transactionType) {
  switch (transactionType) {
    case 'sale_cash':
      return 'بيع نقدي';
    case 'sale_advance':
      return 'مقدم / دفعة';
    case 'sale_other':
      return 'بيع';
    case 'manual_in':
      return 'إيداع يدوي';
    case 'manual_out':
      return 'سحب يدوي';
    case 'installment_payment':
      return 'تسديد قسط';
    case 'supplier_payment':
      return 'دفع مورد';
    case 'supplier_payment_reversal':
      return 'عكس دفع مورد';
    case 'sale_return':
      return 'مرتجع';
    default:
      return transactionType.isEmpty ? 'حركة صندوق' : transactionType;
  }
}

String loyaltyKindLabelAr(String kind) {
  switch (kind) {
    case 'earn':
      return 'كسب نقاط';
    case 'redeem':
      return 'استبدال نقاط';
    case 'adjust':
      return 'تعديل نقاط';
    default:
      return kind.isEmpty ? 'ولاء' : kind;
  }
}

String stockVoucherTypeLabelAr(String voucherType) {
  switch (voucherType) {
    case 'in':
      return 'وارد';
    case 'out':
      return 'صادر';
    case 'transfer':
      return 'نقل';
    default:
      return voucherType.isEmpty ? 'مخزون' : voucherType;
  }
}
