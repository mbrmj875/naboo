/// بيانات المحل النموذجي لمساعد نابو (م0-13، ق54).
///
/// أسماء وأرقام غير حقيقية، مرتبة للتصوير والاختبار. تطابق نتائج الأدوات
/// الجاهزة في `test/assistant/golden/cases.json` حتى تكون الحالات قابلة
/// للفحص على الهاتف نفسه في الاختبار النهائي.
///
/// لا تُستعمل إلا من نسخة الاختبار (`com.basra.storemanager.qa`) عبر
/// البذّار في م7-5. المحل يُعلَّم `is_demo` في `assistant_tenant_settings`
/// فلا يدخل التعلّم ولا يُحسب عليه سقف.
library;

class DemoProduct {
  const DemoProduct({
    required this.name,
    required this.kind,
    required this.qty,
    required this.unit,
    required this.sellIqd,
    required this.buyIqd,
    required this.lowThreshold,
    this.brand,
    this.viscosity,
    this.barcode,
  });

  final String name;

  /// oil | hydraulic | filter | general
  final String kind;
  final num qty;
  final String unit;
  final int sellIqd;
  final int buyIqd;
  final num lowThreshold;
  final String? brand;
  final String? viscosity;
  final String? barcode;
}

class DemoCustomer {
  const DemoCustomer(this.name, this.phone, this.plate, this.car);
  final String name;

  /// أرقام من نطاق غير مخصص، لا تصل لأحد.
  final String phone;
  final String plate;
  final String car;
}

class DemoOilVisit {
  const DemoOilVisit({
    required this.plate,
    required this.daysAgo,
    required this.odometer,
    required this.nextOdometer,
    required this.oilName,
    required this.liters,
    required this.technician,
    this.pending = false,
  });

  final String plate;
  final int daysAgo;
  final int odometer;
  final int nextOdometer;
  final String oilName;
  final num liters;
  final String technician;
  final bool pending;
}

abstract final class DemoShopData {
  static const shopName = 'محل نابو النموذجي';
  static const ownerName = 'أبو مصطفى';

  /// الحسابات الأربعة (م7-5). المستوى يطابق ق48.
  static const staff = <({String name, String role, String assistant})>[
    (name: 'سجاد', role: 'staff_full_no_finance', assistant: 'full'),
    (name: 'حيدر', role: 'technician', assistant: 'guide'),
    (name: 'كرار', role: 'staff_no_assistant', assistant: 'none'),
  ];

  static const products = <DemoProduct>[
    DemoProduct(
      name: 'زيت توتال 5W-30 4 لتر',
      kind: 'oil',
      brand: 'Total',
      viscosity: '5W-30',
      qty: 12,
      unit: 'عبوة',
      sellIqd: 28000,
      buyIqd: 22000,
      lowThreshold: 4,
      barcode: '3425901027683',
    ),
    DemoProduct(
      name: 'زيت موبيل 5W-30 1 لتر',
      kind: 'oil',
      brand: 'Mobil',
      viscosity: '5W-30',
      qty: 3,
      unit: 'عبوة',
      sellIqd: 8000,
      buyIqd: 6000,
      lowThreshold: 6,
    ),
    DemoProduct(
      name: 'زيت شل 10W-40 4 لتر',
      kind: 'oil',
      brand: 'Shell',
      viscosity: '10W-40',
      qty: 9,
      unit: 'عبوة',
      sellIqd: 24000,
      buyIqd: 19000,
      lowThreshold: 3,
    ),
    DemoProduct(
      name: 'زيت كاسترول 0W-20 4 لتر',
      kind: 'oil',
      brand: 'Castrol',
      viscosity: '0W-20',
      qty: 5,
      unit: 'عبوة',
      sellIqd: 32000,
      buyIqd: 26000,
      lowThreshold: 2,
    ),
    DemoProduct(
      name: 'زيت هيدروليك ATF',
      kind: 'hydraulic',
      qty: 0,
      unit: 'لتر',
      sellIqd: 6000,
      buyIqd: 4500,
      lowThreshold: 4,
    ),
    DemoProduct(
      name: 'فلتر زيت تويوتا 90915',
      kind: 'filter',
      qty: 1,
      unit: 'قطعة',
      sellIqd: 7000,
      buyIqd: 5000,
      lowThreshold: 5,
      barcode: '4979477900015',
    ),
    DemoProduct(
      name: 'فلتر هواء كيا',
      kind: 'filter',
      qty: 7,
      unit: 'قطعة',
      sellIqd: 9000,
      buyIqd: 6500,
      lowThreshold: 3,
    ),
    DemoProduct(
      name: 'فلتر هواء هيونداي',
      kind: 'filter',
      qty: 4,
      unit: 'قطعة',
      sellIqd: 9000,
      buyIqd: 6500,
      lowThreshold: 3,
    ),
    DemoProduct(
      name: 'سائل تبريد أخضر 4 لتر',
      kind: 'general',
      qty: 6,
      unit: 'عبوة',
      sellIqd: 10000,
      buyIqd: 7500,
      lowThreshold: 2,
    ),
    DemoProduct(
      name: 'زيت فرامل DOT4',
      kind: 'general',
      qty: 8,
      unit: 'عبوة',
      sellIqd: 5000,
      buyIqd: 3500,
      lowThreshold: 2,
    ),
  ];

