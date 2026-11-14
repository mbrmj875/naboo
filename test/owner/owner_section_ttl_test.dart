import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';

void main() {
  group('OwnerSectionTtl', () {
    test('isFresh returns false when fetchedAt is null', () {
      expect(
        OwnerSectionTtl.isFresh(OwnerSectionIds.sales, null),
        isFalse,
      );
    });

    test('isFresh respects per-section TTL', () {
      final now = DateTime.now();
      expect(
        OwnerSectionTtl.isFresh(
          OwnerSectionIds.openShifts,
          now.subtract(const Duration(seconds: 20)),
        ),
        isTrue,
      );
      expect(
        OwnerSectionTtl.isFresh(
          OwnerSectionIds.openShifts,
          now.subtract(const Duration(seconds: 45)),
        ),
        isFalse,
      );
    });

    test('inventoryShortages TTL is 5 minutes per v1.1.2', () {
      expect(OwnerSectionTtl.inventoryShortages, const Duration(minutes: 5));
      final now = DateTime.now();
      expect(
        OwnerSectionTtl.isFresh(
          OwnerSectionIds.inventoryShortages,
          now.subtract(const Duration(minutes: 4)),
        ),
        isTrue,
      );
      expect(
        OwnerSectionTtl.isFresh(
          OwnerSectionIds.inventoryShortages,
          now.subtract(const Duration(minutes: 6)),
        ),
        isFalse,
      );
    });

    test('isVeryStale true after 3x TTL', () {
      final now = DateTime.now();
      expect(
        OwnerSectionTtl.isVeryStale(OwnerSectionIds.sales, null),
        isTrue,
      );
      // sales TTL = 2 د → 3× = 6 د
      expect(
        OwnerSectionTtl.isVeryStale(
          OwnerSectionIds.sales,
          now.subtract(const Duration(minutes: 7)),
        ),
        isTrue,
      );
      expect(
        OwnerSectionTtl.isVeryStale(
          OwnerSectionIds.sales,
          now.subtract(const Duration(minutes: 4)),
        ),
        isFalse,
      );
    });
  });
}
