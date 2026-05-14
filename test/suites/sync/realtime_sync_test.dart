/*
  SUITE 2 — Sync: realtime channels & connectivity (no real Supabase).

  Goal: prove channel-state and connectivity-debounce logic produces the
  expected callbacks under healthy + unhealthy scenarios.

  Test surfaces (REAL classes, no mocks of return values):
    • RealtimeWatchdog (lib/services/realtime_watchdog.dart)
    • CloudSyncService.handleTenantAccessUpdateForTesting (kill-switch)
    • ConnectivityResumeScheduler (lib/services/connectivity_resume_sync.dart)
    • FakeRealtimeHub (test/helpers/fake_supabase.dart)

  Cross-references:
    test/security/realtime_watchdog_test.dart  (Step 22 — base watchdog)
    test/security/realtime_kill_switch_test.dart (Step 22 — kill switch)
    test/security/connectivity_sync_test.dart   (connectivity wiring)
*/

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/connectivity_resume_sync.dart';
import 'package:naboo/services/license_service.dart';
import 'package:naboo/services/realtime_watchdog.dart';

import '../../helpers/fake_supabase.dart';

const String _kCurrentTenant = 'tenant-aaa';
const String _kOtherTenant = 'tenant-bbb';

// ── Fake timer plumbing identical to the existing watchdog tests ─────────
class _FakeTimer implements Timer {
  _FakeTimer(this.callback, this.delay);
  final void Function() callback;
  final Duration delay;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;
  @override
  bool get isActive => !_cancelled;
  @override
  int get tick => 0;

  void fire() {
    if (_cancelled) {
      throw StateError('Timer already cancelled');
    }
    callback();
  }
}

class _FakeTimerFactory {
  final List<_FakeTimer> created = [];

  Timer create(Duration delay, void Function() callback) {
    final t = _FakeTimer(callback, delay);
    created.add(t);
    return t;
  }
}

