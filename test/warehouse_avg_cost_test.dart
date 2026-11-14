import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/utils/warehouse_avg_cost.dart';

void main() {
  test('computeWacFils — دفعتان بتكلفتين مختلفتين', () {
    // رصيد 50 لتر @ 10,000 فلس/لتر + وارد 50 لتر @ 12,000
    final wac = computeWacFils(
      beforeQtyBase: 50,
      beforeAvgFils: 10000,
      inboundQtyBase: 50,
      inboundCostPerBaseFils: 12000,
    );
    expect(wac, 11000);
  });

  test('costPerBaseFilsFromEnteredPurchase — علبة بسعر علبة', () {
    final cpf = costPerBaseFilsFromEnteredPurchase(
      enteredQty: 10,
      enteredUnitPriceIqd: 50000,
      factorToBase: 5,
    );
    expect(cpf, IqdMoney.toFils(10000));
  });
}
