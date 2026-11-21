/// تسعير محفظة رسائل واتساب — وحدة 25 د.ع/رسالة (الألف الشهري = 25,000).
library;

enum WaBillingCycle { monthly, annual }

abstract final class WaMessagePricing {
  WaMessagePricing._();

  /// 25.00 د.ع للرسالة مخزَّنة ×100.
  static const int defaultUnitPriceIqdX100 = 2500;

  /// شهران مجاناً في الاشتراك السنوي (يدفع 10 أشهر).
  static const int defaultAnnualFreeMonths = 2;

  static const int defaultMinQty = 250;
  static const int defaultStepQty = 250;
  static const int defaultMaxQty = 5000;

  static int clampQty(
    int qty, {
    int minQty = defaultMinQty,
    int stepQty = defaultStepQty,
    int maxQty = defaultMaxQty,
  }) {
    var q = qty;
    if (q < minQty) q = minQty;
    if (q > maxQty) q = maxQty;
    final steps = ((q - minQty) / stepQty).round();
    return minQty + (steps * stepQty).clamp(0, maxQty - minQty);
  }

  /// شهري بالدينار الصحيح (مضاعفات 250 × 25 دائماً صحيحة).
  static int monthlyIqd(
    int qty, {
    int unitPriceIqdX100 = defaultUnitPriceIqdX100,
  }) {
    final q = clampQty(qty);
    return (q * unitPriceIqdX100) ~/ 100;
  }

  static int yearlyFullIqd(
    int qty, {
    int unitPriceIqdX100 = defaultUnitPriceIqdX100,
  }) =>
      monthlyIqd(qty, unitPriceIqdX100: unitPriceIqdX100) * 12;

  static int yearlyPayIqd(
    int qty, {
    int unitPriceIqdX100 = defaultUnitPriceIqdX100,
    int annualFreeMonths = defaultAnnualFreeMonths,
  }) {
    final monthly =
        monthlyIqd(qty, unitPriceIqdX100: unitPriceIqdX100);
    final free = annualFreeMonths.clamp(0, 11);
    return monthly * (12 - free);
  }

  static int yearlySavingsIqd(
    int qty, {
    int unitPriceIqdX100 = defaultUnitPriceIqdX100,
    int annualFreeMonths = defaultAnnualFreeMonths,
  }) {
    return yearlyFullIqd(qty, unitPriceIqdX100: unitPriceIqdX100) -
        yearlyPayIqd(
          qty,
          unitPriceIqdX100: unitPriceIqdX100,
          annualFreeMonths: annualFreeMonths,
        );
  }

  static int amountForCycle(
    int qty,
    WaBillingCycle cycle, {
    int unitPriceIqdX100 = defaultUnitPriceIqdX100,
    int annualFreeMonths = defaultAnnualFreeMonths,
  }) {
    return cycle == WaBillingCycle.annual
        ? yearlyPayIqd(
            qty,
            unitPriceIqdX100: unitPriceIqdX100,
            annualFreeMonths: annualFreeMonths,
          )
        : monthlyIqd(qty, unitPriceIqdX100: unitPriceIqdX100);
  }

  static String formatIqd(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }
}
