import 'pharmacy_invoice_line_view.dart';

/// تفاصيل فاتورة صيدلية كاملة.
class PharmacyInvoiceDetail {
  const PharmacyInvoiceDetail({
    required this.id,
    required this.date,
    required this.customerName,
    required this.lines,
    required this.subtotalDinars,
    required this.discountDinars,
    required this.taxDinars,
    required this.totalDinars,
    this.customerId,
  });

  final int id;
  final DateTime date;
  final String customerName;
  final int? customerId;
  final List<PharmacyInvoiceLineView> lines;
  final double subtotalDinars;
  final double discountDinars;
  final double taxDinars;
  final double totalDinars;
}
