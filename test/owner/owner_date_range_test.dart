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
  });
}
