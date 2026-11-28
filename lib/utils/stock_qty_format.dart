/// عرض الكمية كما هي: الكسور (37.5 لتر) والسالب (−2) دون تقريب (ع-4).
abstract final class StockQtyFormat {
  static String format(num? v) {
    final n = (v ?? 0).toDouble();
    if (!n.isFinite) return '0';
    final r = double.parse(n.toStringAsFixed(3));
    var t = r == r.truncateToDouble()
        ? r.toInt().abs().toString()
        : r.abs().toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
    final dot = t.indexOf('.');
    final intPart = dot < 0 ? t : t.substring(0, dot);
    final frac = dot < 0 ? '' : t.substring(dot);
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    t = '$buf$frac';
    return r < 0 ? '-$t' : t;
  }

  /// يقرأ كمية مكتوبة بكسور، ويقبل الأرقام العربية والفاصلة.
  static double? parse(String raw) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in raw.trim().split('')) {
      final i = ar.indexOf(ch);
      if (i >= 0) {
        b.write(i);
      } else if (ch == '٫') {
        b.write('.');
      } else if (ch != ',' && ch != '،' && ch != ' ') {
        b.write(ch);
      }
    }
    return double.tryParse(b.toString());
  }
}
