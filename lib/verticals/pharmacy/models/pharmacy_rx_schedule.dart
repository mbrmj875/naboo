/// تصنيف Rx/OTC — [pharmacy_product_profile.rxSchedule].
abstract class PharmacyRxSchedule {
  PharmacyRxSchedule._();

  static const otc = 'otc';
  static const rx = 'rx';
  static const monitored = 'monitored';

  static const all = [otc, rx, monitored];
}

/// فئة عمرية — [pharmacy_drug_reference.ageBand].
abstract class PharmacyAgeBand {
  PharmacyAgeBand._();

  static const children = 'children';
  static const adult = 'adult';
  static const both = 'both';

  static const all = [children, adult, both];
}
