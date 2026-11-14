/// شكل صيدلاني — [pharmacy_dosage_forms].
class PharmacyDosageForm {
  const PharmacyDosageForm({
    required this.id,
    required this.tenantId,
    required this.nameAr,
    required this.nameEn,
    required this.code,
    this.unitLabel,
    this.isSplittable = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final String nameAr;
  final String nameEn;
  final String code;
  final String? unitLabel;
  final bool isSplittable;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PharmacyDosageForm.fromMap(Map<String, dynamic> map) {
    return PharmacyDosageForm(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      nameAr: (map['nameAr'] as String?) ?? '',
      nameEn: (map['nameEn'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      unitLabel: map['unitLabel'] as String?,
      isSplittable: (map['isSplittable'] as num?)?.toInt() == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }
}