class _FakeClock {
  DateTime now = DateTime.utc(2026, 5, 7, 12, 0, 0);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CloudSyncService.instance
      ..onTenantRevoked = null
      ..checkLicenseOverrideForTesting = null;
  });

  tearDown(() {
    CloudSyncService.instance
      ..onTenantRevoked = null
      ..checkLicenseOverrideForTesting = null;
  });

  // ─────────────────────────────────────────────────────────────────────
  // Channel health: subscribe / error / silence / backoff.
  // ─────────────────────────────────────────────────────────────────────
  group('RealtimeWatchdog — channel state machine', () {
    late _FakeClock clock;
    late _FakeTimerFactory timers;
    late RealtimeWatchdog watchdog;

    setUp(() {
      clock = _FakeClock();
      timers = _FakeTimerFactory();
      watchdog = RealtimeWatchdog(
        checkInterval: const Duration(seconds: 20),
        unhealthyAfter: const Duration(seconds: 30),
        baseBackoff: const Duration(seconds: 5),
        maxBackoff: const Duration(seconds: 60),
        clock: clock.call,
        timerFactory: timers.create,
      );
    });

    tearDown(() => watchdog.stop());

    test('channel subscribe → markHealthy resets state', () {
      watchdog.register('snapshots', reconnect: () async {});

      // Pretend a few errors happened first.
      watchdog.markError('snapshots');
      watchdog.markError('snapshots');
      expect(watchdog.consecutiveErrors('snapshots'), 2);

      // SUBSCRIBED status → markHealthy clears state.
      watchdog.markHealthy('snapshots');
      expect(watchdog.consecutiveErrors('snapshots'), 0);
      expect(watchdog.scheduledBackoff('snapshots'), isNull);
      expect(watchdog.hasPendingReconnect('snapshots'), isFalse);
    });

    test('channel error → markError schedules reconnect timer', () {
      watchdog.register('snapshots', reconnect: () async {});

      expect(timers.created, isEmpty);

      watchdog.markError('snapshots');

      expect(timers.created, hasLength(1));
      expect(timers.created.first.delay, const Duration(seconds: 5));
      expect(watchdog.hasPendingReconnect('snapshots'), isTrue);
    });

    test('watchdog tick fires reconnect after 30s of silence', () {
      watchdog.register('snapshots', reconnect: () async {});

      // Push past the unhealthy threshold without any markEvent.
      clock.advance(const Duration(seconds: 31));
      watchdog.tick();

      expect(timers.created, hasLength(1));
      expect(watchdog.hasPendingReconnect('snapshots'), isTrue);
      expect(watchdog.consecutiveErrors('snapshots'), 1);
    });

    test('exponential backoff sequence: 5s → 10s → 20s → 40s → 60s', () {
      watchdog.register('snapshots', reconnect: () async {});

      const expected = <Duration>[
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(seconds: 40),
        Duration(seconds: 60),
      ];

      for (final d in expected) {
        watchdog.markError('snapshots');
        expect(timers.created.last.delay, d,
            reason: 'expected backoff $d at error #${timers.created.length}');
      }
    });

    test('backoff resets after successful reconnect (markHealthy)', () {
      watchdog.register('snapshots', reconnect: () async {});

      // 3 consecutive errors → next backoff would be 40s.
      watchdog.markError('snapshots');
      watchdog.markError('snapshots');
      watchdog.markError('snapshots');
      expect(timers.created.last.delay, const Duration(seconds: 20));

      // Subscribe succeeds.
      watchdog.markHealthy('snapshots');

      // Next error must restart at 5s — counter was reset.
      watchdog.markError('snapshots');
      expect(timers.created.last.delay, const Duration(seconds: 5));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Kill-switch realtime event ⇒ onTenantRevoked.
  // ─────────────────────────────────────────────────────────────────────
  group('Kill-switch UPDATE event', () {
    test('UPDATE event for current tenant → onTenantRevoked called', () async {
      final hub = FakeRealtimeHub();
      addTearDown(hub.disposeAll);

      var revokedCalls = 0;

      CloudSyncService.instance.checkLicenseOverrideForTesting =
          () async => LicenseStatus.suspended;
      CloudSyncService.instance.onTenantRevoked = () async => revokedCalls++;

      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        listener: (change) {
          CloudSyncService.instance.handleTenantAccessUpdateForTesting(
            change.newRecord,
            _kCurrentTenant,
          );
        },
      );

      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        newRecord: const {
          'tenant_id': _kCurrentTenant,
          'access_status': 'revoked',
          'kill_switch': true,
        },
      ));

      // Two microtask ticks for the unawaited handler chain.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 1);
    });

    test('UPDATE event for a DIFFERENT tenant → onTenantRevoked NOT called',
        () async {
      final hub = FakeRealtimeHub();
      addTearDown(hub.disposeAll);

      var revokedCalls = 0;
      var checkCalls = 0;

      CloudSyncService.instance.checkLicenseOverrideForTesting = () async {
        checkCalls++;
        return LicenseStatus.suspended;
      };
      CloudSyncService.instance.onTenantRevoked = () async => revokedCalls++;

      hub.on(
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        listener: (change) {
          CloudSyncService.instance.handleTenantAccessUpdateForTesting(
            change.newRecord,
            _kCurrentTenant, // not equal to record's tenant_id
          );
        },
      );

      hub.emit(FakePostgresChange(
        schema: 'public',
        table: 'tenant_access',
        event: FakeChangeEvent.update,
        newRecord: const {
          'tenant_id': _kOtherTenant,
          'access_status': 'revoked',
          'kill_switch': true,
        },
      ));

      await Future<void>.delayed(Duration.zero);
      expect(revokedCalls, 0,
          reason: 'event for another tenant must not trigger logout');
      expect(checkCalls, 0,
          reason: 'license re-check must short-circuit before being called');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Connectivity resume — single sync per offline→online transition.
  // ─────────────────────────────────────────────────────────────────────
  group('ConnectivityResumeScheduler', () {
    late _FakeTimerFactory timers;

    setUp(() => timers = _FakeTimerFactory());

    test('offline→online → syncNow callback called once (after debounce)', () {
      var calls = 0;
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () => calls++,
      );

      s.handle([ConnectivityResult.none]);
      s.handle([ConnectivityResult.wifi]);

      expect(timers.created, hasLength(1));
      expect(calls, 0,
          reason: 'callback must wait for the debounce timer');

      timers.created.first.fire();
      expect(calls, 1);
      s.dispose();
    });

    test('online→online (no offline phase) → callback NOT called', () {
      var calls = 0;
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () => calls++,
      );

      s.handle([ConnectivityResult.wifi]);
      s.handle([ConnectivityResult.mobile]);

      expect(timers.created, isEmpty);
      expect(calls, 0);
      s.dispose();
    });

    test(
      'rapid offline/online sequence → debounced to ONE callback',
      () {
        var calls = 0;
        final s = ConnectivityResumeScheduler(
          debounce: const Duration(seconds: 1),
          timerFactory: timers.create,
          onOfflineToOnlineDebounced: () => calls++,
        );

        // 5 rapid changes: none→wifi→none→wifi→none→wifi.
        s.handle([ConnectivityResult.none]);
        s.handle([ConnectivityResult.wifi]);
        s.handle([ConnectivityResult.none]);
        s.handle([ConnectivityResult.wifi]);
        s.handle([ConnectivityResult.none]);
        s.handle([ConnectivityResult.wifi]);

        // Timers were created at each offline→online transition (3) but
        // only the LAST one is still active; previous timers were cancelled
        // when going offline again.
        final activeTimers =
            timers.created.where((t) => t.isActive).toList();
        expect(activeTimers, hasLength(1));

        // Fire the surviving timer → exactly ONE callback invocation.
        activeTimers.single.fire();
        expect(calls, 1,
            reason: 'rapid transitions must debounce to a single sync');

        s.dispose();
      },
    );
  });
}
