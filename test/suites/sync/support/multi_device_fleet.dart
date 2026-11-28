// أدوات مشتركة لاختبارات تعدد الأجهزة: كل جهاز ملف SQLite خاص، والكود الحقيقي
// للرفع والدمج يعمل عليه بالتناوب.

import 'dart:convert';
import 'dart:io';

import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:naboo/services/sync_queue_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../oil_change/helpers/oil_change_test_harness.dart';

/// خادم وهمي يطابق عقد rpc_push_snapshot: إصدار متفائل ومفتاح عدم تكرار.
abstract class SnapshotCloud {
  Future<Map<String, dynamic>> pushSnapshot({
    required int expectedVersion,
    required Map<String, dynamic> incoming,
    required String idempotencyKey,
  });
  Future<int> currentVersion();
  Future<Map<String, dynamic>?> currentPayload();
}

class FakeCloud implements SnapshotCloud {
  @override
  Future<Map<String, dynamic>> pushSnapshot({
    required int expectedVersion,
    required Map<String, dynamic> incoming,
    required String idempotencyKey,
  }) async =>
      push(
        expectedVersion: expectedVersion,
        incoming: incoming,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<int> currentVersion() async => version;

  @override
  Future<Map<String, dynamic>?> currentPayload() async => payload;

  int version = 0;
  Map<String, dynamic>? payload;
  final Map<String, int> _idempotency = {};
  int pushes = 0;
  int conflicts = 0;
  int bytesUploaded = 0;
  bool dropNextResponse = false;

  Map<String, dynamic> push({
    required int expectedVersion,
    required Map<String, dynamic> incoming,
    required String idempotencyKey,
  }) {
    final seen = _idempotency[idempotencyKey];
    if (seen != null) {
      return {'ok': true, 'new_version': seen, 'idempotent': true};
    }
    if (expectedVersion != version) {
      conflicts++;
      return {
        'ok': false,
        'reason': 'version_conflict',
        'current_version': version,
      };
    }
    final encoded = jsonEncode(incoming);
    pushes++;
    bytesUploaded += utf8.encode(encoded).length;
    version++;
    payload = jsonDecode(encoded) as Map<String, dynamic>;
    _idempotency[idempotencyKey] = version;
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const SocketException('response lost after commit');
    }
    return {
      'ok': true,
      'new_version': version,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

/// جهاز = ملف SQLite خاص + مفتاح prefs خاص (المفاتيح مربوطة بـ userId).
class FleetDevice {
  FleetDevice(this.name, this.file);

  final String name;
  final String file;

  /// جهاز بنسخة قديمة: يعمل بلا إصلاحات [SyncSafety].
  bool legacy = false;
  String get userId => 'baseline-$name';
}

class Fleet {
  Fleet._(this.remote, this.devices, this._livePath);

  final SnapshotCloud remote;
  FakeCloud get cloud => remote as FakeCloud;
  final List<FleetDevice> devices;
  final String _livePath;
  FleetDevice? _active;

  final _helper = OilChangeTestHarness.instance.dbHelper;
  final _sync = CloudSyncService.instance;
  final _builder = ServiceOrderBuilder(OilChangeTestHarness.instance);

  static Future<Fleet> create(
    int count,
    Directory dir, {
    SnapshotCloud? remote,
  }) async {
    final harness = OilChangeTestHarness.instance;
    await harness.reset();
    await harness.configureServiceOnly();
    final db = await harness.database;
    // الأجهزة نسخ من قاعدة أساس: ما التُقط أثناء تجهيزها ليس تعديلاً من جهاز.
    await db.execute('DELETE FROM sync_outbox');
    final base = p.join(dir.path, 'base.db');
    await File(base).parent.create(recursive: true);
    await db.execute('VACUUM INTO ?', [base]);

    final devices = <FleetDevice>[];
    for (var i = 0; i < count; i++) {
      final name = String.fromCharCode(65 + i);
      final file = p.join(dir.path, '$name.db');
      await File(base).copy(file);
      devices.add(FleetDevice(name, file));
    }
    final live = p.join(await getDatabasesPath(), 'business_app.db');
    final fleet = Fleet._(remote ?? FakeCloud(), devices, live);
    await fleet._wire();
    return fleet;
  }

  Future<void> _wire() async {
    _sync
      ..suppressScheduleSyncSoonForTesting = true
      ..remoteBusinessGuardInfoForTesting = ((_) async => (
            chunked: false,
            counts: const <String, int>{},
          ))
      ..pushSnapshotRpcOverrideForTesting = (({
        required expectedVersion,
        required payload,
        required schemaVersion,
        required deviceLabel,
        required idempotencyKey,
        uploadId,
      }) =>
          remote.pushSnapshot(
            expectedVersion: expectedVersion,
            incoming: payload,
            idempotencyKey: idempotencyKey,
          ))
      ..conflictPullOverrideForTesting = (({
        required userId,
        forceImport = false,
      }) =>
          importLatest(userId));
    for (final d in devices) {
      await _sync.setDeviceHydratedForTesting(d.userId, true);
    }
  }

  void dispose() {
    _sync
      ..remoteBusinessGuardInfoForTesting = null
      ..pushSnapshotRpcOverrideForTesting = null
      ..conflictPullOverrideForTesting = null;
  }

  FleetDevice operator [](String name) =>
      devices.firstWhere((d) => d.name == name);

  /// يبدّل الجهاز النشط بنسخ ملفه إلى مسار [DatabaseHelper] الوحيد.
  Future<Database> activate(FleetDevice d) async {
    // كل عملية على الجهاز تعمل بإصلاحات نسخته هو.
    SyncSafety.enabled = !d.legacy;
    if (!identical(_active, d)) {
      if (_active != null) {
        final db = await _helper.database;
        await File(_active!.file).delete();
        await db.execute('VACUUM INTO ?', [_active!.file]);
      }
      await _helper.closeAndDeleteDatabaseFile();
      await File(d.file).copy(_livePath);
      _active = d;
    }
    return _helper.database;
  }

  /// يعيد فتح قاعدة الجهاز كما يحدث عند إعادة تشغيل التطبيق.
  Future<Database> reopen(FleetDevice d) async {
    final current = await activate(d);
    await File(d.file).delete();
    await current.execute('VACUUM INTO ?', [d.file]);
    _active = null;
    await _helper.closeAndDeleteDatabaseFile();
    return activate(d);
  }

  Future<void> importLatest(String userId) async {
    final latest = await this.remote.currentPayload();
    if (latest == null) return;
    final copy = jsonDecode(jsonEncode(latest)) as Map<String, dynamic>;
    await _sync.importSnapshotForTesting(copy);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'sync.last_remote_content_version.$userId',
      await this.remote.currentVersion(),
    );
    // كما في السحب الحقيقي: لا يُعاد رفع ما وصل للتو إن لم يبقَ جديد محلي.
    await _sync.skipEchoPushIfNothingNewForTesting(
      userId: userId,
      payload: copy,
    );
  }

  /// نفس ترتيب scheduleSyncSoon: سحب ثم رفع.
  Future<bool> syncDevice(FleetDevice d, {bool processQueue = true}) async {
    await activate(d);
    if (processQueue) {
      await OilChangeTestHarness.instance.mockSyncQueueProcessed();
      // processQueue يعيد جدولة نفسه بعد ثانيتين؛ لولا هذا لفتح قاعدة جهاز أُغلقت.
      SyncQueueService.instance.authCheckForTesting = () => false;
    }
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt('sync.last_remote_content_version.${d.userId}') ?? 0;
    if (seen < await remote.currentVersion()) await importLatest(d.userId);
    return _sync.pushSnapshotForTesting(userId: d.userId, forcePush: false);
  }

  /// جولات متتالية حتى يهدأ الخادم ولا يبقى تغيير.
  Future<void> converge({bool processQueue = true}) async {
    for (var round = 0; round < 3; round++) {
      for (final d in devices) {
        await syncDevice(d, processQueue: processQueue);
      }
    }
  }

  Future<int> createCard(FleetDevice d, String plate) async {
    await activate(d);
    final id = await _builder.createPending(plate: plate);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return id;
  }

  Future<Set<String>> plates(FleetDevice d) async {
    final db = await activate(d);
    final rows = await db.rawQuery(
      'SELECT deviceSerial FROM service_orders WHERE deletedAt IS NULL',
    );
    return rows.map((r) => r['deviceSerial'].toString()).toSet();
  }

  Future<Map<String, Set<String>>> platesByDevice() async {
    return {for (final d in devices) d.name: await plates(d)};
  }
}
