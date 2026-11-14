import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_trend.dart';
import 'package:naboo/owner/widgets/owner_kpi_card_v3.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/widgets/owner_kpi_trend_line.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  group('OwnerKpiTrendLine', () {
    testWidgets('shows up trend text', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiTrendLine(
            trend: OwnerKpiTrend(
              deltaPercent: 15,
              direction: OwnerTrendDirection.up,
              comparisonLabelAr: 'عن نفس اليوم الأسبوع الماضي',
            ),
          ),
        ),
      );
      expect(find.textContaining('مرتفعة 15%'), findsOneWidget);
      expect(find.textContaining('🔺'), findsOneWidget);
    });
  });

  group('OwnerKpiCardV3 trend', () {
    testWidgets('shows trend line under value', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCardV3(
            title: 'غيارات الفترة',
            section: OwnerSectionResult.success(
              OilChangesKpi(
                changeCount: 10,
                revenueFils: 500000,
                range: OwnerDateRange.today(),
              ),
              DateTime(2026, 5, 28),
            ),
            sectionId: OwnerSectionIds.oilChangesCount,
            valueBuilder: (d) => '${(d as OilChangesKpi).changeCount}',
            onRetry: () {},
            trend: OwnerKpiTrend(
              deltaPercent: 25,
              direction: OwnerTrendDirection.up,
              comparisonLabelAr: 'عن نفس اليوم الأسبوع الماضي',
            ),
          ),
        ),
      );
      expect(find.text('10'), findsOneWidget);
      expect(find.textContaining('مرتفعة 25%'), findsOneWidget);
    });
  });
}
