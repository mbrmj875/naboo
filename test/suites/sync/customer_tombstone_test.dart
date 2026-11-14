// البند 4.4: الزبون المحذوف لا يعود.
//
// حذف الزبون كان يزيل الصف كله. اللقطة التالية تخلو منه، والجهاز الذي لم
// يتزامن بعد يحمله حياً فيرفعه، فيعود إلى كل الأجهزة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/sync_tombstones.dart';
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
    tmp = await Directory.systemTemp.createTemp('naboo_cust_tomb_');
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

  Future<Set<String>> names(FleetDevice d) async {
    await f.activate(d);
    final rows = await DatabaseHelper().getAllCustomers();
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Future<void> addCustomer(FleetDevice d, String name, String phone) async {
    await f.activate(d);
    await DatabaseHelper().insertCustomer(name: name, phone: phone);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  Future<void> deleteCustomer(FleetDevice d, String name) async {
    final db = await f.activate(d);
    final rows =
        await db.query('customers', where: 'name = ?', whereArgs: [name]);
    expect(rows, hasLength(1));
    await DatabaseHelper().deleteCustomers([rows.first['id'] as int]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  test('زبون محذوف لا يعود من جهاز لم يتزامن بعد', () async {
    await addCustomer(f['A'], 'زبون-حذف', '07700000001');
    await f.converge();
    for (final d in f.devices) {
      expect(await names(d), contains('زبون-حذف'));
    }

    await deleteCustomer(f['A'], 'زبون-حذف');
    await f.syncDevice(f['A']);
    await f.syncDevice(f['B']);
    await addCustomer(f['B'], 'زبون-ب', '07700000002');
    await f.syncDevice(f['B']);

    await f.syncDevice(f['C']);
    await addCustomer(f['C'], 'زبون-ج', '07700000003');
    await f.syncDevice(f['C']);
    await f.converge();

    for (final d in f.devices) {
      final n = await names(d);
      expect(n, isNot(contains('زبون-حذف')),
          reason: 'عاد الزبون المحذوف على ${d.name}');
      expect(n, containsAll(['زبون-ب', 'زبون-ج']),
          reason: 'ضاع زبون جديد على ${d.name}');
    }
  }, timeout: slow);

  test('رقم الزبون المحذوف يُستعمل لزبون جديد', () async {
    await addCustomer(f['A'], 'قديم', '07700000009');
    await f.converge();
    await deleteCustomer(f['A'], 'قديم');
    await addCustomer(f['A'], 'جديد', '07700000009');
    await f.converge();
    for (final d in f.devices) {
      final n = await names(d);
      expect(n, contains('جديد'), reason: 'على ${d.name}');
      expect(n, isNot(contains('قديم')), reason: 'على ${d.name}');
    }
  }, timeout: slow);

  test('شاهد حذف الزبون يبقى 90 يوماً ثم يُزال', () async {
    await addCustomer(f['A'], 'قديم-1', '07700000011');
    await addCustomer(f['A'], 'حديث-1', '07700000012');
    await f.converge();
    await deleteCustomer(f['A'], 'قديم-1');
    await deleteCustomer(f['A'], 'حديث-1');
    await f.converge();
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: SyncTombstones.keepDays + 1))
        .toIso8601String();
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.query(SyncTombstones.table);
      expect(rows, hasLength(2), reason: 'لم يصل الشاهد إلى ${d.name}');
      // الأقدم عمره أكثر من 90 يوماً على كل جهاز.
      final oldGid = rows.first['global_id'];
      await db.update(SyncTombstones.table,
          {'removed_at': old, 'updatedAt': old},
          where: 'global_id = ?', whereArgs: [oldGid]);
    }
    await addCustomer(f['A'], 'تحريك', '07700000013');
    await f.converge();
    for (final d in f.devices) {
      final db = await f.activate(d);
      expect(await db.query(SyncTombstones.table), hasLength(1),
          reason: 'على ${d.name}');
      expect(await names(d), isNot(containsAll(['قديم-1', 'حديث-1'])));
    }
  }, timeout: slow);
}
