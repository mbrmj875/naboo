import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/widgets/owner_dashboard_kpi_grid.dart';

void main() {
  testWidgets('OwnerDashboardKpiGrid lays out children in a Wrap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 360,
              child: OwnerDashboardKpiGrid(
                children: const [
                  SizedBox(height: 48, child: Text('أ')),
                  SizedBox(height: 48, child: Text('ب')),
                  SizedBox(height: 48, child: Text('ج')),
                  SizedBox(height: 48, child: Text('د')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('أ'), findsOneWidget);
    expect(find.text('د'), findsOneWidget);
  });
}
