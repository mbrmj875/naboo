import 'pharmacy_rx_schedule.dart';

/// ربط منتج Core بمرجع دوائي — [pharmacy_product_profile].
class PharmacyProductProfile {
  const PharmacyProductProfile({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.drugReferenceId,
    this.manufacturerId,
    this.dosageFormId,
    this.strengthText,
    this.rxSchedule = PharmacyRxSchedule.otc,
    this.productCategory = 'drug',
    this.warningsText,
    this.branchId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final int productId;
  final int drugReferenceId;
  final int? manufacturerId;
  final int? dosageFormId;
  final String? strengthText;
  final String rxSchedule;
  final String productCategory;
  final String? warningsText;
  final int? branchId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PharmacyProductProfile.fromMap(Map<String, dynamic> map) {
    return PharmacyProductProfile(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      productId: (map['productId'] as num).toInt(),
      drugReferenceId: (map['drugReferenceId'] as num).toInt(),
      manufacturerId: (map['manufacturerId'] as num?)?.toInt(),
      dosageFormId: (map['dosageFormId'] as num?)?.toInt(),
      strengthText: map['strengthText'] as String?,
      rxSchedule: (map['rxSchedule'] as String?) ?? PharmacyRxSchedule.otc,
      productCategory: (map['productCategory'] as String?) ?? 'drug',
      warningsText: map['warningsText'] as String?,
      branchId: (map['branchId'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
