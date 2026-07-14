import '../models/oil_change_filter_kind.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';

String _priceLabel(int fils) {
  if (fils <= 0) return '';
  return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
}

/// سطر عرض واحد: «فلتر المحرك: تويوتا أصلي — 15,000 د.ع».
String? oilFilterLineLabel({
  required String kindLabel,
  required String name,
  int priceFils = 0,
}) {
  final n = name.trim();
  if (n.isEmpty) return null;
  final price = _priceLabel(priceFils);
  if (price.isEmpty) return '$kindLabel: $n';
  return '$kindLabel: $n — $price';
}

List<String> oilFilterLinesFromRow(Map<String, dynamic> row) {
  final out = <String>[];
  for (final kind in OilChangeFilterKind.all) {
    final name = (row[kind.nameColumnKey] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final fils = (row[kind.priceColumnKey] as num?)?.toInt() ?? 0;
    final line = oilFilterLineLabel(
      kindLabel: kind.label,
      name: name,
      priceFils: fils,
    );
    if (line != null) out.add(line);
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
  String get nameColumnKey => switch (this) {
        OilChangeFilterKind.engine => 'engineFilterName',
        OilChangeFilterKind.air => 'airFilterName',
        OilChangeFilterKind.gear => 'gearFilterName',
      };

  String get priceColumnKey => switch (this) {
        OilChangeFilterKind.engine => 'engineFilterPriceFils',
        OilChangeFilterKind.air => 'airFilterPriceFils',
        OilChangeFilterKind.gear => 'gearFilterPriceFils',
      };
}
