// المرحلة 4: إرسال التعديلات واستلامها بين الأجهزة، مع بقاء النسخة الكاملة.
//
// الخادم هنا نسخة Dart من قواعد migrations/20261115_sync_changes.sql: رقم لكل
// حساب، ومفتاح عدم تكرار، ورقم جيل، وحذف قديم، وتشغيل لكل حساب.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/change_capture.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/delta_sync_service.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_oil_catalog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

class FakeDeltaServer implements DeltaBackend {
  bool enabled = true;
  bool primary = false;
  int generation = 0;
  int lastSeq = 0;
  final changes = <Map<String, dynamic>>[];
  final _byKey = <String, int>{};
  bool dropNextPushResponse = false;
  bool Function(String table) allowed = (_) => true;
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<Map<String, dynamic>> push({
    required String deviceId,
    required int generation,
    required List<Map<String, dynamic>> changes,
  }) async {
    pushCalls++;
    if (!enabled) return {'ok': false, 'reason': 'disabled'};
    if (generation != this.generation) {
      return {
        'ok': false,
        'reason': 'generation_mismatch',
        'generation': this.generation,
      };
    }
    if (changes.length > 200) return {'ok': false, 'reason': 'too_many'};
    for (final c in changes) {
      if (!allowed(c['table'] as String)) {
        return {'ok': false, 'reason': 'bad_change', 'key': c['key']};
      }
    }
    // الشبكة: JSON ذهاباً.
    final wire = jsonDecode(jsonEncode(changes)) as List;
    final accepted = [];
    for (final raw in wire) {
      final c = Map<String, dynamic>.from(raw as Map);
      final seen = _byKey[c['key']];
      if (seen != null) {
        accepted.add({'key': c['key'], 'seq': seen, 'duplicate': true});
        continue;
      }
      lastSeq++;
      _byKey[c['key'] as String] = lastSeq;
      this.changes.add({
        'seq': lastSeq,
        'generation': this.generation,
        'device_id': deviceId,
        'table': c['table'],
        'row_key': c['row_key'],
        'op': c['op'],
        'row': c['op'] == 'U' ? c['row'] : null,
      });
      accepted.add({'key': c['key'], 'seq': lastSeq});
    }
    if (dropNextPushResponse) {
      dropNextPushResponse = false;
      throw const SocketException('response lost after commit');
    }
    return {
      'ok': true,
      'last_seq': lastSeq,
      'generation': this.generation,
      'accepted': accepted,
    };
  }

  @override
  Future<Map<String, dynamic>> pull({
    required String deviceId,
    required int afterSeq,
    required int generation,
    required int limit,
  }) async {
    pullCalls++;
    if (!enabled) return {'ok': false, 'reason': 'disabled'};
    if (generation != this.generation) {
      return {
        'ok': false,
        'reason': 'generation_changed',
        'generation': this.generation,
        'last_seq': lastSeq,
        'snapshot_required': true,
      };
    }
    final minSeq = changes.isEmpty ? null : changes.first['seq'] as int;
    if ((minSeq != null && afterSeq < minSeq - 1) ||
        (minSeq == null && afterSeq < lastSeq)) {
      return {
        'ok': false,
        'reason': 'too_old',
        'generation': this.generation,
        'last_seq': lastSeq,
        'snapshot_required': true,
      };
    }
    final page = changes
        .where((c) =>
            (c['seq'] as int) > afterSeq && c['generation'] == this.generation)
        .take(limit)
        .toList();
    final max = page.isEmpty ? afterSeq : page.last['seq'] as int;
    return jsonDecode(jsonEncode({
      'ok': true,
      'generation': this.generation,
      'last_seq': lastSeq,
      'changes': page,
      'has_more': max < lastSeq,
      'primary': primary,
    })) as Map<String, dynamic>;
  }

  void prune(int upToSeq) =>
      changes.removeWhere((c) => (c['seq'] as int) <= upToSeq);
}

