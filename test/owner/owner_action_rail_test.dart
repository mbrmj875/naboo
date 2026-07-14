import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_action_alert.dart';
import 'package:naboo/owner/widgets/owner_action_rail.dart';

void main() {
  testWidgets('OwnerActionRail renders CTA for each alert', (tester) async {
    const alerts = [
      OwnerActionAlert(
        id: 'test',
        priority: OwnerAlertPriority.high,
        titleAr: 'نواقص',
        messageAr: '3 أصناف ناقصة',
        ctaLabelAr: 'PDF طلبية',
        actionKind: OwnerActionKind.purchasePdf,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerActionRail(
            alerts: alerts,
            isLoading: false,
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('إجراءات مطلوبة'), findsOneWidget);
    expect(find.text('PDF طلبية'), findsOneWidget);
    expect(find.text('3 أصناف ناقصة'), findsOneWidget);
  });

  testWidgets('OwnerActionRail hidden when no alerts and not loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OwnerActionRail(
            alerts: [],
            isLoading: false,
            onAction: _noop,
          ),
        ),
      ),
    );

    expect(find.text('إجراءات مطلوبة'), findsNothing);
  });
}

void _noop(OwnerActionKind _) {}
