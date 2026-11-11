// البند 4.3: لكل جهاز ورديته، ولا يغلق جهاز وردية جهاز آخر.
//
// المالك يفتح وردية على جهازين. بعد المزامنة يرى كل جهاز ورديتين مفتوحتين
// للموظف نفسه، فكان إصلاح "الورديات المكررة" يغلق الأقدم، وهي وردية الجهاز
// الآخر، دون جرد صندوقها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet f;
  const slow = Timeout(Duration(minutes: 5));
  const owner = 11;

  setUpAll(() async {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    // فتح الوردية يطلب مزامنة الحضور: خادم لا يجيب كما في انقطاع الاتصال.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'offline-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  Future<void> seedStaff(int id) async {
    final db = await DatabaseHelper().database;
    final columns = await db.rawQuery('PRAGMA table_info(users)');
    final row = <String, Object?>{'id': id};
    for (final c in columns) {
      final name = c['name']! as String;
      if (name == 'id' || c['notnull'] != 1 || c['dflt_value'] != null) {
        continue;
      }
      final type = (c['type']! as String).toUpperCase();
      row[name] = type.contains('INT') || type.contains('REAL') ? 1 : 'u$id';
    }
    await db.insert('users', row);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_shift_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    await OilChangeTestHarness.instance.reset();
    f = await Fleet.create(2, tmp);
    for (final d in f.devices) {
      await f.activate(d);
      await seedStaff(owner);
      await f.syncDevice(d);
    }
  });

  tearDown(() async {
    f.dispose();
    CloudSyncService.instance.suppressScheduleSyncSoonForTesting = false;
    await tmp.delete(recursive: true);
  });

  Future<int> openShift(FleetDevice d) async {
    await f.activate(d);
    final id = await DatabaseHelper().openWorkShift(
      sessionUserId: owner,
      shiftStaffUserId: owner,
      systemBalanceAtOpen: 0,
      declaredPhysicalCash: 0,
      addedCashAtOpen: 0,
      shiftStaffName: 'المالك',
      shiftStaffPin: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return id;
  }

  Future<String> gidOf(FleetDevice d, int id) async {
    final db = await f.activate(d);
    final r = await db.query('work_shifts',
        columns: ['global_id'], where: 'id = ?', whereArgs: [id]);
    return r.first['global_id'].toString();
  }

  Future<Set<String>> openGids(FleetDevice d) async {
    final db = await f.activate(d);
    final r = await db.query('work_shifts',
        columns: ['global_id'],
        where: "(closedAt IS NULL OR TRIM(closedAt) = '') "
            'AND deleted_at IS NULL');
    return r.map((e) => e['global_id'].toString()).toSet();
  }

  test('وردية المالك على جهازين تبقى مفتوحة على كل جهاز', () async {
    final a = await gidOf(f['A'], await openShift(f['A']));
    final b = await gidOf(f['B'], await openShift(f['B']));
    await f.converge();

    // ما تفعله لوحة المالك وشاشة فتح الوردية عند كل فتح.
    for (final d in f.devices) {
      await f.activate(d);
      await DatabaseHelper().repairDuplicateOpenShifts();
    }
    await f.converge();

    for (final d in f.devices) {
      expect(await openGids(d), {a, b},
          reason: 'أُغلقت وردية جهاز آخر دون جرد على ${d.name}');
    }
  }, timeout: slow);

  test('كل جهاز يرى ورديته هو', () async {
    final a = await gidOf(f['A'], await openShift(f['A']));
    await f.converge();
    // B يفتح وردية للمالك بعد أن وصلته وردية A.
    final bId = await openShift(f['B']);
    final b = await gidOf(f['B'], bId);
    expect(b, isNot(a), reason: 'أخذ الجهاز B وردية الجهاز A');

    await f.activate(f['B']);
    final open = await DatabaseHelper().getOpenWorkShiftForStaff(owner);
    expect(open?['global_id'], b);
    await f.activate(f['A']);
    final openA = await DatabaseHelper().getOpenWorkShiftForStaff(owner);
    expect(openA?['global_id'], a);
  }, timeout: slow);
}
