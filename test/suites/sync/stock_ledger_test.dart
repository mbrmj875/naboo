// البند 4.1: كمية المخزون تتفق على كل الأجهزة.
//
// الكمية تُكتب فوق نفسها على كل جهاز، والدمج يحمي الكمية المحلية. فإذا باع
// جهازان من المنتج نفسه رأى كل جهاز مبيعه وحده.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/stock_ledger.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet f;
  const slow = Timeout(Duration(minutes: 5));

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_stock_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    f = await Fleet.create(3, tmp);
    for (final d in f.devices) {
      await f.syncDevice(d);
    }
  });

  tearDown(() async {
    f.dispose();
    CloudSyncService.instance.suppressScheduleSyncSoonForTesting = false;
    await tmp.delete(recursive: true);
  });

  Future<void> addProduct(FleetDevice d, String name, double qty) async {
    await f.activate(d);
    await seedLowStockOilProduct(DatabaseHelper(), name: name, qty: qty);
    final db = await DatabaseHelper().database;
    // المنتج المضاف مباشرة يحتاج معرفاً عاماً كما في شاشة المنتجات.
    await db.rawUpdate(
      "UPDATE products SET global_id = lower(hex(randomblob(16))), "
      "updatedAt = ? WHERE name = ? AND (global_id IS NULL OR global_id = '')",
      [DateTime.now().toUtc().toIso8601String(), name],
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  Future<int> productId(FleetDevice d, String name) async {
    final db = await f.activate(d);
    final r = await db.query('products',
        columns: ['id'], where: 'name = ?', whereArgs: [name]);
    return r.first['id'] as int;
  }

  Future<void> sell(FleetDevice d, String name, double qty,
      {bool isReturn = false}) async {
    final pid = await productId(d, name);
    await DatabaseHelper().insertInvoiceWithPolicy(
      Invoice(
        customerName: 'زبون',
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: name,
            quantity: qty,
            price: 3000,
            total: 3000 * qty,
            productId: pid,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: 3000 * qty,
        isReturned: isReturn,
      ),
      enforceStockNonZero: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  Future<Map<String, double>> qtyByDevice(String name) async {
    final out = <String, double>{};
    for (final d in f.devices) {
      final db = await f.activate(d);
      final r = await db.query('products',
          columns: ['qty'], where: 'name = ?', whereArgs: [name]);
      out[d.name] = (r.first['qty'] as num).toDouble();
    }
    return out;
  }

  test('بيع جهازين من المنتج نفسه يظهر على الجهازين', () async {
    await addProduct(f['A'], 'زيت-1', 10);
    await f.converge();
    expect((await qtyByDevice('زيت-1')).values.toSet(), {10.0});

    // دون إنترنت: كل جهاز يبيع وحده، ثم يتزامنون.
    await sell(f['A'], 'زيت-1', 2);
    await sell(f['B'], 'زيت-1', 3);
    await f.converge();

    expect(await qtyByDevice('زيت-1'), {'A': 5.0, 'B': 5.0, 'C': 5.0});
  }, timeout: slow);

  test('المرتجع على جهاز يرجع الكمية على كل الأجهزة', () async {
    await addProduct(f['A'], 'زيت-2', 10);
    await f.converge();
    await sell(f['A'], 'زيت-2', 4);
    await f.converge();
    await sell(f['C'], 'زيت-2', 1, isReturn: true);
    await f.converge();
    expect(await qtyByDevice('زيت-2'), {'A': 7.0, 'B': 7.0, 'C': 7.0});
  }, timeout: slow);

  test('تعديل الكمية مباشرة (جرد أو شاشة المنتج) يصل إلى كل الأجهزة', () async {
    await addProduct(f['A'], 'زيت-3', 10);
    await f.converge();
    final c = await f.activate(f['C']);
    await c.update('products', {'qty': 20},
        where: 'name = ?', whereArgs: ['زيت-3']);
    await f.converge();
    expect(await qtyByDevice('زيت-3'), {'A': 20.0, 'B': 20.0, 'C': 20.0});
  }, timeout: slow);

  test('أجهزة مختلفة الكمية قبل التحديث تتفق بعده', () async {
    // قبل التحديث: لا سجل على أي جهاز، فيرى كل جهاز بيعه وحده.
    for (final d in f.devices) {
      final db = await f.activate(d);
      await db.execute('DROP TRIGGER IF EXISTS trg_stock_ledger_qty');
      await db.execute('DROP TABLE IF EXISTS ${StockLedger.table}');
    }
    await addProduct(f['A'], 'زيت-4', 10);
    await f.converge();
    for (final d in f.devices) {
      final db = await f.activate(d);
      await db.execute('DROP TRIGGER IF EXISTS trg_stock_ledger_qty');
      await db.execute('DROP TABLE IF EXISTS ${StockLedger.table}');
    }
    await sell(f['A'], 'زيت-4', 2);
    await sell(f['B'], 'زيت-4', 3);
    final before = await qtyByDevice('زيت-4');
    expect(before.values.toSet().length, greaterThan(1));

    // التحديث: أول مزامنة تنشئ السجل. افتتاحية أول رافع تغلب.
    for (final d in f.devices) {
      final db = await f.activate(d);
      await StockLedger.ensureSchema(db);
    }
    await f.converge();
    await sell(f['B'], 'زيت-4', 1);
    await f.converge();
    final after = await qtyByDevice('زيت-4');
    expect(after.values.toSet(), hasLength(1), reason: '$after');
  }, timeout: slow);

  test('ضم الحركات الأقدم من 90 يوماً لا يغيّر الكمية على أي جهاز', () async {
    await addProduct(f['A'], 'زيت-5', 10);
    await f.converge();
    await sell(f['A'], 'زيت-5', 2);
    await sell(f['B'], 'زيت-5', 3);
    await f.converge();

    // كأن البيعين قبل 100 يوم، على كل الأجهزة.
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 100))
        .toIso8601String();
    for (final d in f.devices) {
      final db = await f.activate(d);
      await db.rawUpdate(
        "UPDATE ${StockLedger.table} SET created_at = ? "
        "WHERE global_id NOT LIKE 'open-%'",
        [old],
      );
    }

    // A يضم أولاً ويرفع، ثم يسحب B وC افتتاحيته ويزيلان حركاتهما القديمة.
    await f.syncDevice(f['A']);
    await f.syncDevice(f['B']);
    await f.syncDevice(f['C']);
    await f.converge();
    expect(await qtyByDevice('زيت-5'), {'A': 5.0, 'B': 5.0, 'C': 5.0});
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.rawQuery(
        "SELECT l.global_id, l.delta FROM ${StockLedger.table} l "
        "JOIN products p ON p.global_id = l.product_global_id "
        "WHERE p.name = 'زيت-5'",
      );
      expect(rows, hasLength(1), reason: 'بقيت حركات قديمة على ${d.name}');
      expect((rows.first['delta'] as num).toDouble(), 5.0);
    }

    // بيع جديد بعد الضم يُحسب كالعادة.
    await sell(f['C'], 'زيت-5', 1);
    await f.converge();
    expect(await qtyByDevice('زيت-5'), {'A': 4.0, 'B': 4.0, 'C': 4.0});
  }, timeout: slow);
}
