import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/data/assistant_period.dart';
import 'package:naboo/assistant/data/device_shop_data.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/utils/stock_quantity_kind.dart';

import '../integration/helpers/vertical_test_harness.dart';

/// الاستعلامات على مخطط القاعدة الحقيقي (sqflite ffi)، لا على بيانات وهمية.
void main() {
  setUpAll(initVerticalTestEnvironment);
  setUp(() async {
    await resetTestDatabase();
    TenantContext.instance.set('assistant-device-data-test');
  });

  Future<int> product(String name, {num qty = 0, num sell = 0, num buy = 0, num th = 0, int kind = 0}) async {
    final db = await DatabaseHelper().database;
    return db.insert('products', {
      'name': name,
      'qty': qty,
      'sellPrice': sell,
      'buyPrice': buy,
      'lowStockThreshold': th,
      'stockBaseKind': kind,
      'isActive': 1,
      'tenantId': TenantContextService.instance.activeTenantId,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  test('المخزون والنواقص من القاعدة: الأسعار بالفلس والنوع من الوحدة والاسم', () async {
    await product('زيت توتال 5W-30', qty: 12.5, sell: 14000, buy: 10000, th: 5, kind: StockBaseKind.volumeLiter);
    await product('فلتر زيت كورولا', qty: 0, sell: 5000, th: 2);
    await product('زيت هيدروليك ATF', qty: 1, sell: 7000, th: 2, kind: StockBaseKind.volumeLiter);

    final data = DeviceShopData();
    final items = await data.stockItems();
    final byName = {for (final x in items) x['name']: x};
    expect(byName['زيت توتال 5W-30']!['sell_price_fils'], 14000000);
    expect(byName['زيت توتال 5W-30']!['unit'], 'لتر');
    expect(byName['زيت توتال 5W-30']!['kind'], 'oil');
    expect(byName['فلتر زيت كورولا']!['kind'], 'filter');
    expect(byName['زيت هيدروليك ATF']!['kind'], 'hydraulic');

    final low = await data.lowStock();
    expect(low.map((x) => x['name']), containsAll(['فلتر زيت كورولا', 'زيت هيدروليك ATF']));
    expect(low.firstWhere((x) => x['name'] == 'فلتر زيت كورولا')['alert'], 'out');

    final id = byName['زيت توتال 5W-30']!['id']! as int;
    expect((await data.productDetail(id))!['warehouses'], isA<List<Object?>>());
  });

  test('البطاقات والصندوق والديون تعمل على قاعدة فارغة بلا خطأ', () async {
    final data = DeviceShopData();
    final p = AssistantPeriod.resolve('today', now: DateTime.now())!;
    expect(await data.oilCards(status: 'pending'), isEmpty);
    expect(await data.carVisits(plate: '12345'), isEmpty);
    final cash = await data.cash(p);
    expect(cash['in_fils'], 0);
    expect((await data.debtTotals())['debtors'], 0);
    expect((await data.shift())['open_shift'], isFalse);
  });

  test('زيت أُدخل كصنف عادي يُعرف من اسمه (اختبار الهاتف 1.4)', () {
    String k(String n, [int base = 0]) => DeviceShopData.kindOf(name: n, stockBaseKind: base);
    expect(k('زيت توتال 5W-30 4 لتر'), 'oil');
    expect(k('Mobil 10w40'), 'oil');
    expect(k('دهن محرك'), 'oil');
    expect(k('زيت هيدروليك ATF'), 'hydraulic');
    expect(k('فلتر زيت تويوتا 90915'), 'filter');
    expect(k('سائل تبريد أخضر 4 لتر'), 'general');
    expect(k('زيتون'), 'general');
    expect(k('كفر 205/55R16'), 'general');
  });
}
