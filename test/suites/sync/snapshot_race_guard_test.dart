/*
  Snapshot race guard — البند 1.

  يغطي:
    (أ) رفعان بنفس expected_version → الأول ok والثاني version_conflict
    (ب) الجهاز المرفوض: سحب + إعادة تطبيق طابور + رفع ينجح
    (ج) محلي فارغ + سحابة غنية → رفض قبل أي RPC
    (د) إعادة محاولة بنفس idempotency_key → ok بدون رفع نسخة جديدة منطقياً
    (هـ) أجزاء اللقطة تُفلتر بـ upload_id
    (و) محاكاة كاتب قديم (تحديث مباشر يرفع الإصدار) → التعارض التالي
*/

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/snapshot_race_guard.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openRaceGuardDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            global_id TEXT UNIQUE,
            name TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0,
            updatedAt TEXT,
            deletedAt TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            mutation_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            synced_at TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            last_attempt_at TEXT
          )
        ''');
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // path_provider قد يُستدعى من مسارات جانبية.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
  });

  tearDown(() {
    final s = CloudSyncService.instance;
    s
      ..pushSnapshotRpcOverrideForTesting = null
      ..remoteSnapshotHasNonEmptyOverrideForTesting = null
      ..conflictPullOverrideForTesting = null
      ..localDbHasNoSyncDataOverrideForTesting = null
      ..databaseProviderForTesting = null
      ..suppressScheduleSyncSoonForTesting = false;
  });

  group('SnapshotRaceGuard pure helpers', () {
    test('(أ) parse: ok ثم version_conflict', () {
      final ok = SnapshotRaceGuard.parsePushRpcResponse({
        'ok': true,
        'new_version': 2,
        'updated_at': '2026-07-16T00:00:00Z',
      });
      expect(ok.ok, isTrue);
      expect(ok.newVersion, 2);

      final conflict = SnapshotRaceGuard.parsePushRpcResponse({
        'ok': false,
        'reason': 'version_conflict',
        'current_version': 2,
      });
      expect(conflict.isVersionConflict, isTrue);
      expect(conflict.currentVersion, 2);
    });

    test('(د) parse: idempotent retry', () {
      final r = SnapshotRaceGuard.parsePushRpcResponse({
        'ok': true,
        'new_version': 5,
        'idempotent': true,
      });
      expect(r.ok, isTrue);
      expect(r.idempotent, isTrue);
      expect(r.newVersion, 5);
    });

    test('shouldSkipPull prefers content_version over updated_at', () {
      expect(
        SnapshotRaceGuard.shouldSkipPullAsCurrent(
          remoteContentVersion: 3,
          lastImportedContentVersion: 3,
          remoteUpdatedAt: 'a',
          lastImportedUpdatedAt: 'b',
        ),
        isTrue,
      );
      expect(
        SnapshotRaceGuard.shouldSkipPullAsCurrent(
          remoteContentVersion: 4,
          lastImportedContentVersion: 3,
          remoteUpdatedAt: 'same',
          lastImportedUpdatedAt: 'same',
        ),
        isFalse,
      );
      expect(
        SnapshotRaceGuard.shouldSkipPullAsCurrent(
          remoteContentVersion: null,
          lastImportedContentVersion: null,
          remoteUpdatedAt: 't1',
          lastImportedUpdatedAt: 't1',
        ),
        isTrue,
      );
    });

    test('SyncEntityTypes.sqliteTableFor covers queue entities', () {
      expect(SyncEntityTypes.sqliteTableFor(SyncEntityTypes.customer), 'customers');
      expect(SyncEntityTypes.sqliteTableFor(SyncEntityTypes.cashLedger), 'cash_ledger');
      expect(SyncEntityTypes.sqliteTableFor('unknown'), isNull);
    });
  });

  group('CloudSyncService race-guard paths', () {
    late Database db;
    late CloudSyncService sync;

    setUp(() async {
      db = await _openRaceGuardDb();
      sync = CloudSyncService.instance
        ..databaseProviderForTesting = (() async => db)
        ..suppressScheduleSyncSoonForTesting = true;
    });

    tearDown(() async {
      await db.close();
    });

    test('(أ) جهازان بنفس expected_version — واحد ينجح والثاني يتعارض', () async {
      await db.insert('customers', {
        'global_id': 'c1',
        'name': 'زبون',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync.last_remote_content_version.user-a', 1);

      var calls = 0;
      final versionsSeen = <int>[];
      sync.pushSnapshotRpcOverrideForTesting =
          ({
            required expectedVersion,
            required payload,
            required schemaVersion,
            required deviceLabel,
            required idempotencyKey,
            uploadId,
          }) async {
            calls++;
            versionsSeen.add(expectedVersion);
            if (calls == 1) {
              return {
                'ok': true,
                'new_version': expectedVersion + 1,
                'updated_at': '2026-07-16T01:00:00Z',
              };
            }
            return {
              'ok': false,
              'reason': 'version_conflict',
              'current_version': expectedVersion + 1,
            };
          };

      final first = await sync.pushSnapshotForTesting(userId: 'user-a');
      expect(first, isTrue);
      expect(prefs.getInt('sync.last_remote_content_version.user-a'), 2);

      // جهاز ثانٍ ما زال يتوقع 1 (محاكاة prefs منفصلة عبر إعادة المفتاح).
      await prefs.setInt('sync.last_remote_content_version.user-b', 1);
      sync.conflictPullOverrideForTesting =
          ({required userId, forceImport = false}) async {
            await prefs.setInt('sync.last_remote_content_version.$userId', 2);
          };
      // بعد تعارض واحد سيعيد السحب ثم يحاول مجدداً — نجعل المحاولة الثانية تنجح
      // بعد تحديث الإصدار المتوقع.
      var bCalls = 0;
      sync.pushSnapshotRpcOverrideForTesting =
          ({
            required expectedVersion,
            required payload,
            required schemaVersion,
            required deviceLabel,
            required idempotencyKey,
            uploadId,
          }) async {
            bCalls++;
            if (expectedVersion == 1) {
              return {
                'ok': false,
                'reason': 'version_conflict',
                'current_version': 2,
              };
            }
            return {
              'ok': true,
              'new_version': expectedVersion + 1,
              'updated_at': '2026-07-16T01:01:00Z',
            };
          };

      final second = await sync.pushSnapshotForTesting(userId: 'user-b');
      expect(second, isTrue);
      expect(bCalls, greaterThanOrEqualTo(2));
      expect(versionsSeen, isNotEmpty);
    });

    test('(ب) بعد التعارض: إعادة تطبيق pending تفوز على قيمة مدموجة', () async {
      await db.insert('customers', {
        'global_id': 'cust-x',
        'name': 'من-اللقطة',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      await db.insert('sync_queue', {
        'mutation_id': 'm1',
        'entity_type': SyncEntityTypes.customer,
        'operation': 'UPDATE',
        'payload': jsonEncode({
          'global_id': 'cust-x',
          'name': 'من-الطابور-المحلي',
          'updatedAt': '2026-07-16T00:00:00Z',
        }),
        'created_at': '2026-07-16T00:00:00Z',
        'status': 'pending',
        'retry_count': 0,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync.last_remote_content_version.u1', 5);

      var rpcCalls = 0;
      sync.pushSnapshotRpcOverrideForTesting =
          ({
            required expectedVersion,
            required payload,
            required schemaVersion,
            required deviceLabel,
            required idempotencyKey,
            uploadId,
          }) async {
            rpcCalls++;
            if (rpcCalls == 1) {
              return {
                'ok': false,
                'reason': 'version_conflict',
                'current_version': 6,
              };
            }
            // بعد إعادة التطبيق يجب أن يحمل الـ payload الاسم المحلي.
            final tables = payload['tables'];
            expect(tables, isA<Map>());
            final customers = (tables as Map)['customers'];
            expect(customers, isA<List>());
            final names = (customers as List)
                .whereType<Map>()
                .map((e) => e['name']?.toString())
                .toList();
            expect(names, contains('من-الطابور-المحلي'));
            return {
              'ok': true,
              'new_version': 7,
              'updated_at': '2026-07-16T02:00:00Z',
            };
          };

      sync.conflictPullOverrideForTesting =
          ({required userId, forceImport = false}) async {
            // يحاكي دمج لقطة بعيدة أعادت الاسم القديم.
            await db.update(
              'customers',
              {'name': 'من-اللقطة'},
              where: 'global_id = ?',
              whereArgs: ['cust-x'],
            );
            await prefs.setInt('sync.last_remote_content_version.$userId', 6);
          };

      final ok = await sync.pushSnapshotForTesting(userId: 'u1');
      expect(ok, isTrue);
      expect(rpcCalls, 2);

      final rows = await db.query(
        'customers',
        where: 'global_id = ?',
        whereArgs: ['cust-x'],
      );
      expect(rows.first['name'], 'من-الطابور-المحلي');
    });

    test('(ج) محلي فارغ + سحابة غنية يُرفض قبل RPC', () async {
      var rpcCalls = 0;
      sync
        ..localDbHasNoSyncDataOverrideForTesting = (() async => true)
        ..remoteSnapshotHasNonEmptyOverrideForTesting = ((_) async => true)
        ..pushSnapshotRpcOverrideForTesting =
            ({
              required expectedVersion,
              required payload,
              required schemaVersion,
              required deviceLabel,
              required idempotencyKey,
              uploadId,
            }) async {
              rpcCalls++;
              return {'ok': true, 'new_version': 1};
            };

      final ok = await sync.pushSnapshotForTesting(userId: 'empty-user');
      expect(ok, isFalse);
      expect(rpcCalls, 0);
      expect(sync.lastError.value, contains('فارغة'));
    });

    test('(د) نفس idempotency_key يعيد ok بدون فشل', () async {
      await db.insert('customers', {
        'global_id': 'c-idem',
        'name': 'x',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync.last_remote_content_version.idem', 3);
      await prefs.setString(
        'sync.pending_idempotency_key.idem',
        'same-key-123',
      );

      var calls = 0;
      sync.pushSnapshotRpcOverrideForTesting =
          ({
            required expectedVersion,
            required payload,
            required schemaVersion,
            required deviceLabel,
            required idempotencyKey,
            uploadId,
          }) async {
            calls++;
            expect(idempotencyKey, 'same-key-123');
            return {
              'ok': true,
              'new_version': 3,
              'idempotent': true,
              'updated_at': '2026-07-16T03:00:00Z',
            };
          };

      expect(await sync.pushSnapshotForTesting(userId: 'idem'), isTrue);
      expect(calls, 1);
      expect(prefs.getInt('sync.last_remote_content_version.idem'), 3);
    });

    test('(هـ) filterChunksByUploadId يتجاهل upload_id أجنبي', () {
      final rows = [
        {'chunk_index': 0, 'chunk_data': 'a', 'upload_id': 'u1'},
        {'chunk_index': 1, 'chunk_data': 'b', 'upload_id': 'foreign'},
        {'chunk_index': 2, 'chunk_data': 'c', 'upload_id': 'u1'},
      ];
      final filtered = CloudSyncService.filterChunksByUploadId(
        rows: rows,
        uploadId: 'u1',
      );
      expect(filtered.length, 2);
      expect(filtered.map((e) => e['chunk_data']), ['a', 'c']);
    });

    test('(و) محاكاة كاتب قديم يرفع الإصدار → التعارض على المتوقع القديم', () async {
      // وثائقي سلوكي: أي UPDATE مباشر على app_snapshots يحرّك trigger
      // trg_bump_snapshot_version؛ الكلاينت الذي ما زال يتوقع النسخة القديمة
      // يحصل على version_conflict من rpc_push_snapshot.
      await db.insert('customers', {
        'global_id': 'legacy',
        'name': 'n',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync.last_remote_content_version.legacy', 10);

      // محاكاة: بعد bump من كاتب قديم أصبحت السحابة على 11.
      var serverVersion = 11;
      sync.conflictPullOverrideForTesting =
          ({required userId, forceImport = false}) async {
            await prefs.setInt(
              'sync.last_remote_content_version.$userId',
              serverVersion,
            );
          };
      sync.pushSnapshotRpcOverrideForTesting =
          ({
            required expectedVersion,
            required payload,
            required schemaVersion,
            required deviceLabel,
            required idempotencyKey,
            uploadId,
          }) async {
            if (expectedVersion != serverVersion) {
              return {
                'ok': false,
                'reason': 'version_conflict',
                'current_version': serverVersion,
              };
            }
            serverVersion += 1;
            return {
              'ok': true,
              'new_version': serverVersion,
              'updated_at': '2026-07-16T04:00:00Z',
            };
          };

      final ok = await sync.pushSnapshotForTesting(userId: 'legacy');
      expect(ok, isTrue);
      expect(prefs.getInt('sync.last_remote_content_version.legacy'), 12);
    });
  });
}
