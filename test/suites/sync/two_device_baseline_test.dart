/*
  خط أساس تعدد الأجهزة — يقيس سلوك المزامنة الحالي قبل أي إعادة بناء.

  يشغّل كود الرفع والدمج الحقيقي ([CloudSyncService]) على عدة ملفات SQLite
  تمثل أجهزة حساب واحد، مع خادم وهمي يطبق قواعد rpc_push_snapshot.
  لا يتصل بأي شبكة ولا يلمس الخادم الحقيقي.

  الاختبارات تفحص الثوابت المطلوبة، لذلك فشل بعضها الآن متوقع وهو نفسه النتيجة.
  التقرير: build/two_device_baseline.json، أو المسار في BASELINE_REPORT.

  flutter test test/suites/sync/two_device_baseline_test.dart
*/

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

final _report = <String, Map<String, Object?>>{};

Future<void> _flushReport() async {
  final path =
      Platform.environment['BASELINE_REPORT'] ?? 'build/two_device_baseline.json';
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(
    const JsonEncoder.withIndent('  ').convert(_report),
  );
}

Map<String, Object?> _lossMetrics(
  Set<String> expected,
  Map<String, Set<String>> actual,
) {
  return {
    'expected': expected.length,
    for (final e in actual.entries) ...{
      'device_${e.key}_count': e.value.intersection(expected).length,
      'device_${e.key}_lost': (expected.difference(e.value).toList()..sort()),
    },
    'devices_agree': actual.values.toSet().length == 1 ||
        actual.values.every((s) => s.containsAll(actual.values.first) &&
            actual.values.first.containsAll(s)),
  };
}

