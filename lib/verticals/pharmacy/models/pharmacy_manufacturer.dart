import 'pharmacy_manufacturer_type.dart';

/// شركة منتجة — [pharmacy_manufacturers].
class PharmacyManufacturer {
  const PharmacyManufacturer({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.type,
    this.countryCode,
    this.qualityTier,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final String name;
  final String type;
  final String? countryCode;
  final String? qualityTier;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PharmacyManufacturer.fromMap(Map<String, dynamic> map) {
    return PharmacyManufacturer(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      name: (map['name'] as String?) ?? '',
      type: (map['type'] as String?) ?? PharmacyManufacturerType.generic,
      countryCode: map['countryCode'] as String?,
      qualityTier: map['qualityTier'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
