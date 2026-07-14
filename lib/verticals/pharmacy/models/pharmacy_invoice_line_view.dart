/// سطر دواء في قائمة أو تفاصيل فاتورة صيدلية.
class PharmacyInvoiceLineView {
  const PharmacyInvoiceLineView({
    required this.productName,
    required this.qty,
    required this.unitPriceDinars,
    required this.lineTotalDinars,
    this.strengthText,
    this.innName,
    this.atcCode,
    this.rxSchedule,
  });

  final String productName;
  final double qty;
  final double unitPriceDinars;
  final double lineTotalDinars;
  final String? strengthText;
  final String? innName;
  final String? atcCode;
  final String? rxSchedule;

  String get displayName {
    final strength = strengthText?.trim();
    if (strength == null || strength.isEmpty) return productName;
    return '$productName $strength';
  }

  String get compactLabel {
    final qtyLabel = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(1);
    return '$displayName · $qtyLabel ص · ${unitPriceDinars.round()}د';
  }
}
