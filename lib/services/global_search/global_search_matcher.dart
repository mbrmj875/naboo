/// مطابقة احترافية — يفضّل بداية الكلمات ثم بداية العنوان ثم التضمين.
class GlobalSearchMatcher {
  GlobalSearchMatcher._();

  static String normalize(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 0 = لا مطابقة، أعلى = أفضل.
  static int score(String query, String title, {String? context}) {
    final q = normalize(query);
    if (q.isEmpty) return 0;

    final t = normalize(title);
    if (t.isEmpty) return 0;

    if (t == q) return 200;

    final words = t.split(' ');
    for (final w in words) {
      if (w.startsWith(q)) return 150;
    }

    if (t.startsWith(q)) return 120;

    for (final w in words) {
      if (w.contains(q)) return 80;
    }

    if (t.contains(' $q')) return 70;
    if (t.contains(q)) return 55;

    if (context != null) {
      final c = normalize(context);
      if (c.startsWith(q) || c.contains(q)) return 35;
    }

    return 0;
  }

  static int scoreFields(String query, List<String> fields) {
    var best = 0;
    for (final f in fields) {
      final s = score(query, f);
      if (s > best) best = s;
    }
    return best;
  }
}
