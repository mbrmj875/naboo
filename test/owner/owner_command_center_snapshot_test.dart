import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';

void main() {
  group('OwnerCommandCenterSnapshot.screenStatus', () {
    test('idle when all sections idle', () {
      expect(
        OwnerCommandCenterSnapshot.initial.screenStatus,
        CommandCenterScreenStatus.idle,
      );
    });

    test('loading when every active section is loading', () {
      const snapshot = OwnerCommandCenterSnapshot(
        staffUsers: OwnerSectionResult.loading(),
        sales: OwnerSectionResult.loading(),
      );
      expect(snapshot.screenStatus, CommandCenterScreenStatus.loading);
    });

    test('partial when one section errors but another succeeds', () {
      final fetchedAt = DateTime(2026, 5, 28);
      final snapshot = OwnerCommandCenterSnapshot(
        staffUsers: OwnerSectionResult.success(
          const StaffUsersData(users: [
            StaffUserRow(id: 1, displayName: 'أحمد', username: 'ahmed'),
          ]),
          fetchedAt,
        ),
        sales: OwnerSectionResult.error(
          'فشل',
          staleData: SalesKpi(
            salesFils: 1000,
            range: const OwnerDateRange.today(),
          ),
          fetchedAt: fetchedAt,
        ),
      );
      expect(snapshot.screenStatus, CommandCenterScreenStatus.partial);
    });

    test('offlineStale when sales section is stale', () {
      final fetchedAt = DateTime(2026, 5, 28);
      final snapshot = OwnerCommandCenterSnapshot(
        sales: OwnerSectionResult.stale(
          SalesKpi(
            salesFils: 5000,
            range: const OwnerDateRange.today(),
          ),
          fetchedAt,
        ),
      );
      expect(snapshot.screenStatus, CommandCenterScreenStatus.offlineStale);
    });

    test('ready when all active sections succeed', () {
      final fetchedAt = DateTime(2026, 5, 28);
      final snapshot = OwnerCommandCenterSnapshot(
        staffUsers: OwnerSectionResult.success(
          const StaffUsersData(users: []),
          fetchedAt,
        ),
        openShifts: OwnerSectionResult.success(
          const OpenShiftsKpi(items: []),
          fetchedAt,
        ),
      );
      expect(snapshot.screenStatus, CommandCenterScreenStatus.ready);
    });
  });
}
