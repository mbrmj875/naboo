/// سياسة مخزون صيدلانية — [pharmacy_stock_policy].
class PharmacyStockPolicy {
  const PharmacyStockPolicy({
    required this.id,
    required this.tenantId,
    required this.productId,
    this.minQty = 0,
    this.maxQty = 0,
    this.reorderQty = 0,
    this.shelfLocation,
    this.branchId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final int productId;
  final double minQty;
  final double maxQty;
  final double reorderQty;
  final String? shelfLocation;
  final int? branchId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PharmacyStockPolicy.fromMap(Map<String, dynamic> map) {
    return PharmacyStockPolicy(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      productId: (map['productId'] as num).toInt(),
      minQty: (map['minQty'] as num?)?.toDouble() ?? 0,
      maxQty: (map['maxQty'] as num?)?.toDouble() ?? 0,
      reorderQty: (map['reorderQty'] as num?)?.toDouble() ?? 0,
      shelfLocation: map['shelfLocation'] as String?,
      branchId: (map['branchId'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
