/// بديل صيدلاني — نفس INN + تركيز + شكل.
class PharmacySubstituteCandidate {
  const PharmacySubstituteCandidate({
    required this.productId,
    required this.productName,
    required this.sellPrice,
    this.manufacturerName,
    this.qualityTier,
    this.strengthText,
  });

  final int productId;
  final String productName;
  final double sellPrice;
  final String? manufacturerName;
  final String? qualityTier;
  final String? strengthText;
}
