import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/widgets/owner_hero_kpi_card.dart';
import 'package:naboo/owner/widgets/owner_kpi_card_v3.dart';
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('OwnerHeroKpiCard', () {
    testWidgets('shows large active cars count', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerHeroKpiCard(
            title: 'سيارات في الورشة',
            sectionId: OwnerSectionIds.oilActiveCars,
            section: OwnerSectionResult.success(
              const OilActiveCarsKpi(activeCount: 4),
              DateTime(2026, 5, 28),
            ),
            valueBuilder: (d) => '${(d as OilActiveCarsKpi).activeCount}',
            onRetry: () {},
          ),
        ),
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.text('سيارات في الورشة'), findsOneWidget);
    });
  });

  group('OwnerKpiCardV3 empty state', () {
    testWidgets('shows CTA when active cars is zero', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          OwnerKpiCardV3(
            title: 'سيارات في الورشة',
            section: OwnerSectionResult.success(
              const OilActiveCarsKpi(activeCount: 0),
              DateTime(2026, 5, 28),
            ),
            sectionId: 'oilActiveCars',
            valueBuilder: (d) => '${(d as OilActiveCarsKpi).activeCount}',
            onRetry: () {},
            emptyState: OwnerKpiEmptyState(
              message: 'لا توجد سيارات',
              ctaLabel: 'غيار زيت جديد',
              onCta: () => tapped = true,
            ),
            isEmpty: (d) => (d as OilActiveCarsKpi).activeCount <= 0,
          ),
        ),
      );
      expect(find.text('لا توجد سيارات'), findsOneWidget);
      await tester.tap(find.text('غيار زيت جديد'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