void main() {
  late Directory tmp;
  late Fleet f;
  late FakeDeltaServer server;
  late String current;
  var snapshotPulls = 0;
  const slow = Timeout(Duration(minutes: 5));
  final delta = DeltaSyncService.instance;
  late Future<String> Function() realDeviceId;
  late Future<void> Function()? realSnapshotHook;
  late DeltaBackend realBackend;

  setUpAll(() {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    CloudSyncService.instance; // يربط مسارات الخدمة.
    realDeviceId = delta.deviceId;
    realSnapshotHook = delta.onSnapshotRequired;
    realBackend = delta.backend;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_delta_');
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    SyncSafety.changeCapture = true;
    SyncSafety.deltaSync = true;
    await OilChangeTestHarness.instance.reset();
    f = await Fleet.create(3, tmp);
    server = FakeDeltaServer();
    snapshotPulls = 0;
    delta
      ..backend = server
      ..deviceId = (() async => current)
      ..onSnapshotRequired = (() async {
        snapshotPulls++;
      })
      ..resetBackoff();
    // السجل يبدأ من نسخة واحدة مشتركة.
    for (final d in f.devices) {
      final db = await f.activate(d);
      await db.delete(ChangeCapture.outbox);
    }
  });

  tearDown(() async {
    SyncSafety.changeCapture = false;
    SyncSafety.deltaSync = false;
    delta
      ..backend = realBackend
      ..deviceId = realDeviceId
      ..onSnapshotRequired = realSnapshotHook
      ..resetBackoff();
    f.dispose();
    await tmp.delete(recursive: true);
  });

  Future<DeltaCycleResult> cycle(FleetDevice d) async {
    await f.activate(d);
    current = d.name;
    return delta.runCycle();
  }

  Future<void> settle() async {
    for (var round = 0; round < 2; round++) {
      for (final d in f.devices) {
        await cycle(d);
      }
    }
  }

  Future<int> outboxSize(FleetDevice d) async =>
      ChangeCapture.pendingCount(await f.activate(d));

  test('cards from three devices reach every device once', () async {
    await f.createCard(f['A'], 'A-1');
    await f.createCard(f['B'], 'B-1');
    await f.createCard(f['C'], 'C-1');
    await settle();
    for (final d in f.devices) {
      expect(await f.plates(d), {'A-1', 'B-1', 'C-1'}, reason: d.name);
      final db = await f.activate(d);
      final dup = await db.rawQuery(
        'SELECT global_id FROM service_orders GROUP BY global_id '
        'HAVING COUNT(*) > 1',
      );
      expect(dup, isEmpty, reason: d.name);
      expect(await outboxSize(d), 0, reason: d.name);
    }
  }, timeout: slow);

  test('what a device receives is not sent back', () async {
    await f.createCard(f['A'], 'ECHO');
    await cycle(f['A']);
    final sent = server.lastSeq;
    final r = await cycle(f['B']);
    expect(r.received, greaterThan(0));
    expect(await outboxSize(f['B']), 0);
    await cycle(f['B']);
    expect(server.lastSeq, sent);
  }, timeout: slow);

  test('edit, delete and a catalog item travel as changes', () async {
    final id = await f.createCard(f['A'], 'EDIT-1');
    await settle();
    var db = await f.activate(f['A']);
    await db.update(
      'service_orders',
      {
        'deviceSerial': 'EDIT-2',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await OilChangeOilCatalogRepository.instance.insert(
      brandName: 'Castrol',
      viscosity: '5W30',
      sellPerLiterFils: 9000,
    );
    await settle();
    expect(await f.plates(f['C']), {'EDIT-2'});
    db = await f.activate(f['C']);
    expect(
      (await db.rawQuery(
        "SELECT COUNT(*) c FROM oil_change_oil_catalog WHERE brandName='Castrol'",
      )).first['c'],
      1,
    );

    db = await f.activate(f['B']);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.update(
      'service_orders',
      {
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: "deviceSerial = 'EDIT-2'",
    );
    await settle();
    expect(await f.plates(f['A']), isEmpty);
    expect(await f.plates(f['C']), isEmpty);
  }, timeout: slow);

  test('a lost response does not create a second copy', () async {
    await f.createCard(f['A'], 'LOST');
    server.dropNextPushResponse = true;
    final first = await cycle(f['A']);
    expect(first.stoppedBy, 'error');
    expect(await outboxSize(f['A']), greaterThan(0));
    final before = server.lastSeq;
    await cycle(f['A']);
    expect(server.lastSeq, before, reason: 'resend is all duplicates');
    expect(await outboxSize(f['A']), 0);
    await cycle(f['B']);
    expect(await f.plates(f['B']), {'LOST'});
  }, timeout: slow);

  test('account not enabled: nothing sent, quiet, then resumes', () async {
    server.enabled = false;
    await f.createCard(f['A'], 'WAIT');
    final r = await cycle(f['A']);
    expect(r.stoppedBy, 'disabled');
    final calls = server.pushCalls;
    expect((await cycle(f['A'])).stoppedBy, 'disabled');
    expect(server.pushCalls, calls, reason: 'backoff: no second call');
    expect(await outboxSize(f['A']), greaterThan(0));

    server.enabled = true;
    delta.resetBackoff();
    await cycle(f['A']);
    await cycle(f['B']);
    expect(await f.plates(f['B']), {'WAIT'});
  }, timeout: slow);

  test('restore on the server: device takes the snapshot and moves on',
      () async {
    await f.createCard(f['A'], 'GEN-1');
    await settle();
    server.generation = 1;
    final r = await cycle(f['B']);
    expect(r.snapshotRequired, isTrue);
    expect(snapshotPulls, 1);
    final db = await f.activate(f['B']);
    final cur = await ChangeCapture.readCursor(db);
    expect(cur.generation, 1);
    expect(cur.lastSeq, server.lastSeq, reason: 'jumps past old generation');

    await f.createCard(f['B'], 'GEN-2');
    final again = await cycle(f['B']);
    expect(again.pushed, greaterThan(0));
    expect(server.changes.last['generation'], 1);
  }, timeout: slow);

  test('a device away longer than the log takes the snapshot', () async {
    await f.createCard(f['A'], 'OLD-1');
    await cycle(f['A']);
    server.prune(server.lastSeq);
    await f.createCard(f['A'], 'OLD-2');
    await cycle(f['A']);
    final r = await cycle(f['C']);
    expect(r.snapshotRequired, isTrue);
    expect(snapshotPulls, 1);
    final db = await f.activate(f['C']);
    expect((await ChangeCapture.readCursor(db)).lastSeq, server.lastSeq);
  }, timeout: slow);

  test('many changes go in batches and arrive in order', () async {
    final db = await f.activate(f['A']);
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < 450; i++) {
      await db.insert('activity_logs', {
        'type': 'bulk',
        'title': 't$i',
        'createdAt': now,
      });
    }
    final r = await cycle(f['A']);
    expect(r.pushed, 450);
    expect(server.pushCalls, 3);
    final rb = await cycle(f['B']);
    expect(rb.received, 450);
    final dbB = await f.activate(f['B']);
    expect(
      (await dbB.rawQuery(
        "SELECT COUNT(*) c FROM activity_logs WHERE type='bulk'",
      )).first['c'],
      450,
    );
    expect((await ChangeCapture.readCursor(dbB)).lastSeq, server.lastSeq);
  }, timeout: slow);

  test('a table the server refuses does not block the rest', () async {
    server.allowed = (t) => t != 'activity_logs';
    final db = await f.activate(f['A']);
    await db.insert('activity_logs', {
      'type': 'note',
      'title': 'x',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await f.createCard(f['A'], 'GO');
    final r = await cycle(f['A']);
    expect(r.rejected, 1);
    expect(r.pushed, greaterThan(0));
    expect(await outboxSize(f['A']), 0);
    await cycle(f['B']);
    expect(await f.plates(f['B']), {'GO'});
  }, timeout: slow);

  group('phase 5: when the changes cover the full snapshot', () {
    test('not primary on the server: the snapshot stays', () async {
      await f.createCard(f['A'], 'P-0');
      final r = await cycle(f['A']);
      expect(r.primary, isFalse);
      expect(r.coversSnapshot, isFalse);
    }, timeout: slow);

    test('primary and everything delivered: covered', () async {
      server.primary = true;
      await f.createCard(f['A'], 'P-1');
      final r = await cycle(f['A']);
      expect(r.pushed, greaterThan(0));
      expect(r.leftInOutbox, 0);
      expect(r.coversSnapshot, isTrue);
    }, timeout: slow);

    test('a change still waiting: not covered', () async {
      server.primary = true;
      server.allowed = (_) => true;
      await f.createCard(f['A'], 'P-2');
      server.enabled = false;
      final r = await cycle(f['A']);
      expect(r.leftInOutbox, greaterThan(0));
      expect(r.coversSnapshot, isFalse);
    }, timeout: slow);

    test('restore on the server: not covered', () async {
      server.primary = true;
      await f.createCard(f['A'], 'P-3');
      await cycle(f['A']);
      server.generation++;
      final r = await cycle(f['B']);
      expect(r.snapshotRequired, isTrue);
      expect(r.coversSnapshot, isFalse);
    }, timeout: slow);

    test('the full snapshot is due once a day', () async {
      final sync = CloudSyncService.instance;
      expect(await sync.fullSnapshotDue('u1'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      Future<bool> due(DateTime now, Duration ago) async {
        await prefs.setString(
          'delta.last_full_snapshot.u1',
          now.toUtc().subtract(ago).toIso8601String(),
        );
        return sync.fullSnapshotDue('u1', now: now);
      }

      final noon = DateTime(2026, 11, 14, 12);
      final night = DateTime(2026, 11, 15, 2);
      expect(await due(noon, const Duration(hours: 2)), isFalse);
      expect(await due(noon, const Duration(hours: 20)), isFalse);
      expect(await due(noon, const Duration(hours: 25)), isTrue);
      // في الليل تكفي 12 ساعة، فتنتقل النسخة إلى الليل.
      expect(await due(night, const Duration(hours: 13)), isTrue);
      expect(await due(night, const Duration(hours: 5)), isFalse);
    }, timeout: slow);
  });

  test('daily snapshot: a lost delete shows up as drift, nothing removed',
      () async {
    final sync = CloudSyncService.instance;
    var db = await f.activate(f['A']);
    final id = await OilChangeOilCatalogRepository.instance.insert(
      brandName: 'Drift',
      viscosity: '5W20',
      sellPerLiterFils: 5000,
    );
    await f.syncDevice(f['A']);
    await f.activate(f['B']);
    await f.importLatest(f['B'].userId);
    expect(sync.lastSnapshotDrift, isEmpty);

    // الحذف على أ لا يصل إلى ب بالتعديلات (ضاع)، ثم تصل النسخة اليومية.
    db = await f.activate(f['A']);
    await db.delete('oil_change_oil_catalog', where: 'id = ?', whereArgs: [id]);
    await db.delete(ChangeCapture.outbox);
    await f.syncDevice(f['A']);
    final dbB = await f.activate(f['B']);
    await f.importLatest(f['B'].userId);
    expect(sync.lastSnapshotDrift, {'oil_change_oil_catalog': 1});
    expect(
      await dbB.query('oil_change_oil_catalog',
          where: "brandName = 'Drift'"),
      isNotEmpty,
      reason: 'the check only records',
    );
  }, timeout: slow);

  test('switch off: no calls at all', () async {
    SyncSafety.deltaSync = false;
    await f.createCard(f['A'], 'OFF');
    final r = await cycle(f['A']);
    expect(r.stoppedBy, 'off');
    expect(server.pushCalls + server.pullCalls, 0);
  }, timeout: slow);

  test('changes and the full snapshot together stay consistent', () async {
    await f.createCard(f['A'], 'MIX-A');
    await f.createCard(f['B'], 'MIX-B');
    await cycle(f['A']);
    await f.converge();
    await settle();
    await f.converge();
    for (final d in f.devices) {
      expect(await f.plates(d), {'MIX-A', 'MIX-B'}, reason: d.name);
      final Database db = await f.activate(d);
      final dup = await db.rawQuery(
        'SELECT global_id FROM service_orders GROUP BY global_id '
        'HAVING COUNT(*) > 1',
      );
      expect(dup, isEmpty, reason: d.name);
    }
  }, timeout: slow);
}
