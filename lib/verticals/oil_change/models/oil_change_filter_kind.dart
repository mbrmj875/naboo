/// فئة فلتر في بطاقة غيار الزيت.
enum OilChangeFilterKind {
  engine('engine', 'فلتر المحرك'),
  air('air', 'فلتر الهواء'),
  gear('gear', 'فلتر الكير'),
  cooling('cooling', 'فلتر التبريد');

  const OilChangeFilterKind(this.code, this.label);

  final String code;
  final String label;

  static OilChangeFilterKind? fromCode(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    if (k.isEmpty) return null;
    for (final v in OilChangeFilterKind.values) {
      if (v.code == k) return v;
    }
    return null;
  }

  static const all = OilChangeFilterKind.values;
}
