import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/owner_trend_repository.dart';

void main() {
  group('OwnerTrendRepository.buildSevenDaySeries', () {
    test('fills missing days with zero oldest first', () {
      final start = DateTime(2026, 5, 22);
      final series = OwnerTrendRepository.buildSevenDaySeries(
        {
          '2026-05-22': 1000,
          '2026-05-24': 3000,
        },
        start,
      );
      expect(series.length, 7);
      expect(series.first, 1000);
      expect(series[1], 0);
      expect(series[2], 3000);
      expect(series.last, 0);
    });
  });
}
