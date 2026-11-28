// البند 5.1: ملف قاعدة لكل حساب.
//
// كان تبديل الحساب السحابي يحذف ملف القاعدة، فتضيع بطاقة بيعت دون إنترنت ولم
// تُرفع. الآن يُحفظ الملف جانباً، ويعود إذا دخل الحساب نفسه، ثم تصل البطاقة
// إلى الخادم وإلى الجهاز الآخر.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/db_file_parking.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  late Directory tmp;
  late Fleet f;
  const slow = Timeout(Duration(minutes: 5));
  final helper = OilChangeTestHarness.instance.dbHelper;

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_park_');
    // ملفات محفوظة من تشغيل سابق في مجلد القواعد المشترك.
    for (final e in Directory(await getDatabasesPath()).listSync()) {
      if (p.basename(e.path).contains('.parked.')) e.deleteSync();
    }
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.set('1');
    f = await Fleet.create(2, tmp);
    for (final d in f.devices) {
      await f.syncDevice(d);
    }
  });

  tearDown(() async {
    f.dispose();
    CloudSyncService.instance.suppressScheduleSyncSoonForTesting = false;
    await tmp.delete(recursive: true);
  });

  /// التطبيق يمسح كل مفاتيح sync. على الجهاز. هنا الأجهزة تتشارك التفضيلات،
  /// ومفاتيح كل جهاز تحمل معرّفه، فيُمسح ما يخص الجهاز وحده.
  Future<void> clearSyncPrefs([String device = 'A']) async {
    final prefs = await SharedPreferences.getInstance();
    final id = f[device].userId;
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith('sync.') && k.endsWith(id)) await prefs.remove(k);
    }
  }

  /// ما يفعله التطبيق بعد دخول الحساب: مسح تفضيلات المزامنة، ثم سحب ودمج
  /// إجباري يعلّم الجهاز مرطّباً، ثم يُسمح بالرفع.
  Future<void> signBackIn(FleetDevice d) async {
    await clearSyncPrefs(d.name);
    await f.importLatest(d.userId);
    await CloudSyncService.instance.setDeviceHydratedForTesting(d.userId, true);
  }

  test('بطاقة لم تُرفع تبقى بعد تبديل الحساب وتصل الخادم عند العودة', () async {
    await f.activate(f['A']);
    await f.createCard(f['A'], 'OFFLINE-1'); // بيعت دون إنترنت، لم تُرفع.

    // دخول حساب آخر على الجهاز A: يرى قاعدة فارغة لا بيانات الحساب الأول.
    final restoredOther = await helper.closeAndSwapAccountDatabaseFile(
      parkAs: 'cloud:owner-1',
      restoreFor: 'cloud:owner-2',
    );
    expect(restoredOther, isFalse);
    await clearSyncPrefs();
    expect(await f.plates(f['A']), isEmpty,
        reason: 'الحساب الآخر رأى بطاقات الحساب الأول');

    // عودة الحساب الأول: يُستعاد ملفه ثم يُدمج مع السحابة ويُرفع.
    final restored = await helper.closeAndSwapAccountDatabaseFile(
      parkAs: 'cloud:owner-2',
      restoreFor: 'cloud:owner-1',
    );
    expect(restored, isTrue);
    await signBackIn(f['A']);
    expect(await f.plates(f['A']), contains('OFFLINE-1'),
        reason: 'ضاعت البطاقة في الدمج بعد العودة');

    await f.converge();
    expect(await f.plates(f['B']), contains('OFFLINE-1'),
        reason: 'البطاقة لم تصل إلى الجهاز الآخر');
  }, timeout: slow);

  test('عودة الحساب لا تُرجع ما حذفه جهاز آخر أثناء الغياب', () async {
    await f.createCard(f['B'], 'KEEP');
    await f.createCard(f['B'], 'GONE');
    await f.converge();

    await f.activate(f['A']);
    await helper.closeAndSwapAccountDatabaseFile(
      parkAs: 'cloud:owner-1',
      restoreFor: 'cloud:owner-2',
    );
    await clearSyncPrefs();

    // أثناء غياب الحساب عن A يحذف B بطاقة.
    final dbB = await f.activate(f['B']);
    final now = DateTime.now().toUtc().toIso8601String();
    final n = await dbB.update(
      'service_orders',
      {'deletedAt': now, 'updatedAt': now},
      where: "deviceSerial = 'GONE' AND deletedAt IS NULL",
    );
    expect(n, 1);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await f.syncDevice(f['B']);

    // A يعود: ملفه القديم فيه GONE، لكن الخادم أحدث فلا تعود.
    await f.activate(f['A']);
    await helper.closeAndSwapAccountDatabaseFile(
      parkAs: 'cloud:owner-2',
      restoreFor: 'cloud:owner-1',
    );
    await signBackIn(f['A']);
    await f.converge();
    for (final d in f.devices) {
      final plates = await f.plates(d);
      expect(plates, contains('KEEP'));
      expect(plates, isNot(contains('GONE')),
          reason: 'عادت بطاقة محذوفة على ${d.name}');
    }
  }, timeout: slow);

  test('ملف محفوظ سابقاً لنفس الحساب لا يُكتب فوقه', () async {
    final dir = await Directory.systemTemp.createTemp('naboo_park_files_');
    addTearDown(() => dir.delete(recursive: true));
    final live = p.join(dir.path, 'business_app.db');
    const parking = DbFileParking.instance;

    await File(live).writeAsString('first');
    await parking.park(live, 'cloud:owner-1');
    await File(live).writeAsString('second');
    await parking.park(live, 'cloud:owner-1');

    final names = dir.listSync().map((e) => p.basename(e.path)).toList();
    expect(names.where((n) => n.contains('parked')), hasLength(2),
        reason: 'حُذف ملف محفوظ');
    expect(await parking.restore(live, 'cloud:owner-1'), isTrue);
    expect(await File(live).readAsString(), 'second');

    // الاستعادة فوق ملف موجود تحفظه أولاً.
    await File(p.join(dir.path, 'business_app.parked.cloud_owner-3.db'))
        .writeAsString('third');
    expect(await parking.restore(live, 'cloud:owner-3'), isTrue);
    expect(await File(live).readAsString(), 'third');
    final all = dir.listSync().map((e) => p.basename(e.path)).toList();
    expect(all.where((n) => n.contains('replaced')), hasLength(1));
  });

  test('مالك مجهول يُحفظ باسم مؤرخ ولا يُستعاد تلقائياً', () {
    expect(
      DbFileParking.ownerKeyForParking(active: 'cloud:a', lastAfterUnlink: 'x'),
      'cloud:a',
    );
    expect(
      DbFileParking.ownerKeyForParking(active: null, lastAfterUnlink: 'cloud:b'),
      'cloud:b',
    );
    expect(
      DbFileParking.ownerKeyForParking(
        active: '',
        lastAfterUnlink: null,
        now: DateTime.utc(2026, 11, 12),
      ),
      startsWith('unknown-'),
    );
  });

  test('ملف بلا ملحقات WAL ينقل كاملاً', () async {
    final dir = await Directory.systemTemp.createTemp('naboo_park_wal_');
    addTearDown(() => dir.delete(recursive: true));
    final live = p.join(dir.path, 'business_app.db');
    final db = await databaseFactoryFfi.openDatabase(live);
    await db.execute('PRAGMA journal_mode = WAL');
    await db.execute('CREATE TABLE t (x)');
    await db.insert('t', {'x': 1});
    await db.close();
    await DbFileParking.instance.park(live, 'cloud:w');
    expect(await File(live).exists(), isFalse);
    expect(await DbFileParking.instance.restore(live, 'cloud:w'), isTrue);
    final again = await databaseFactoryFfi.openDatabase(live);
    expect(await again.query('t'), hasLength(1));
    await again.close();
  });
}
