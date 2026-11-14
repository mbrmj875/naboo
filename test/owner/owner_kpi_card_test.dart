import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/widgets/owner_kpi_card.dart';
import 'package:naboo/owner/widgets/owner_kpi_card_skeleton.dart';
import 'package:naboo/owner/widgets/owner_kpi_card_v3.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  group('OwnerKpiCard', () {
    testWidgets('shows retry button on error without data', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'مبيعات اليوم',
            section: OwnerSectionResult.error('تعذّر التحميل'),
            sectionId: OwnerSectionIds.sales,
            valueBuilder: (_) => '',
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('إعادة المحاولة'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('semantics label includes formatted value', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'مبيعات اليوم',
            section: OwnerSectionResult.success(
              const SalesKpi(
                salesFils: 5000000,
                range: OwnerDateRange.today(),
              ),
              DateTime(2026, 5, 28),
            ),
            sectionId: OwnerSectionIds.sales,
            valueBuilder: (_) => '5,000 د.ع',
            onRetry: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(OwnerKpiCard));
      expect(semantics.label, 'مبيعات اليوم: 5,000 د.ع');
    });

    testWidgets('shows stale badge when section is stale', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'الصندوق',
            section: OwnerSectionResult.stale(
              const CashSummary(
                balanceFils: 1000000,
                todayInFils: 0,
                todayOutFils: 0,
              ),
              DateTime.now().subtract(const Duration(minutes: 5)),
            ),
            sectionId: OwnerSectionIds.cash,
            valueBuilder: (_) => '1,000 د.ع',
            onRetry: () {},
          ),
        ),
      );

      expect(find.textContaining('آخر تحديث'), findsOneWidget);
    });

    testWidgets('shows skeleton pulse while loading without data', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'مبيعات اليوم',
            section: const OwnerSectionResult.loading(),
            sectionId: OwnerSectionIds.sales,
            valueBuilder: (_) => '',
            onRetry: () {},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(OwnerKpiPulseScope), findsOneWidget);
    });

    testWidgets('shows offline empty with retry', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'مبيعات اليوم',
            section: OwnerSectionResult.error(
              ownerKpiOfflineEmptyMessage,
              isOffline: true,
            ),
            sectionId: OwnerSectionIds.sales,
            valueBuilder: (_) => '',
            onRetry: () {},
          ),
        ),
      );

      expect(find.text(ownerKpiOfflineEmptyMessage), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    testWidgets('forwards warningGlowWhen to OwnerKpiCard', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCardV3(
            title: 'نواقص الزيت',
            section: OwnerSectionResult.success(
              const InventoryAlert(shortageCount: 4),
              DateTime(2026, 6, 2),
            ),
            sectionId: OwnerSectionIds.oilStockShortages,
            valueBuilder: (data) =>
                '${(data as InventoryAlert).shortageCount}',
            warningGlowWhen: (data) =>
                (data as InventoryAlert).shortageCount >= 3,
            onRetry: () {},
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.side.color.a, greaterThan(0.4));
    });
  });
}
