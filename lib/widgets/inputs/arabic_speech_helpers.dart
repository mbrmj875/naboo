// أدوات مساعدة للتعرّف على الصوت العربي/العراقي (خالية من Flutter UI).

/// يوحّد معرّف اللغة للمقارنة: `ar-IQ` و `ar_IQ` و `AR_iq` → `ar_iq`.
String normalizeSpeechLocaleId(String raw) {
  return raw.trim().toLowerCase().replaceAll('-', '_');
}

/// ترتيب تفضيل اللهجات للورشة العراقية: عراقي ثم خليجي قريب ثم فصحى/شائع.
const List<String> kPreferredArabicSpeechLocales = [
  'ar_iq',
  'ar_kw',
  'ar_bh',
  'ar_ae',
  'ar_qa',
  'ar_sa',
  'ar_jo',
  'ar_sy',
  'ar_lb',
  'ar_eg',
  'ar',
];

/// يختار أفضل locale عربي متاح للجهاز (يفضّل العراقي ثم الخليج).
String? pickBestArabicSpeechLocale(Iterable<String> availableLocaleIds) {
  final byNorm = <String, String>{};
  for (final id in availableLocaleIds) {
    final n = normalizeSpeechLocaleId(id);
    if (n.isEmpty) continue;
    byNorm.putIfAbsent(n, () => id);
  }
  if (byNorm.isEmpty) return null;

  for (final preferred in kPreferredArabicSpeechLocales) {
    final exact = byNorm[preferred];
    if (exact != null) return exact;
  }

  // أي لهجة عربية أخرى (بادئة ar_).
  for (final e in byNorm.entries) {
    if (e.key == 'ar' || e.key.startsWith('ar_')) return e.value;
  }
  return null;
}

/// دمج مقطع كلام جديد دون مسح ما سبق (يدعم التوقف القصير ثم المتابعة).
String mergeSpeechChunk(String existing, String incoming) {
  if (incoming.isEmpty) return existing;
  if (existing.isEmpty) return incoming;
  if (existing == incoming) return existing;
  if (incoming.startsWith(existing)) return incoming;
  if (existing.endsWith(incoming)) return existing;
  return '$existing $incoming';
}

bool isSpeechSameOrRefinement(String earlier, String later) {
  if (earlier.isEmpty || later.isEmpty) return true;
  final e = earlier.trim();
  final l = later.trim();
  if (e == l) return true;
  if (l.startsWith(e) || e.startsWith(l)) return true;
  return false;
}

/// تنظيف خفيف لنص الإملاء: أرقام غربية + مسافات + تصحيحات عراقية شائعة من ASR.
String polishIraqiSpeechText(String raw) {
  if (raw.isEmpty) return raw;
  var s = _toWesternDigits(raw);
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = _applyLightIraqiAsrFixes(s);
  return s;
}

String _toWesternDigits(String raw) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    final a = arabicIndic.indexOf(ch);
    if (a >= 0) {
      buf.write(a);
      continue;
    }
    final p = persianIndic.indexOf(ch);
    if (p >= 0) {
      buf.write(p);
      continue;
    }
    buf.write(ch);
  }
  return buf.toString();
}

/// تصحيحات قصيرة لأخطاء شائعة عند إملاء اللهجة العراقية (لا تغيّر الأسماء الطويلة).
String _applyLightIraqiAsrFixes(String s) {
  var out = s;
  // أخطاء شائعة من محرّك Google مع لهجة بغداد/الجنوب في سياق الورشة.
  const pairs = <List<String>>[
    ['شلونج', 'شلونك'],
    ['شلونچ', 'شلونك'],
    ['چاك', 'جاك'],
    ['چان', 'كان'],
    ['چبير', 'كبير'],
    ['چبيره', 'كبيرة'],
    ['زيت المكينه', 'زيت المكينة'],
    ['زيت الماكينة', 'زيت المكينة'],
  ];
  for (final p in pairs) {
    out = out.replaceAll(p[0], p[1]);
  }
  return out;
}
