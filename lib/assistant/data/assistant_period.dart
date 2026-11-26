import '../../services/reports_repository.dart';

/// فترة يكتبها النموذج كلمة (today، this_week…) ويحسبها الهاتف بتوقيته (4.3).
///
/// الأسبوع يبدأ السبت كما في العراق. `custom` يحتاج `from` و`to` بصيغة
/// YYYY-MM-DD، والنهاية تشمل يومها.
class AssistantPeriod {
  const AssistantPeriod(this.key, this.range);

  final String key;
  final ReportDateRange range;

  static const keys = {'today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'custom'};

  /// عدد الأيام في الفترة، شاملاً الطرفين.
  int get days =>
      DateTime(
        range.to.year,
        range.to.month,
        range.to.day,
      ).difference(DateTime(range.from.year, range.from.month, range.from.day)).inDays +
      1;

  /// null إن كانت الكلمة غير معروفة أو التاريخ المخصص ناقصاً أو مقلوباً.
  static AssistantPeriod? resolve(
    Object? key, {
    Object? from,
    Object? to,
    required DateTime now,
    String fallback = 'today',
  }) {
    final k = (key is String && key.isNotEmpty) ? key : fallback;
    final today = DateTime(now.year, now.month, now.day);
    DateTime d(int y, int m, int day) => DateTime(y, m, day);
    // السبت = 6 في DateTime.weekday، فبداية الأسبوع قبل (weekday + 1) % 7 يوماً.
    final weekStart = today.subtract(Duration(days: (today.weekday + 1) % 7));
    switch (k) {
      case 'today':
        return AssistantPeriod(k, ReportDateRange(from: today, to: today));
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        return AssistantPeriod(k, ReportDateRange(from: y, to: y));
      case 'this_week':
        return AssistantPeriod(k, ReportDateRange(from: weekStart, to: today));
      case 'last_week':
        final s = weekStart.subtract(const Duration(days: 7));
        return AssistantPeriod(k, ReportDateRange(from: s, to: weekStart.subtract(const Duration(days: 1))));
      case 'this_month':
        return AssistantPeriod(k, ReportDateRange(from: d(today.year, today.month, 1), to: today));
      case 'last_month':
        final s = d(today.year, today.month - 1, 1);
        return AssistantPeriod(k, ReportDateRange(from: s, to: d(today.year, today.month, 0)));
      case 'custom':
        final f = _date(from);
        final t = _date(to);
        if (f == null || t == null || t.isBefore(f)) return null;
        return AssistantPeriod(k, ReportDateRange(from: f, to: t));
    }
    return null;
  }

  static DateTime? _date(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final da = int.parse(m[3]!);
    final out = DateTime(y, mo, da);
    return out.month == mo && out.day == da ? out : null;
  }

  Map<String, Object?> toJson() => {'period': key, 'from': _iso(range.from), 'to': _iso(range.to)};

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
