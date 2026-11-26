import 'package:naboo/assistant/data/assistant_period.dart';
import 'package:naboo/assistant/data/assistant_shop_data.dart';

/// بيانات محل وهمية لأدوات المساعد.
class FakeShopData implements AssistantShopData {
  final items = <Map<String, Object?>>[
    _p(1, 'زيت توتال 5W-30 تخليقي', 'oil', 12, 'لتر', 14000, 10000, 5, viscosity: '5W-30', brand: 'Total'),
    _p(2, 'زيت موبيل 5w30', 'oil', 3, 'لتر', 15000, 11000, 4),
    _p(3, 'زيت شل 10W-40', 'oil', 20, 'لتر', 9000, 6500, 5),
    _p(4, 'فلتر زيت كورولا', 'filter', 0, 'قطعة', 5000, 3000, 2),
    _p(5, 'زيت هيدروليك ATF', 'hydraulic', 8, 'لتر', 7000, 5000, 2),
    _p(6, 'فلتر زيت النترا', 'filter', 6, 'قطعة', 5000, 3000, 2),
  ];
  AssistantPeriod? lastPeriod;
  String? lastStatus;

  static Map<String, Object?> _p(
    int id,
    String name,
    String kind,
    num qty,
    String unit,
    int sell,
    int buy,
    num th, {
    String? viscosity,
    String? brand,
  }) => {
    'id': id,
    'name': name,
    'kind': kind,
    'qty': qty,
    'unit': unit,
    'sell_price_fils': sell * 1000,
    'buy_price_fils': buy * 1000,
    'threshold': th,
    'viscosity': ?viscosity,
    'brand': ?brand,
  };

  @override
  Future<List<Map<String, Object?>>> stockItems() async => items;
  @override
  Future<List<Map<String, Object?>>> lowStock() async => [
    {'id': 4, 'name': 'فلتر زيت كورولا', 'qty': 0, 'kind': 'filter', 'alert': 'out'},
    {'id': 2, 'name': 'زيت موبيل 5w30', 'qty': 3, 'kind': 'oil', 'alert': 'low'},
  ];
  @override
  Future<int?> productIdByBarcode(String code) async => code == '6281000000017' ? 2 : null;

  @override
  Future<Map<String, Object?>?> productDetail(int id) async => {
    ...items.firstWhere((x) => x['id'] == id),
    'warehouses': [
      {'warehouse': 'الرئيسي', 'qty': 10},
    ],
  };
  @override
  Future<List<Map<String, Object?>>> oilCards({
    int? id,
    String? plate,
    String? customer,
    AssistantPeriod? period,
    String status = 'any',
    int limit = 20,
  }) async {
    lastPeriod = period;
    lastStatus = status;
    return cards;
  }

  @override
  Future<List<Map<String, Object?>>> carVisits({String? plate, int? customerId, int limit = 5}) async => [
    {'id': 9, 'oil': '5W-30', 'odometer': 120000, 'next_odometer': 125000, 'date': '2026-11-01'},
    {'id': 8, 'oil': '5W-30', 'odometer': 115000, 'next_odometer': 120000, 'date': '2026-08-01'},
  ];
  @override
  Future<Map<String, Object?>> sales(AssistantPeriod period, String channel) async => switch (channel) {
    'oil' => {'count': 10, 'total_fils': 500000000, 'cost_fils': 300000000},
    'direct' => {'count': 4, 'total_fils': 100000000, 'returns': 1, 'returns_fils': 5000000},
    _ => {'count': 6, 'total_fils': 60000000},
  };
  @override
  Future<List<Map<String, Object?>>> productSales(AssistantPeriod period) async {
    salesPeriods.add(period);
    return salesByKey[period.key] ?? sold;
  }

  final salesPeriods = <AssistantPeriod>[];
  Map<String, List<Map<String, Object?>>> salesByKey = {};
  List<Map<String, Object?>> sold = [
    {'id': 1, 'name': 'أ', 'sold_qty': 5, 'amount_fils': 1000, 'profit_fils': 300, 'unit': 'لتر'},
    {'id': 3, 'name': 'ب', 'sold_qty': 0, 'amount_fils': 0, 'unit': 'لتر'},
    {'id': 4, 'name': 'ج', 'sold_qty': 2, 'amount_fils': 9000, 'profit_fils': 100, 'unit': 'قطعة'},
  ];
  @override
  Future<Map<String, Object?>> debtTotals() async => {'open_total_fils': 75000000, 'debtors': 2};
  @override
  Future<List<Map<String, Object?>>> debtors() async => [
    {'customer': 'ابو علي', 'customer_id': 1, 'amount_fils': 50000000, 'invoices': 2},
    {'customer': 'حسن', 'amount_fils': 25000000, 'invoices': 1},
  ];
  @override
  Future<Map<String, Object?>> cash(AssistantPeriod period) async => {
    'balance_fils': 1,
    'in_fils': 2,
    'out_fils': 3,
    'expenses_fils': 4,
  };
  @override
  Future<Map<String, Object?>> shift() async => {
    'open_shift': true,
    'staff': ['علي'],
    'invoices': 5,
  };
  @override
  Future<List<Map<String, Object?>>> ratingsByEmployee() async => [
    {'employee': 'علي', 'count': 3, 'avg': 5.0},
    {'employee': 'حسن', 'count': 1, 'avg': 1.0},
    {'employee': 'جديد', 'count': 0, 'avg': 0.0},
  ];
  @override
  Future<Map<String, Object?>> whatsapp(AssistantPeriod period) async => {'connected': true, 'sent': 10};
  @override
  Future<List<Map<String, Object?>>> customers(String query, {int limit = 8}) async => [
    {'id': 1, 'name': 'ابو علي', 'phone': '07700000000', 'open_debt_fils': 50000000},
  ];

  List<Map<String, Object?>> visits = [];
  int delay = 90;
  List<Map<String, Object?>> cards = [
    {'id': 7, 'plate': '12345 بغداد', 'status': 'pending'},
  ];
  List<Map<String, Object?>> techs = [];

  @override
  Future<List<Map<String, Object?>>> latestVisitPerCar() async => visits;
  @override
  Future<int> followupDelayDays() async => delay;
  @override
  Future<List<Map<String, Object?>>> technicians(AssistantPeriod period) async => techs;
  @override
  Future<List<Map<String, Object?>>> purchases(int productId, {int limit = 10}) async => [
    {'date': '2026-11-01', 'supplier': 'مورد', 'qty': 20, 'unit_price_fils': 10000000},
  ];
  @override
  Future<Map<String, Object?>> nabooAccount() async => {'status': 'active', 'days_left': 40, 'wa_balance': 900};
}
