/// صنف هيدروليك في كتالوج أسعار غيار الزيت (ماركة + درجة + سعر/لتر).
class OilChangeHydraulicCatalogEntry {
  const OilChangeHydraulicCatalogEntry({
    required this.id,
    required this.brandName,
    required this.grade,
    required this.sellPerLiterFils,
    this.sortOrder = 0,
  });

  final int id;
  final String brandName;
  final String grade;
  final int sellPerLiterFils;
  final int sortOrder;

  factory OilChangeHydraulicCatalogEntry.fromMap(Map<String, dynamic> m) {
    return OilChangeHydraulicCatalogEntry(
      id: (m['id'] as num).toInt(),
      brandName: (m['brandName'] ?? '').toString().trim(),
      grade: (m['grade'] ?? '').toString().trim(),
      sellPerLiterFils: (m['sellPerLiterFils'] as num?)?.toInt() ?? 0,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// نتيجة اختيار هيدروليك من الكتالوج.
class OilChangeHydraulicCatalogPick {
  const OilChangeHydraulicCatalogPick({
    required this.brandName,
    required this.grade,
    required this.sellPerLiterFils,
    this.catalogEntryId,
  });

  final String brandName;
  final String grade;
  final int sellPerLiterFils;
  final int? catalogEntryId;
}
