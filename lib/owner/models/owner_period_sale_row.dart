/// صف واحد في تفصيل مبيعات فترة لوحة المالك.
enum OwnerPeriodSaleKind { oilCard, invoice }

class OwnerPeriodSaleRow {
  const OwnerPeriodSaleRow({
    required this.kind,
    required this.recordId,
    required this.createdAtIso,
    required this.title,
    required this.amountFils,
    this.subtitle,
    this.invoiceId,
    this.orderGlobalId,
    this.staffName,
  });

  final OwnerPeriodSaleKind kind;

  /// معرف بطاقة الغيار أو الفاتورة.
  final int recordId;

  final String createdAtIso;
  final String title;
  final String? subtitle;
  final int amountFils;
  final int? invoiceId;
  final String? orderGlobalId;
  final String? staffName;

  bool get hasInvoice => invoiceId != null && invoiceId! > 0;
}
