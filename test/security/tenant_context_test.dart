/*
  STEP 4 — TenantContext (JWT-tenant gate).

  Goal: prove the contract that every DAO will eventually rely on:
    1. Without a successful [TenantContext.set] call, [requireTenantId]
       throws — DAOs must NEVER fall back to a default/zero tenant.
    2. After [set], the same value is returned.
    3. Listeners are notified on real changes (and only on real changes).
    4. [clear] (called by AuthProvider on logout) wipes the tenant and
       returns the gate to the "throws" state.

  Tests use [TenantContext.newForTesting] so each test owns an isolated
  instance with no leakage from earlier tests. A separate group exercises
  the singleton wiring (since AuthProvider talks to `TenantContext.instance`).
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/tenant_context.dart';

void main() {
  group('TenantContext (isolated per-test instance)', () {
    late TenantContext ctx;

    setUp(() {
      ctx = TenantContext.newForTesting();
    });

    test('requireTenantId throws StateError when not set', () {
      expect(ctx.requireTenantId, throwsStateError);
      expect(ctx.tenantId, isNull);
      expect(ctx.hasTenant, isFalse);
    });

    test('returns the same tenantId after set()', () {
      ctx.set('977a9553-069e-4fa1-aef9-e45fbc313eb4');
      expect(
        ctx.requireTenantId(),
        '977a9553-069e-4fa1-aef9-e45fbc313eb4',
      );
      expect(ctx.tenantId, '977a9553-069e-4fa1-aef9-e45fbc313eb4');
      expect(ctx.hasTenant, isTrue);
    });

    test('set() trims surrounding whitespace before storing', () {
      ctx.set('  tenant-A  ');
      expect(ctx.tenantId, 'tenant-A');
      expect(ctx.requireTenantId(), 'tenant-A');
    });

    test('set() rejects empty / whitespace-only tenant ids', () {
      expect(() => ctx.set(''), throwsArgumentError);
      expect(() => ctx.set('   '), throwsArgumentError);
      expect(ctx.tenantId, isNull);
    });

    test('notifies listeners on a real change to a different value', () {
      var calls = 0;
      ctx.addListener(() => calls++);

      ctx.set('a');
      expect(calls, 1);

      ctx.set('b');
      expect(calls, 2);
    });

    test('does NOT notify listeners when set() is called with same value', () {
      var calls = 0;
      ctx.set('same');
      ctx.addListener(() => calls++);

      ctx.set('same');
      expect(
        calls,
        0,
        reason:
            'Avoid spurious rebuilds when the tenant did not actually change.',
      );

      // Whitespace-padded same value also collapses to no-op after trimming.
      ctx.set('  same  ');
      expect(calls, 0);
    });

    test('clear() removes tenant and notifies listeners', () {
      ctx.set('to-be-cleared');

      var calls = 0;
      ctx.addListener(() => calls++);
      ctx.clear();

      expect(calls, 1);
      expect(ctx.tenantId, isNull);
      expect(ctx.hasTenant, isFalse);
      expect(
        ctx.requireTenantId,
        throwsStateError,
        reason: 'After clear() the gate must close again.',
      );
    });

    test('clear() on already-empty context does NOT notify', () {
      var calls = 0;
      ctx.addListener(() => calls++);

      ctx.clear();

      expect(
        calls,
        0,
        reason:
            'Idempotent clear() must not wake listeners when nothing changed.',
      );
    });
  });

  group('TenantContext.instance (singleton used by AuthProvider)', () {
    setUp(() {
      // Guarantee a clean slate; later tests in the same `flutter test` run
      // could otherwise see a tenant set by an earlier integration helper.
      TenantContext.instance.clear();
    });

    tearDown(() {
      TenantContext.instance.clear();
    });

    test('login → tenantId is queryable; logout → gate closes again', () {
      // Pre-login: gate is closed.
      expect(
        () => TenantContext.instance.requireTenantId(),
        throwsStateError,
      );

      // AuthProvider.set() (login).
      TenantContext.instance.set('cloud-uuid-A');
      expect(TenantContext.instance.requireTenantId(), 'cloud-uuid-A');
      expect(TenantContext.instance.hasTenant, isTrue);

      // AuthProvider.clear() (logout).
      TenantContext.instance.clear();
      expect(
        () => TenantContext.instance.requireTenantId(),
        throwsStateError,
      );
      expect(TenantContext.instance.hasTenant, isFalse);
    });

    test('switching tenants (account swap) replaces tenantId', () {
      TenantContext.instance.set('owner-A');
      expect(TenantContext.instance.requireTenantId(), 'owner-A');

      TenantContext.instance.set('owner-B');
      expect(
        TenantContext.instance.requireTenantId(),
        'owner-B',
        reason:
            'When the user signs into a different account on the same device, '
            'the tenant must be replaced — not merged.',
      );
    });
  });
}
