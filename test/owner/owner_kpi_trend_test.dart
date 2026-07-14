import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_trend.dart';

void main() {
  group('OwnerKpiTrend', () {
    test('compute returns up when current exceeds reference by >5%', () {
      final trend = OwnerKpiTrend.compute(
        current: 12,
        reference: 10,
        range: const OwnerDateRange.today(),
      );
      expect(trend, isNotNull);
      expect(trend!.direction, OwnerTrendDirection.up);
      expect(trend.deltaPercent, closeTo(20, 0.01));
      expect(trend.displayLineAr, contains('20%'));
      expect(trend.displayLineAr, contains('الأسبوع الماضي'));
    });

    test('compute returns down when current drops by >5%', () {
      final trend = OwnerKpiTrend.compute(
        current: 8,
        reference: 10,
        range: const OwnerDateRange.today(),
      );
      expect(trend!.direction, OwnerTrendDirection.down);
    });

    test('compute returns flat for small delta', () {
      final trend = OwnerKpiTrend.compute(
        current: 102,
        reference: 100,
        range: const OwnerDateRange.today(),
      );
      expect(trend!.direction, OwnerTrendDirection.flat);
      expect(trend.displayLineAr, contains('مستقرة'));
    });

    test('compute returns null when both zero', () {
      expect(
        OwnerKpiTrend.compute(
          current: 0,
          reference: 0,
          range: const OwnerDateRange.today(),
        ),
        isNull,
      );
    });

    test('referenceRangeWoW shifts boundaries by 7 days', () {
      final range = OwnerDateRange.custom(
        DateTime(2026, 5, 20),
        DateTime(2026, 5, 26),
      );
      final ref = OwnerKpiTrend.referenceRangeWoW(range);
      expect(ref.startLocal, DateTime(2026, 5, 13));
      expect(ref.endExclusiveLocal, DateTime(2026, 5, 20));
    });
  });
}
