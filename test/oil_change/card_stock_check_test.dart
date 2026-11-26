// المرحلة 3 — فحص رصيد موحّد لكل أقسام البطاقة، وتجاوز المالك برصيد سالب.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/oil_change/services/oil_card_stock_check.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_stock_service.dart';

import 'helpers/oil_change_test_harness.dart';

Future<int> _product(String name, double qty, {int track = 1}) async {
  final db = await DatabaseHelper().database;
  return db.insert('products', {
    'tenantId': oilTestTenantId,
    'name': name,
    'qty': qty,
    'isActive': 1,
    'trackInventory': track,
    'isService': 0,
    'buyPrice': 1000,
    'sellPrice': 2000,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<double> _qty(int id) async {
  final db = await DatabaseHelper().database;
  final r = await db.query('products', where: 'id = ?', whereArgs: [id]);
  return (r.first['qty'] as num).toDouble();
}

void main() {
  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
  });

  test('رصيد كافٍ: لا نقص', () async {
    final oil = await _product('زيت 5W-30', 10);
    final filter = await _product('فلتر تويوتا', 3);
    final out = await OilCardStockCheck.shortages([
      OilStockNeed(label: 'الزيت', productId: oil, qty: 4, unit: 'لتر'),
      OilStockNeed(label: 'فلتر المحرك', productId: filter, qty: 1),
    ]);
    expect(out, isEmpty);
  });

  test('قسمان من نفس الصنف يُجمعان', () async {
    final filter = await _product('فلتر عام', 1);
    final out = await OilCardStockCheck.shortages([
      OilStockNeed(label: 'فلتر المحرك', productId: filter, qty: 1),
      OilStockNeed(label: 'فلتر الهواء', productId: filter, qty: 1),
    ]);
    expect(out, hasLength(1));
    expect(out.single.labels, ['فلتر المحرك', 'فلتر الهواء']);
    expect(out.single.needed, 2);
    expect(out.single.available, 1);
    expect(out.single.text, contains('متوفر 1 قطعة'));
  });

  test('المنتجات والفلاتر تُفحص، لا الزيت والهيدروليك فقط', () async {
    final product = await _product('منظف محرك', 0);
    final out = await OilCardStockCheck.shortages([
      OilStockNeed(label: 'منتج: منظف محرك', productId: product, qty: 2),
    ]);
    expect(out.single.productName, 'منظف محرك');
  });

  test('في التعديل يُحسب ما صُرف سابقاً من نفس الصنف', () async {
    final oil = await _product('زيت', 1);
    final out = await OilCardStockCheck.shortages([
      OilStockNeed(
        label: 'الزيت',
        productId: oil,
        qty: 4,
        credit: 4,
        unit: 'لتر',
      ),
    ]);
    expect(out, isEmpty, reason: '4 لترات صُرفت سابقاً وتعود');
  });

  test('صنف لا يتتبع المخزون لا يُمنع', () async {
    final svc = await _product('خدمة غسل', 0, track: 0);
    expect(
      await OilCardStockCheck.shortages([
        OilStockNeed(label: 'منتج', productId: svc, qty: 1),
      ]),
      isEmpty,
    );
  });

  // ق-6 (خطة المخزون): الصرف بلا رصيد يمر وينبّه، ولا يحتاج رمز المالك.
  test('الصرف بلا رصيد يمر ويصير الرصيد سالباً', () async {
    final oil = await _product('زيت قليل', 1);
    final vid = await OilChangeStockService.instance.issueForOilChangeOrder(
      orderId: 900,
      productId: oil,
      liters: 4,
      warehouseId: 0,
    );
    expect(vid, greaterThan(0));
    expect(await _qty(oil), -3);
  });
}
