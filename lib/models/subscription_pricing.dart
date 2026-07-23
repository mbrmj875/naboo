/// مصدر حقيقة التسعير — يطابق admin-web/lib/plan-presets.ts
abstract class SubscriptionPricingCatalog {
  static const int pricePerComputerUnitIqd = 15000;
  static const int includedPhones = 1;
  static const int minComputers = 1;
  static const int annualPaidMonths = 10;
  static const int annualCoverageMonths = 12;

  static int clampComputers(int computers) {
    final n = computers.floor();
    if (n < minComputers) return minComputers;
    return n;
  }

  static int maxDevicesForComputers(int computers) {
    return includedPhones + clampComputers(computers);
  }

  static int monthlyPriceIqd(int computers) {
    return pricePerComputerUnitIqd * clampComputers(computers);
  }

  static int annualPriceIqd(int computers) {
    return monthlyPriceIqd(computers) * annualPaidMonths;
  }

  static int priceIqd({
    required int computers,
    required SubscriptionBillingCycle cycle,
  }) {
    return cycle == SubscriptionBillingCycle.annual
        ? annualPriceIqd(computers)
        : monthlyPriceIqd(computers);
  }

  static String formatIqd(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String devicesBreakdownAr(int computers) {
    final n = clampComputers(computers);
    if (n == 1) return 'هاتف واحد + حاسوب واحد';
    if (n == 2) return 'هاتف واحد + حاسوبان';
    return 'هاتف واحد + $n حاسبات';
  }

  static bool isLegacyPlanKey(String? planKey) {
    return switch (planKey) {
      'basic' || 'pro' || 'unlimited' => true,
      _ => false,
    };
  }

  static SubscriptionBillingCycle billingCycleFromPlanKey(String? planKey) {
    final key = (planKey ?? '').toLowerCase().trim();
    if (key == 'annual') return SubscriptionBillingCycle.annual;
    return SubscriptionBillingCycle.monthly;
  }

  static int computersFromMaxDevices(int maxDevices) {
    if (maxDevices <= includedPhones) return minComputers;
    return maxDevices - includedPhones;
  }
}

enum SubscriptionBillingCycle {
  monthly,
  annual;

  String get periodSuffixAr =>
      this == SubscriptionBillingCycle.annual ? 'سنة' : 'شهر';
}
