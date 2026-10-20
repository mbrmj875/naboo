/// مطابقة نصوص عربية للبحث الفوري (أسماء العملاء، الفنيين، المنتجات).
///
/// كلّها دوال نقية بلا حالة ولا قاعدة بيانات، لتُستدعى على كل ضغطة مفتاح
/// داخل الإطار الواحد دون أي انتظار غير متزامن.
library;

const _diacritics = {
  0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0653,
  0x0654, 0x0655, 0x0656, 0x0657, 0x0658, 0x0670, 0x0640, // التطويل ـ
};

/// أشكال الحروف التي يكتبها الناس بالتبادل، تُوحَّد إلى شكل واحد.
const _letterFolds = <int, int>{
  0x0623: 0x0627, // أ → ا
  0x0625: 0x0627, // إ → ا
  0x0622: 0x0627, // آ → ا
  0x0671: 0x0627, // ٱ → ا
  0x0629: 0x0647, // ة → ه
  0x0649: 0x064A, // ى → ي
  0x0626: 0x064A, // ئ → ي
  0x0624: 0x0648, // ؤ → و
  0x06A9: 0x0643, // ک → ك
  0x06CC: 0x064A, // ی → ي
  0x06AF: 0x0643, // گ → ك
  0x067E: 0x0628, // پ → ب
  0x0686: 0x062C, // چ → ج
  0x0698: 0x0632, // ژ → ز
};

/// تحويل الأرقام العربية-الهندية والفارسية إلى 0-9.
int? _foldDigit(int code) {
  if (code >= 0x0660 && code <= 0x0669) return code - 0x0660 + 0x30;
  if (code >= 0x06F0 && code <= 0x06F9) return code - 0x06F0 + 0x30;
  return null;
}

/// نص موحَّد للبحث: بلا تشكيل ولا تطويل، بأحرف وأرقام موحّدة، ومسافة واحدة.
String normalizeArabicSearchText(String raw) {
  if (raw.isEmpty) return '';
  final out = StringBuffer();
  var pendingSpace = false;
  var wroteAny = false;

  for (final code in raw.toLowerCase().runes) {
    if (_diacritics.contains(code)) continue;

    final digit = _foldDigit(code);
    final folded = digit ?? _letterFolds[code] ?? code;

    // كل ما ليس حرفاً ولا رقماً يُعامل فاصلاً (شرطة، نقطة، قوس، تحكّم اتجاه).
    if (!_isWordCode(folded)) {
      if (wroteAny) pendingSpace = true;
      continue;
    }
    if (pendingSpace) {
      out.writeCharCode(0x20);
      pendingSpace = false;
    }
    out.writeCharCode(folded);
    wroteAny = true;
  }
  return out.toString();
}

bool _isWordCode(int code) {
  if (code >= 0x30 && code <= 0x39) return true; // 0-9
  if (code >= 0x61 && code <= 0x7A) return true; // a-z
  if (code >= 0x0621 && code <= 0x064A) return true; // العربية الأساسية
  if (code >= 0x0660 && code <= 0x066F) return true;
  if (code >= 0x0671 && code <= 0x06FF) return true;
  return false;
}

/// أرقام فقط — لمطابقة الهواتف مهما كان شكل كتابتها (+964، مسافات، شرطات).
String digitsOnly(String raw) {
  final out = StringBuffer();
  for (final code in raw.runes) {
    final digit = _foldDigit(code);
    if (digit != null) {
      out.writeCharCode(digit);
    } else if (code >= 0x30 && code <= 0x39) {
      out.writeCharCode(code);
    }
  }
  return out.toString();
}

/// أرقام الهاتف العراقية تُكتب بصيغ متعددة لنفس الرقم؛ يُقارَن آخر 10 خانات.
String phoneMatchKey(String raw) {
  var d = digitsOnly(raw);
  if (d.startsWith('00964')) {
    d = d.substring(5);
  } else if (d.startsWith('964')) {
    d = d.substring(3);
  }
  if (d.startsWith('0')) d = d.substring(1);
  return d;
}

/// درجة تطابق الاستعلام مع النص: كلما زادت كان الترتيب أعلى، و0 يعني لا تطابق.
///
/// المنطق: كل كلمة في الاستعلام يجب أن توجد في النص (ترتيب الكلمات لا يهم،
/// فـ«محمد باقر» تجد «باقر محمد»)، ثم تُرفَع درجة البدايات على الأواسط.
int scoreNameMatch({
  required String normalizedName,
  required String normalizedQuery,
}) {
  return scoreNameMatchTokens(
    normalizedName: normalizedName,
    nameTokens: splitSearchTokens(normalizedName),
    normalizedQuery: normalizedQuery,
    queryTokens: splitSearchTokens(normalizedQuery),
  );
}

List<String> splitSearchTokens(String normalized) {
  if (normalized.isEmpty) return const [];
  return normalized.split(' ').where((t) => t.isNotEmpty).toList(growable: false);
}

/// نسخة الأداء: الكلمات محسوبة مسبقاً، فلا تخصيص ذاكرة داخل حلقة البحث.
int scoreNameMatchTokens({
  required String normalizedName,
  required List<String> nameTokens,
  required String normalizedQuery,
  required List<String> queryTokens,
}) {
  if (normalizedQuery.isEmpty) return 0;
  if (normalizedName.isEmpty) return 0;
  if (queryTokens.isEmpty) return 0;

  if (normalizedName == normalizedQuery) return 1000;

  var score = 0;
  if (normalizedName.startsWith(normalizedQuery)) {
    score += 400;
  } else if (normalizedName.contains(normalizedQuery)) {
    score += 150;
  }

  for (final token in queryTokens) {
    var best = 0;
    for (final part in nameTokens) {
      if (part == token) {
        best = 120;
        break;
      }
      if (part.startsWith(token)) {
        best = best < 90 ? 90 : best;
      } else if (part.contains(token)) {
        best = best < 40 ? 40 : best;
      }
    }
    if (best == 0) {
      // أثناء الكتابة: الحرف/المقطع الأخير القصير غير المكتمل لا يصفّر النتائج
      // (مثال: «محمد ف» يبقى يُظهر «محمد فؤاد» و«محمد علي» إلى أن تكتمل الكلمة).
      final isTrailingStub = identical(token, queryTokens.last) &&
          token.length <= 2 &&
          score > 0;
      if (isTrailingStub) continue;
      return 0; // كلمة من الاستعلام غير موجودة إطلاقاً.
    }
    score += best;
  }

  // الاسم الأقصر أقرب لما يقصده المستخدم عند تساوي بقية المعايير.
  final lengthPenalty = normalizedName.length ~/ 8;
  return score - lengthPenalty < 1 ? 1 : score - lengthPenalty;
}

/// درجة تطابق رقم الهاتف: البداية أفضل من الاحتواء.
int scorePhoneMatch({required String phoneKey, required String queryDigits}) {
  if (queryDigits.length < 2 || phoneKey.isEmpty) return 0;
  if (phoneKey == queryDigits) return 900;
  if (phoneKey.startsWith(queryDigits)) return 500;
  if (phoneKey.contains(queryDigits)) return 200;
  return 0;
}