void main() {
  late Directory tmp;
  late Fleet fleet;

  setUpAll(initOilChangeTestEnvironment);

  Future<Fleet> start(int count) async {
    tmp = await Directory.systemTemp.createTemp('naboo_baseline_');
    SharedPreferences.setMockInitialValues({});
    fleet = await Fleet.create(count, tmp);
    return fleet;
  }

  tearDown(() async {
    fleet.dispose();
    await tmp.delete(recursive: true);
    await _flushReport();
  });

  const slow = Timeout(Duration(minutes: 5));

  // ─── ضوابط: تثبت أن الأداة لا تصنع فقداً وهمياً ───

  test('ضابط 1: جهازان بالتناوب دون تزامن لا يفقدان شيئاً', () async {
    final f = await start(2);
    final expected = <String>{};
    for (var i = 0; i < 5; i++) {
      final plate = 'SEQ-$i';
      expected.add(plate);
      final d = i.isEven ? f['A'] : f['B'];
      await f.syncDevice(d);
      await f.createCard(d, plate);
      await f.syncDevice(d);
    }
    await f.converge();
    final actual = await f.platesByDevice();
    _report['control_sequential'] = _lossMetrics(expected, actual);
    for (final s in actual.values) {
      expect(s, containsAll(expected));
    }
  }, timeout: slow);

  test('ضابط 2: الزبائن تُدمج بالمعرف العالمي فتنجو من تصادم الرقم', () async {
    final f = await start(2);
    Future<void> addCustomer(FleetDevice d, String gid) async {
      final db = await f.activate(d);
      final tid = await OilChangeTestHarness.instance.tenantId();
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('customers', {
        'global_id': gid,
        'tenantId': tid,
        'name': gid,
        'createdAt': now,
        'updatedAt': now,
      });
    }

    await addCustomer(f['A'], 'cust-A');
    await addCustomer(f['B'], 'cust-B');
    await f.converge();
    final names = <String, Set<String>>{};
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.rawQuery('SELECT name FROM customers');
      names[d.name] = rows.map((r) => r['name'].toString()).toSet();
    }
    _report['control_customers_by_gid'] =
        _lossMetrics({'cust-A', 'cust-B'}, names);
    for (final s in names.values) {
      expect(s, containsAll({'cust-A', 'cust-B'}));
    }
  }, timeout: slow);

  // ─── الثوابت ───

  test('س1: بطاقتان بنفس الرقم المحلي تبقيان على الجهازين', () async {
    final f = await start(2);
    final idA = await f.createCard(f['A'], 'A-1');
    final idB = await f.createCard(f['B'], 'B-1');
    await f.converge();
    final actual = await f.platesByDevice();
    _report['s1_same_local_id'] = {
      'local_id_a': idA,
      'local_id_b': idB,
      ..._lossMetrics({'A-1', 'B-1'}, actual),
    };
    for (final s in actual.values) {
      expect(s, containsAll({'A-1', 'B-1'}));
    }
  }, timeout: slow);

  test('س1ب: نفس السيناريو والطابور معلق (لم يُعالج)', () async {
    final f = await start(2);
    await f.createCard(f['A'], 'A-1');
    await f.createCard(f['B'], 'B-1');
    await f.converge(processQueue: false);
    final actual = await f.platesByDevice();
    _report['s1b_queue_pending'] = _lossMetrics({'A-1', 'B-1'}, actual);
    for (final s in actual.values) {
      expect(s, containsAll({'A-1', 'B-1'}));
    }
  }, timeout: slow);

  test('س2: أربعة أجهزة بترتيب عشوائي ثابت لا تفقد أي بطاقة', () async {
    final f = await start(4);
    final rnd = Random(42);
    final expected = <String>{};
    for (var round = 0; round < 3; round++) {
      for (final d in f.devices) {
        await f.syncDevice(d);
        for (var i = 0; i < 5; i++) {
          final plate = '${d.name}-$round-$i';
          expected.add(plate);
          await f.createCard(d, plate);
        }
      }
      final order = [...f.devices]..shuffle(rnd);
      for (final d in order) {
        await f.syncDevice(d);
      }
    }
    await f.converge();
    final actual = await f.platesByDevice();
    _report['s2_four_devices'] = {
      ..._lossMetrics(expected, actual),
      'pushes': f.cloud.pushes,
      'conflicts': f.cloud.conflicts,
      'uploaded_bytes': f.cloud.bytesUploaded,
    };
    for (final s in actual.values) {
      expect(s, containsAll(expected));
    }
  }, timeout: slow);

  for (final syncRate in const [1.0, 0.9, 0.7]) {
    test('س2ب: 60 بطاقة ونسبة مزامنة قبل وبعد كل بطاقة = $syncRate', () async {
      final f = await start(4);
      final rnd = Random(7);
      final expected = <String>{};
      for (var i = 0; i < 60; i++) {
        final d = f.devices[rnd.nextInt(4)];
        if (rnd.nextDouble() < syncRate) await f.syncDevice(d);
        final plate = 'P-$i';
        expected.add(plate);
        await f.createCard(d, plate);
        if (rnd.nextDouble() < syncRate) await f.syncDevice(d);
      }
      await f.converge();
      final actual = await f.platesByDevice();
      final survivors = actual['A']!.intersection(expected).length;
      _report['s2b_sync_rate_$syncRate'] = {
        'cards': expected.length,
        'lost_on_device_A': expected.length - survivors,
        'lost_percent':
            ((expected.length - survivors) * 100 / expected.length).round(),
        'devices_agree': _lossMetrics(expected, actual)['devices_agree'],
        'pushes': f.cloud.pushes,
        'conflicts': f.cloud.conflicts,
        'uploaded_bytes': f.cloud.bytesUploaded,
      };
      expect(survivors, expected.length);
    }, timeout: slow);
  }

  test('س3: حذف بطاقة على جهاز لا يحذف بطاقة أخرى بنفس الرقم', () async {
    final f = await start(2);
    await f.createCard(f['A'], 'SHARED');
    await f.converge();
    final idA = await f.createCard(f['A'], 'A-DEL');
    await f.createCard(f['B'], 'B-KEEP');
    final db = await f.activate(f['A']);
    await db.update(
      'service_orders',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [idA],
    );
    await f.converge();
    final actual = await f.platesByDevice();
    _report['s3_delete_by_local_id'] =
        _lossMetrics({'SHARED', 'B-KEEP'}, actual);
    for (final s in actual.values) {
      expect(s, contains('B-KEEP'));
    }
  }, timeout: slow);

  test('س4: البطاقة تبقى مرتبطة بفاتورتها الصحيحة بعد الدمج', () async {
    final f = await start(2);
    final helper = OilChangeTestHarness.instance.dbHelper;
    Future<void> addLinked(FleetDevice d, String plate, String invGid) async {
      final cardId = await f.createCard(d, plate);
      final db = await f.activate(d);
      final tid = await OilChangeTestHarness.instance.tenantId();
      final invId = await seedInvoice(dbHelper: helper, tenantId: tid);
      await db.update(
        'invoices',
        {
          'global_id': invGid,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invId],
      );
      await db.update(
        'service_orders',
        {
          'invoiceId': invId,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [cardId],
      );
    }

    // فاتورة إضافية على B تجعل الأرقام المحلية تختلف بين الجهازين.
    final bDb = await f.activate(f['B']);
    final tid = await OilChangeTestHarness.instance.tenantId();
    final filler = await seedInvoice(dbHelper: helper, tenantId: tid);
    await bDb.update(
      'invoices',
      {'global_id': 'inv-filler'},
      where: 'id = ?',
      whereArgs: [filler],
    );

    await addLinked(f['A'], 'A-LINK', 'inv-A');
    await addLinked(f['B'], 'B-LINK', 'inv-B');
    await f.converge();

    final wrong = <String, String?>{};
    for (final d in f.devices) {
      final db = await f.activate(d);
      for (final entry in {'A-LINK': 'inv-A', 'B-LINK': 'inv-B'}.entries) {
        final rows = await db.rawQuery(
          'SELECT i.global_id AS gid FROM service_orders s '
          'LEFT JOIN invoices i ON i.id = s.invoiceId '
          'WHERE s.deviceSerial = ?',
          [entry.key],
        );
        final gid = rows.isEmpty ? '(البطاقة مفقودة)' : rows.first['gid'] as String?;
        if (gid != entry.value) wrong['${d.name}:${entry.key}'] = gid;
      }
    }
    _report['s4_invoice_link'] = {'wrong_links': wrong};
    expect(wrong, isEmpty);
  }, timeout: slow);

  test('س5: صف صندوق يبقى مرة واحدة ومجموع الصندوق صحيح', () async {
    final f = await start(2);
    Future<void> addCash(FleetDevice d, String gid, double amount) async {
      final db = await f.activate(d);
      final tid = await OilChangeTestHarness.instance.tenantId();
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('cash_ledger', {
        'global_id': gid,
        'tenantId': tid,
        'transactionType': 'sale_cash',
        'amount': amount,
        'amountFils': (amount * 1000).round(),
        'createdAt': now,
        'updatedAt': now,
      });
    }

    await addCash(f['A'], 'cash-A', 1000);
    await addCash(f['B'], 'cash-B', 2000);
    await f.converge();
    final out = <String, Object?>{};
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(amount),0) s FROM cash_ledger',
      );
      out['device_${d.name}'] = rows.first;
    }
    _report['s5_cash'] = out;
    for (final v in out.values) {
      final r = v as Map<String, Object?>;
      expect(r['c'], 2);
      expect((r['s'] as num).toDouble(), 3000);
    }
  }, timeout: slow);

  test('س5ب: صف صندوق بلا معرف عالمي لا يتكرر بين الجهازين', () async {
    final f = await start(2);
    final db = await f.activate(f['A']);
    final tid = await OilChangeTestHarness.instance.tenantId();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('cash_ledger', {
      'tenantId': tid,
      'transactionType': 'sale_cash',
      'amount': 1000.0,
      'amountFils': 1000000,
      'createdAt': now,
      'updatedAt': now,
    });
    final before = await db.rawQuery('SELECT id, global_id FROM cash_ledger');
    await f.converge();
    final out = <String, Object?>{'on_A_before_sync': before};
    for (final d in f.devices) {
      final dbx = await f.activate(d);
      final rows = await dbx.rawQuery('SELECT COUNT(*) c FROM cash_ledger');
      out['device_${d.name}'] = rows.first['c'];
      out['rows_${d.name}'] = await dbx.rawQuery(
          'SELECT id, amountFils, global_id, transactionType FROM cash_ledger ORDER BY id');
    }
    _report['s5b_cash_no_gid'] = out;
    expect([out['device_A'], out['device_B']], [1, 1]);
  }, timeout: slow);

  test('س6: ضياع رد الخادم ثم إعادة الإرسال لا ينشئ نسخة جديدة', () async {
    final f = await start(1);
    final d = f['A'];
    await f.createCard(d, 'RETRY');
    f.cloud.dropNextResponse = true;
    Object? thrown;
    try {
      await f.syncDevice(d);
    } catch (e) {
      thrown = e;
    }
    final afterFirst = f.cloud.version;
    await f.syncDevice(d);
    _report['s6_lost_response'] = {
      'first_attempt_threw': thrown?.runtimeType.toString(),
      'version_after_first': afterFirst,
      'version_after_retry': f.cloud.version,
      'pushes_applied': f.cloud.pushes,
    };
    expect(f.cloud.version, afterFirst);
  }, timeout: slow);

  test('س7: تعديلان لحقلين مختلفين في نفس البطاقة يبقيان معاً', () async {
    final f = await start(2);
    await f.createCard(f['A'], 'EDIT');
    await f.converge();
    Future<void> edit(FleetDevice d, Map<String, Object?> values) async {
      final db = await f.activate(d);
      await db.update(
        'service_orders',
        {...values, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
        where: 'deviceSerial = ?',
        whereArgs: ['EDIT'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    await edit(f['A'], {'technicianName': 'TECH-A'});
    await edit(f['B'], {'carModel': 'MODEL-B'});
    await f.converge();
    final out = <String, Object?>{};
    for (final d in f.devices) {
      final db = await f.activate(d);
      final rows = await db.query(
        'service_orders',
        columns: ['technicianName', 'carModel'],
        where: 'deviceSerial = ?',
        whereArgs: ['EDIT'],
      );
      out['device_${d.name}'] = rows.first;
    }
    _report['s7_field_merge'] = out;
    for (final v in out.values) {
      final r = v as Map<String, Object?>;
      expect(r['technicianName'], 'TECH-A');
      expect(r['carModel'], 'MODEL-B');
    }
  }, timeout: slow);

  test('س8: ساعة جهاز متأخرة لا تُسقط تعديله الأحدث', () async {
    final f = await start(2);
    await f.createCard(f['A'], 'CLOCK');
    await f.converge();
    final db = await f.activate(f['B']);
    final skewed = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    await db.update(
      'service_orders',
      {'technicianName': 'LATER-EDIT', 'updatedAt': skewed},
      where: 'deviceSerial = ?',
      whereArgs: ['CLOCK'],
    );
    await f.converge();
    final out = <String, Object?>{};
    for (final d in f.devices) {
      final dbx = await f.activate(d);
      final rows = await dbx.query(
        'service_orders',
        columns: ['technicianName'],
        where: 'deviceSerial = ?',
        whereArgs: ['CLOCK'],
      );
      out['device_${d.name}'] = rows.first['technicianName'];
    }
    _report['s8_clock_skew'] = out;
    expect(out.values.toSet(), {'LATER-EDIT'});
  }, timeout: slow);

  test('قياس: كلفة تغيير صف واحد عند حجم العكيل (444 بطاقة)', () async {
    final f = await start(2);
    final a = f['A'];
    final db = await f.activate(a);
    final tid = await OilChangeTestHarness.instance.tenantId();
    await db.transaction((txn) async {
      for (var i = 0; i < 444; i++) {
        final row = oilTestOrderPayload(deviceSerial: 'BULK-$i')
          ..['global_id'] = 'bulk-$i'
          ..['tenantId'] = tid
          ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        await txn.insert('service_orders', row);
      }
    });
    await f.syncDevice(a);
    await f.syncDevice(f['B']);

    await f.activate(a);
    final dbA = await f.activate(a);
    await dbA.update(
      'service_orders',
      {
        'technicianName': 'ONE-ROW',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'deviceSerial = ?',
      whereArgs: ['BULK-7'],
    );
    final changed = await dbA.query(
      'service_orders',
      where: 'deviceSerial = ?',
      whereArgs: ['BULK-7'],
    );
    final rowBytes = utf8.encode(jsonEncode(changed.first)).length;

    final before = f.cloud.bytesUploaded;
    final pushWatch = Stopwatch()..start();
    await f.syncDevice(a);
    pushWatch.stop();
    final uploaded = f.cloud.bytesUploaded - before;
    final gz = gzip.encode(utf8.encode(jsonEncode(f.cloud.payload))).length;

    final b = f['B'];
    await f.activate(b);
    final pullWatch = Stopwatch()..start();
    await f.syncDevice(b);
    pullWatch.stop();

    _report['cost_one_row_change'] = {
      'cards': 444,
      'changed_row_bytes': rowBytes,
      'uploaded_snapshot_bytes': uploaded,
      // صفوف الاختبار متطابقة تقريباً فالضغط هنا أعلى كثيراً من البيانات الحقيقية.
      'uploaded_snapshot_gzip_bytes_identical_rows': gz,
      'ratio_snapshot_to_row': (uploaded / rowBytes).round(),
      'push_ms_this_mac_no_network': pushWatch.elapsedMilliseconds,
      'pull_merge_ms_this_mac_no_network': pullWatch.elapsedMilliseconds,
    };
    expect(uploaded, greaterThan(0));
  }, timeout: slow);
}
