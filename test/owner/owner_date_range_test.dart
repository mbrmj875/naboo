import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';

void main() {
  group('OwnerDateRange', () {
    test('custom range uses inclusive end day in endExclusiveLocal', () {
      final range = OwnerDateRange.custom(
        DateTime(2026, 1, 10),
        DateTime(2026, 1, 15),
      );
      expect(range.startLocal, DateTime(2026, 1, 10));
      expect(range.endExclusiveLocal, DateTime(2026, 1, 16));
      expect(range.salesTitleAr, 'مبيعات الفترة');
    });

    test('custom swaps inverted dates', () {
      final range = OwnerDateRange.custom(
        DateTime(2026, 5, 20),
        DateTime(2026, 5, 10),
      );
      expect(range.customEnd, DateTime(2026, 5, 20));
    });

    test('equality compares custom boundaries', () {
      final a = OwnerDateRange.custom(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 7),
      );
      final b = OwnerDateRange.custom(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 7),
      );
      final c = OwnerDateRange.custom(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 8),
      );
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('thisWeek covers last 7 local calendar days including today', () {
      const range = OwnerDateRange.thisWeek();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(range.startLocal, today.subtract(const Duration(days: 6)));
      expect(range.endExclusiveLocal, today.add(const Duration(days: 1)));
      expect(range.salesTitleAr, 'مبيعات الأسبوع');
    });

    test('today sales title and local day bounds', () {
      const range = OwnerDateRange.today();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(range.startLocal, today);
      expect(range.endExclusiveLocal, today.add(const Duration(days: 1)));
      expect(range.salesTitleAr, 'مبيعات اليوم');
    });

    test('utc bounds convert local midnight correctly', () {
      const range = OwnerDateRange.today();
      expect(range.startUtcIso, range.startLocal.toUtc().toIso8601String());
      expect(
        range.endExclusiveUtcIso,
        range.endExclusiveLocal.toUtc().toIso8601String(),
      );
      expect(range.startUtcIso.endsWith('Z'), isTrue);
    });
  });
}
