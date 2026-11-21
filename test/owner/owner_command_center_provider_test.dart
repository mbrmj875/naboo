import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_kpi_trend.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';

import '../mocks/owner_mock_repositories.dart';

void main() {
  group('OwnerCommandCenterProvider', () {
    late FakeOwnerCommandCenterRepository repo;
    late OwnerCommandCenterProvider provider;

    setUp(() {
      repo = FakeOwnerCommandCenterRepository();
      provider = OwnerCommandCenterProvider(
        repository: repo,
        oilOwnerSectionLoader: oilOwnerSectionLoaderFrom(repo),
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('partial failure keeps sales when debts section fails', () async {
      repo = FakeOwnerCommandCenterRepository(
        failOn: {OwnerSectionIds.debts},
      );
      provider.dispose();
      provider = OwnerCommandCenterProvider(
        repository: repo,
        oilOwnerSectionLoader: oilOwnerSectionLoaderFrom(repo),
      );

      await provider.loadSection(OwnerSectionIds.sales, force: true);
      await provider.loadSection(OwnerSectionIds.debts, force: true);

      expect(provider.snapshot.sales.isSuccess, isTrue);
      expect(provider.snapshot.debts?.isError, isTrue);
      expect(provider.screenStatus, CommandCenterScreenStatus.partial);
    });

    test('partial failure keeps sales when oil section fails', () async {
      repo = FakeOwnerCommandCenterRepository(
        failOn: {OwnerSectionIds.oilActiveCars},
      );
      provider.dispose();
      provider = OwnerCommandCenterProvider(
        repository: repo,
        oilOwnerSectionLoader: oilOwnerSectionLoaderFrom(repo),
      );

      await provider.loadSection(OwnerSectionIds.sales, force: true);
      await provider.loadSection(OwnerSectionIds.oilActiveCars, force: true);

      expect(provider.snapshot.sales.isSuccess, isTrue);
      expect(provider.snapshot.oilActiveCars?.isError, isTrue);
      expect(provider.screenStatus, CommandCenterScreenStatus.partial);
    });

    test('refreshSection reloads only requested section', () async {
      await provider.loadSection(OwnerSectionIds.sales, force: true);
      await provider.loadSection(OwnerSectionIds.openShifts, force: true);
      repo.loadedSections.clear();

      await provider.refreshSection(OwnerSectionIds.sales);

      expect(repo.loadedSections, [OwnerSectionIds.sales]);
    });

    test('TTL skips second fetch when section is fresh', () async {
      await provider.loadSection(OwnerSectionIds.sales, force: true);
      repo.loadedSections.clear();

      await provider.loadSection(OwnerSectionIds.sales, force: false);

      expect(repo.loadedSections, isEmpty);
    });

    test('invalidateSection bypasses TTL', () async {
      await provider.loadSection(OwnerSectionIds.sales, force: true);
      repo.loadedSections.clear();
      provider.invalidateSection(OwnerSectionIds.sales);
      await Future<void>.delayed(Duration.zero);
      expect(repo.loadedSections, contains(OwnerSectionIds.sales));
    });

    test('feature gate off removes debts and skips debt load', () async {
      provider.updateFeatureGate(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
          enableDebtsCustom: true,
        ),
      );
      await provider.refreshAll(force: true);
      expect(repo.loadedSections, contains(OwnerSectionIds.debts));

      repo.loadedSections.clear();
      provider.updateFeatureGate(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.oilChange,
          enableDebtsCustom: false,
        ),
      );
      expect(provider.snapshot.debts, isNull);

      await provider.refreshAll(force: true);
      expect(repo.loadedSections, isNot(contains(OwnerSectionIds.debts)));
    });
    test('setDateRange custom triggers refresh when boundaries change', () async {
      provider.setDateRange(
        OwnerDateRange.custom(DateTime(2026, 1, 1), DateTime(2026, 1, 7)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.loadedSections, isNotEmpty);

      repo.loadedSections.clear();
      provider.setDateRange(
        OwnerDateRange.custom(DateTime(2026, 1, 1), DateTime(2026, 1, 7)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.loadedSections, isEmpty);

      provider.setDateRange(
        OwnerDateRange.custom(DateTime(2026, 2, 1), DateTime(2026, 2, 7)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.loadedSections, isNotEmpty);
    });
    test('supermarket v2 loads retail shortages not oil-only filter', () async {
      provider.updateFeatureGate(
        BusinessSetupSettingsData.createForVertical(
          BusinessVertical.supermarket,
        ),
      );
      await provider.refreshAll(force: true);

      expect(repo.retailShortagesLoaded, isTrue);
      expect(provider.snapshot.inventoryShortages?.data?.shortageCount, 12);
    });

    test('oil changes section loads WoW trend without failing card', () async {
      repo = FakeOwnerCommandCenterRepository();
      repo.oilChangesTrendResult = const OwnerKpiTrend(
        deltaPercent: 33,
        direction: OwnerTrendDirection.up,
        comparisonLabelAr: 'عن نفس اليوم الأسبوع الماضي',
      );
      provider.dispose();
      provider = OwnerCommandCenterProvider(
        repository: repo,
        oilOwnerSectionLoader: oilOwnerSectionLoaderFrom(repo),
      );

      await provider.loadSection(OwnerSectionIds.oilChangesCount, force: true);

      expect(provider.snapshot.oilChangesCount?.isSuccess, isTrue);
      expect(provider.trendForSection(OwnerSectionIds.oilChangesCount)?.deltaPercent,
          closeTo(33, 0.01));
    });
  });
}
