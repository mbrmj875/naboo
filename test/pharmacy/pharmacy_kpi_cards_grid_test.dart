import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_owner_dashboard.dart';
import 'package:naboo/verticals/pharmacy/widgets/pharmacy_kpi_cards_grid.dart';

void main() {
  group('PharmacyKpiCardsGrid', () {
    testWidgets('renders 12 KPI cards from dashboard snapshot', (tester) async {
      final dashboard = PharmacyOwnerDashboard(
        expiringSoonCount: 3,
        outOfStockCount: 1,
        topDrugs: [],
        originatorQty: 10,
        genericQty: 5,
        inventoryValueFils: 250000,
        dailyProfitFils: 12000,
        monthlyProfitFils: 180000,
        topCustomers: [],
        bestSupplierMatches: 4,
        inventoryTurnover: 1.25,
        avgTicketFils: 15000,
        totalReceivableFils: 50000,
        totalPayableFils: 20000,
        calculatedAt: DateTime(2026, 6, 11),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: PharmacyKpiCardsGrid(dashboard: dashboard),
              ),
            ),
          ),
        ),
      );

      expect(find.text('أدوية تنتهي قريباً'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('المديونية الشاملة'), findsOneWidget);
      expect(find.text('70 د.ع'), findsOneWidget);
    });
  });
}
