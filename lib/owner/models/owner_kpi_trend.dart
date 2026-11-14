import 'owner_date_range.dart';

/// اتجاه مقارنة WoW.
enum OwnerTrendDirection {
  up,
  down,
  flat,
}

/// مقارنة KPI — WoW / فترة مرجعية.
class OwnerKpiTrend {
  const OwnerKpiTrend({
    required this.deltaPercent,
    required this.direction,
    required this.comparisonLabelAr,
  });

  final double deltaPercent;
  final OwnerTrendDirection direction;
  final String comparisonLabelAr;

  /// نص العرض: «مرتفعة 15% عن نفس اليوم الأسبوع الماضي».
  String get displayLineAr {
    final pct = deltaPercent.abs().round();
    if (direction == OwnerTrendDirection.flat) {
      return 'مستقرة $comparisonLabelAr';
    }
    final verb = direction == OwnerTrendDirection.up ? 'مرتفعة' : 'منخفضة';
    return '$verb $pct% $comparisonLabelAr';
  }

  /// يبني trend من قيمتين — null إذا لا معنى للمقارنة.
  static OwnerKpiTrend? compute({
    required int current,
    required int reference,
    required OwnerDateRange range,
  }) {
    if (current == 0 && reference == 0) return null;

    final label = labelForRange(range);

    if (reference == 0) {
      if (current <= 0) return null;
      return OwnerKpiTrend(
        deltaPercent: 100,
        direction: OwnerTrendDirection.up,
        comparisonLabelAr: label,
      );
    }

    final delta = ((current - reference) / reference) * 100.0;
    final direction = directionFor(delta);
    return OwnerKpiTrend(
      deltaPercent: delta,
      direction: direction,
      comparisonLabelAr: label,
    );
  }

  static OwnerTrendDirection directionFor(double deltaPercent) {
    if (deltaPercent > 5) return OwnerTrendDirection.up;
    if (deltaPercent < -5) return OwnerTrendDirection.down;
    return OwnerTrendDirection.flat;
  }

  static String labelForRange(OwnerDateRange range) {
    switch (range.kind) {
      case OwnerDateRangeKind.today:
        return 'عن نفس اليوم الأسبوع الماضي';
      case OwnerDateRangeKind.thisWeek:
        return 'عن نفس الأسبوع الماضي';
      case OwnerDateRangeKind.thisMonth:
        return 'عن نفس الفترة قبل شهر';
      case OwnerDateRangeKind.custom:
        return 'عن الفترة قبل 7 أيام';
    }
  }

  /// نطاق مرجعي — نفس المدة قبل 7 أيام.
  static OwnerDateRange referenceRangeWoW(OwnerDateRange range) {
    final refStart = range.startLocal.subtract(const Duration(days: 7));
    final refEndInclusive = range.endExclusiveLocal
        .subtract(const Duration(days: 1))
        .subtract(const Duration(days: 7));
    return OwnerDateRange.custom(refStart, refEndInclusive);
  }
}
