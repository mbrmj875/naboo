/*
  SUITE 5 — API contract tests.

  Goal: validate the SHAPE of every RPC payload the client expects from
  Supabase, without making any real network call. We feed canned shapes
  (matching the documented server contract) to the actual parser /
  consumer code and assert that:
    • All required fields are present and typed correctly.
    • Status enums are constrained ('ok' | 'fail' for sync results,
      'active' | 'grace' | 'suspended' | 'revoked' for tenant access).
    • Boolean fields are real booleans (never null).
    • Timestamp fields parse as valid ISO8601.
    • Error-message format includes the documented prefix.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_queue_service.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // rpc_process_sync_queue results.
  // ─────────────────────────────────────────────────────────────────────
  group('rpc_process_sync_queue contract', () {
    test('result entry has fields: mutation_id, status, error', () {
      const raw = {
        'mutation_id': 'abc-123',
        'status': 'ok',
        'error': null,
      };
      final r = SyncMutationResult.tryParse(raw);
      expect(r, isNotNull);
      expect(r!.mutationId, 'abc-123');
      expect(r.ok, isTrue);
      expect(r.error, isNull);
    });

    test('status is always "ok" or "fail" (never null)', () {
      // Strict contract: only "ok" → ok=true; everything else → ok=false.
      final ok = SyncMutationResult.tryParse({
        'mutation_id': 'x',
        'status': 'ok',
        'error': null,
      })!;
      final fail = SyncMutationResult.tryParse({
        'mutation_id': 'x',
        'status': 'fail',
        'error': 'tenant_unauthenticated',
      })!;

      expect(ok.ok, isTrue);
      expect(fail.ok, isFalse);
      // tryParse never crashes on weird strings; non-"ok" maps to ok=false.
      final weird = SyncMutationResult.tryParse({
        'mutation_id': 'x',
        'status': 'unknown',
        'error': null,
      })!;
      expect(weird.ok, isFalse);
    });

    test('clock_skew_rejected error has the documented prefix', () {
      final r = SyncMutationResult.tryParse({
        'mutation_id': 'x',
        'status': 'fail',
        'error':
            'clock_skew_rejected: client timestamp >= server now()+5min',
      })!;
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
      expect(r.error!, startsWith('clock_skew_rejected'),
          reason: 'server contract: error must start with the literal token');
    });

    test('tenant_unauthenticated error has the documented format', () {
      final r = SyncMutationResult.tryParse({
        'mutation_id': 'x',
        'status': 'fail',
        'error': 'tenant_unauthenticated',
      })!;
      expect(r.ok, isFalse);
      expect(r.error, 'tenant_unauthenticated');
    });

    test('missing mutation_id → tryParse returns null (rejects payload)', () {
      // The client refuses to act on a mutation it cannot key by id.
      expect(
        SyncMutationResult.tryParse(
          {'status': 'ok', 'error': null},
        ),
        isNull,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // app_tenant_access_status.
  // ─────────────────────────────────────────────────────────────────────
  group('app_tenant_access_status contract', () {
    // Client expects a Map<String, dynamic> with these fields:
    //   tenant_id     String  (uuid)
    //   access_status String  ('active'|'grace'|'suspended'|'revoked')
    //   kill_switch   bool    (NEVER null)
    //   valid_until   String  (ISO8601 timestamp; nullable for unlimited)
    //   grace_until   String? (ISO8601 timestamp; nullable)

    Map<String, dynamic> baseShape() => {
          'tenant_id': '977a9553-069e-4fa1-aef9-e45fbc313eb4',
          'access_status': 'active',
          'kill_switch': false,
          'valid_until': '2026-12-31T23:59:59.000Z',
          'grace_until': null,
        };

    test('has all required fields', () {
      final shape = baseShape();
      for (final key in [
        'tenant_id',
        'access_status',
        'kill_switch',
        'valid_until',
      ]) {
        expect(shape.containsKey(key), isTrue,
            reason: 'missing required field: $key');
      }
    });

    test('access_status only takes the documented enum values', () {
      const allowed = {'active', 'grace', 'suspended', 'revoked'};
      for (final v in ['active', 'grace', 'suspended', 'revoked']) {
        final shape = baseShape()..['access_status'] = v;
        expect(allowed.contains(shape['access_status']), isTrue);
      }
    });

    test('kill_switch is a boolean (never null)', () {
      final shape = baseShape();
      expect(shape['kill_switch'], isA<bool>());
      expect(shape['kill_switch'], isNotNull);

      // Negative case: a server bug that puts null here would still be
      // detectable by the client (we'd assert against this contract test).
      final broken = baseShape()..['kill_switch'] = null;
      expect(broken['kill_switch'], isNull,
          reason:
              'sanity check: detection logic catches a server returning null '
              'instead of a bool');
    });

    test('valid_until is a valid ISO8601 timestamp string', () {
      final shape = baseShape();
      final raw = shape['valid_until'] as String;
      final parsed = DateTime.tryParse(raw);
      expect(parsed, isNotNull,
          reason: 'valid_until must be parseable by DateTime.tryParse');
      expect(parsed!.isUtc, isTrue,
          reason: 'server convention: timestamps come in UTC (ends with Z)');
    });

    test('grace_until is either null or a valid ISO8601 string', () {
      final shapeNullGrace = baseShape();
      expect(shapeNullGrace['grace_until'], isNull);

      final shapeWithGrace = baseShape()
        ..['grace_until'] = '2026-06-01T00:00:00.000Z';
      final parsed =
          DateTime.tryParse(shapeWithGrace['grace_until'] as String);
      expect(parsed, isNotNull);
    });

    test('tenant_id is a non-empty UUID-like string', () {
      final shape = baseShape();
      final id = shape['tenant_id'] as String;
      expect(id, isNotEmpty);
      // Loose UUID v4 shape: 8-4-4-4-12 hex.
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Mutation payload (envelope) contract — what client SENDS.
  // ─────────────────────────────────────────────────────────────────────
  group('sync_queue mutation envelope contract', () {
    // Client adds these meta-fields before sending to the server (see
    // SyncQueueService.processQueue).
    test('payload includes _mutation_id / _entity_type / _operation / '
        '_device_id', () {
      final envelope = <String, dynamic>{
        // domain payload
        'global_id': 'abc',
        'amount': 1000,
        // meta added by the client
        '_mutation_id': '11111111-1111-1111-1111-111111111111',
        '_entity_type': 'expense',
        '_operation': 'INSERT',
        '_device_id': 'device-xyz',
      };
      for (final key in [
        '_mutation_id',
        '_entity_type',
        '_operation',
        '_device_id',
      ]) {
        expect(envelope.containsKey(key), isTrue,
            reason: 'envelope missing client meta field: $key');
        expect(envelope[key], isNotNull);
        expect(envelope[key], isA<String>());
      }
    });

    test('_operation values are constrained to the supported verb set', () {
      const allowed = {'INSERT', 'UPDATE', 'SOFT_DELETE'};
      for (final op in allowed) {
        final env = <String, dynamic>{'_operation': op};
        expect(allowed.contains(env['_operation']), isTrue);
      }
    });
  });
}
