import '../models/pharmacy_drug_reference.dart';

/// يطابق حساسيات العميل مع مرجع الدواء.
class AllergyChecker {
  const AllergyChecker();

  bool matchesAllergy({
    required List<String> allergies,
    required PharmacyDrugReference reference,
    required String productName,
  }) {
    if (allergies.isEmpty) return false;
    final needles = <String>{
      reference.id.toString(),
      reference.nameEn.trim().toLowerCase(),
      reference.nameAr.trim(),
      productName.trim().toLowerCase(),
      if (reference.atcCode != null) reference.atcCode!.trim().toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    for (final allergy in allergies) {
      final a = allergy.trim();
      if (a.isEmpty) continue;
      final lower = a.toLowerCase();
      if (needles.contains(a) || needles.contains(lower)) return true;
      for (final n in needles) {
        if (n.length >= 3 && (lower.contains(n) || n.contains(lower))) {
          return true;
        }
      }
    }
    return false;
  }
}
