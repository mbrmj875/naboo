/// يفصل الاسم عن الرمز: «ديفلون_0W8» و«ديفلون – 0W8» يصبحان نفس الكلمات.
List<String> saleGridSearchTokens(String query) {
  return query
      .trim()
      .split(RegExp(r'[\s_\-–—/]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

/// نمط LIKE آمن: `%` و `_` حرفان عاديان وليسا رموز بحث.
String saleGridLikeContains(String token) {
  final escaped = token
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}
