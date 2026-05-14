/*
  SUITE 2 — Sync: offline queue lifecycle (no real Supabase).

  Goal: prove the SyncQueueService state machine for every realistic input
  the server might return — and for every transport / clock-skew failure
  mode — using the existing `rpcOverrideForTesting` and
  `databaseProviderForTesting` injection points.

  Rules:
    • In-memory sqflite_common_ffi DB matching the production sync_queue
      schema (kept narrow, identical to the one used by
      test/security/sync_queue_per_mutation_test.dart).
    • Real SyncQueueService.processQueue() drives the assertions.
    • RPC behaviour is faked through `rpcOverrideForTesting`. No real
      Supabase, no real network.

  Cross-references:
    test/security/sync_queue_per_mutation_test.dart (Step 17 — base cases)
    test/security/lww_clock_skew_test.dart           (Step 19 — clock skew)
  This file is COMPLEMENTARY: it stitches together the user-spec offline
  flows (3 offline mutations, dead-after-5-fails, idempotent duplicate, …).
*/

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openSyncQueueDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
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
  String? lastError,
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
    'last_error': lastError,
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

Future<int> _countByStatus(Database db, String status) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM sync_queue WHERE status = ?',
    [status],
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

void main() {
  late SyncQueueService service;
  late Database db;

  setUp(() async {
    db = await _openSyncQueueDb();
    service = SyncQueueService.instance
      ..databaseProviderForTesting = (() async => db)
      ..authCheckForTesting = (() => true)
      ..deviceIdProviderForTesting = (() async => 'device-suite2');
  });

  tearDown(() async {
    service
      ..databaseProviderForTesting = null
      ..authCheckForTesting = null
      ..deviceIdProviderForTesting = null
      ..rpcOverrideForTesting = null;
    await db.close();
  });

  // ── enqueue offline ────────────────────────────────────────────────────
  test('add 3 mutations offline → all status="pending"', () async {
    await _seed(db, mutationId: 'm1');
    await _seed(db, mutationId: 'm2');
    await _seed(db, mutationId: 'm3');

    expect(await _countByStatus(db, 'pending'), 3);
    expect(await _countByStatus(db, 'synced'), 0);
    expect(await _countByStatus(db, 'failed'), 0);
    expect(await _countByStatus(db, 'dead'), 0);
  });

  // ── all-OK batch ───────────────────────────────────────────────────────
  test('process queue with all-success RPC → all synced, retry_count=0',
      () async {
    await _seed(db, mutationId: 'm1');
    await _seed(db, mutationId: 'm2');
    await _seed(db, mutationId: 'm3');

    service.rpcOverrideForTesting = (mutations) async {
      return [
        for (final m in mutations)
          SyncMutationResult(
            mutationId: m['_mutation_id'] as String,
            ok: true,
          ),
      ];
    };

    await service.processQueue();

    for (final id in ['m1', 'm2', 'm3']) {
      final r = await _readRow(db, id);
      expect(r['status'], 'synced', reason: 'mutation $id should be synced');
      expect(r['retry_count'], 0,
          reason: 'success must NOT touch retry_count');
      expect(r['last_error'], isNull);
    }
  });

  // ── partial failure batch ──────────────────────────────────────────────
  test(
    'process queue with [{ok},{fail},{ok}] → 1&3 synced, 2 failed (retry=1)',
    () async {
      await _seed(db, mutationId: 'm1');
      await _seed(db, mutationId: 'm2');
      await _seed(db, mutationId: 'm3');

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'm1', ok: true),
            SyncMutationResult(
                mutationId: 'm2', ok: false, error: 'category_not_found'),
            SyncMutationResult(mutationId: 'm3', ok: true),
          ];

      await service.processQueue();

      final r1 = await _readRow(db, 'm1');
      expect(r1['status'], 'synced');
      expect(r1['retry_count'], 0);

      final r2 = await _readRow(db, 'm2');
      expect(r2['status'], 'failed');
      expect(r2['retry_count'], 1);
      expect(r2['last_error'], 'category_not_found');

      final r3 = await _readRow(db, 'm3');
      expect(r3['status'], 'synced');
      expect(r3['retry_count'], 0,
          reason: 'success in mixed batch must NOT increment retry_count');
    },
  );

  // ── network error ──────────────────────────────────────────────────────
  test(
    'process queue with network error → ALL stay pending, retry_count=0',
    () async {
      await _seed(db, mutationId: 'm1');
      await _seed(db, mutationId: 'm2');
      await _seed(db, mutationId: 'm3');

      service.rpcOverrideForTesting = (_) async {
        throw const SyncRpcTransportException('SocketException: lookup');
      };

      await service.processQueue();

      for (final id in ['m1', 'm2', 'm3']) {
        final r = await _readRow(db, id);
        expect(r['status'], 'pending',
            reason: 'transport error must not move row off pending');
        expect(r['retry_count'], 0,
            reason: 'transport error must not penalise retry_count');
        expect(r['last_error'], isNull);
        expect(r['last_attempt_at'], isNull);
      }
    },
  );

  // ── dead after 5 ───────────────────────────────────────────────────────
  test(
    'mutation fails 5 times → status becomes "dead" on the 5th failure',
    () async {
      // Start at retry_count=4 so the very next failure increments to 5
      // and the service flips status → dead.
      await _seed(db, mutationId: 'm1', retryCount: 4);

      service.rpcOverrideForTesting = (_) async => const [
            SyncMutationResult(mutationId: 'm1', ok: false, error: 'fatal'),
          ];

      await service.processQueue();

      final r = await _readRow(db, 'm1');
      expect(r['status'], 'dead');
      expect(r['retry_count'], 5);
      expect(r['last_error'], 'fatal');
    },
  );

  test('dead mutation is NOT picked up by subsequent processQueue', () async {
    await _seed(
      db,
      mutationId: 'm-dead',
      status: 'dead',
      retryCount: 5,
      lastError: 'previous fatal',
    );
    // Also a healthy pending row to confirm processing still happens.
    await _seed(db, mutationId: 'm-live');

    var rpcCalls = 0;
    final seenIds = <String>{};
    service.rpcOverrideForTesting = (mutations) async {
      rpcCalls++;
      for (final m in mutations) {
        seenIds.add(m['_mutation_id'] as String);
      }
      return [
        for (final m in mutations)
          SyncMutationResult(
            mutationId: m['_mutation_id'] as String,
            ok: true,
          ),
      ];
    };

    await service.processQueue();

    expect(rpcCalls, 1);
    expect(seenIds, contains('m-live'));
    expect(seenIds, isNot(contains('m-dead')),
        reason: 'dead mutations must never be sent to the server again');

    // The dead row stays dead, untouched.
    final dead = await _readRow(db, 'm-dead');
    expect(dead['status'], 'dead');
    expect(dead['retry_count'], 5);
    expect(dead['last_error'], 'previous fatal');
  });

  // ── clock skew rejection ───────────────────────────────────────────────
  test('clock_skew_rejected fail moves mutation to failed (not synced)',
      () async {
    await _seed(db, mutationId: 'm1');

    service.rpcOverrideForTesting = (_) async => const [
          SyncMutationResult(
            mutationId: 'm1',
            ok: false,
            error: 'clock_skew_rejected: client timestamp >= server now()+5min',
          ),
        ];

    await service.processQueue();

    final r = await _readRow(db, 'm1');
    expect(r['status'], 'failed');
    expect(r['retry_count'], 1);
    expect(r['last_error'].toString(), contains('clock_skew_rejected'));
  });

  // ── duplicate mutation (same entity + op) ──────────────────────────────
  test(
    'duplicate mutation (same entity_id + operation) processed correctly '
    '(idempotent server behaviour)',
    () async {
      // The client may enqueue the same logical change twice (e.g., user
      // double-tapped before the first round-trip completed). Each row has
      // its own mutation_id, so the server returns ok for both.
      await _seed(
        db,
        mutationId: 'dup-1',
        entityType: 'expense',
        operation: 'INSERT',
        payload: {'global_id': 'shared-xyz', 'amount': 1000},
      );
      await _seed(
        db,
        mutationId: 'dup-2',
        entityType: 'expense',
        operation: 'INSERT',
        payload: {'global_id': 'shared-xyz', 'amount': 1000},
      );

      service.rpcOverrideForTesting = (mutations) async {
        return [
          for (final m in mutations)
            SyncMutationResult(
              mutationId: m['_mutation_id'] as String,
              ok: true,
            ),
        ];
      };

      await service.processQueue();

      final r1 = await _readRow(db, 'dup-1');
      final r2 = await _readRow(db, 'dup-2');
      expect(r1['status'], 'synced');
      expect(r2['status'], 'synced');
      expect(await _countByStatus(db, 'synced'), 2);
    },
  );
}
