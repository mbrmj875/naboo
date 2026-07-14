import 'oil_change_filter_kind.dart';

/// صنف فلتر في كتالوج غيار الزيت (فئة + اسم + سعر بالفلس).
class OilChangeFilterCatalogEntry {
  const OilChangeFilterCatalogEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.priceFils,
    this.sortOrder = 0,
  });

  final int id;
  final OilChangeFilterKind kind;
  final String name;
  final int priceFils;
  final int sortOrder;

  factory OilChangeFilterCatalogEntry.fromMap(Map<String, dynamic> m) {
    return OilChangeFilterCatalogEntry(
      id: (m['id'] as num).toInt(),
      kind: OilChangeFilterKind.fromCode(m['filterKind']?.toString()) ??
          OilChangeFilterKind.engine,
      name: (m['name'] ?? '').toString().trim(),
      priceFils: (m['priceFils'] as num?)?.toInt() ?? 0,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// اختيار فلتر واحد على البطاقة.
class OilChangeFilterPick {
  const OilChangeFilterPick({
    required this.kind,
    required this.name,
    required this.priceFils,
    this.catalogEntryId,
  });

  final OilChangeFilterKind kind;
  final String name;
  final int priceFils;
  final int? catalogEntryId;
}

/// حالة فلتر واحد في نموذج البطاقة.
class OilChangeFilterSlot {
  int? catalogEntryId;
  String? name;
  int priceFils = 0;

  bool get hasSelection => (name ?? '').trim().isNotEmpty;

  void clear() {
    catalogEntryId = null;
    name = null;
    priceFils = 0;
  }

  void applyEntry(OilChangeFilterCatalogEntry e) {
    catalogEntryId = e.id;
    name = e.name;
    priceFils = e.priceFils;
  }

  void loadFromRow(
    Map<String, dynamic> row, {
    required String nameKey,
    required String priceKey,
  }) {
    final n = (row[nameKey] ?? '').toString().trim();
    final p = (row[priceKey] as num?)?.toInt() ?? 0;
    if (n.isEmpty) {
      clear();
      return;
    }
    catalogEntryId = null;
    name = n;
    priceFils = p < 0 ? 0 : p;
  }
}
