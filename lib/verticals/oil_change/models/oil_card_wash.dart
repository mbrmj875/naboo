import 'dart:convert';

/// نوع غسيل مختار داخل بطاقة الغيار وسعره لحظة البيع.
class OilCardWashLine {
  const OilCardWashLine({required this.name, required this.priceFils});

  final String name;
  final int priceFils;

  Map<String, dynamic> toJson() => {'name': name, 'priceFils': priceFils};

  static OilCardWashLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final p = raw['priceFils'];
    return OilCardWashLine(name: name, priceFils: p is num ? p.toInt() : 0);
  }
}

/// الغسلة داخل بطاقة الغيار (تُحفظ في `service_orders.cardWashJson`).
///
/// مبلغها بعد العرض [netFils] يدخل إجمالي البطاقة وفاتورتها، ويُطرح من تقرير
/// الغيار؛ وتُسجَّل طلب غسيل مرتبطاً بالبطاقة ليُعدّ في سجل الغسيل وتقريره.
class OilCardWash {
  const OilCardWash({
    required this.lines,
    this.washerName = '',
    this.discountFils = 0,
    this.offerCode,
    this.offerNote,
  });

  final List<OilCardWashLine> lines;
  final String washerName;
  final int discountFils;
  final String? offerCode;
  final String? offerNote;

  bool get isEmpty => lines.isEmpty;

  int get grossFils =>
      lines.fold<int>(0, (a, l) => a + (l.priceFils > 0 ? l.priceFils : 0));

  int get netFils {
    final n = grossFils - discountFils;
    return n < 0 ? 0 : n;
  }

  bool get isFree => !isEmpty && grossFils > 0 && netFils == 0;

  List<String> get serviceNames => [for (final l in lines) l.name];

  /// اسم سطر الفاتورة والإيصال.
  String get invoiceLineName => 'غسيل: ${serviceNames.join('، ')}';

  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    if (washerName.trim().isNotEmpty) 'washer': washerName.trim(),
    if (discountFils > 0) 'discountFils': discountFils,
    if ((offerCode ?? '').isNotEmpty) 'offerCode': offerCode,
    if ((offerNote ?? '').isNotEmpty) 'offerNote': offerNote,
  };

  String toJsonString() => jsonEncode(toJson());

  /// null إن لم تكن في البطاقة غسلة.
  static OilCardWash? fromOrder(Map<String, dynamic>? order) {
    final raw = order?['cardWashJson'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final lines = <OilCardWashLine>[
        if (m['lines'] is List)
          for (final e in m['lines'] as List) ?OilCardWashLine.fromJson(e),
      ];
      if (lines.isEmpty) return null;
      final d = m['discountFils'];
      final gross = lines.fold<int>(
        0,
        (a, l) => a + (l.priceFils > 0 ? l.priceFils : 0),
      );
      final disc = d is num ? d.toInt().clamp(0, gross) : 0;
      final code = (m['offerCode'] ?? '').toString().trim();
      final note = (m['offerNote'] ?? '').toString().trim();
      return OilCardWash(
        lines: lines,
        washerName: (m['washer'] ?? '').toString().trim(),
        discountFils: disc,
        offerCode: code.isEmpty ? null : code,
        offerNote: note.isEmpty ? null : note,
      );
    } catch (_) {
      return null;
    }
  }

  /// أعمدة البطاقة؛ بلا غسلة تُفرَّغ (حذف الغسلة عند التعديل).
  static Map<String, Object?> columnsFor(OilCardWash? wash) {
    if (wash == null || wash.isEmpty) {
      return {'cardWashJson': null, 'cardWashNetFils': null};
    }
    return {
      'cardWashJson': wash.toJsonString(),
      'cardWashNetFils': wash.netFils,
    };
  }
}
