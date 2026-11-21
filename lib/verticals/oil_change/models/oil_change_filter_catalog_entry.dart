import 'oil_change_filter_kind.dart';

/// صنف فلتر في كتالوج غيار الزيت (فئة + اسم + سعر بالفلس).
class OilChangeFilterCatalogEntry {
  const OilChangeFilterCatalogEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.priceFils,
    this.sortOrder = 0,
    this.productId,
    this.availableQty,
  });

  final int id;

  /// صنف المخزون حين يأتي الفلتر من المخزون (حسب حقل «الصنف»).
  final int? productId;

  /// الرصيد الظاهر في المخزون (للمعلومة فقط).
  final double? availableQty;
  final OilChangeFilterKind kind;
  final String name;
  final int priceFils;
  final int sortOrder;

  factory OilChangeFilterCatalogEntry.fromMap(Map<String, dynamic> m) {
    final code = (m['filterKind'] ?? '').toString().trim().toLowerCase();
    final known = OilChangeFilterKind.fromCode(code);
    return OilChangeFilterCatalogEntry(
      id: (m['id'] as num).toInt(),
      kind: known ??
          OilChangeFilterKind(
            code: code.isEmpty ? 'custom' : code,
            label: 'فلتر',
          ),
      name: (m['name'] ?? '').toString().trim(),
      priceFils: (m['priceFils'] as num?)?.toInt() ?? 0,
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  /// يحدّث تسمية الفئة من قائمة الفئات النشطة (بعد تحميل kinds من DB).
  OilChangeFilterCatalogEntry withResolvedKind(List<OilChangeFilterKind> kinds) {
    for (final k in kinds) {
      if (k.code == kind.code) {
        return OilChangeFilterCatalogEntry(
          id: id,
          kind: k,
          name: name,
          priceFils: priceFils,
          sortOrder: sortOrder,
          productId: productId,
          availableQty: availableQty,
        );
      }
    }
    return this;
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

  /// الفلتر أحضره العميل: لا ثمن ولا مخزون، فقط أجرة التركيب.
  bool customerProvided = false;

  /// أجرة التركيب التي كتبها الموظف لهذه البطاقة (null = من الإعدادات).
  int? laborCardFils;

  /// صنف المخزون المختار (مصدر الفلاتر «مرتبط بالمخزون»).
  int? productId;

  /// عدد القطع. [priceFils] = [unitPriceFils] × [qty].
  int qty = 1;
  int unitPriceFils = 0;

  /// سند الصرف المحفوظ على البطاقة (يبقى إن لم يتغير الصنف ولا العدد).
  int? stockVoucherId;

  void setQty(int value) {
    final q = value < 1 ? 1 : value;
    final unit = unitPriceFils > 0
        ? unitPriceFils
        : (qty > 0 ? priceFils ~/ qty : priceFils);
    qty = q;
    unitPriceFils = unit;
    priceFils = unit * q;
  }

  bool get hasSelection =>
      customerProvided ||
      priceFils > 0 ||
      catalogEntryId != null ||
      (name ?? '').trim().isNotEmpty;

  void clear() {
    catalogEntryId = null;
    name = null;
    priceFils = 0;
    customerProvided = false;
    laborCardFils = null;
    productId = null;
    qty = 1;
    unitPriceFils = 0;
    stockVoucherId = null;
  }

  void applyEntry(OilChangeFilterCatalogEntry e) {
    catalogEntryId = e.id;
    name = e.name;
    productId = e.productId;
    unitPriceFils = e.priceFils;
    priceFils = e.priceFils * (qty < 1 ? 1 : qty);
  }

  void loadFromRow(
    Map<String, dynamic> row, {
    required String nameKey,
    required String priceKey,
  }) {
    final n = (row[nameKey] ?? '').toString().trim();
    final p = (row[priceKey] as num?)?.toInt() ?? 0;
    if (n.isEmpty && p <= 0) {
      clear();
      return;
    }
    catalogEntryId = null;
    name = n.isEmpty ? null : n;
    priceFils = p < 0 ? 0 : p;
  }
}
