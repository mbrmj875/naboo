/*
  SUITE 3 — Performance: sync queue & realtime watchdog throughput.

  Each test PRINTS the actual time and asserts an upper bound from the
  user spec.
*/

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/realtime_watchdog.dart';
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

Stopwatch _start() => Stopwatch()..start();

void _print(String label, Stopwatch sw) {
  // ignore: avoid_print
  print('[perf] $label: ${sw.elapsedMilliseconds}ms');
}

void main() {
  group('Sync performance — real services, fake transport', () {
    late Database db;
    late SyncQueueService service;

    setUp(() async {
      db = await _openSyncQueueDb();
      service = SyncQueueService.instance
        ..databaseProviderForTesting = (() async => db)
        ..authCheckForTesting = (() => true)
        ..deviceIdProviderForTesting = (() async => 'device-perf');
    });

    tearDown(() async {
      service
        ..databaseProviderForTesting = null
        ..authCheckForTesting = null
        ..deviceIdProviderForTesting = null
        ..rpcOverrideForTesting = null;
      await db.close();
    });

    test('process 100 mutations in queue < 3000ms', () async {
      // Seed 100 pending mutations.
      await db.transaction((txn) async {
        final now = DateTime.now().toUtc().toIso8601String();
        for (var i = 0; i < 100; i++) {
          await txn.insert('sync_queue', {
            'mutation_id': 'mut-$i',
            'entity_type': 'expense',
            'operation': 'INSERT',
            'payload': jsonEncode({
              'global_id': 'g-$i',
              'amount': 100 + i,
              'note': 'بيان',
            }),
            'created_at': now,
            'status': 'pending',
            'retry_count': 0,
          });
        }
      });

      service.rpcOverrideForTesting = (mutations) async {
        // Simulate a fast server: confirm every mutation in O(N).
        return [
          for (final m in mutations)
            SyncMutationResult(
              mutationId: m['_mutation_id'] as String,
              ok: true,
            ),
        ];
      };

      final sw = _start();
      // Default _batchSize is 50 → process queue twice.
      await service.processQueue();
      await service.processQueue();
      sw.stop();
      _print('Sync 100', sw);

      final remaining = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending'",
      );
      expect((remaining.first['c'] as num).toInt(), 0,
          reason: 'all 100 mutations should be synced');
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('parse 1000 sync results from RPC < 500ms', () async {
      // Build 1000 server-shaped result entries.
      final serverResponse = <Map<String, dynamic>>[
        for (var i = 0; i < 1000; i++)
          {
            'mutation_id': 'mut-$i',
            'status': i % 3 == 0 ? 'fail' : 'ok',
            'error': i % 3 == 0 ? 'category_not_found' : null,
          },
      ];

      final sw = _start();
      final parsed = <SyncMutationResult>[];
      for (final raw in serverResponse) {
        final r = SyncMutationResult.tryParse(raw);
        if (r == null) {
          throw FormatException('parse failure: $raw');
        }
        parsed.add(r);
      }
      sw.stop();
      _print('Parse 1000', sw);

      expect(parsed.length, 1000);
      // ~333 of them are failures (every 3rd).
      final failed = parsed.where((p) => !p.ok).length;
      expect(failed, greaterThan(300));
      expect(failed, lessThan(400));
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('Watchdog tick throughput', () {
    late RealtimeWatchdog wd;

    setUp(() {
      wd = RealtimeWatchdog(
        checkInterval: const Duration(seconds: 20),
        unhealthyAfter: const Duration(seconds: 30),
        baseBackoff: const Duration(seconds: 5),
        maxBackoff: const Duration(seconds: 60),
      );
    });

    tearDown(() => wd.stop());

    test('watchdog tick with 10 channels < 50ms', () {
      for (var i = 0; i < 10; i++) {
        wd.register('channel-$i', reconnect: () async {});
      }

      final sw = _start();
      wd.tick();
      sw.stop();
      _print('Watchdog tick', sw);

      // No errors, no markEvent — every channel's lastHealthyAt is ~now,
      // so no reconnect is scheduled.
      for (var i = 0; i < 10; i++) {
        expect(wd.consecutiveErrors('channel-$i'), 0);
        expect(wd.hasPendingReconnect('channel-$i'), isFalse);
      }
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
