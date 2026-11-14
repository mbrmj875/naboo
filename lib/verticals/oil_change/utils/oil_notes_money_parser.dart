/// محلّل محلي لاستخراج مبالغ الدينار العراقي من ملاحظات بطاقة غيار الزيت (v2).
///
/// تصنيف: unit / lineTotal / unknown + افتراضات اختيار ذكية (لا جمع مخفي).
/// نافذة سياق ±48 حرفاً لتناسب النص الصوتي الطويل.
library;

/// نوع الرقم المستخرج من السياق.
enum OilNotesMoneyHitType {
  /// سعر وحدة (سعر الفلتر، ثمن…).
  unit,

  /// مجموع بند / يصبح / الإجمالي.
  lineTotal,

  /// رقم مقبول بدون تصنيف واضح.
  unknown,
}

/// رقم مرشّح واحد مع تصنيفه وسياق قصير للواجهة.
class OilNotesMoneyHit {
  const OilNotesMoneyHit({
    required this.dinars,
    required this.raw,
    required this.start,
    required this.end,
    required this.type,
    required this.contextLabel,
    required this.defaultSelected,
  });

  /// المبلغ بالدينار (عدد صحيح، بدون كسور).
  final int dinars;

  /// النص الخام كما ظهر في الملاحظات.
  final String raw;

  final int start;
  final int end;

  final OilNotesMoneyHitType type;

  /// مقتطف قصير يُعرض بجانب الرقم (كلمات قريبة).
  final String contextLabel;

  /// هل يُقترح اختياره افتراضياً؟
  final bool defaultSelected;

  String get typeLabelAr => _typeLabelAr(type);
}

String _typeLabelAr(OilNotesMoneyHitType type) {
  switch (type) {
    case OilNotesMoneyHitType.unit:
      return 'سعر وحدة';
    case OilNotesMoneyHitType.lineTotal:
      return 'مجموع بند';
    case OilNotesMoneyHitType.unknown:
      return 'مبلغ';
  }
}

/// نتيجة تحليل ملاحظات الزيوت.
class OilNotesMoneyParseResult {
  const OilNotesMoneyParseResult({
    required this.hits,
    required this.totalDinars,
    required this.totalFils,
    this.source = 'local',
    this.summary,
  });

  static const empty = OilNotesMoneyParseResult(
    hits: [],
    totalDinars: 0,
    totalFils: 0,
  );

  final List<OilNotesMoneyHit> hits;

  /// مجموع الافتراضات الذكية بالدينار.
  final int totalDinars;

  /// `totalDinars × 1000` — مطابق لقانون الفلس في المشروع.
  final int totalFils;

  /// `local` | `ai`
  final String source;

  /// ملخص قصير من التحليل الذكي (اختياري).
  final String? summary;

  bool get isEmpty => hits.isEmpty;
  bool get isNotEmpty => hits.isNotEmpty;
  bool get isFromAi => source == 'ai';

  List<bool> get defaultSelection =>
      hits.map((h) => h.defaultSelected).toList(growable: false);

  /// مجموع فلس حسب اختيار المستخدم (طول [selected] = طول [hits]).
  int totalFilsForSelection(List<bool> selected) {
    if (selected.length != hits.length) return totalFils;
    var dinars = 0;
    for (var i = 0; i < hits.length; i++) {
      if (selected[i]) dinars += hits[i].dinars;
    }
    return dinars * 1000;
  }

  int totalDinarsForSelection(List<bool> selected) {
    return totalFilsForSelection(selected) ~/ 1000;
  }

  /// يبني نتيجة من رد Edge Function (DeepSeek) بعد التحقق.
  static OilNotesMoneyParseResult? fromAiPayload(Map<String, dynamic> map) {
    final rawItems = map['items'];
    if (rawItems is! List || rawItems.isEmpty) return null;

    final hits = <OilNotesMoneyHit>[];
    for (final raw in rawItems.take(12)) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final dinars = _aiDinars(m);
      if (dinars < 250 || dinars > 50000000) continue;
      final type = _aiType(m['type']?.toString());
      final label = (m['label'] ?? m['context'] ?? '')
          .toString()
          .trim();
      final selected = m['selected'] == true ||
          m['selected'] == 1 ||
          (m['selected'] == null && type != OilNotesMoneyHitType.unit);
      hits.add(
        OilNotesMoneyHit(
          dinars: dinars,
          raw: dinars.toString(),
          start: hits.length,
          end: hits.length + 1,
          type: type,
          contextLabel: label.isEmpty ? _typeLabelAr(type) : label,
          defaultSelected: selected,
        ),
      );
    }
    if (hits.isEmpty) return null;