  static const customers = <DemoCustomer>[
    DemoCustomer('ابو علي', '07700000101', '12345 ب', 'تويوتا كورولا 2016'),
    DemoCustomer('مرتضى', '07700000102', '5555 د', 'هيونداي النترا 2019'),
    DemoCustomer('حسين', '07700000103', '777 ج', 'كيا سيراتو 2018'),
    DemoCustomer('ابو احمد', '07700000104', '4321 أ', 'تويوتا لاندكروزر 2014'),
    DemoCustomer('علي كاظم', '07700000105', '2468 هـ', 'نيسان صني 2020'),
  ];

  static const oilVisits = <DemoOilVisit>[
    DemoOilVisit(
      plate: '12345 ب',
      daysAgo: 180,
      odometer: 113000,
      nextOdometer: 118000,
      oilName: 'زيت توتال 5W-30 4 لتر',
      liters: 4,
      technician: 'حيدر',
    ),
    DemoOilVisit(
      plate: '12345 ب',
      daysAgo: 82,
      odometer: 118000,
      nextOdometer: 123000,
      oilName: 'زيت توتال 5W-30 4 لتر',
      liters: 4,
      technician: 'حيدر',
    ),
    DemoOilVisit(
      plate: '5555 د',
      daysAgo: 40,
      odometer: 64000,
      nextOdometer: 69000,
      oilName: 'زيت شل 10W-40 4 لتر',
      liters: 4,
      technician: 'حيدر',
    ),
    DemoOilVisit(
      plate: '777 ج',
      daysAgo: 0,
      odometer: 91000,
      nextOdometer: 96000,
      oilName: 'زيت توتال 5W-30 4 لتر',
      liters: 4,
      technician: 'حيدر',
      pending: true,
    ),
    DemoOilVisit(
      plate: '4321 أ',
      daysAgo: 0,
      odometer: 210000,
      nextOdometer: 215000,
      oilName: 'زيت شل 10W-40 4 لتر',
      liters: 8,
      technician: 'حيدر',
      pending: true,
    ),
    DemoOilVisit(
      plate: '2468 هـ',
      daysAgo: 95,
      odometer: 30000,
      nextOdometer: 35000,
      oilName: 'زيت كاسترول 0W-20 4 لتر',
      liters: 4,
      technician: 'حيدر',
    ),
  ];

  /// دين مفتوح على ابو علي (حالة rep10).
  static const openDebt = (customer: 'ابو علي', amountIqd: 75000, invoices: 2);

  static const expensesToday = <({String title, int amountIqd})>[
    (title: 'كهرباء المولدة', amountIqd: 50000),
    (title: 'غداء العمال', amountIqd: 15000),
  ];

  /// غسيل اليوم.
  static const washesToday = 3;
}
