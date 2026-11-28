/// المبلغ كتابةً بالعربية للفاتورة الرسمية:
/// «فقط ثلاثة وأربعون ألف دينار عراقي لا غير».
library;

abstract final class ArabicAmountWords {
  static const _ones = [
    '',
    'واحد',
    'اثنان',
    'ثلاثة',
    'أربعة',
    'خمسة',
    'ستة',
    'سبعة',
    'ثمانية',
    'تسعة',
  ];
  static const _teens = [
    'عشرة',
    'أحد عشر',
    'اثنا عشر',
    'ثلاثة عشر',
    'أربعة عشر',
    'خمسة عشر',
    'ستة عشر',
    'سبعة عشر',
    'ثمانية عشر',
    'تسعة عشر',
  ];
  static const _tens = [
    '',
    '',
    'عشرون',
    'ثلاثون',
    'أربعون',
    'خمسون',
    'ستون',
    'سبعون',
    'ثمانون',
    'تسعون',
  ];
  static const _hundreds = [
    '',
    'مائة',
    'مائتان',
    'ثلاثمائة',
    'أربعمائة',
    'خمسمائة',
    'ستمائة',
    'سبعمائة',
    'ثمانمائة',
    'تسعمائة',
  ];

  /// (مفرد، مثنى، جمع) لكل مرتبة: ألف، مليون، مليار.
  static const _scales = [
    ('ألف', 'ألفان', 'آلاف'),
    ('مليون', 'مليونان', 'ملايين'),
    ('مليار', 'ملياران', 'مليارات'),
  ];

  /// عدد من 1 إلى 999 كتابةً.
  static String _below1000(int n) {
    final parts = <String>[];
    final h = n ~/ 100, r = n % 100;
    if (h > 0) parts.add(_hundreds[h]);
    if (r >= 10 && r < 20) {
      parts.add(_teens[r - 10]);
    } else if (r > 0) {
      final t = r ~/ 10, o = r % 10;
      if (o > 0 && t > 0) {
        parts.add('${_ones[o]} و${_tens[t]}');
      } else if (t > 0) {
        parts.add(_tens[t]);
      } else {
        parts.add(_ones[o]);
      }
    }
    return parts.join(' و');
  }

  /// عدد صحيح موجب كتابةً («صفر» للصفر).
  static String number(int n) {
    if (n <= 0) return 'صفر';
    final groups = <String>[];
    var rest = n;
    final chunks = <int>[];
    while (rest > 0) {
      chunks.add(rest % 1000);
      rest ~/= 1000;
    }
    for (var i = chunks.length - 1; i >= 0; i--) {
      final g = chunks[i];
      if (g == 0) continue;
      if (i == 0) {
        groups.add(_below1000(g));
        continue;
      }
      final (one, two, many) = _scales[(i - 1).clamp(0, _scales.length - 1)];
      if (g == 1) {
        groups.add(one);
      } else if (g == 2) {
        groups.add(two);
      } else if (g >= 3 && g <= 10) {
        groups.add('${_below1000(g)} $many');
      } else {
        groups.add('${_below1000(g)} $one');
      }
    }
    return groups.join(' و');
  }

  /// المبلغ بالفلس (1000 فلس = دينار) كتابةً بصيغة الفاتورة.
  static String iqd(int fils) {
    final dinars = (fils.abs() / 1000).round();
    return 'فقط ${number(dinars)} دينار عراقي لا غير';
  }
}
