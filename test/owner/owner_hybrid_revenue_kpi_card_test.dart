import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/widgets/owner_hybrid_revenue_kpi_card.dart';

void main() {
  testWidgets('OwnerHybridRevenueKpiCard highlights dominant revenue stream', (
    tester,
  ) async {
    final section = OwnerSectionResult.success(
      HybridRevenueKpi(
        serviceFils: 700_000,
        posRetailFils: 300_000,
        range: const OwnerDateRange.today(),
      ),
      DateTime(2026, 5, 28),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerHybridRevenueKpiCard(
            title: 'إجمالي الإيرادات',
            section: section,
            sectionId: OwnerSectionIds.hybridRevenueSplit,
            onRetry: () {},
            isHero: true,
          ),
        ),
      ),
    );

    expect(find.text('غيار الزيت'), findsOneWidget);
    expect(find.text('تجزئة POS'), findsOneWidget);
    expect(find.textContaining('70%'), findsOneWidget);
    expect(find.textContaining('30%'), findsOneWidget);
  });

  testWidgets('split bar uses distinct colors for service and POS', (
    tester,
  ) async {
    final section = OwnerSectionResult.success(
      HybridRevenueKpi(
        serviceFils: 200_000,
        posRetailFils: 800_000,
        range: const OwnerDateRange.today(),
      ),
      DateTime(2026, 5, 28),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: OwnerHybridRevenueKpiCard(
            title: 'إجمالي الإيرادات',
            section: section,
            sectionId: OwnerSectionIds.hybridRevenueSplit,
            onRetry: () {},
          ),
        ),
      ),
    );

    final cs = Theme.of(tester.element(find.byType(OwnerHybridRevenueKpiCard))).colorScheme;
    final barColors = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map(
          (w) => (w.color as Color?) ?? Colors.transparent,
        );
    expect(barColors, contains(cs.primary));
    expect(barColors, contains(cs.tertiary));
  });
}