    // إن وُجد lineTotal في القائمة، لا نبقي unit مختارة إن نسي النموذج.
    final hasLine = hits.any((h) => h.type == OilNotesMoneyHitType.lineTotal);
    final normalized = hasLine
        ? [
            for (final h in hits)
              OilNotesMoneyHit(
                dinars: h.dinars,
                raw: h.raw,
                start: h.start,
                end: h.end,
                type: h.type,
                contextLabel: h.contextLabel,
                defaultSelected: h.type == OilNotesMoneyHitType.unit
                    ? false
                    : h.defaultSelected,
              ),
          ]
        : hits;

    final totalDinars = normalized.fold<int>(
      0,
      (a, h) => a + (h.defaultSelected ? h.dinars : 0),
    );
    final summary = (map['summary'] ?? '').toString().trim();
    return OilNotesMoneyParseResult(
      hits: List.unmodifiable(normalized),
      totalDinars: totalDinars,
      totalFils: totalDinars * 1000,
      source: 'ai',
      summary: summary.isEmpty ? null : summary,
    );
  }

  static int _aiDinars(Map<String, dynamic> m) {
    final d = m['dinars'] ?? m['amount'] ?? m['iqd'];
    if (d is int) return d;
    if (d is num) return d.round();
    final s = d?.toString().replaceAll(RegExp(r'[^\d]'), '') ?? '';
    return int.tryParse(s) ?? 0;
  }

  static OilNotesMoneyHitType _aiType(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'unit':
      case 'سعر':
      case 'سعر_وحدة':
        return OilNotesMoneyHitType.unit;
      case 'linetotal':
      case 'line_total':
      case 'total':
      case 'مجموع':
      case 'مجموع_بند':
        return OilNotesMoneyHitType.lineTotal;
      default:
        return OilNotesMoneyHitType.unknown;
    }
  }
}

/// خريطة الأرقام العربية-الهندية → غربية.
const Map<String, String> _kArabicIndicDigits = {
  '٠': '0',
  '١': '1',
  '٢': '2',
  '٣': '3',
  '٤': '4',
  '٥': '5',
  '٦': '6',
  '٧': '7',
  '٨': '8',
  '٩': '9',
  '۰': '0',
  '۱': '1',
  '۲': '2',
  '۳': '3',
  '۴': '4',
  '۵': '5',
  '۶': '6',
  '۷': '7',
  '۸': '8',
  '۹': '9',
};

/// كلمات مجموع بند / إجمالي.
const List<String> _kLineTotalKeywords = [
  'المجموع',
  'مجموع',
  'الإجمالي',
  'اجمالي',
  'إجمالي',
  'يصبح',
  'يصير',
  'المحصلة',
  'محصلة',
  'الكلفة الإجمالية',
  'كلفة اجمالية',
  'الكل',
];

/// كلمات سعر وحدة.
const List<String> _kUnitKeywords = [
  'سعره',
  'سعرها',
  'بسعر',
  'سعر الفلتر',
  'سعر الزيت',
  'سعر العلبة',
  'سعر العلبه',
  'سعر الواحد',
  'ثمن',
  'سعر',
];

/// كلمات قبول عامة (ليست تصنيفاً دقيقاً → unknown).
const List<String> _kAcceptKeywords = [
  'بـ',
  'بـِ',
  'مبلغ',
  'بمبلغ',
  'دينار',
  'دنانير',
  'د.ع',
  'دع',
  'ألف',
  'الف',
  'علينا',
  'كلفة',
  'تكلفة',
  'التبديل',
];

/// كلمات ترفض أن الرقم سعر (هاتف، لوحة، موديل…).
const List<String> _kRejectKeywords = [
  'هاتف',
  'جوال',
  'موبايل',
  'تلفون',
  'لوحة',
  'موديل',
  'مودل',
  'قراءة',
  'كم',
  'كيلو',
  'سنة',
  'موديلها',
  'رقم الهاتف',
  'رقم جوال',
];

/// فواصل جمل ناعمة للنص الصوتي.
final RegExp _kSentenceSplit = RegExp(
  r'[.!؟?\n;]+|\s*(?:وايضا|وأيضا|كذلك|ثم)\s+',
  caseSensitive: false,
);

final RegExp _kTashkeel = RegExp(r'[\u064B-\u065F\u0670]');

