/// تقييمات العملاء لخدمة غيار الزيت — تُقرأ من Supabase فقط (تُكتب من Edge).
class OilChangeEmployeeRatingSummary {
  const OilChangeEmployeeRatingSummary({
    required this.employeeName,
    required this.ratingsCount,
    required this.averageScore,
    required this.notesCount,
    required this.repliesCount,
    this.lastRatingAt,
  });

  /// فني بلا أي رد بعد — يُعرض في القائمة حتى لا تختفي أسماء المحل.
  factory OilChangeEmployeeRatingSummary.empty(String employeeName) {
    return OilChangeEmployeeRatingSummary(
      employeeName: employeeName,
      ratingsCount: 0,
      averageScore: null,
      notesCount: 0,
      repliesCount: 0,
    );
  }

  final String employeeName;

  /// عدد البطاقات المُقيَّمة (آخر رد لكل بطاقة).
  final int ratingsCount;
  final double? averageScore;
  final int notesCount;

  /// كل ردود العميل المنسوبة لهذا الفني، بما فيها المكررة والملاحظات.
  final int repliesCount;
  final DateTime? lastRatingAt;

  bool get hasReplies => repliesCount > 0;

  factory OilChangeEmployeeRatingSummary.fromMap(Map<String, dynamic> row) {
    final rawAvg = row['average_score'];
    return OilChangeEmployeeRatingSummary(
      employeeName: (row['employee_name'] ?? 'غير محدد').toString(),
      ratingsCount: _toInt(row['ratings_count']),
      averageScore: rawAvg == null
          ? null
          : double.tryParse(rawAvg.toString()),
      notesCount: _toInt(row['notes_count']),
      repliesCount: _toInt(row['replies_count']),
      lastRatingAt: DateTime.tryParse((row['last_rating_at'] ?? '').toString()),
    );
  }
}

class OilChangeRatingEntry {
  const OilChangeRatingEntry({
    required this.id,
    required this.customerPhone,
    required this.createdAt,
    this.employeeName,
    this.orderRef,
    this.score,
    this.note,
    required this.source,
  });

  final String id;
  final String customerPhone;
  final DateTime? createdAt;
  final String? employeeName;
  final String? orderRef;
  final int? score;
  final String? note;
  final String source;

  /// إسناد دقيق عبر ردّ العميل مباشرة على البطاقة.
  bool get isExactMatch => source == 'reply_context';

  factory OilChangeRatingEntry.fromMap(Map<String, dynamic> row) {
    return OilChangeRatingEntry(
      id: (row['id'] ?? '').toString(),
      customerPhone: (row['customer_phone'] ?? '').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
      employeeName: (row['employee_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : (row['employee_name'] as String).trim(),
      orderRef: (row['order_ref'] as String?)?.trim(),
      score: row['score'] == null ? null : _toInt(row['score']),
      note: (row['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : (row['note'] as String).trim(),
      source: (row['source'] ?? 'recent_card').toString(),
    );
  }
}

int _toInt(Object? v) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
