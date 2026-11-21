/// حساسيات شائعة — تُخزَّن [key] في JSON وتُعرَض [labelAr] في الواجهة.
class CommonPharmacyAllergy {
  const CommonPharmacyAllergy({
    required this.key,
    required this.labelAr,
  });

  final String key;
  final String labelAr;
}

const kCommonPharmacyAllergies = <CommonPharmacyAllergy>[
  CommonPharmacyAllergy(key: 'Penicillin', labelAr: 'بنسلين'),
  CommonPharmacyAllergy(key: 'Aspirin', labelAr: 'أسبرين'),
  CommonPharmacyAllergy(key: 'NSAIDs', labelAr: 'مضادات الالتهاب (NSAIDs)'),
  CommonPharmacyAllergy(key: 'Codeine', labelAr: 'كودايين'),
  CommonPharmacyAllergy(key: 'Sulfa', labelAr: 'سلفا'),
  CommonPharmacyAllergy(key: 'Latex', labelAr: 'لاتекс'),
  CommonPharmacyAllergy(key: 'Iodine', labelAr: 'يود'),
  CommonPharmacyAllergy(key: 'Morphine', labelAr: 'مورفين'),
  CommonPharmacyAllergy(key: 'Cephalosporins', labelAr: 'سيفالوسبورين'),
  CommonPharmacyAllergy(key: 'Tetracycline', labelAr: 'تتراسيكلين'),
];

String pharmacyAllergyLabelAr(String key) {
  for (final a in kCommonPharmacyAllergies) {
    if (a.key.toLowerCase() == key.toLowerCase()) return a.labelAr;
  }
  return key;
}
