import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/tools/extra_tools.dart';
import 'package:naboo/services/permission_service.dart';

import 'fake_shop_data.dart';

bool _none(String _) => false;

void main() {
  late FakeShopData data;
  late AssistantToolRegistry reg;
  final now = DateTime(2026, 11, 24, 10);
  final owner = AssistantToolContext(
    isOwner: true,
    can: _none,
    level: AssistantLevel.full,
    now: now,
    userName: 'المالك',
  );
  AssistantToolContext staff(Set<String> perms, {String name = 'علي'}) =>
      AssistantToolContext(isOwner: false, can: perms.contains, level: AssistantLevel.full, now: now, userName: name);

  setUp(() {
    data = FakeShopData();
    reg = AssistantToolRegistry(tools: buildExtraTools(data, canOpen: (_) => true));
  });

  test('م1-20 reorder_suggest: المعدل من آخر 30 يوماً، والأقرب للنفاد أولاً', () async {
    data.sold = [
      {'id': 1, 'name': 'توتال', 'sold_qty': 60, 'qty': 12, 'unit': 'لتر', 'days_of_cover': 6.0, 'reorder_qty': 48},
      {'id': 4, 'name': 'فلتر', 'sold_qty': 30, 'qty': 3, 'unit': 'قطعة', 'days_of_cover': 3.0, 'reorder_qty': 27},
      {'id': 3, 'name': 'شل', 'sold_qty': 1, 'qty': 20, 'unit': 'لتر', 'days_of_cover': 600.0, 'reorder_qty': 0},
    ];
    final r = await reg.execute('reorder_suggest', {}, owner);
    final sold = r.rows.where((x) => x['basis'] == null).toList();
    expect(sold.map((x) => x['name']), ['فلتر', 'توتال']);
    expect(sold.last['suggest_qty'], 48);
    // الناقص بلا مبيعات يأتي بعدها، ليرجع فوق حدّه (ت4.8).
    final idle = r.rows.where((x) => x['basis'] == 'below_threshold_no_sales').toList();
    expect(r.rows.take(2).map((x) => x['name']), ['فلتر', 'توتال']);
    for (final x in idle) {
      expect((x['qty']! as num) <= (x['threshold']! as num), isTrue);
      expect(x['suggest_qty'], (x['threshold']! as num) - (x['qty']! as num) + 1);
    }
    expect(data.salesPeriods.single.days, 30);
    final oil = await reg.execute('reorder_suggest', {'kind': 'oil'}, owner);
    expect(oil.rows.first['name'], 'توتال');
    expect(oil.rows.every((x) => x['name'] != 'فلتر'), isTrue);
  });

  test('م1-21 due_customers: آخر زيارة + مدة المتابعة، والمتأخر أولاً', () async {
    data.delay = 90;
    data.visits = [
      {'plate': 'أ', 'customer': 'متأخر', 'date': '2026-08-01'},
      {'plate': 'ب', 'customer': 'بعد يومين', 'date': '2026-08-28'},
      {'plate': 'ج', 'customer': 'بعيد', 'date': '2026-10-01'},
    ];
    final r = await reg.execute('due_customers', {}, staff({PermissionKeys.customersView}));
    expect(r.rows.map((x) => x['customer']), ['متأخر', 'بعد يومين']);
    expect(r.rows.first['overdue_days'], 25);
    expect(r.rows.first['due_date'], '2026-10-30');
    expect(r.rows.any((x) => x.containsKey('phone')), isFalse);
  });

  test('م1-22 compare_periods: الفرق يطابق مجموع القنوات للفترتين', () async {
    data.salesByKey = {
      'this_month': [
        {'name': 'توتال', 'amount_fils': 900},
      ],
      'last_month': [
        {'name': 'توتال', 'amount_fils': 300},
      ],
    };
    final r = await reg.execute('compare_periods', {'a': 'this_month', 'b': 'last_month'}, owner);
    expect(r.rows.first['count'], 20);
    expect(r.extra['count_diff'], 0);
    final moves = r.extra['product_moves']! as List;
    expect((moves.single as Map)['a_fils'], 900);
    expect((await reg.execute('compare_periods', {'a': 'today', 'b': 'custom'}, owner)).error, 'bad_args:period');
  });

  test('م1-23 account_audit: للمالك فقط، وكل فحص يلتقط حالته', () async {
    data.items.add({'id': 9, 'name': 'زيت سالب', 'kind': 'oil', 'qty': -2, 'buy_price_fils': 0});
    data.cards = [
      {'id': 1, 'plate': 'قديمة', 'date': '2026-11-10'},
      {'id': 2, 'plate': 'جديدة', 'date': '2026-11-23'},
    ];
    data.sold = [
      {'name': 'خاسر', 'sold_qty': 1, 'profit_fils': -500},
    ];
    final denied = await reg.execute('account_audit', {}, staff({PermissionKeys.ownerKpiFinancial}));
    expect(denied.error, 'forbidden');
    final r = await reg.execute('account_audit', {}, owner);
    final by = {for (final x in r.rows) x['check']: x};
    expect(by['negative_stock']!['count'], 1);
    expect(by['no_buy_price']!['count'], 1);
    expect(by['sold_under_cost']!['examples'], ['خاسر']);
    expect(by['old_pending_cards']!['count'], 1);
    expect(by['old_debts']!['ok'], isTrue);
  });

  group('م1-25 الحاسبة: عشرون حالة تطابق الحساب اليدوي', () {
    final cases = <(String, Map<String, Object?>, String, num)>[
      ('liter_price_from_bulk', {'bulk_price_iqd': 200000, 'liters': 20}, 'liter_price_fils', 10000000),
      ('liter_price_from_bulk', {'bulk_price_iqd': 1000000, 'liters': 208}, 'liter_price_fils', 4807692),
      ('liter_price_from_bulk', {'bulk_price_iqd': 45000, 'liters': 4}, 'liter_price_fils', 11250000),
      ('liter_price_from_bulk', {'bulk_price_iqd': '٦٠٠٠٠', 'liters': 5}, 'liter_price_fils', 12000000),
      ('liter_price_from_bulk', {'bulk_price_iqd': 3500, 'liters': 1}, 'liter_price_fils', 3500000),
      ('bottles_for_capacity', {'capacity_l': 4.2, 'bottle_l': 1}, 'bottles', 5),
      ('bottles_for_capacity', {'capacity_l': 4, 'bottle_l': 1}, 'bottles', 4),
      ('bottles_for_capacity', {'capacity_l': 6.5, 'bottle_l': 4}, 'bottles', 2),
      ('bottles_for_capacity', {'capacity_l': 3.5, 'bottle_l': 0.5}, 'bottles', 7),
      ('bottles_for_capacity', {'capacity_l': 4.2, 'bottle_l': 1}, 'leftover_l', 0.8),
      ('next_change_km', {'odometer': 120000, 'interval_km': 5000}, 'next_km', 125000),
      ('next_change_km', {'odometer': 98500, 'interval_km': 7500}, 'next_km', 106000),
      ('next_change_km', {'odometer': '١٥٠٠٠٠', 'interval_km': 10000}, 'next_km', 160000),
      ('next_change_km', {'odometer': 0, 'interval_km': 3000}, 'next_km', 3000),
      ('full_change_total', {'liters': 4, 'liter_price_iqd': 12000}, 'total_fils', 48000000),
      ('qty_times_price', {'qty': 4, 'unit_price_iqd': 7000}, 'total_fils', 28000000),
      ('qty_times_price', {'qty': 3, 'unit_price_iqd': '28,000'}, 'total_fils', 84000000),
      ('percent_off', {'amount_iqd': 28000, 'percent': 10}, 'after_fils', 25200000),
      ('percent_off', {'amount_iqd': 28000, 'percent': 10}, 'discount_fils', 2800000),
      ('full_change_total', {'liters': 4, 'liter_price_iqd': 12000, 'filter_price_iqd': 5000}, 'total_fils', 53000000),
      (
        'full_change_total',
        {'liters': 4.5, 'liter_price_iqd': 10000, 'filter_price_iqd': 5000, 'labor_iqd': 5000},
        'total_fils',
        55000000,
      ),
      ('full_change_total', {'liters': 5, 'liter_price_iqd': 9000, 'labor_iqd': 3000}, 'oil_fils', 45000000),
      ('full_change_total', {'liters': 3.5, 'liter_price_iqd': 15000}, 'total_fils', 52500000),
      ('full_change_total', {'liters': 6, 'liter_price_iqd': 8500, 'filter_price_iqd': 7000}, 'filter_fils', 7000000),
    ];
    for (final (i, c) in cases.indexed) {
      test('حالة ${i + 1}: ${c.$1}', () async {
        final r = await reg.execute('calc', {'fn': c.$1, 'args': c.$2}, owner);
        expect(r.ok, isTrue, reason: r.error);
        expect(r.rows.single[c.$3], c.$4);
      });
    }

    test('معطى ناقص أو صفر يُرفض باسمه', () async {
      final r = await reg.execute('calc', {
        'fn': 'bottles_for_capacity',
        'args': {'capacity_l': 4, 'bottle_l': 0},
      }, owner);
      expect(r.error, 'bad_args:bottle_l');
      expect(
        (await reg.execute('calc', {
          'fn': 'next_change_km',
          'args': {'odometer': 1},
        }, owner)).error,
        'bad_args:interval_km',
      );
    });
  });

  test('م1-27 my_performance: الموظف يرى بطاقاته فقط مهما كتب', () async {
    data.cards = [
      {'id': 1, 'technician': 'علي'},
      {'id': 2, 'technician': 'حسن'},
      {'id': 3, 'technician': 'علي'},
    ];
    final r = await reg.execute('my_performance', {'name': 'حسن'}, staff({}));
    expect(r.rows.single['cards'], 2);
    expect(r.rows.single['rating_avg'], 5.0);
    final h = await reg.execute('my_performance', {}, staff({}, name: 'حسن'));
    expect(h.rows.single['cards'], 1);
  });

  test('م1-28 day_summary: الأقسام تتغير بالصلاحية', () async {
    final full = await reg.execute('day_summary', {}, owner);
    expect(full.extra['sections'], ['sales', 'cash', 'cards', 'stock', 'debts']);
    final tech = await reg.execute('day_summary', {}, staff({}));
    expect(tech.extra['sections'], ['cards']);
    expect(tech.rows.single.containsKey('sales_fils'), isFalse);
    final cashier = await reg.execute('day_summary', {}, staff({PermissionKeys.cashView}));
    expect(cashier.extra['sections'], ['cash', 'cards']);
  });

  test('م1-29 purchase_history: للمالي فقط، والاسم الواضح يكفي', () async {
    final no = await reg.execute('purchase_history', {'name': 'شل'}, staff({PermissionKeys.inventoryView}));
    expect(no.needs, PermissionKeys.ownerKpiFinancial);
    final r = await reg.execute('purchase_history', {'name': 'شل 10w40'}, owner);
    expect(r.rows.single['supplier'], 'مورد');
    expect(r.extra['product'], 'زيت شل 10W-40');
  });

  test('م1-31 naboo_account: الاشتراك ورصيد واتساب', () async {
    final r = await reg.execute('naboo_account', {}, owner);
    expect(r.rows.single['days_left'], 40);
    expect((await reg.execute('naboo_account', {}, staff({}))).needs, PermissionKeys.settingsApp);
  });
}
