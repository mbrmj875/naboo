// المرحلة 3: التقاط التعديلات في سجل محلي (وضع الظل).
//
// الاختبار الأساسي من الدراسة: النسخة القديمة + التعديلات الملتقطة على جهاز
// آخر = النسخة الحالية سطراً بسطر.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/change_capture.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:naboo/services/sync_tombstones.dart';
import 'package:naboo/services/sync_tables.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_oil_catalog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet f;
  const slow = Timeout(Duration(minutes: 5));

  setUpAll(() {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_capture_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    SyncSafety.changeCapture = true;
    await OilChangeTestHarness.instance.reset();
    f = await Fleet.create(2, tmp);
  });

  tearDown(() async {
    SyncSafety.changeCapture = false;
    f.dispose();
    await tmp.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> outbox(Database db) =>
      db.query(ChangeCapture.outbox, orderBy: 'id');

  test('a new card is captured once, edits fold into the same entry', () async {
    final db = await f.activate(f['A']);
    await db.delete(ChangeCapture.outbox);
    final id = await f.createCard(f['A'], 'CAP-1');
    final gid = (await db.query('service_orders',
            columns: ['global_id'], where: 'id = ?', whereArgs: [id]))
        .single['global_id'];
    final before = (await outbox(db))
        .where((r) => r['tbl'] == 'service_orders')
        .toList();
    expect(before.map((r) => r['row_key']), [gid]);

    await db.update('service_orders', {'deviceSerial': 'CAP-1b'},
        where: 'id = ?', whereArgs: [id]);
    await db.update('service_orders', {'deviceSerial': 'CAP-1c'},
        where: 'id = ?', whereArgs: [id]);
    final after = (await outbox(db))
        .where((r) => r['tbl'] == 'service_orders')
        .toList();
    expect(after.length, 1);
    expect(after.single['op'], 'U');

    final pending = await ChangeCapture.pending(db, limit: 1000);
    final card = pending.singleWhere((c) => c.table == 'service_orders');
    expect(card.row!['deviceSerial'], 'CAP-1c');
  }, timeout: slow);

  test('a hard delete is captured as a delete by key', () async {
    final db = await f.activate(f['A']);
    final id = await OilChangeOilCatalogRepository.instance.insert(
      brandName: 'Castrol',
      viscosity: '5W30',
      sellPerLiterFils: 9000,
    );
    final gid = (await db.query('oil_change_oil_catalog',
            where: 'id = ?', whereArgs: [id]))
        .single['global_id'];
    await db.delete('oil_change_oil_catalog', where: 'id = ?', whereArgs: [id]);
    final row = (await outbox(db))
        .singleWhere((r) => r['tbl'] == 'oil_change_oil_catalog');
    expect(row['row_key'], gid);
    expect(row['op'], 'D');
  }, timeout: slow);

  test('rows that arrive from the server are not captured again', () async {
    await f.createCard(f['A'], 'ECHO-1');
    await f.syncDevice(f['A']);
    final db = await f.activate(f['B']);
    await db.delete(ChangeCapture.outbox);
    await f.importLatest(f['B'].userId);
    expect(await outbox(db), isEmpty);
    final plates = await f.plates(f['B']);
    expect(plates, contains('ECHO-1'));
  }, timeout: slow);

  test('wiping business data does not record deletes', () async {
    await f.createCard(f['A'], 'WIPE-1');
    final db = await f.activate(f['A']);
    await OilChangeTestHarness.instance.dbHelper.wipeBusinessDataKeepUsers();
    // لا حذف واحد يُسجَّل. بذرة المستأجر الافتراضي تُكتب بعد الإفراغ، وهي
    // نفسها على كل جهاز.
    final after = await outbox(db);
    expect(after.where((r) => r['op'] == 'D'), isEmpty);
    expect(after.map((r) => r['tbl']).toSet(), anyOf(isEmpty, {'tenants'}));
    // الالتقاط يعود بعد الإفراغ.
    await f.createCard(f['A'], 'WIPE-2');
    expect(await outbox(db), isNotEmpty);
  }, timeout: slow);

  test('repairs run while opening the database are not captured', () async {
    var db = await f.activate(f['A']);
    // خطة تقسيط وصلت قبل فاتورتها: إصلاح الفتح يحذفها محلياً.
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('installment_plans', {
      'invoiceId': 987654,
      'customerName': 'x',
      'totalAmount': 10.0,
      'paidAmount': 0.0,
      'numberOfInstallments': 2,
    });
    await db.execute('PRAGMA foreign_keys = ON');
    await db.delete(ChangeCapture.outbox);

    db = await f.reopen(f['A']);
    expect(
      await db.query('installment_plans', where: 'invoiceId = 987654'),
      isEmpty,
    );
    expect(
      (await outbox(db)).where((r) => r['tbl'] == 'installment_plans'),
      isEmpty,
    );
    // الالتقاط عاد بعد الفتح.
    final ctl = await db.query(ChangeCapture.ctlTable);
    expect(ctl.single['paused'], 0);
    await f.createCard(f['A'], 'AFTER-OPEN');
    expect(
      (await outbox(db)).where((r) => r['tbl'] == 'service_orders'),
      isNotEmpty,
    );
  }, timeout: slow);

  test('upload-time cleanup is not captured', () async {
    final db = await f.activate(f['A']);
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 400))
        .toIso8601String();
    await SyncTombstones.ensureTable(db);
    await ChangeCapture.ensure(db);
    await db.insert(SyncTombstones.table, {
      'table_name': 'customers',
      'global_id': 'old-tombstone',
      'removed_at': old,
      'updatedAt': old,
    });
    expect(
      (await outbox(db)).where((r) => r['tbl'] == SyncTombstones.table),
      isNotEmpty,
      reason: 'the table is captured, so the check below means something',
    );
    await db.delete(ChangeCapture.outbox);

    await CloudSyncService.instance.runLocalCleanup(db);
    expect(
      await db.query(SyncTombstones.table,
          where: 'global_id = ?', whereArgs: ['old-tombstone']),
      isEmpty,
      reason: 'the old record is cleaned up before upload',
    );
    expect(
      (await outbox(db)).where((r) => r['op'] == 'D'),
      isEmpty,
    );
  }, timeout: slow);

  test('a table created after opening is captured from its first row',
      () async {
    final db = await f.activate(f['A']);
    await db.execute(
      'CREATE TABLE late_things (id INTEGER PRIMARY KEY, '
      'global_id TEXT, name TEXT)',
    );
    await db.insert('late_things', {'global_id': 'late-1', 'name': 'a'});
    expect(
      await ChangeCapture.tablesWithoutTriggers(db),
      contains('late_things'),
    );
    await ChangeCapture.ensureLateTables(db);
    expect(await ChangeCapture.tablesWithoutTriggers(db), isEmpty);
    await db.insert('late_things', {'global_id': 'late-2', 'name': 'b'});
    final keys = (await outbox(db))
        .where((r) => r['tbl'] == 'late_things')
        .map((r) => r['row_key'])
        .toSet();
    // السطر الذي كُتب قبل المشغّل يُسجَّل أيضاً.
    expect(keys, {'late-1', 'late-2'});
  }, timeout: slow);

  test('re-checking the staff directory with no change writes nothing',
      () async {
    final db = await f.activate(f['A']);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('users', {
      'username': 'staff.probe',
      'role': 'staff',
      'isActive': 1,
      'passwordHash': 'h',
      'passwordSalt': 's',
      'createdAt': now,
      'updatedAt': now,
    });
    final helper = OilChangeTestHarness.instance.dbHelper;
    await helper.reconcileUserDirectoryAfterCloudImport();
    expect(await db.query('user_profiles'), isNotEmpty);
    await db.delete(ChangeCapture.outbox);
    await helper.reconcileUserDirectoryAfterCloudImport();
    expect(
      (await outbox(db)).where((r) => r['tbl'] == 'user_profiles'),
      isEmpty,
    );
  }, timeout: slow);

  test('a settings change is captured by its key', () async {
    final db = await f.activate(f['A']);
    await db.delete(ChangeCapture.outbox);
    await db.insert(
      'app_settings',
      {
        'key': 'probe.setting',
        'value': '1',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final row = (await outbox(db)).singleWhere((r) => r['tbl'] == 'app_settings');
    expect(row['row_key'], 'probe.setting');
    final change = (await ChangeCapture.pending(db, limit: 100))
        .singleWhere((c) => c.table == 'app_settings');
    expect(change.row!['value'], '1');
  }, timeout: slow);

  test('turning capture on the first time does not record existing rows',
      () async {
    SyncSafety.changeCapture = false;
    var db = await f.reopen(f['A']);
    await f.createCard(f['A'], 'BEFORE-ON');
    await db.delete(ChangeCapture.outbox);
    SyncSafety.changeCapture = true;
    db = await f.reopen(f['A']);
    expect(await outbox(db), isEmpty);
  }, timeout: slow);

  test('switch off: no triggers and nothing captured', () async {
    SyncSafety.changeCapture = false;
    final db = await f.reopen(f['A']);
    final triggers = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' "
      "AND name LIKE 'trg_cap_%'",
    );
    expect(triggers, isEmpty);
    await db.delete(ChangeCapture.outbox);
    await f.createCard(f['A'], 'OFF-1');
    expect(await outbox(db), isEmpty);
  }, timeout: slow);

  test('old snapshot + captured changes = current device, row by row',
      () async {
    // النسخة القديمة على الخادم، والسجل يبدأ بعدها.
    await f.syncDevice(f['A']);
    var db = await f.activate(f['A']);
    await db.delete(ChangeCapture.outbox);

    // يوم عمل صغير على الجهاز أ.
    final c1 = await f.createCard(f['A'], 'DAY-1');
    final c2 = await f.createCard(f['A'], 'DAY-2');
    db = await f.activate(f['A']);
    await db.update('service_orders', {'deviceSerial': 'DAY-1x'},
        where: 'id = ?', whereArgs: [c1]);
    await db.update(
      'service_orders',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [c2],
    );
    final oil = await OilChangeOilCatalogRepository.instance.insert(
      brandName: 'Mobil',
      viscosity: '10W40',
      sellPerLiterFils: 7000,
    );
    await OilChangeOilCatalogRepository.instance.insert(
      brandName: 'Total',
      viscosity: '5W40',
      sellPerLiterFils: 8000,
    );
    await db.delete('oil_change_oil_catalog', where: 'id = ?', whereArgs: [oil]);
    await db.insert('activity_logs', {
      'type': 'note',
      'title': 'day',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // ما يُرسل على الشبكة: JSON.
    final changes = [
      for (final c in await ChangeCapture.pending(db, limit: 100000))
        c,
    ];
    final wire = jsonDecode(jsonEncode([for (final c in changes) c.toJson()]))
        as List;
    final received = [
      for (var i = 0; i < wire.length; i++)
        CapturedChange(
          outboxId: i,
          table: wire[i]['table'] as String,
          key: wire[i]['key'] as String,
          op: wire[i]['op'] as String,
          row: (wire[i]['row'] as Map?)?.cast<String, dynamic>(),
        ),
    ];
    expect(received, isNotEmpty);

    Future<Map<String, List<String>>> dump(Database db) async {
      final out = <String, List<String>>{};
      final names = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      for (final n in names) {
        final t = n['name'].toString();
        if (!SyncTables.isCaptured(t)) continue;
        final key = await ChangeCapture.keyColumn(db, t);
        if (key == null) continue;
        final rows = await db.query(t, orderBy: key);
        out[t] = [for (final r in rows) jsonEncode(r)];
      }
      return out;
    }

    final want = await dump(db);

    // الجهاز ب: النسخة القديمة ثم التعديلات.
    final dbB = await f.activate(f['B']);
    // فتح القاعدة لا يكتب شيئاً يُلتقط.
    expect(await outbox(dbB), isEmpty);
    await f.importLatest(f['B'].userId);
    await CloudSyncService.instance.applyCapturedChanges(received);
    final got = await dump(dbB);

    final diff = <String>[];
    for (final t in {...want.keys, ...got.keys}) {
      final a = want[t] ?? const [];
      final b = got[t] ?? const [];
      if (a.length != b.length) {
        diff.add('$t: rows ${a.length} vs ${b.length}');
        continue;
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          diff.add('$t[$i]:\n  A ${a[i]}\n  B ${b[i]}');
          break;
        }
      }
    }
    expect(diff, isEmpty, reason: diff.join('\n'));
    // ما طُبِّق لم يُلتقط على ب.
    expect(await outbox(dbB), isEmpty);
  }, timeout: slow);
}
