import '../data/oil_query_normalize.dart';

/// درجة مطابقة صف مقروء (فاتورة مورّد أو جملة جرد) بالمخزون (4.5).
enum AssistantMatchGrade {
  /// صنف واحد واضح: يدخل السند كما هو.
  matched,

  /// مرشحون قريبون: لا يُعتمد حتى يختار المستخدم بنفسه.
  likely,

  /// لا شيء قريب: لا يدخل السند، ويُفتح له نموذج إضافة منتج.
  none,
}

class AssistantMatch {
  const AssistantMatch(this.grade, {this.productId, this.candidates = const []});

  final AssistantMatchGrade grade;
  final int? productId;

  /// أفضل المرشحين (معرّف، اسم) مرتبين، للاختيار عند «محتمل».
  final List<(int, String)> candidates;
}

/// المطابقة على الجهاز بالاسم المطبَّع والماركة واللزوجة.
///
/// الكلمات تُقارن بلا ترتيب: قياس ب0 وجد أن قراءة الصور تقلب ترتيب الأسماء
/// التي تخلط العربي باللاتيني («زيت توتال 4 5W-30 لتر»).
abstract final class AssistantNameMatch {
  static const matchedAt = 0.75;
  static const likelyAt = 0.34;

  static Set<String> tokens(String raw) {
    final norm = OilQueryNormalize.normalize(raw);
    final out = <String>{};
    for (final w in norm.split(RegExp(r'[\s/،,()\-+]+'))) {
      // اللزوجة تبقى بشكلها الموحّد كلمة واحدة.
      final v = OilQueryNormalize.viscosityOf(w);
      final k = v ?? OilQueryNormalize.key(w);
      if (k.isEmpty || _noise.contains(k)) continue;
      out.add(v == null ? k.replaceFirst(RegExp('^ال'), '') : v.toLowerCase());
    }
    return out;
  }

  // وحدات وكلمات لا تميّز صنفاً عن آخر.
  static const _noise = {'لتر', 'لترات', 'ل', 'l', 'ltr', 'liter', 'علبه', 'قطعه', 'كارتون', 'حبه', 'عدد', 'x'};

  static double score(String a, String b) {
    final ta = tokens(a);
    final tb = tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final va = OilQueryNormalize.viscosityOf(a);
    final vb = OilQueryNormalize.viscosityOf(b);
    // لزوجتان مختلفتان صنفان مختلفان مهما تشابه الاسم.
    if (va != null && vb != null && va != vb) return 0;
    final inter = ta.intersection(tb).length;
    return inter / (ta.length > tb.length ? ta.length : tb.length);
  }

  /// [items]: صفوف المخزون بالحقول id، name، brand، viscosity.
  static AssistantMatch match(String read, List<Map<String, Object?>> items) {
    final scored = <(int, String, double)>[];
    for (final it in items) {
      final id = it['id'];
      if (id is! num) continue;
      final name = '${it['name'] ?? ''}';
      final full = [name, if (it['brand'] != null && !name.contains('${it['brand']}')) '${it['brand']}'].join(' ');
      final s = score(read, full) > score(read, name) ? score(read, full) : score(read, name);
      if (s >= likelyAt) scored.add((id.toInt(), name, s));
    }
    if (scored.isEmpty) return const AssistantMatch(AssistantMatchGrade.none);
    scored.sort((x, y) => y.$3.compareTo(x.$3));
    final best = scored.first;
    final runnerUp = scored.length > 1 ? scored[1].$3 : 0.0;
    final candidates = [for (final s in scored.take(5)) (s.$1, s.$2)];
    // «مطابق» يحتاج درجة عالية وفارقاً واضحاً عن الثاني، وإلا يختار المستخدم.
    if (best.$3 >= matchedAt && best.$3 - runnerUp >= 0.2) {
      return AssistantMatch(AssistantMatchGrade.matched, productId: best.$1, candidates: candidates);
    }
    return AssistantMatch(AssistantMatchGrade.likely, candidates: candidates);
  }
}
