import '../../verticals/oil_change/utils/oil_change_lookup_normalize.dart';

/// تطبيع ما يكتبه المستخدم عن الزيت قبل البحث في المخزون (م1-7).
///
/// «5w30» و«٥ دبليو ٣٠» و«دهن 5-30» و«5W/30» كلها تصبح `5W-30`. الأرقام
/// العربية تُحوَّل أولاً بنفس دالة لوحات السيارات.
abstract final class OilQueryNormalize {
  static const _winter = {'0', '5', '10', '15', '20', '25'};
  static const _hot = {'8', '12', '16', '20', '30', '40', '50', '60'};

  // «دهن» و«زيت» كلمات تُقال قبل اللزوجة ولا تفيد البحث.
  static final _filler = RegExp(r'(^|\s)(دهن|الدهن|زيت|الزيت|لزوجة|لزوجه|نوع)(?=\s|$)');

  static final _viscosity = RegExp(r'(?<!\d)(\d{1,2})\s*(?:w|W|دبليو|دبلو|دبل|ڤي|و)?\s*[-/\\_.]?\s*(\d{1,2})(?!\d)');

  /// اللزوجة بشكلها الموحَّد أو null إن لم تُذكر.
  static String? viscosityOf(String raw) {
    final s = _digits(raw);
    for (final m in _viscosity.allMatches(s)) {
      final a = int.parse(m[1]!).toString();
      final b = int.parse(m[2]!).toString();
      if (_winter.contains(a) && _hot.contains(b) && int.parse(b) > int.parse(a)) return '${a}W-$b';
    }
    return null;
  }

  /// النص بعد التوحيد: اللزوجة بشكلها، والكلمات الزائدة محذوفة.
  static String normalize(String raw) {
    var s = _digits(raw).trim();
    final v = viscosityOf(s);
    if (v != null) {
      final m = _viscosity.allMatches(s).firstWhere((m) => viscosityOf(m[0]!) == v);
      s = s.replaceRange(m.start, m.end, v);
    }
    s = s.replaceAll(_filler, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty && v != null ? v : s;
  }

  /// مفتاح مقارنة: حروف وأرقام فقط، بلا همزات، صغيرة.
  static String key(String raw) => _digits(raw)
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[^a-z0-9ء-ي]'), '');

  static String _digits(String raw) {
    final buf = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final d = OilChangeLookupNormalize.toWesternDigits(ch);
      buf.write(d.isNotEmpty ? d : ch);
    }
    return buf.toString();
  }
}
