// البند 4.4: البطاقة المحذوفة لا تعود.
//
// الجهاز الذي يحذف يبقي البطاقة بتاريخ حذف. الجهاز الذي يستلم الحذف كان يزيلها
// كلها، فلا يبقى عنده أثر. أول رفعة منه بعدها تحمل لقطة بلا البطاقة أصلاً،
// فيضيع الحذف من الخادم، وجهاز ثالث لم يتزامن بعد يرفعها حية فتعود للجميع.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
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
    tmp = await Directory.systemTemp.createTemp('naboo_tombstone_');
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

  Future<void> deleteCard(FleetDevice d, String plate) async {
    final db = await f.activate(d);
    final now = DateTime.now().toUtc().toIso8601String();
    final n = await db.update(
      'service_orders',
      {'deletedAt': now, 'updatedAt': now},
      where: 'deviceSerial = ? AND deletedAt IS NULL',
      whereArgs: [plate],
    );
    expect(n, 1);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  test('بطاقة محذوفة لا تعود من جهاز لم يتزامن بعد', () async {
    await f.createCard(f['A'], 'DEL-1');
    await f.converge();
    for (final d in f.devices) {
      expect(await f.plates(d), contains('DEL-1'));
    }

    // C لا يتزامن الآن. A يحذف، ثم B يستلم الحذف ويرفع تغييراً له.
    await deleteCard(f['A'], 'DEL-1');
    await f.syncDevice(f['A']);
    await f.syncDevice(f['B']);
    await f.createCard(f['B'], 'B-NEW');
    await f.syncDevice(f['B']);

    // C يعود ويرفع تغييراً له.
    await f.syncDevice(f['C']);
    await f.createCard(f['C'], 'C-NEW');
    await f.syncDevice(f['C']);
    await f.converge();

    final by = await f.platesByDevice();
    for (final e in by.entries) {
      expect(e.value, isNot(contains('DEL-1')),
          reason: 'عادت البطاقة المحذوفة على ${e.key}');
      expect(e.value, containsAll(['B-NEW', 'C-NEW']),
          reason: 'ضاعت بطاقة جديدة على ${e.key}');
    }
  }, timeout: slow);

  test('البطاقة المحذوفة تبقى 90 يوماً ثم تُزال', () async {
    await f.createCard(f['A'], 'OLD-DEL');
    await f.createCard(f['A'], 'NEW-DEL');
    await f.converge();
    await deleteCard(f['A'], 'OLD-DEL');
    await deleteCard(f['A'], 'NEW-DEL');
    await f.converge();
    // وصل الحذف إلى كل جهاز. نعيد تاريخه كأن الأيام مرّت على الجميع.
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: CloudSyncService.cardTombstoneDays + 1))
        .toIso8601String();
    final recent = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: CloudSyncService.cardTombstoneDays - 1))
        .toIso8601String();
    for (final d in f.devices) {
      final db = await f.activate(d);
      expect(
          (await db.query('service_orders',
                  where: "deviceSerial IN ('OLD-DEL', 'NEW-DEL') "
                      'AND deletedAt IS NOT NULL'))
              .length,
          2,
          reason: 'لم يصل الحذف إلى ${d.name}');
      await db.update('service_orders', {'deletedAt': old, 'updatedAt': old},
          where: 'deviceSerial = ?', whereArgs: ['OLD-DEL']);
      await db.update(
          'service_orders', {'deletedAt': recent, 'updatedAt': recent},
          where: 'deviceSerial = ?', whereArgs: ['NEW-DEL']);
    }
    await f.createCard(f['A'], 'TICK');
    await f.converge();
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.query('service_orders',
          columns: ['deviceSerial'],
          where: "deviceSerial IN ('OLD-DEL', 'NEW-DEL')");
      expect(rows.map((r) => r['deviceSerial']), ['NEW-DEL'],
          reason: 'على ${d.name}');
    }
  }, timeout: slow);

  test('حذف أقدم من تعديل لاحق لا يغلبه', () async {
    await f.createCard(f['A'], 'EDIT-1');
    await f.converge();
    await deleteCard(f['A'], 'EDIT-1');
    // B يعدّل البطاقة بعد الحذف وقبل أن يصله.
    final b = await f.activate(f['B']);
    final later = DateTime.now().toUtc().add(const Duration(seconds: 5));
    await b.update(
      'service_orders',
      {'updatedAt': later.toIso8601String()},
      where: 'deviceSerial = ?',
      whereArgs: ['EDIT-1'],
    );
    await f.syncDevice(f['A']);
    await f.converge();
    // الأحدث يفوز على كل الأجهزة، والمهم أن تتفق كلها.
    final by = await f.platesByDevice();
    final has = by.values.map((s) => s.contains('EDIT-1')).toSet();
    expect(has.length, 1, reason: 'الأجهزة مختلفة: $by');
  }, timeout: slow);
}
