/// سطر منتج مرفق ببطاقة غيار الزيت (يُحفظ في [service_order_items]).
class OilChangeProductLine {
  OilChangeProductLine({
    this.id,
    required this.productId,
    required this.productName,
    this.quantity = 1,
    required this.priceFils,
  })  : assert(productId > 0),
        assert(quantity > 0),
        assert(priceFils >= 0);

  final int? id;
  final int productId;
  final String productName;
  int quantity;
  int priceFils;

  int get totalFils => quantity * priceFils;

  factory OilChangeProductLine.fromMap(Map<String, dynamic> row) {
    final pid = (row['productId'] as num?)?.toInt() ?? 0;
    final q = (row['quantity'] as num?)?.toInt() ?? 1;
    final p = (row['priceFils'] as num?)?.toInt() ?? 0;
    return OilChangeProductLine(
      id: (row['id'] as num?)?.toInt(),
      productId: pid,
      productName: (row['productName'] ?? '').toString().trim(),
      quantity: q <= 0 ? 1 : q,
      priceFils: p < 0 ? 0 : p,
    );
  }

  OilChangeProductLine copyWith({
    int? quantity,
    int? priceFils,
  }) {
    return OilChangeProductLine(
      id: id,
      productId: productId,
      productName: productName,
      quantity: quantity ?? this.quantity,
      priceFils: priceFils ?? this.priceFils,
    );
  }
}
