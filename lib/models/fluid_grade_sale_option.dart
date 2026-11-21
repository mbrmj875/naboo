/// صف بيع لعائلة سوائل (زيت / هيدروليك) في نقطة البيع.
class FluidGradeSaleOption {
  const FluidGradeSaleOption({
    required this.linkedProductId,
    required this.gradeLabel,
    required this.sellPerLiter,
    required this.stockLiters,
    required this.packs,
  });

  final int linkedProductId;
  final String gradeLabel;
  final double sellPerLiter;
  final double stockLiters;
  final List<FluidPackSaleOption> packs;
}

class FluidPackSaleOption {
  const FluidPackSaleOption({
    required this.unitVariantId,
    required this.unitName,
    required this.unitSymbol,
    required this.factorToBase,
    this.sellPrice,
  });

  final int unitVariantId;
  final String unitName;
  final String unitSymbol;
  final double factorToBase;
  final double? sellPrice;

  String get displayLabel {
    if ((factorToBase - 1).abs() < 1e-9) return unitName;
    final n = factorToBase % 1 == 0
        ? factorToBase.toInt().toString()
        : factorToBase.toStringAsFixed(2);
    return '$unitName ($n لتر)';
  }

  /// سعر البيع لكل وحدة عبوة واحدة (لتر أو علبة…).
  double sellPerUnit(double gradeSellPerLiter) {
    if (sellPrice != null && sellPrice! > 0) return sellPrice!;
    return gradeSellPerLiter * factorToBase;
  }
}

String fluidSalePackKey(int linkedProductId, int unitVariantId) =>
    '$linkedProductId|$unitVariantId';

({int linkedProductId, int unitVariantId})? parseFluidSalePackKey(String key) {
  final parts = key.split('|');
  if (parts.length != 2) return null;
  final linked = int.tryParse(parts[0]);
  final unit = int.tryParse(parts[1]);
  if (linked == null || unit == null || linked <= 0 || unit <= 0) return null;
  return (linkedProductId: linked, unitVariantId: unit);
}
