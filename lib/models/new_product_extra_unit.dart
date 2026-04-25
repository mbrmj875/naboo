/// وحدة بيع إضافية تُمرَّر مع إنشاء المنتج ليُدرج كل شيء في معاملة واحدة.
class NewProductExtraUnit {
  const NewProductExtraUnit({
    required this.unitName,
    this.unitSymbol,
    required this.factorToBase,
    this.barcode,
    this.sellPrice,
    this.minSellPrice,
  });

  final String unitName;
  final String? unitSymbol;
  final double factorToBase;
  final String? barcode;
  final double? sellPrice;
  final double? minSellPrice;
}
