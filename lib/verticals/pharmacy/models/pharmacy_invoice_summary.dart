import 'pharmacy_invoice_line_view.dart';

/// ملخص فاتورة للقائمة — مع أول بنود للعرض المختصر.
class PharmacyInvoiceSummary {
  const PharmacyInvoiceSummary({
    required this.id,
    required this.date,
    required this.customerName,
    required this.totalDinars,
    required this.previewLines,
  });

  final int id;
  final DateTime date;
  final String customerName;
  final double totalDinars;
  final List<PharmacyInvoiceLineView> previewLines;
}
