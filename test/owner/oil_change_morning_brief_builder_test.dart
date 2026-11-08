import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/verticals/oil_change/owner/oil_change_morning_brief_builder.dart';

void main() {
  group('OilChangeMorningBriefBuilder', () {
    test('joins changes, active cars, and shortages', () {
      final text = OilChangeMorningBriefBuilder.build(
        OwnerCommandCenterSnapshot(
          oilChangesCount: OwnerSectionResult.success(
            const OilChangesKpi(
              changeCount: 12,
              revenueFils: 0,
              range: OwnerDateRange.today(),
            ),
            DateTime(2026, 5, 28),
          ),
          oilActiveCars: OwnerSectionResult.success(
            const OilActiveCarsKpi(activeCount: 3),
            DateTime(2026, 5, 28),
          ),
          oilStockShortages: OwnerSectionResult.success(
            const InventoryAlert(shortageCount: 2),
            DateTime(2026, 5, 28),
          ),
        ),
      );
      expect(text, '12 غيار · 3 سيارات بالانتظار · 2 نواقص حرجة');
    });

    test('counts wash and direct sale, not only oil cards', () {
      final text = OilChangeMorningBriefBuilder.build(
        OwnerCommandCenterSnapshot(
          oilChangesCount: OwnerSectionResult.success(
            const OilChangesKpi(
              changeCount: 0,
              revenueFils: 0,
              range: OwnerDateRange.today(),
              washCount: 4,
              directSaleCount: 9,
            ),
            DateTime(2026, 11, 8),
          ),
        ),
      );
      expect(text, '4 غسيل · 9 بيع مباشر');
      expect(text, isNot(contains('لا نشاط')));
    });

    test('oil count uses invoiced cards when card opened earlier', () {
      final text = OilChangeMorningBriefBuilder.build(
        OwnerCommandCenterSnapshot(
          oilChangesCount: OwnerSectionResult.success(
            const OilChangesKpi(
              changeCount: 0,
              revenueFils: 0,
              range: OwnerDateRange.today(),
              oilInvoiceCount: 3,
            ),
            DateTime(2026, 11, 8),
          ),
        ),
      );
      expect(text, '3 غيار');
    });

    test('never says no activity while period sales are positive', () {
      final text = OilChangeMorningBriefBuilder.build(
        OwnerCommandCenterSnapshot(
          sales: OwnerSectionResult.success(
            const SalesKpi(salesFils: 130000000, range: OwnerDateRange.today()),
            DateTime(2026, 11, 8),
          ),
          oilChangesCount: OwnerSectionResult.success(
            const OilChangesKpi(
              changeCount: 0,
              revenueFils: 0,
              range: OwnerDateRange.today(),
            ),
            DateTime(2026, 11, 8),
          ),
        ),
      );
      expect(text, OilChangeMorningBriefBuilder.salesOnlyText);
    });

    test('shows loading text while operations are still loading', () {
      final text = OilChangeMorningBriefBuilder.build(
        const OwnerCommandCenterSnapshot(
          oilChangesCount: OwnerSectionResult.loading(),
        ),
      );
      expect(text, OilChangeMorningBriefBuilder.loadingText);
    });

    test('returns fallback when snapshot empty', () {
      expect(
        OilChangeMorningBriefBuilder.build(OwnerCommandCenterSnapshot.initial),
        'لا نشاط مسجّل بعد — اسحب للتحديث',
      );
    });
  });
}
