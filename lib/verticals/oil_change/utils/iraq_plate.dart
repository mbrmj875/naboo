/// لوحة سيارة عراقية منظمة (المرحلة 6 — الشريحة 2): رقم، وحرف اختياري،
/// ومحافظة اختيارية. تُحفظ نصاً واحداً في `deviceSerial` بالشكل
/// «12345 B البصرة»، فكل ما يقرأ اللوحة نصاً يبقى يعمل.
library;

/// المحافظات الـ18 بأسمائها.
const List<String> kIraqProvinces = [
  'بغداد',
  'البصرة',
  'نينوى',
  'أربيل',
  'السليمانية',
  'دهوك',
  'كركوك',
  'الأنبار',
  'ديالى',
  'صلاح الدين',
  'بابل',
  'كربلاء',
  'النجف',
  'واسط',
  'القادسية',
  'ميسان',
  'ذي قار',
  'المثنى',
];

/// حروف اللوحات الجديدة.
const List<String> kIraqPlateLetters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

String _foldArabic(String s) => s
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// اسم المحافظة القياسي لكتابة قريبة («اربيل» → «أربيل»، «بصرة» → «البصرة»).
String? canonicalProvince(String raw) {
  final f = _foldArabic(raw);
  if (f.isEmpty) return null;
  for (final p in kIraqProvinces) {
    final fp = _foldArabic(p);
    if (fp == f) return p;
    if (fp.startsWith('ال') && fp.substring(2) == f) return p;
  }
  return null;
}

class IraqPlate {
  const IraqPlate({required this.number, this.letter, this.province});

  /// الرقم كما كُتب. للوحة قديمة غير مفهومة («12345-14») يبقى النص كله هنا.
  final String number;
  final String? letter;
  final String? province;

  static const empty = IraqPlate(number: '');

  bool get isEmpty => number.trim().isEmpty;

  /// أرقام فقط؟ (لا رمز قديم بعد شرطة ولا نص).
  bool get isPlainNumber => RegExp(r'^[0-9٠-٩۰-۹]+$').hasMatch(number.trim());

  String format() {
    final n = number.trim();
    if (n.isEmpty) return '';
    final b = StringBuffer(n);
    if ((letter ?? '').isNotEmpty) b.write(' $letter');
    if ((province ?? '').isNotEmpty) b.write(' $province');
    return b.toString();
  }

  IraqPlate copyWith({
    String? number,
    String? letter,
    String? province,
    bool clearLetter = false,
    bool clearProvince = false,
  }) => IraqPlate(
    number: number ?? this.number,
    letter: clearLetter ? null : (letter ?? this.letter),
    province: clearProvince ? null : (province ?? this.province),
  );

  /// يقرأ أي كتابة: «12345 B البصرة»، «12345-بغداد»، «12345»، «12345-14».
  static IraqPlate parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return empty;
    String? province;
    // المحافظة في الآخر (كلمة أو كلمتان)، بعد مسافة أو شرطة.
    final words = s.split(RegExp(r'[\s\-ـ]+'));
    for (final take in [2, 1]) {
      if (words.length <= take) continue;
      final tail = words.sublist(words.length - take).join(' ');
      final p = canonicalProvince(tail);
      if (p != null) {
        province = p;
        words.removeRange(words.length - take, words.length);
        break;
      }
    }
    String? letter;
    if (words.length >= 2 && RegExp(r'^[A-Za-z]$').hasMatch(words.last)) {
      letter = words.removeLast().toUpperCase();
    }
    if (province == null && letter == null) {
      // لا شيء مفهوم بعد الرقم: يبقى النص كما كُتب.
      return IraqPlate(number: s);
    }
    s = words.join(' ');
    return IraqPlate(number: s, letter: letter, province: province);
  }
}
