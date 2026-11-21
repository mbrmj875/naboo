import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/utils/iraqi_currency_format.dart';

void main() {
  test('open credit debt dinars convert to fils for banner display', () {
    const openDebtDinars = 66000.0;
    final fils = IqdMoney.toFils(openDebtDinars);
    expect(fils, 66000000);
    expect(
      IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils)),
      '66,000 د.ع',
    );
  });
}
