/*
  هل الإصلاحات آمنة على حساب يعمل الآن؟
  يحاكي الجهاز الذي لم يتحدث بتعطيل الإصلاحات عليه فقط.
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

final _report = <String, Object?>{};

void main() {
  late Directory tmp;
  late Fleet f;
  const fils = 50000;
  const slow = Timeout(Duration(minutes: 5));

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_rollout_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    f = await Fleet.create(2, tmp);
    await f.syncDevice(f['A']);
    await f.syncDevice(f['B']);
  });

  tearDown(() async {
    f.dispose();
    await tmp.delete(recursive: true);
    final path = Platform.environment['BASELINE_REPORT'] ?? 'build/rollout.json';
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(_report),
    );
  });

  Future<void> sell(FleetDevice d, String plate, {int price = fils}) async {
    await f.activate(d);
    final b = ServiceOrderBuilder(OilChangeTestHarness.instance);
    final id = await b.createPending(plate: plate, agreedPriceFils: price);
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      id,
      advancePaymentFils: price,
      agreedPriceFils: price,
    );
    final order = (await b.byId(id))!;
    await OilChangeCheckoutService.instance
        .completeFromOrder(order: order, orderId: id);
  }

  Future<List<Map<String, Object?>>> cycles(int n) async {
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < n; i++) {
      final row = <String, Object?>{};
      for (final d in f.devices) {
        await f.activate(d);
        final m =
            await OilChangeTestHarness.instance.dbHelper.getCashSummary();
        row['screen_${d.name}'] = m['balance'];
      }
      await f.converge();
      for (final d in f.devices) {
        final db = await f.activate(d);
        final r = await db.rawQuery(
          'SELECT COUNT(*) c, COALESCE(SUM(amountFils),0) s FROM cash_ledger WHERE deleted_at IS NULL',
        );
        row['rows_${d.name}'] = r.first['c'];
        row['fils_${d.name}'] = r.first['s'];
      }
      out.add(row);
    }
    return out;
  }

  test('ت1: نسخة جديدة مع قديمة: الجديد لا يفقد، والقديم يتعافى بعد تحديثه', () async {
    f['B'].legacy = true;
    final expected = <String>{};
    for (var i = 0; i < 6; i++) {
      final a = 'MIX-A$i', b = 'MIX-B$i';
      expected.addAll({a, b});
      await f.createCard(f['A'], a);
      await f.createCard(f['B'], b);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
    }
    await f.converge();
    final mixedA = (await f.plates(f['A'])).intersection(expected).length;
    final mixedB = (await f.plates(f['B'])).intersection(expected).length;
    f['B'].legacy = false;
    await f.converge();
    final afterA = (await f.plates(f['A'])).intersection(expected).length;
    final afterB = (await f.plates(f['B'])).intersection(expected).length;
    // الجهاز الجديد يحمل البطاقة، وأول تغيير عادي عليه يعيدها إلى الجميع.
    await f.createCard(f['A'], 'HEAL');
    expected.add('HEAL');
    await f.converge();
    final healedB = (await f.plates(f['B'])).intersection(expected).length;
    _report['t1_mixed_cards'] = {
      'expected': expected.length,
      'mixed_new_device': mixedA,
      'mixed_old_device': mixedB,
      'after_update_A': afterA,
      'after_update_B': afterB,
      'after_next_change_B': healedB,
    };
    expect(afterA, 12);
    expect(healedB, expected.length);
  }, timeout: slow);

  test('ت2: حساب عمل بالنسخة الحالية ثم تحدّث: لا يضيع شيء ويتوقف التأرجح', () async {
    f['A'].legacy = true;
    f['B'].legacy = true;
    for (var i = 0; i < 4; i++) {
      final d = i.isEven ? f['A'] : f['B'];
      await f.syncDevice(d);
      await sell(d, 'OLD-$i');
      await f.syncDevice(d);
    }
    await f.createCard(f['A'], 'OLD-C1');
    await f.syncDevice(f['A']);
    await f.syncDevice(f['B']);
    final cardsBefore = await f.plates(f['A']);
    final oldCycles = await cycles(2);
    f['A'].legacy = false;
    f['B'].legacy = false;
    final newCycles = await cycles(4);
    final cardsAfter = await f.plates(f['A']);
    final cardsAfterB = await f.plates(f['B']);
    _report['t2_upgrade_in_place'] = {
      'expected_fils': 4 * fils,
      'old_cycles': oldCycles,
      'new_cycles': newCycles,
      'cards_before': cardsBefore.length,
      'cards_after_A': cardsAfter.length,
      'cards_after_B': cardsAfterB.length,
    };
    expect(cardsAfter, containsAll(cardsBefore));
    expect(cardsAfterB, containsAll(cardsBefore));
    expect(newCycles.last['fils_A'], 4 * fils);
    expect(newCycles.last['fils_B'], 4 * fils);
    expect(newCycles[2]['rows_A'], newCycles[3]['rows_A']);
  }, timeout: slow);

  test('ت3: الرجوع إلى النسخة السابقة لا يضيع ما حُفظ', () async {
    for (var i = 0; i < 3; i++) {
      final d = i.isEven ? f['A'] : f['B'];
      await f.syncDevice(d);
      await sell(d, 'NEW-$i');
      await f.syncDevice(d);
    }
    final before = await cycles(1);
    final cards = await f.plates(f['A']);
    f['A'].legacy = true;
    f['B'].legacy = true;
    final after = await cycles(3);
    final cardsA = await f.plates(f['A']);
    final cardsB = await f.plates(f['B']);
    _report['t3_rollback'] = {
      'expected_fils': 3 * fils,
      'before': before,
      'after_rollback': after,
      'cards_before': cards.length,
      'cards_A': cardsA.length,
      'cards_B': cardsB.length,
    };
    expect(after.last['fils_A'], 3 * fils);
    expect(cardsA, containsAll(cards));
    expect(cardsB, containsAll(cards));
  }, timeout: slow);

  test('ت4: بيع على جهاز جديد وآخر قديم معاً', () async {
    f['B'].legacy = true;
    for (var i = 0; i < 4; i++) {
      final d = i.isEven ? f['A'] : f['B'];
      await f.syncDevice(d);
      await sell(d, 'MS-$i');
      await f.syncDevice(d);
    }
    final mixed = await cycles(3);
    f['B'].legacy = false;
    final updated = await cycles(3);
    _report['t4_mixed_sales'] = {
      'expected_fils': 4 * fils,
      'mixed': mixed,
      'after_update': updated,
    };
    expect(updated.last['fils_A'], 4 * fils);
    expect(updated.last['fils_B'], 4 * fils);
  }, timeout: slow);

  Future<void> seedCollision(FleetDevice d) async {
    await sell(d, 'COL-1');
    final db = await f.activate(d);
    final tid = await OilChangeTestHarness.instance.tenantId();
    final inv = (await db.rawQuery('SELECT MAX(id) m FROM invoices')).first['m'];
    await db.insert('cash_ledger', {
      'global_id': 'col-2',
      'tenantId': tid,
      'transactionType': 'sale_cash',
      'amount': 70.0,
      'amountFils': 70000,
      'invoiceId': inv,
      'createdAt': '2026-11-01T11:00:00.000002Z',
      'updatedAt': '2026-11-01T11:00:00.000002Z',
    });
  }

  test('ت5: قيدان بمبلغين مختلفين: يبقى المطابق للفاتورة على كل الأجهزة', () async {
    await seedCollision(f['A']);
    await f.converge();
    final out = await cycles(3);
    _report['t5_keeps_row_matching_invoice'] = {'cycles': out};
    expect(out.last['fils_A'], out.last['fils_B']);
    expect(out.last['fils_A'], 50000);
  }, timeout: slow);

  test('ت7: ترتيب محلي معكوس على جهازين: يبقى القيد نفسه على الاثنين', () async {
    Future<int> seed(FleetDevice d, List<String> order) async {
      await sell(d, 'ORD-${d.name}');
      final db = await f.activate(d);
      final tid = await OilChangeTestHarness.instance.tenantId();
      final inv =
          (await db.rawQuery('SELECT MAX(id) m FROM invoices')).first['m'] as int;
      for (final g in order) {
        await db.insert('cash_ledger', {
          'global_id': g,
          'tenantId': tid,
          'transactionType': 'sale_cash',
          'amount': g == 'twin-a' ? 70.0 : 80.0,
          'amountFils': g == 'twin-a' ? 70000 : 80000,
          'invoiceId': inv,
          'createdAt': '2026-11-01T11:00:00.000002Z',
          'updatedAt': '2026-11-01T11:00:00.000002Z',
        });
      }
      await db.delete('cash_ledger',
          where: "invoiceId = ? AND global_id NOT LIKE 'twin-%'",
          whereArgs: [inv]);
      return inv;
    }

    Future<List<Object?>> live(FleetDevice d, int inv) async {
      final db = await f.activate(d);
      await OilChangeTestHarness.instance.dbHelper.getCashSummary();
      final r = await db.rawQuery(
        'SELECT global_id g FROM cash_ledger WHERE invoiceId = ? AND deleted_at IS NULL',
        [inv],
      );
      return r.map((e) => e['g']).toList();
    }

    final ia = await seed(f['A'], ['twin-a', 'twin-b']);
    final ib = await seed(f['B'], ['twin-b', 'twin-a']);
    final a = await live(f['A'], ia);
    final b = await live(f['B'], ib);
    _report['t7_same_survivor'] = {'A': a, 'B': b};
    expect(a, ['twin-a']);
    expect(b, ['twin-a']);
  }, timeout: slow);

  test('ت6: ضابط: النسخة الحالية تبقي قيداً واحداً أيضاً', () async {
    f['A'].legacy = true;
    f['B'].legacy = true;
    await seedCollision(f['A']);
    await f.converge();
    final out = await cycles(3);
    _report['t6_control_legacy_deletes'] = {
      'expected_fils': 120000,
      'cycles': out,
    };
    expect(out.last['fils_A'], lessThan(120000));
  }, timeout: slow);
}
