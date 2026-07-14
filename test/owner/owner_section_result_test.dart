import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';

void main() {
  group('OwnerSectionResult', () {
    test('success exposes data and fetchedAt', () {
      final at = DateTime(2026, 5, 28);
      final r = OwnerSectionResult.success(
        const SalesKpi(salesFils: 100, range: OwnerDateRange.today()),
        at,
      );
      expect(r.isSuccess, isTrue);
      expect(r.hasData, isTrue);
      expect(r.fetchedAt, at);
    });

    test('error keeps stale data when provided', () {
      final stale = const SalesKpi(salesFils: 50, range: OwnerDateRange.today());
      final r = OwnerSectionResult.error('فشل', staleData: stale);
      expect(r.isError, isTrue);
      expect(r.data, stale);
      expect(r.errorMessage, 'فشل');
    });

    test('stale is distinct from success', () {
      final at = DateTime(2026, 5, 28);
      final r = OwnerSectionResult.stale(
        const SalesKpi(salesFils: 1, range: OwnerDateRange.today()),
        at,
      );
      expect(r.isStale, isTrue);
      expect(r.isSuccess, isFalse);
      expect(r.hasData, isTrue);
    });

    test('isOffline marks stale display without error', () {
      final at = DateTime(2026, 5, 28);
      final r = OwnerSectionResult.stale(
        const SalesKpi(salesFils: 1, range: OwnerDateRange.today()),
        at,
        isOffline: true,
      );
      expect(r.isOffline, isTrue);
      expect(r.isStale, isTrue);
      expect(r.isError, isFalse);
    });

    test('isAgeStale uses 3x TTL', () {
      final at = DateTime.now().subtract(const Duration(minutes: 7));
      final r = OwnerSectionResult.success(
        const SalesKpi(salesFils: 1, range: OwnerDateRange.today()),
        at,
      );
      expect(r.isAgeStale(OwnerSectionIds.sales), isTrue);
    });
  });
}
