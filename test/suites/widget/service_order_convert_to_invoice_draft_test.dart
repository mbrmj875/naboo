import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/iqd_money.dart';

void main() {
  group('Service order → sale draft mapping', () {
    test('advancePaymentFils maps to advance dinars string', () {
      final advF = 12500; // 12.500 د.ع
      final din = IqdMoney.fromFils(advF);
      expect(din, closeTo(12.5, 1e-9));
      expect(din.toString(), anyOf('12.5', '12.500'));
    });
  });
}

