import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';

void main() {
  group('Owner KPI models', () {
    test('CashSummary holds fils fields', () {
      const summary = CashSummary(
        balanceFils: 1000000,
        todayInFils: 50000,
        todayOutFils: 10000,
      );
      expect(summary.balanceFils, 1000000);
      expect(summary.todayInFils, 50000);
    });

    test('InventoryValueKpi holds aggregate fields', () {
      const kpi = InventoryValueKpi(totalCostFils: 2500000, productCount: 12);
      expect(kpi.productCount, 12);
    });
  });
}
