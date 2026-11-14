/// وحدة عبوة لزوجة زيت (لتر / كوارت / علبة …) عند الحفظ.
class OilGradePackInput {
  const OilGradePackInput({
    required this.unitName,
    this.unitSymbol,
    required this.factorToBase,
    this.barcode,
    this.sellPrice,
    this.minSellPrice,
  });

  final String unitName;
  final String? unitSymbol;
  /// كم لتراً يُخصم من المخزون لكل وحدة مبيعة واحدة.
  final double factorToBase;
  final String? barcode;
  final double? sellPrice;
  final double? minSellPrice;
}

/// لزوجة واحدة ضمن عائلة زيت.
class OilGradeInput {
  const OilGradeInput({
    required this.viscosity,
    required this.openingQtyLiters,
    required this.buyPrice,
    required this.sellPrice,
    this.minSellPrice,
    this.barcode,
    this.packs = const [],
  });

  final String viscosity;
  final double openingQtyLiters;
  final double buyPrice;
  final double sellPrice;
  final double? minSellPrice;
  final String? barcode;
  final List<OilGradePackInput> packs;
}
