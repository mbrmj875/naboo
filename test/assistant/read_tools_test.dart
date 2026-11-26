import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/data/assistant_period.dart';
import 'package:naboo/assistant/data/oil_query_normalize.dart';
import 'package:naboo/assistant/tools/read_tools.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/permission_service.dart';

import 'fake_shop_data.dart';

bool _none(String _) => false;

void main() {
  late FakeShopData data;
  late AssistantToolRegistry reg;
  var canOpenLog = true;
  final now = DateTime(2026, 11, 24, 10); // ثلاثاء
  final owner = AssistantToolContext(isOwner: true, can: _none, level: AssistantLevel.full, now: now);
  AssistantToolContext staff(Set<String> perms) =>
      AssistantToolContext(isOwner: false, can: perms.contains, level: AssistantLevel.full, now: now);

  setUp(() {
    data = FakeShopData();
    canOpenLog = true;
    reg = AssistantToolRegistry(tools: buildReadTools(data, canOpen: (_) => canOpenLog));
  });

  group('الفترات (4.3)', () {
    test('الأسبوع يبدأ السبت، والشهر الماضي كاملاً', () {
      final w = AssistantPeriod.resolve('this_week', now: now)!;
      expect(w.range.from, DateTime(2026, 11, 21));
      expect(w.days, 4);
      final lw = AssistantPeriod.resolve('last_week', now: now)!;
      expect([lw.range.from, lw.range.to], [DateTime(2026, 11, 14), DateTime(2026, 11, 20)]);
      final lm = AssistantPeriod.resolve('last_month', now: now)!;
      expect([lm.range.from, lm.range.to], [DateTime(2026, 10, 1), DateTime(2026, 10, 31)]);
    });

    test('المخصص يحتاج تاريخين صحيحين بالترتيب', () {
      expect(AssistantPeriod.resolve('custom', from: '2026-11-01', to: '2026-11-10', now: now)!.days, 10);
      expect(AssistantPeriod.resolve('custom', from: '2026-11-10', to: '2026-11-01', now: now), isNull);
      expect(AssistantPeriod.resolve('custom', from: '2026-02-30', to: '2026-03-01', now: now), isNull);
      expect(AssistantPeriod.resolve('someday', now: now), isNull);
    });
  });

  test('م1-7: خمس عشرة صيغة لـ5W-30 تعطي النتيجة نفسها', () {
    const forms = [
      '5W-30',
      '5w30',
      '5W30',
      '5 w 30',
      '5w-30',
      '5W/30',
      '5-30',
      '5 30',
      '٥ دبليو ٣٠',
      '٥w٣٠',
      'دهن 5-30',
      'زيت 5W-30',
      '5 دبليو 30',
      '5و30',
      'الدهن ٥-٣٠',
    ];
    for (final f in forms) {
      expect(OilQueryNormalize.viscosityOf(f), '5W-30', reason: f);
    }
    expect(OilQueryNormalize.viscosityOf('فلتر كورولا 2018'), isNull);
    expect(OilQueryNormalize.viscosityOf('30 5'), isNull);
    expect(OilQueryNormalize.normalize('دهن 5-30 توتال'), '5W-30 توتال');
  });

  group('أدوات المخزون (م1-5)', () {
    test('stock_search: الصيغ المختلفة تجد الصنفين، وسعر الشراء لا يصل لغير المالي', () async {
      final r = await reg.execute('stock_search', {'query': 'دهن ٥ دبليو ٣٠'}, staff({PermissionKeys.inventoryView}));
      expect(r.ok, isTrue);
      expect(r.rows.map((x) => x['id']), unorderedEquals([1, 2]));
      expect(r.rows.every((x) => !x.containsKey('buy_price_fils')), isTrue);
      expect(r.rows.firstWhere((x) => x['id'] == 2)['alert'], 'low');
      final o = await reg.execute('stock_search', {'query': '5W30'}, owner);
      expect(o.rows.first.containsKey('buy_price_fils'), isTrue);
    });

    test('stock_search: لزوجة مختلفة لا تُقدَّم، والنوع يصفّي، ولا شيء = no_match', () async {
      final r = await reg.execute('stock_search', {'query': '10w40'}, owner);
      expect(r.rows.single['id'], 3);
      final f = await reg.execute('stock_search', {'query': 'فلتر', 'kind': 'filter'}, owner);
      expect(f.rows.map((x) => x['id']), unorderedEquals([4, 6]));
      final none = await reg.execute('stock_search', {'query': '0W-20'}, owner);
      expect(none.rows, isEmpty);
      expect(none.extra['no_match'], isTrue);
    });

    test('stock_search: «زيت» وحدها تعطي كل الزيوت لا شيئاً (ت4.5)', () async {
      final r = await reg.execute('stock_search', {'query': 'زيت'}, owner);
      expect(r.rows, isNotEmpty);
      expect(r.rows.every((x) => x['kind'] == 'oil' || x['kind'] == 'hydraulic'), isTrue);
      final d = await reg.execute('stock_search', {'query': 'الدهن'}, owner);
      expect(d.rows.length, r.rows.length);
    });

    test('stock_search بلا صلاحية المخزون يسمّي الصلاحية', () async {
      final r = await reg.execute('stock_search', {'query': 'زيت'}, staff({}));
      expect(r.error, 'forbidden');
      expect(r.needs, PermissionKeys.inventoryView);
    });

    test('stock_low يصفّي بالنوع ويرتب الأقل أولاً', () async {
      final all = await reg.execute('stock_low', {}, owner);
      expect(all.rows.first['qty'], 0);
      final oil = await reg.execute('stock_low', {'kind': 'oil'}, owner);
      expect(oil.rows.single['id'], 2);
    });

    test('product_detail: بالاسم الواضح يعطي التفاصيل، والغامض يعطي أزرار اختيار', () async {
      final one = await reg.execute('product_detail', {'name': 'شل 10w40'}, owner);
      expect(one.rows.single['warehouses'], isNotEmpty);
      final amb = await reg.execute('product_detail', {'name': 'فلتر زيت'}, owner);
      expect(amb.extra['ambiguous'], isTrue);
      expect((amb.extra['candidates']! as List).length, 2);
    });
  });

  group('البطاقات والسيارة', () {
    test('oil_card_find: المعلّقة بلا فترة، وبلا مفتاح تأخذ اليوم', () async {
      await reg.execute('oil_card_find', {'status': 'pending'}, owner);
      expect(data.lastPeriod, isNull);
      await reg.execute('oil_card_find', {}, owner);
      expect(data.lastPeriod!.key, 'today');
      await reg.execute('oil_card_find', {'plate': '12345'}, owner);
      expect(data.lastPeriod, isNull);
    });

    test('بلا دخول سجل الزيت: forbidden', () async {
      canOpenLog = false;
      expect((await reg.execute('oil_card_find', {}, owner)).error, 'forbidden');
      expect((await reg.execute('car_history', {'plate': '1'}, owner)).error, 'forbidden');
      expect(AppContentRoutes.oilServicesLog, isNotEmpty);
    });

    test('car_history: الموعد القادم من آخر زيارة، واللوحة شرط', () async {
      final r = await reg.execute('car_history', {'plate': '12345 بغداد'}, owner);
      expect(r.extra['next_odometer'], 125000);
      expect((await reg.execute('car_history', {}, owner)).error, 'bad_args:missing_plate');
    });
  });

  group('التقارير والمال (م1-6)', () {
    test('sales_summary: كل القنوات تُجمع، والربح للغيار وحده وللمالي فقط', () async {
      final all = await reg.execute('sales_summary', {'period': 'today'}, owner);
      final head = all.rows.first;
      expect(head['count'], 20);
      expect(head['total_fils'], 660000000);
      expect(head['avg_fils'], 33000000);
      expect(head['returns'], 1);
      expect(head.containsKey('profit_fils'), isFalse);
      expect(all.rows.length, 4);

      final oil = await reg.execute('sales_summary', {'period': 'today', 'channel': 'oil'}, owner);
      expect(oil.rows.single['profit_fils'], 200000000);
      final noFin = await reg.execute('sales_summary', {
        'period': 'today',
        'channel': 'oil',
      }, staff({PermissionKeys.reportsAccess}));
      expect(noFin.rows.single.containsKey('profit_fils'), isFalse);
    });

    test('top_products: المباع فقط، بالمبلغ', () async {
      final r = await reg.execute('top_products', {'period': 'this_month'}, owner);
      expect(r.rows.map((x) => x['name']), ['ج', 'أ']);
    });

    test('debts_summary: الإجمالي أولاً، والزبون المحدد بلا همزات', () async {
      final r = await reg.execute('debts_summary', {'customer': 'أبو علي'}, owner);
      expect(r.rows.first['open_total_fils'], 75000000);
      expect(r.rows.last['customer'], 'ابو علي');
      expect(r.rows.length, 2);
    });

    test('cash_summary وstaff_status وwa_status بصلاحياتها', () async {
      expect((await reg.execute('cash_summary', {}, owner)).rows.single['period'], 'today');
      expect((await reg.execute('cash_summary', {}, staff({}))).needs, PermissionKeys.cashView);
      expect((await reg.execute('staff_status', {}, staff({PermissionKeys.shiftsAccess}))).ok, isTrue);
      expect((await reg.execute('wa_status', {}, owner)).rows.single['period'], 'this_month');
      expect((await reg.execute('wa_status', {}, staff({}))).needs, PermissionKeys.settingsApp);
    });

    test('ratings_summary: متوسط موزون بلا الموظف الذي لا تقييم له', () async {
      final r = await reg.execute('ratings_summary', {}, owner);
      expect(r.rows.length, 2);
      expect(r.extra['avg'], 4.0);
      expect(r.extra['count'], 4);
    });

    test('customer_find: الهاتف لا يصل أبداً', () async {
      final r = await reg.execute('customer_find', {'query': 'علي'}, owner);
      expect(r.rows.single.containsKey('phone'), isFalse);
      expect(r.rows.single['open_debt_fils'], 50000000);
    });

    test('فترة غير معروفة تُرفض قبل التنفيذ', () async {
      expect((await reg.execute('sales_summary', {'period': 'someday'}, owner)).error, startsWith('bad_args'));
    });
  });
}
