/// تمييز نوع متغيرات المنتج على [products.variantKind].
abstract class ProductVariantKind {
  ProductVariantKind._();

  /// منتج عادي (قطعة / لتر مفرد / صنف زيت فرعي).
  static const int none = 0;

  /// ملابس — [product_colors] + [product_variants].
  static const int clothing = 1;

  /// عائلة هيدروليك — [product_oil_grades] + أصناف فرعية.
  static const int hydraulicFamily = 2;

  /// عائلة زيت — [product_oil_grades] + أصناف فرعية (لزوجات).
  static const int oilFamily = 3;

  static bool isHydraulicFamilyParent(Map<String, dynamic> row) =>
      (row['variantKind'] as num?)?.toInt() == hydraulicFamily;

  static bool isOilFamilyParent(Map<String, dynamic> row) =>
      (row['variantKind'] as num?)?.toInt() == oilFamily;

  static bool isFluidFamilyParent(Map<String, dynamic> row) {
    final k = (row['variantKind'] as num?)?.toInt() ?? 0;
    return k == hydraulicFamily || k == oilFamily;
  }

  static bool isOilFamilyChild(Map<String, dynamic> row) {
    final pid = (row['parentProductId'] as num?)?.toInt();
    return pid != null && pid > 0;
  }
}
