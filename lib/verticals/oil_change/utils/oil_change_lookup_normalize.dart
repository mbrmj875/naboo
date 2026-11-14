/// تطبيع مفاتيح البحث — لوحة السيارة واسم العميل.
abstract final class OilChangeLookupNormalize {
  OilChangeLookupNormalize._();

  static String normalizePlateKey(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final ai = arabicIndic.indexOf(ch);
      if (ai >= 0) {
        buf.write(ai);
        continue;
      }
      final ea = easternArabicIndic.indexOf(ch);
      if (ea >= 0) {
        buf.write(ea);
        continue;
      }
      buf.write(ch);
    }
    s = buf.toString();
    s = s.replaceAll(RegExp(r'[\s\-_ـ،,./\\]'), '');
    return s.toLowerCase();
  }

  static String normalizeNameKey(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  /// أرقام غربية فقط — يحوّل العربية/الفارسية ويزيل غير الأرقام.
  static String toWesternDigits(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final ai = arabicIndic.indexOf(ch);
      if (ai >= 0) {
        buf.write(ai);
        continue;
      }
      final ea = easternArabicIndic.indexOf(ch);
      if (ea >= 0) {
        buf.write(ea);
        continue;
      }
      if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }
}
