import 'dart:convert';

import '../models/oil_change_filter_kind.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';

String _priceLabel(int fils) {
  if (fils <= 0) return '';
  return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
}

/// سطر عرض واحد: «فلتر المحرك: تويوتا أصلي — 15,000 د.ع»
/// أو بدون اسم: «فلتر المحرك — 15,000 د.ع».
String? oilFilterLineLabel({
  required String kindLabel,
  required String name,
  int priceFils = 0,
}) {
  final n = name.trim();
  final price = _priceLabel(priceFils);
  if (n.isEmpty && price.isEmpty) return null;
  if (n.isEmpty) return '$kindLabel — $price';
  if (price.isEmpty) return '$kindLabel: $n';
  return '$kindLabel: $n — $price';
}

/// عنصر فلتر محفوظ على البطاقة (فئة ديناميكية).
class OilFilterLineData {
  const OilFilterLineData({
    required this.code,
    required this.name,
    required this.priceFils,
    this.catalogEntryId,
    this.label,
  });

  final String code;
  final String name;
  final int priceFils;
  final int? catalogEntryId;
  final String? label;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'priceFils': priceFils,
        if (catalogEntryId != null) 'catalogEntryId': catalogEntryId,
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
      };

  factory OilFilterLineData.fromJson(Map<String, dynamic> m) {
    return OilFilterLineData(
      code: (m['code'] ?? '').toString().trim().toLowerCase(),
      name: (m['name'] ?? '').toString().trim(),
      priceFils: (m['priceFils'] as num?)?.toInt() ?? 0,
      catalogEntryId: (m['catalogEntryId'] as num?)?.toInt(),
      label: (m['label'] ?? '').toString().trim().isEmpty
          ? null
          : (m['label'] ?? '').toString().trim(),
    );
  }
}

List<OilFilterLineData> parseOilFiltersJson(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return const [];
  try {
    final decoded = jsonDecode(t);
    if (decoded is! List) return const [];
    final out = <OilFilterLineData>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final line = OilFilterLineData.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (line.code.isEmpty) continue;
      if (line.name.isEmpty && line.priceFils <= 0) continue;
      out.add(line);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String encodeOilFiltersJson(List<OilFilterLineData> lines) {
  if (lines.isEmpty) return '';
  return jsonEncode([for (final l in lines) l.toJson()]);
}

/// يقرأ الفلاتر من JSON الحديث أو أعمدة المحرك/الهواء/الكير القديمة.
List<OilFilterLineData> oilFilterLinesDataFromRow(Map<String, dynamic> row) {
  final fromJson = parseOilFiltersJson(row['oilFiltersJson']?.toString());
  if (fromJson.isNotEmpty) return fromJson;

  final out = <OilFilterLineData>[];
  for (final kind in OilChangeFilterKind.builtins) {
    final name = (row[kind.nameColumnKey] ?? '').toString().trim();
    final fils = (row[kind.priceColumnKey] as num?)?.toInt() ?? 0;
    if (name.isEmpty && fils <= 0) continue;
    out.add(OilFilterLineData(code: kind.code, name: name, priceFils: fils));
  }
  return out;
}

List<String> oilFilterLinesFromRow(Map<String, dynamic> row) {
  final out = <String>[];
  final labelByCode = <String, String>{
    for (final k in OilChangeFilterKind.builtins) k.code: k.label,
  };
  for (final line in oilFilterLinesDataFromRow(row)) {
    final label =
        (line.label?.trim().isNotEmpty == true)
            ? line.label!.trim()
            : (labelByCode[line.code] ?? 'فلتر');
    final text = oilFilterLineLabel(
      kindLabel: label,
      name: line.name,
      priceFils: line.priceFils,
    );
    if (text != null) out.add(text);
  }
  return out;
}

/// ملخص للعرض في الجداول والرسائل (يُحفظ أيضاً في filterType للتوافق).
String oilFilterSummaryFromRow(Map<String, dynamic> row) {
  final lines = oilFilterLinesFromRow(row);
  if (lines.isNotEmpty) return lines.join(' · ');
  final legacy = (row['filterType'] ?? '').toString().trim();
  return legacy.isEmpty ? '—' : legacy;
}

extension OilChangeFilterKindRowKeys on OilChangeFilterKind {
  String get nameColumnKey => switch (code) {
        'engine' => 'engineFilterName',
        'air' => 'airFilterName',
        'gear' => 'gearFilterName',
        _ => 'engineFilterName',
      };

  String get priceColumnKey => switch (code) {
        'engine' => 'engineFilterPriceFils',
        'air' => 'airFilterPriceFils',
        'gear' => 'gearFilterPriceFils',
        _ => 'engineFilterPriceFils',
      };

  bool get hasLegacyColumns =>
      code == 'engine' || code == 'air' || code == 'gear';
}
