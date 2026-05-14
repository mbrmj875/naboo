/// مقاسات ملابس شائعة بمعايير متعددة في صف واحد؛ النص المحفوظ ثابت عبر [storageLabel].
class ClothingIntlSizeRow {
  const ClothingIntlSizeRow({
    required this.ar,
    required this.us,
    required this.en,
    required this.uk,
  });

  final int ar;
  final int us;
  final int en;
  /// حروف مثل S، M، 2XL
  final String uk;

  /// نص موحّد يُحفظ في حقل المقاس ويُستخدم للمقارنة وتجنب التكرار.
  String get storageLabel {
    final ukDisp = uk.trim().toUpperCase();
    return 'AR $ar · US $us · EN $en · UK $ukDisp';
  }

  /// صفوف الجدول المعتمدة (يمكن توسيعها لاحقاً).
  static const List<ClothingIntlSizeRow> standard = <ClothingIntlSizeRow>[
    ClothingIntlSizeRow(ar: 1, us: 36, en: 6, uk: 'S'),
    ClothingIntlSizeRow(ar: 2, us: 38, en: 8, uk: 'M'),
    ClothingIntlSizeRow(ar: 3, us: 40, en: 10, uk: 'L'),
    ClothingIntlSizeRow(ar: 4, us: 42, en: 12, uk: 'XL'),
    ClothingIntlSizeRow(ar: 5, us: 44, en: 14, uk: '2XL'),
    ClothingIntlSizeRow(ar: 6, us: 46, en: 16, uk: '3XL'),
  ];
}
