import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/verticals/oil_change/services/wa_message_pricing.dart';

void main() {
  group('WaMessagePricing', () {
    test('1000 monthly is 25000', () {
      expect(WaMessagePricing.monthlyIqd(1000), 25000);
    });

    test('stepper clamps to multiples of 250', () {
      expect(WaMessagePricing.clampQty(300), 250);
      expect(WaMessagePricing.clampQty(400), 500);
      expect(WaMessagePricing.clampQty(1000), 1000);
    });

    test('annual is two free months', () {
      expect(WaMessagePricing.yearlyFullIqd(1000), 300000);
      expect(WaMessagePricing.yearlyPayIqd(1000), 250000);
      expect(WaMessagePricing.yearlySavingsIqd(1000), 50000);
    });

    test('250 monthly is 6250', () {
      expect(WaMessagePricing.monthlyIqd(250), 6250);
      expect(WaMessagePricing.yearlyPayIqd(250), 62500);
    });
  });
}