/// رقم مع فواصل آلاف اختيارية: 18000 / 18,000 / 18.000
final RegExp _kNumberToken = RegExp(
  r'(?<![\d])(\d{1,3}(?:[.,]\d{3})+|\d{3,})(?![\d])',
);

const int _kContextRadius = 48;

/// تطبيع النص: أرقام عربية→غربية وإزالة التشكيل.
String normalizeOilNotesText(String input) {
  final buf = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kArabicIndicDigits[ch] ?? ch);
  }
  return buf.toString().replaceAll(_kTashkeel, '');
}

int _parseDinarToken(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[.,\s]'), '');
  return int.tryParse(cleaned) ?? 0;
}

String? _firstKeywordIn(String window, List<String> keywords) {
  String? best;
  var bestPos = 1 << 30;
  for (final k in keywords) {
    final i = window.indexOf(k);
    if (i >= 0 && i < bestPos) {
      bestPos = i;
      best = k;
    }
  }
  return best;
}

bool _contextHasAny(String window, List<String> keywords) =>
    _firstKeywordIn(window, keywords) != null;

bool _contextHasReject(String window) {
  for (final k in _kRejectKeywords) {
    if (window.contains(k)) return true;
  }
  if (RegExp(r'(?<!\d)07\d{8,10}(?!\d)').hasMatch(window)) return true;
  return false;
}

bool _precededByBaPriceMarker(String normalized, int numberStart) {
  var i = numberStart - 1;
  while (i >= 0 && (normalized[i] == ' ' || normalized[i] == '\u00A0')) {
    i--;
  }
  if (i < 0) return false;
  if (normalized[i] == 'ب') return true;
  if (normalized[i] == 'ـ' && i > 0 && normalized[i - 1] == 'ب') return true;
  return false;
}

OilNotesMoneyHitType _classifyType(
  String normalized,
  int start,
  int end, {
  required bool baMarker,
}) {
  final leftStart = (start - _kContextRadius).clamp(0, normalized.length);
  final left = normalized.substring(leftStart, start);
  // يمين أضيق — كلمات بعد الرقم أضعف من التي قبله (سعر … 10,000 يصبح …).
  final rightEnd = (end + 28).clamp(0, normalized.length);
  final right = normalized.substring(end, rightEnd);

  ({OilNotesMoneyHitType type, int dist, String key})? best;

  void consider(OilNotesMoneyHitType type, String side, List<String> keys,
      {required bool isLeft}) {
    for (final k in keys) {
      if (isLeft) {
        final i = side.lastIndexOf(k);
        if (i < 0) continue;
        final dist = side.length - i - k.length;
        if (best == null || dist < best!.dist) {
          best = (type: type, dist: dist, key: k);
        }
      } else {
        final i = side.indexOf(k);
        if (i < 0) continue;
        // عقوبة للجانب الأيمن حتى لا يسرق تصنيف رقم سابق.
        final dist = i + 80;
        if (best == null || dist < best!.dist) {
          best = (type: type, dist: dist, key: k);
        }
      }
    }
  }

  consider(OilNotesMoneyHitType.lineTotal, left, _kLineTotalKeywords,
      isLeft: true);
  consider(OilNotesMoneyHitType.unit, left, _kUnitKeywords, isLeft: true);
  consider(OilNotesMoneyHitType.lineTotal, right, _kLineTotalKeywords,
      isLeft: false);
  consider(OilNotesMoneyHitType.unit, right, _kUnitKeywords, isLeft: false);

  if (best != null) return best!.type;
  if (baMarker || _contextHasAny('$left$right', _kAcceptKeywords)) {
    return OilNotesMoneyHitType.unknown;
  }
  return OilNotesMoneyHitType.unknown;
}

