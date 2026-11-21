import '../../../../services/reports_repository.dart';

/// قيمة يوم واحد في مخطط الاتجاه. الأيام الفارغة صفر، لا تُحذف.
class ReportDayPoint {
  const ReportDayPoint({
    required this.day,
    required this.count,
    required this.amountFils,
  });

  final DateTime day;
  final int count;
  final int amountFils;
}

/// مؤشر مع قيمته في الفترة السابقة بنفس الطول.
class ReportMetric {
  const ReportMetric(this.current, this.previous);

  final num current;
  final num previous;

  /// التغيّر بالنسبة المئوية؛ `null` إن لم تكن للفترة السابقة قيمة.
  double? get changePct {
    if (previous == 0) return null;
    return (current - previous) / previous.abs() * 100;
  }
}

/// تغطية التكلفة: كم سطراً تكلفته مثبّتة لحظة البيع وكم تقديرية.
class ReportCostCoverage {
  const ReportCostCoverage({
    this.stamped = 0,
    this.fallback = 0,
    this.missing = 0,
  });

  final int stamped;
  final int fallback;
  final int missing;

  int get total => stamped + fallback + missing;
  bool get isExact => fallback == 0 && missing == 0;
}

/// صف مرتب (منتج، نوع غسيل، عامل…).
class ReportRankRow {
  const ReportRankRow({
    required this.label,
    required this.count,
    required this.amountFils,
    this.costFils = 0,
    this.quantity = 0,
  });

  final String label;
  final int count;
  final int amountFils;
  final int costFils;
  final double quantity;

  int get profitFils => amountFils - costFils;
}

abstract final class ReportMath {
  /// الفترة السابقة: نفس عدد الأيام، تنتهي في اليوم السابق لبداية الفترة.
  static ReportDateRange previousRange(ReportDateRange range) {
    final from = DateTime(range.from.year, range.from.month, range.from.day);
    final to = DateTime(range.to.year, range.to.month, range.to.day);
    final days = to.difference(from).inDays + 1;
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: days - 1));
    return ReportDateRange(from: prevFrom, to: prevTo);
  }

  static String dayKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// كل أيام الفترة بالترتيب، والأيام بلا حركة صفر.
  static List<ReportDayPoint> zeroFill(
    ReportDateRange range, {
    required Map<String, int> counts,
    required Map<String, int> amountsFils,
  }) {
    final from = DateTime(range.from.year, range.from.month, range.from.day);
    final to = DateTime(range.to.year, range.to.month, range.to.day);
    final out = <ReportDayPoint>[];
    // حد أعلى يحمي من فترة خاطئة طويلة جداً.
    for (var d = from, i = 0; !d.isAfter(to) && i < 400; i++) {
      final k = dayKey(d);
      out.add(
        ReportDayPoint(
          day: d,
          count: counts[k] ?? 0,
          amountFils: amountsFils[k] ?? 0,
        ),
      );
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// يوم الأسبوع (0 = السبت … 6 = الجمعة) — أسبوع العمل في العراق.
  static int weekdayRow(DateTime d) => (d.weekday + 1) % 7;

  static const weekdayLabels = [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  /// ترتيب تنازلي حسب المبلغ ثم العدد.
  static List<ReportRankRow> rank(Iterable<ReportRankRow> rows) {
    final list = rows.toList()
      ..sort((a, b) {
        final byAmount = b.amountFils.compareTo(a.amountFils);
        return byAmount != 0 ? byAmount : b.count.compareTo(a.count);
      });
    return list;
  }

  static int toFils(num? iqd) => ((iqd ?? 0) * 1000).round();

  /// حدود الفترة بتوقيت UTC لأعمدة تُحفظ بـ `toUtc()` مثل
  /// `service_orders.createdAt`. الفواتير تُحفظ بالتوقيت المحلي فتبقى على
  /// [ReportDateRange.fromIso].
  static (String, String) utcBounds(ReportDateRange range) {
    final start = DateTime(range.from.year, range.from.month, range.from.day);
    final end = DateTime(range.to.year, range.to.month, range.to.day + 1);
    return (start.toUtc().toIso8601String(), end.toUtc().toIso8601String());
  }
}
