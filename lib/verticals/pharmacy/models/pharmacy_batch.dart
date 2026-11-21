/// دفعة مخزون صيدلانية — [pharmacy_batches].
class PharmacyBatch {
  const PharmacyBatch({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.batchNo,
    required this.expiryDate,
    required this.qty,
    required this.costFils,
    this.supplierId,
    this.branchId,
    this.recallFrozenAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final int productId;
  final String batchNo;
  final DateTime expiryDate;
  final double qty;
  final int costFils;
  final int? supplierId;
  final int? branchId;
  final DateTime? recallFrozenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  static DateTime _calendarDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// أيام متبقية حتى تاريخ الصلاحية (0 = ينتهي اليوم).
  int daysUntilExpiryOn(DateTime on) {
    return _calendarDay(expiryDate).difference(_calendarDay(on)).inDays;
  }

  int get daysUntilExpiry => daysUntilExpiryOn(DateTime.now());

  bool isExpiredOn(DateTime on) => daysUntilExpiryOn(on) <= 0;

  bool get isExpired => isExpiredOn(DateTime.now());

  factory PharmacyBatch.fromMap(Map<String, dynamic> map) {
    return PharmacyBatch(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      productId: (map['productId'] as num).toInt(),
      batchNo: (map['batchNo'] as String?) ?? '',
      expiryDate: DateTime.parse(map['expiryDate'] as String),
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      costFils: (map['costFils'] as num?)?.toInt() ?? 0,
      supplierId: (map['supplierId'] as num?)?.toInt(),
      branchId: (map['branchId'] as num?)?.toInt(),
      recallFrozenAt: map['recallFrozenAt'] != null
          ? DateTime.tryParse(map['recallFrozenAt'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
