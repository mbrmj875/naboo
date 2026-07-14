/// صنف زيت في كتالوج أسعار غيار الزيت (ماركة + لزوجة + سعر/لتر).
class OilChangeOilCatalogEntry {
  const OilChangeOilCatalogEntry({
    required this.id,
    required this.brandName,
    required this.viscosity,
    required this.sellPerLiterFils,
    this.sortOrder = 0,
  });

  final int id;
  final String brandName;
  final String viscosity;
  final int sellPerLiterFils;
  final int sortOrder;

  factory OilChangeOilCatalogEntry.fromMap(Map<String, dynamic> m) {
    return OilChangeOilCatalogEntry(
      id: (m['id'] as num).toInt(),
      brandName: (m['brandName'] ?? '').toString().trim(),
      viscosity: (m['viscosity'] ?? '').toString().trim(),
      sellPerLiterFils: (m['sellPerLiterFils'] as num?)?.toInt() ?? 0,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// نتيجة اختيار زيت من الكتالوج.
class OilChangeOilCatalogPick {
  const OilChangeOilCatalogPick({
    required this.brandName,
    required this.viscosity,
    required this.sellPerLiterFils,
    this.catalogEntryId,
  });

  final String brandName;
  final String viscosity;
  final int sellPerLiterFils;
  final int? catalogEntryId;
}
