import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/widgets/owner_kpi_card.dart';
import 'package:naboo/owner/widgets/owner_kpi_micro_animations.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  group('ownerDateRangeMorphKey', () {
    test('differs by kind and custom bounds', () {
      const today = OwnerDateRange.today();
      const week = OwnerDateRange.thisWeek();
      expect(ownerDateRangeMorphKey(today), isNot(ownerDateRangeMorphKey(week)));

      final custom = OwnerDateRange.custom(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 2),
      );
      expect(
        ownerDateRangeMorphKey(custom),
        isNot(ownerDateRangeMorphKey(today)),
      );
    });
  });

  group('OwnerKpiWarningGlow', () {
    testWidgets('wraps child when inactive', (tester) async {
      await tester.pumpWidget(
        wrap(
          const OwnerKpiWarningGlow(
            active: false,
            child: Text('محتوى'),
          ),
        ),
      );
      expect(find.text('محتوى'), findsOneWidget);
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('adds glow decoration when active', (tester) async {
      await tester.pumpWidget(
        wrap(
          const OwnerKpiWarningGlow(
            active: true,
            child: Text('تحذير'),
          ),
        ),
      );
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  });

  group('OwnerAnimatedKpiValue', () {
    testWidgets('animates when valueKey changes', (tester) async {
      var key = 'a';
      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  OwnerAnimatedKpiValue(
                    valueKey: key,
                    text: key == 'a' ? '100' : '200',
                  ),
                  TextButton(
                    onPressed: () => setState(() => key = 'b'),
                    child: const Text('تغيير'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.text('تغيير'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('200'), findsOneWidget);
    });
  });

  group('OwnerKpiCard warningGlowWhen', () {
    testWidgets('shows error border when shortage count >= 3', (tester) async {
      await tester.pumpWidget(
        wrap(
          OwnerKpiCard(
            title: 'نواقص المخزون',
            section: OwnerSectionResult.success(
              const InventoryAlert(shortageCount: 5),
              DateTime(2026, 6, 2),
            ),
            sectionId: OwnerSectionIds.inventoryShortages,
            valueBuilder: (data) => '${(data as InventoryAlert).shortageCount}',
            warningGlowWhen: (data) =>
                (data as InventoryAlert).shortageCount >= 3,
            onRetry: () {},
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      final shape = card.shape as RoundedRectangleBorder;
      final border = shape.side;
      expect(border.color.a, greaterThan(0.4));
    });
  });
}
