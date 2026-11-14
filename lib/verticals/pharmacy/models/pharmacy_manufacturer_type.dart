/// نوع الشركة المنتجة — قيم [pharmacy_manufacturers.type].
abstract class PharmacyManufacturerType {
  PharmacyManufacturerType._();

  static const originator = 'originator';
  static const generic = 'generic';
  static const local = 'local';

  static const all = [originator, generic, local];
}

/// تصنيف جودة A/B/C — [pharmacy_manufacturers.qualityTier].
abstract class PharmacyQualityTier {
  PharmacyQualityTier._();

  static const a = 'A';
  static const b = 'B';
  static const c = 'C';

  static const all = [a, b, c];
}
