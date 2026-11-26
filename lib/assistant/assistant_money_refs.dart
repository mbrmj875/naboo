import '../utils/iraqi_currency_format.dart';

/// المبالغ بالعلامات المرجعية (ق29، م1-12ج).
///
/// النموذج لا يرى المبلغ ولا يكتبه: الحارس يحوّل كل حقل `*_fils` في نتيجة
/// الأداة إلى علامة مثل `⟦m3⟧`، والنموذج ينسخ العلامة، والصفحة تطبعها بدالة
/// التنسيق نفسها التي تستعملها الشاشات. بهذا لا يخالف رقم في الجواب شاشته.
///
/// نسخة واحدة لكل محادثة، فتبقى العلامات صالحة عبر الخطوات.
class AssistantMoneyRefs {
  final Map<String, int> _fils = {};
  int _next = 1;

  static final RegExp tokenPattern = RegExp(r'⟦m(\d{1,4})⟧');
  static const filsSuffix = '_fils';

  int get length => _fils.length;

  /// يسجّل مبلغاً بالفلس ويعيد علامته.
  String ref(int fils) {
    final token = '⟦m${_next++}⟧';
    _fils[token] = fils;
    return token;
  }

  int? filsOf(String token) => _fils[token];

  /// كل العلامات المعروفة، للحفظ مع المحادثة.
  Map<String, int> snapshot() => Map.unmodifiable(_fils);

  /// يعيد علامات محفوظة بعد إعادة فتح محادثة، فتبقى صالحة للخطوات الجديدة.
  void restore(Map<String, int> saved) {
    saved.forEach((token, fils) {
      _fils[token] = fils;
      final m = tokenPattern.firstMatch(token);
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n >= _next) _next = n + 1;
    });
  }

  void clear() {
    _fils.clear();
    _next = 1;
  }

  /// يحوّل كل حقل `x_fils` رقمي إلى `x: ⟦mN⟧` داخل الخريطة وما فيها من قوائم.
  Object? wrap(Object? value) {
    if (value is Map) {
      final out = <String, Object?>{};
      value.forEach((k, v) {
        final key = k.toString();
        if (key.endsWith(filsSuffix) && v is num) {
          out[key.substring(0, key.length - filsSuffix.length)] = ref(v.round());
        } else {
          out[key] = wrap(v);
        }
      });
      return out;
    }
    if (value is List) return value.map(wrap).toList();
    return value;
  }

  /// يستبدل العلامات في نص الجواب بالمبلغ المنسّق. العلامة المجهولة تصبح «—».
  String render(String text) {
    return text.replaceAllMapped(tokenPattern, (m) {
      final fils = _fils[m.group(0)];
      if (fils == null) return '—';
      return IraqiCurrencyFormat.formatIqd(fils / 1000.0);
    });
  }

  /// نص يحوي مبلغاً بالدينار كتبه النموذج بنفسه (رقم مع دينار/د.ع/ألف).
  /// يُستعمل للتسجيل والمراقبة، لا للحذف: قد يكون المستخدم قد كتب المبلغ.
  static bool hasRawAmount(String text) {
    final t = text.replaceAllMapped(tokenPattern, (_) => '');
    return RegExp(r'\d[\d,٬.]*\s*(?:الف|ألف)?\s*(?:دينار|د\.?\s?ع)').hasMatch(t);
  }
}
