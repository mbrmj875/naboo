/// الشكل الموحّد لنتيجة أداة المساعد (خطة المساعد 4.2).
///
/// الأداة تُرجع صفوفاً خاماً، والحارس يقصّها ويحذف المالي ويحوّل المبالغ
/// إلى علامات قبل أن تصل للنموذج. البطاقة تُرسم من [rows] المحفوظة في الهاتف،
/// لا من نص النموذج.
library;

class AssistantToolResult {
  const AssistantToolResult({
    required this.ok,
    required this.tool,
    this.rows = const [],
    int? total,
    this.truncated = false,
    this.card,
    this.asOf,
    this.error,
    this.needs,
    this.needsLabel,
    this.source,
    this.extra = const {},
  }) : total = total ?? rows.length;

  factory AssistantToolResult.success(
    String tool,
    List<Map<String, Object?>> rows, {
    int? total,
    String? card,
    String? source,
    Map<String, Object?> extra = const {},
  }) {
    return AssistantToolResult(
      ok: true,
      tool: tool,
      rows: rows,
      total: total,
      card: card,
      source: source,
      asOf: DateTime.now(),
      extra: extra,
    );
  }

  factory AssistantToolResult.failure(String tool, String error, {String? needs, String? needsLabel}) {
    return AssistantToolResult(ok: false, tool: tool, error: error, needs: needs, needsLabel: needsLabel);
  }

  final bool ok;
  final String tool;
  final List<Map<String, Object?>> rows;
  final int total;
  final bool truncated;

  /// نوع البطاقة التي ترسمها الصفحة، مثل `stock_table`.
  final String? card;
  final DateTime? asOf;

  /// forbidden | bad_args | timeout | failed | not_available
  final String? error;

  /// مفتاح الصلاحية الناقصة عند الرفض (ق49).
  final String? needs;
  final String? needsLabel;

  /// وصف مقروء للمصدر يكتبه الهاتف لا النموذج (ق68).
  final String? source;

  /// حقول إضافية خارج الصفوف (مثل الإجماليات المحسوبة على الجهاز).
  final Map<String, Object?> extra;

  AssistantToolResult copyWith({
    List<Map<String, Object?>>? rows,
    int? total,
    bool? truncated,
    Map<String, Object?>? extra,
  }) {
    return AssistantToolResult(
      ok: ok,
      tool: tool,
      rows: rows ?? this.rows,
      total: total ?? this.total,
      truncated: truncated ?? this.truncated,
      card: card,
      asOf: asOf,
      error: error,
      needs: needs,
      needsLabel: needsLabel,
      source: source,
      extra: extra ?? this.extra,
    );
  }

  /// ما يُرسل للنموذج.
  Map<String, Object?> toJson() {
    if (!ok) {
      return {
        'ok': false,
        'tool': tool,
        'error': error ?? 'failed',
        if (needs != null) 'needs': needs,
        if (needsLabel != null) 'needs_label': needsLabel,
      };
    }
    return {
      'ok': true,
      'tool': tool,
      'total': total,
      'rows': rows,
      if (truncated) 'truncated': true,
      if (card != null) 'card': {'type': card},
      if (asOf != null) 'as_of': asOf!.toIso8601String(),
      ...extra,
    };
  }

  /// للحفظ على الجهاز مع المحادثة (الصفوف خام، كما تقرؤها البطاقة).
  Map<String, Object?> toStore() => {
    'ok': ok,
    'tool': tool,
    'rows': rows,
    'total': total,
    if (truncated) 'truncated': true,
    if (card != null) 'card': card,
    if (asOf != null) 'as_of': asOf!.toIso8601String(),
    if (error != null) 'error': error,
    if (source != null) 'source': source,
    if (extra.isNotEmpty) 'extra': extra,
  };

  static AssistantToolResult? fromStore(Object? v) {
    if (v is! Map) return null;
    final rows = v['rows'];
    final extra = v['extra'];
    return AssistantToolResult(
      ok: v['ok'] == true,
      tool: v['tool']?.toString() ?? '',
      rows: rows is List
          ? [
              for (final r in rows)
                if (r is Map) r.map((k, x) => MapEntry(k.toString(), x)),
            ]
          : const [],
      total: (v['total'] as num?)?.toInt(),
      truncated: v['truncated'] == true,
      card: v['card'] as String?,
      asOf: DateTime.tryParse(v['as_of']?.toString() ?? ''),
      error: v['error'] as String?,
      source: v['source'] as String?,
      extra: extra is Map ? extra.map((k, x) => MapEntry(k.toString(), x)) : const {},
    );
  }
}