String _buildContextLabel(
  String normalized,
  int start,
  int end,
  OilNotesMoneyHitType type,
) {
  final ctxStart = (start - _kContextRadius).clamp(0, normalized.length);
  final ctxEnd = (end + 28).clamp(0, normalized.length);
  final window = normalized.substring(ctxStart, ctxEnd);
  final fromLine = _firstKeywordIn(window, _kLineTotalKeywords);
  final fromUnit = _firstKeywordIn(window, _kUnitKeywords);
  final fromAccept = _firstKeywordIn(window, _kAcceptKeywords);
  final key = switch (type) {
    OilNotesMoneyHitType.lineTotal => fromLine ?? fromAccept,
    OilNotesMoneyHitType.unit => fromUnit ?? fromAccept,
    OilNotesMoneyHitType.unknown => fromAccept ?? fromUnit ?? fromLine,
  };
  if (key == null || key.isEmpty) {
    return type == OilNotesMoneyHitType.unit
        ? 'سعر'
        : (type == OilNotesMoneyHitType.lineTotal ? 'مجموع' : 'مبلغ');
  }
  final i = window.indexOf(key);
  final s = (i - 4).clamp(0, window.length);
  final e = (i + key.length + 18).clamp(0, window.length);
  return window.substring(s, e).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// حدود الجمل في النص المعياري: قائمة (start, end) نصف مفتوحة.
List<({int start, int end})> _sentenceRanges(String normalized) {
  final ranges = <({int start, int end})>[];
  var start = 0;
  for (final m in _kSentenceSplit.allMatches(normalized)) {
    if (m.start > start) {
      ranges.add((start: start, end: m.start));
    }
    start = m.end;
  }
  if (start < normalized.length) {
    ranges.add((start: start, end: normalized.length));
  }
  if (ranges.isEmpty) {
    ranges.add((start: 0, end: normalized.length));
  }
  return ranges;
}

int _sentenceIndexFor(int offset, List<({int start, int end})> ranges) {
  for (var i = 0; i < ranges.length; i++) {
    final r = ranges[i];
    if (offset >= r.start && offset < r.end) return i;
  }
  return ranges.length - 1;
}

/// يستخرج مبالغ الدينار من [text] مع تصنيف وافتراضات اختيار.
OilNotesMoneyParseResult parseOilNotesMoney(String text) {
  final normalized = normalizeOilNotesText(text);
  if (normalized.trim().isEmpty) return OilNotesMoneyParseResult.empty;

  final draft = <({
    int dinars,
    String raw,
    int start,
    int end,
    OilNotesMoneyHitType type,
    String contextLabel,
  })>[];

  for (final m in _kNumberToken.allMatches(normalized)) {
    final raw = m.group(1)!;
    final dinars = _parseDinarToken(raw);
    if (dinars <= 0) continue;
    if (dinars < 250 || dinars > 50000000) continue;

    final start = m.start;
    final end = m.end;
    final ctxStart = (start - _kContextRadius).clamp(0, normalized.length);
    final ctxEnd = (end + _kContextRadius).clamp(0, normalized.length);
    final window = normalized.substring(ctxStart, ctxEnd);

    if (_contextHasReject(window)) continue;

    final ba = _precededByBaPriceMarker(normalized, start);
    final hasLine = _contextHasAny(window, _kLineTotalKeywords);
    final hasUnit = _contextHasAny(window, _kUnitKeywords);
    final hasAccept = _contextHasAny(window, _kAcceptKeywords);
    if (!hasLine && !hasUnit && !hasAccept && !ba) continue;

    final type = _classifyType(normalized, start, end, baMarker: ba);
    draft.add((
      dinars: dinars,
      raw: raw,
      start: start,
      end: end,
      type: type,
      contextLabel: _buildContextLabel(normalized, start, end, type),
    ));
  }

  if (draft.isEmpty) return OilNotesMoneyParseResult.empty;

  final sentences = _sentenceRanges(normalized);
  final sentenceHasLineTotal = List<bool>.filled(sentences.length, false);
  for (final d in draft) {
    if (d.type != OilNotesMoneyHitType.lineTotal) continue;
    final si = _sentenceIndexFor(d.start, sentences);
    if (si >= 0 && si < sentenceHasLineTotal.length) {
      sentenceHasLineTotal[si] = true;
    }
  }

  final hits = <OilNotesMoneyHit>[];
  for (final d in draft) {
    final si = _sentenceIndexFor(d.start, sentences);
    final suppressUnit = d.type == OilNotesMoneyHitType.unit &&
        si >= 0 &&
        si < sentenceHasLineTotal.length &&
        sentenceHasLineTotal[si];

    final defaultSelected = switch (d.type) {
      OilNotesMoneyHitType.lineTotal => true,
      OilNotesMoneyHitType.unknown => true,
      OilNotesMoneyHitType.unit => !suppressUnit,
    };

    hits.add(
      OilNotesMoneyHit(
        dinars: d.dinars,
        raw: d.raw,
        start: d.start,
        end: d.end,
        type: d.type,
        contextLabel: d.contextLabel,
        defaultSelected: defaultSelected,
      ),
    );
  }

  final totalDinars = hits.fold<int>(
    0,
    (a, h) => a + (h.defaultSelected ? h.dinars : 0),
  );
  return OilNotesMoneyParseResult(
    hits: List.unmodifiable(hits),
    totalDinars: totalDinars,
    totalFils: totalDinars * 1000,
    source: 'local',
  );
}
