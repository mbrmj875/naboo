import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// قاعدة بيانات ذاكرية تحتوي فقط جدول `sync_queue` كي تُختبر دورة حياة
/// طابور المزامنة بدون الاعتماد على DatabaseHelper الكامل.
Future<Database> _openSyncQueueDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
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
  return db;
}

Future<void> _seed(
  Database db, {
  required String mutationId,
  String entityType = 'expense',
  String operation = 'INSERT',
  Map<String, dynamic>? payload,
  String status = 'pending',
  int retryCount = 0,
  String? lastAttemptAt,
}) async {
  await db.insert('sync_queue', {
    'mutation_id': mutationId,
    'entity_type': entityType,
    'operation': operation,
    'payload': jsonEncode(payload ?? {'global_id': 'g_$mutationId'}),
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'status': status,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
  });
}

Future<Map<String, Object?>> _readRow(Database db, String mutationId) async {
  final rows = await db.query(
    'sync_queue',
    where: 'mutation_id = ?',
    whereArgs: [mutationId],
  );
  expect(rows, hasLength(1), reason: 'mutation $mutationId missing');
  return rows.first;
}

void main() {
  late SyncQueueService service;
  late Database db;

  setUp(() async {
    db = await _openSyncQueueDb();
    service = SyncQueueService.instance
      ..databaseProviderForTesting = (() async => db)
      ..authCheckForTesting = (() => true)
      ..deviceIdProviderForTesting = (() async => 'device-test');
  });

  tearDown(() async {
    service
      ..databaseProviderForTesting = null
      ..authCheckForTesting = null
      ..deviceIdProviderForTesting = null
      ..rpcOverrideForTesting = null;
    await db.close();
  });

  group('rpc_process_sync_queue per-mutation results', () {
    test('mock RPC returns [{ok}, {fail}, {ok}] → 1st & 3rd synced, 2nd failed',
        () async {
      await _seed(db, mutationId: 'm1');
      await _seed(db, mutationId: 'm2');
      await _seed(db, mutationId: 'm3');

      List<Map<String, dynamic>>? receivedPayload;
      service.rpcOverrideForTesting = (mutations) async {
        receivedPayload = mutations;
        return const [
          SyncMutationResult(mutationId: 'm1', ok: true),
          SyncMutationResult(
            mutationId: 'm2',
            ok: false,
            error: 'category not found',
          ),
          SyncMutationResult(mutationId: 'm3', ok: true),
        ];
      };

      await service.processQueue();

      expect(receivedPayload, hasLength(3));
      // كل عنصر يجب أن يحوي meta-fields التي أضافها العميل قبل الإرسال.
      for (final p in receivedPayload!) {
        expect(p['_mutation_id'], isA<String>());
        expect(p['_entity_type'], 'expense');
        expect(p['_operation'], 'INSERT');
        expect(p['_device_id'], 'device-test');
      }

      final r1 = await _readRow(db, 'm1');
      expect(r1['status'], 'synced');
      expect(r1['retry_count'], 0);
      expect(r1['last_error'], isNull);
      expect(r1['synced_at'], isA<String>());

      final r2 = await _readRow(db, 'm2');
      expect(r2['status'], 'failed');
      expect(r2['retry_count'], 1);
      expect(r2['last_error'], 'category not found');
      expect(r2['last_attempt_at'], isA<String>());

      final r3 = await _readRow(db, 'm3');
      expect(r3['status'], 'synced');
      expect(r3['retry_count'], 0);
      expect(r3['last_error'], isNull);
    });

    test('does not increment retry_count for successful mutations in a mixed batch',
        () async {
      // m1 نجاح، m2 فشل — m1 retry_count يجب أن يبقى 0 ولا يزيد إلى 1.
      await _seed(db, mutationId: 'm1', retryCount: 0);
      await _seed(db, mutationId: 'm2', retryCount: 0);

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'm1', ok: true),
            SyncMutationResult(mutationId: 'm2', ok: false, error: 'boom'),
          ];

      await service.processQueue();

      final r1 = await _readRow(db, 'm1');
      expect(r1['status'], 'synced');
      expect(r1['retry_count'], 0,
          reason: 'success must NOT increment retry_count');
      final r2 = await _readRow(db, 'm2');
      expect(r2['status'], 'failed');
      expect(r2['retry_count'], 1);
    });

    test('all mutations ok → all marked synced', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await _seed(db, mutationId: id);
      }

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'a', ok: true),
            SyncMutationResult(mutationId: 'b', ok: true),
            SyncMutationResult(mutationId: 'c', ok: true),
            SyncMutationResult(mutationId: 'd', ok: true),
          ];

      await service.processQueue();

      for (final id in ['a', 'b', 'c', 'd']) {
        final r = await _readRow(db, id);
        expect(r['status'], 'synced', reason: 'mutation $id');
        expect(r['retry_count'], 0);
        expect(r['last_error'], isNull);
      }
    });

    test('all mutations fail → all marked failed (retry_count incremented)',
        () async {
      for (final id in ['x', 'y', 'z']) {
        await _seed(db, mutationId: id);
      }

      service.rpcOverrideForTesting = (_) async => [
            const SyncMutationResult(mutationId: 'x', ok: false, error: 'e1'),
            const SyncMutationResult(mutationId: 'y', ok: false, error: 'e2'),
            const SyncMutationResult(mutationId: 'z', ok: false, error: 'e3'),
          ];

      await service.processQueue();

      for (final id in ['x', 'y', 'z']) {
        final r = await _readRow(db, id);
        expect(r['status'], 'failed', reason: 'mutation $id');
        expect(r['retry_count'], 1);
        expect(r['last_error'], isNotNull);
      }
    });

    test('empty queue → no RPC call made', () async {
      var rpcCalls = 0;
      service.rpcOverrideForTesting = (_) async {
        rpcCalls++;
        return const [];
      };

      await service.processQueue();
      expect(rpcCalls, 0, reason: 'must not call RPC when queue is empty');
    });

    test('RPC network error → all mutations stay pending (no retry increment)',
        () async {
      await _seed(db, mutationId: 'm1', retryCount: 0);
      await _seed(db, mutationId: 'm2', retryCount: 0);

      service.rpcOverrideForTesting = (_) async {
        throw const SyncRpcTransportException('SocketException: failed host lookup');
      };

      await service.processQueue();

      final r1 = await _readRow(db, 'm1');
      expect(r1['status'], 'pending');
      expect(r1['retry_count'], 0);
      expect(r1['last_error'], isNull);
      expect(r1['last_attempt_at'], isNull);

      final r2 = await _readRow(db, 'm2');
      expect(r2['status'], 'pending');
      expect(r2['retry_count'], 0);
      expect(r2['last_error'], isNull);
      expect(r2['last_attempt_at'], isNull);
    });

    test(
        'mutation missing from RPC response → marked failed with explicit reason',
        () async {
      // الباتش فيه m1 و m2، السيرفر يُرجع نتيجة m1 فقط — m2 يجب ألّا يضيع.
      await _seed(db, mutationId: 'm1', retryCount: 0);
      await _seed(db, mutationId: 'm2', retryCount: 0);

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'm1', ok: true),
          ];

      await service.processQueue();

      final r1 = await _readRow(db, 'm1');
      expect(r1['status'], 'synced');
      expect(r1['retry_count'], 0);

      final r2 = await _readRow(db, 'm2');
      expect(r2['status'], 'failed');
      expect(r2['retry_count'], 1);
      expect(r2['last_error'].toString(), contains('no_result_for_mutation'));
    });

    test('reaching max retries marks mutation as dead', () async {
      // 5 محاولات سابقة + فشل جديد → retry_count يصبح 5 → الحالة dead.
      await _seed(db, mutationId: 'm1', retryCount: 4, status: 'pending');

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'm1', ok: false, error: 'fatal'),
          ];

      await service.processQueue();

      final r = await _readRow(db, 'm1');
      expect(r['status'], 'dead');
      expect(r['retry_count'], 5);
      expect(r['last_error'], 'fatal');
    });

    test('SyncMutationResult.tryParse handles canonical and edge inputs', () {
      final ok = SyncMutationResult.tryParse({
        'mutation_id': 'abc',
        'status': 'OK',
        'error': null,
      });
      expect(ok, isNotNull);
      expect(ok!.ok, isTrue);
      expect(ok.error, isNull);

      final fail = SyncMutationResult.tryParse({
        'mutation_id': 'xyz',
        'status': 'fail',
        'error': 'category not found',
      });
      expect(fail!.ok, isFalse);
      expect(fail.error, 'category not found');

      // مدخلات سيئة:
      expect(SyncMutationResult.tryParse(null), isNull);
      expect(SyncMutationResult.tryParse('not a map'), isNull);
      expect(SyncMutationResult.tryParse({'status': 'ok'}), isNull,
          reason: 'missing mutation_id');
    });
  });

  group('rpc_process_sync_queue migration (documentary)', () {
    test('migration file exists and contains the expected SQL hooks', () {
      final f = File('migrations/20260508_rpc_per_mutation.sql');
      expect(f.existsSync(), isTrue,
          reason: 'migrations/20260508_rpc_per_mutation.sql must exist');

      final sql = f.readAsStringSync();

      // 1) drop+create على نوع الإرجاع الجديد jsonb.
      expect(sql.contains('drop function if exists public.rpc_process_sync_queue(jsonb)'),
          isTrue);
      expect(sql.contains('returns jsonb'), isTrue);

      // 2) نقطة التفويض إلى المنطق القديم.
      expect(sql.contains('_rpc_process_sync_queue_legacy'), isTrue);

      // 3) per-mutation isolation عبر BEGIN ... EXCEPTION.
      expect(sql.contains('exception when others'), isTrue);

      // 4) شكل العنصر النهائي.
      expect(sql.contains("'mutation_id'"), isTrue);
      expect(sql.contains("'status'"), isTrue);
      expect(sql.contains("'error'"), isTrue);

      // 5) لا تخفيض في حماية JWT/tenant.
      expect(sql.contains('tenant_unauthenticated'), isTrue);
      expect(sql.contains('tenant_mismatch'), isTrue);

      // 6) ROLLBACK مذكور (تعليق فقط).
      expect(sql.toLowerCase().contains('rollback'), isTrue);
    });
  });
}
