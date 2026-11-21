import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/owner_action_alert_resolver.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/widgets/owner_action_rail.dart';
import 'package:naboo/owner/widgets/owner_hero_kpi_card.dart';
import 'package:naboo/owner/widgets/owner_kpi_card.dart';
import 'package:naboo/owner/widgets/owner_kpi_card_v3.dart';
import 'package:naboo/services/business_setup_settings.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  BusinessSetupSettingsData serviceFeatures() {
    return verticalSettings(BusinessVertical.oilChange, enablePos: false);
  }

  BusinessSetupSettingsData hybridFeatures() {
    return verticalSettings(BusinessVertical.oilChange, enablePos: true);
  }

  group('OwnerOilDashboardPanel KPI cards', () {
    testWidgets('service mode preset includes 5+ oil KPI cards', (tester) async {
      final preset = OilChangeTestHarness.instance.ownerPreset(enablePos: false);
      expect(preset.defaultCardOrder.length, greaterThanOrEqualTo(5));
      expect(preset.profile, OwnerDashboardProfile.oilChangeService);
    });

    testWidgets('hybrid mode hero is hybrid revenue split', (tester) async {
      final preset = OilChangeTestHarness.instance.ownerPreset(enablePos: true);
      expect(preset.profile, OwnerDashboardProfile.oilChangeHybrid);
      expect(preset.hybridRevenueSplit, isTrue);
      expect(preset.defaultHeroCatalogId, 'hybrid_revenue_split');
    });

    testWidgets('hero card renders active cars count', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerHeroKpiCard(
            title: 'سيارات في الورشة',
            sectionId: OwnerSectionIds.oilActiveCars,
            section: OwnerSectionResult.success(
              const OilActiveCarsKpi(activeCount: 3, staleWaitingCount: 1),
              DateTime(2026, 6, 15),
            ),
            valueBuilder: (d) => '${(d as OilActiveCarsKpi).activeCount}',
            onRetry: () {},
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('oil changes KPI respects date range label', (tester) async {
      final range = OwnerDateRange.custom(
        DateTime(2026, 6, 10),
        DateTime(2026, 6, 16),
      );
      await tester.pumpWidget(
        wrap(
          OwnerKpiCardV3(
            title: 'غيارات الفترة',
            sectionId: OwnerSectionIds.oilChangesCount,
            section: OwnerSectionResult.success(
              OilChangesKpi(
                changeCount: 7,
                revenueFils: 350000,
                range: range,
              ),
              DateTime(2026, 6, 15),
            ),
            valueBuilder: (d) => '${(d as OilChangesKpi).changeCount}',
            onRetry: () {},
            isEmpty: (d) => (d as OilChangesKpi).changeCount <= 0,
          ),
        ),
      );
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('Action Rail shows oil garage stale alert', (tester) async {
      final snapshot = OwnerDashboardAssertion.oilServiceSnapshot(
        activeCars: 1,
        staleCars: 2,
        shortages: 3,
      );
      final alertIds = OwnerDashboardAssertion.oilAlertIds(snapshot);
      expect(alertIds, isNotEmpty);

      final alerts = OwnerActionAlertResolver.resolve(
        profile: OwnerDashboardProfile.oilChangeService,
        features: serviceFeatures(),
        snapshot: snapshot,
      );

      await tester.pumpWidget(
        wrap(
          OwnerActionRail(
            alerts: alerts,
            isLoading: false,
            onAction: (_) {},
          ),
        ),
      );
      expect(find.text('إجراءات مطلوبة'), findsOneWidget);
      expect(find.textContaining('سيارات'), findsWidgets);
    });

    testWidgets('offline stale KPI shows old data badge', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'غيارات الفترة',
            sectionId: OwnerSectionIds.oilChangesCount,
            section: OwnerSectionResult.stale(
              OilChangesKpi(
                changeCount: 4,
                revenueFils: 200000,
                range: OwnerDateRange.today(),
              ),
              DateTime(2026, 6, 14),
              isOffline: true,
            ),
            valueBuilder: (d) => '${(d as OilChangesKpi).changeCount}',
            onRetry: () {},
          ),
        ),
      );
      expect(find.textContaining('البيانات قديمة'), findsOneWidget);
    });
  });
}
