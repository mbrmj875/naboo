import 'dart:math';

/// نتيجة استخراج حقول شائعة من نص باركود GS1 (Code-128 / Data Matrix) بدون الاعتماد على FNC1 في النص.
class Gs1ParseResult {
  const Gs1ParseResult({
    this.gtin14,
    this.productionDate,
    this.expiryDate,
    this.netWeightKg,
  });

  final String? gtin14;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  /// الوزن الصافي بالكيلوغرام (من AI 3100–3109).
  final double? netWeightKg;
}

DateTime? parseGs1YyMmDd(String six) {
  if (six.length != 6) return null;
  final yy = int.tryParse(six.substring(0, 2)) ?? -1;
  final mm = int.tryParse(six.substring(2, 4)) ?? -1;
  final dd = int.tryParse(six.substring(4, 6)) ?? -1;
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  final year = yy >= 70 ? 1900 + yy : 2000 + yy;
  try {
    return DateTime(year, mm, dd);
  } catch (_) {
    return null;
  }
}

String _linearFromParentheses(String raw) {
  final buf = StringBuffer();
  final re = RegExp(r'\((\d{2,4})\)([^()]*)');
  for (final m in re.allMatches(raw.trim())) {
    buf.write(m.group(1));
    buf.write(m.group(2)?.trim() ?? '');
  }
  final s = buf.toString();
  return s.isNotEmpty ? s : raw.replaceAll(RegExp(r'[()\s]'), '');
}

bool _knownAiAhead(String s, int i) {
  if (i + 2 > s.length) return false;
  final sub = s.substring(i);
  if (sub.startsWith('01') && i + 16 <= s.length) return true;
  if (sub.startsWith('11') && i + 8 <= s.length) return true;
  if (sub.startsWith('17') && i + 8 <= s.length) return true;
  if (sub.startsWith('10')) return true;
  if (sub.startsWith('21')) return true;
  if (sub.length >= 4 &&
      sub.startsWith('310') &&
      RegExp(r'^[0-9]$').hasMatch(sub[3]) &&
      i + 10 <= s.length) {
    return true;
  }
  return false;
}

/// يحلل سلسلة خطية (أرقام وحروف) بعد إزالة الأقواس إن وُجدت.
Gs1ParseResult parseGs1Linear(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[\u001D]'), '');
  if (s.isEmpty) return const Gs1ParseResult();

  String? gtin;
  DateTime? prod;
  DateTime? exp;
  double? wKg;

  var i = 0;
  while (i < s.length) {
    if (i + 4 <= s.length) {
      final four = s.substring(i, i + 4);
      if (four.startsWith('310') &&
          RegExp(r'^[0-9]$').hasMatch(four[3]) &&
          i + 10 <= s.length) {
        final dec = int.parse(four[3]);
        final v = int.parse(s.substring(i + 4, i + 10));
        wKg = v / pow(10, dec);
        i += 10;
        continue;
      }
    }

    if (i + 2 > s.length) break;
    final two = s.substring(i, i + 2);

    if (two == '01' && i + 16 <= s.length) {
      gtin = s.substring(i + 2, i + 16);
      i += 16;
      continue;
    }
    if (two == '11' && i + 8 <= s.length) {
      prod = parseGs1YyMmDd(s.substring(i + 2, i + 8));
      i += 8;
      continue;
    }
    if (two == '17' && i + 8 <= s.length) {
      exp = parseGs1YyMmDd(s.substring(i + 2, i + 8));
      i += 8;
      continue;
    }
    if (two == '10') {
      i += 2;
      final start = i;
      while (i < s.length && !_knownAiAhead(s, i)) {
        i++;
      }
      if (i == start) i++;
      continue;
    }
    if (two == '21') {
      i += 2;
      final start = i;
      while (i < s.length && !_knownAiAhead(s, i)) {
        i++;
      }
      if (i == start) i++;
      continue;
    }

    i++;
  }

  return Gs1ParseResult(
    gtin14: gtin,
    productionDate: prod,
    expiryDate: exp,
    netWeightKg: wKg,
  );
}

/// يستخرج GTIN والتواريخ والوزن من نص الماسح (يدعم صيغة بأقواس أو سلسلة مدمجة).
Gs1ParseResult parseGs1Barcode(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return const Gs1ParseResult();
  final linear =
      t.contains('(') ? _linearFromParentheses(t) : t.replaceAll(RegExp(r'\s'), '');
  return parseGs1Linear(linear);
}
