import 'dart:async';

import 'package:naboo/services/realtime_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake timer captured by [_FakeTimerFactory]. Doesn't actually schedule.
class _FakeTimer implements Timer {
  _FakeTimer(this.callback, this.delay);
  final void Function() callback;
  final Duration delay;
  bool _cancelled = false;

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

class _FakeTimerFactory {
  final List<_FakeTimer> created = [];

  Timer create(Duration delay, void Function() callback) {
    final t = _FakeTimer(callback, delay);
    created.add(t);
    return t;
  }

  /// Fires the most recently created timer (the one for the current pending
  /// reconnect). Returns the [Duration] it was scheduled for.
  Duration fireLast() {
    final t = created.last;
    if (t._cancelled) {
      throw StateError('Tried to fire a cancelled timer.');
    }
    t.callback();
    return t.delay;
  }

  Duration get lastDelay => created.last.delay;
}

/// Mutable clock controlled by tests.
class _FakeClock {
  DateTime now = DateTime.utc(2026, 5, 7, 12, 0, 0);

  DateTime call() => now;

  void advance(Duration d) {
    now = now.add(d);
  }
}

void main() {
  group('RealtimeWatchdog', () {
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

    tearDown(() {
      watchdog.stop();
    });

    test('schedules reconnect after channelError', () async {
      var reconnectCount = 0;
      watchdog.register(
        'snapshots',
        reconnect: () async {
          reconnectCount++;
        },
      );

      // No reconnect yet.
      expect(timers.created, isEmpty);
      expect(watchdog.hasPendingReconnect('snapshots'), isFalse);

      // Simulate channelError.
      watchdog.markError('snapshots');

      // Watchdog must schedule a reconnect Timer with the base backoff (5s).
      expect(timers.created, hasLength(1));
      expect(timers.lastDelay, const Duration(seconds: 5));
      expect(watchdog.hasPendingReconnect('snapshots'), isTrue);
      expect(watchdog.scheduledBackoff('snapshots'),
          const Duration(seconds: 5));

      // Fire the timer → reconnect callback executes.
      timers.fireLast();
      // Allow microtask queue to drain (async reconnect callback).
      await Future<void>.delayed(Duration.zero);
      expect(reconnectCount, 1);
      expect(watchdog.hasPendingReconnect('snapshots'), isFalse);
    });

    test('respects exponential backoff sequence: 5 → 10 → 20 → 40 → 60', () {
      watchdog.register('snapshots', reconnect: () async {});

      const expected = [
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(seconds: 40),
        Duration(seconds: 60),
      ];

      for (final exp in expected) {
        watchdog.markError('snapshots');
        expect(timers.created.last.delay, exp,
            reason: 'expected backoff $exp at error '
                '#${timers.created.length}');
      }
      expect(watchdog.consecutiveErrors('snapshots'), expected.length);
    });

    test('resets backoff on successful subscribe (markHealthy)', () {
      watchdog.register('snapshots', reconnect: () async {});

      // Three consecutive errors → backoff = 5s, 10s, 20s.
      watchdog.markError('snapshots');
      watchdog.markError('snapshots');
      watchdog.markError('snapshots');
      expect(timers.created.last.delay, const Duration(seconds: 20));
      expect(watchdog.consecutiveErrors('snapshots'), 3);

      // Successful subscribe → counters & pending reconnect reset.
      watchdog.markHealthy('snapshots');
      expect(watchdog.consecutiveErrors('snapshots'), 0);
      expect(watchdog.scheduledBackoff('snapshots'), isNull);
      expect(watchdog.hasPendingReconnect('snapshots'), isFalse);

      // Next error must restart at 5s.
      watchdog.markError('snapshots');
      expect(timers.created.last.delay, const Duration(seconds: 5));
    });

    test('updates lastHealthyAt on every event', () {
      final start = clock.now;
      watchdog.register('snapshots', reconnect: () async {});
      expect(watchdog.lastHealthyAt('snapshots'), start);

      clock.advance(const Duration(seconds: 7));
      watchdog.markEvent('snapshots');
      expect(watchdog.lastHealthyAt('snapshots'),
          start.add(const Duration(seconds: 7)));

      clock.advance(const Duration(seconds: 13));
      watchdog.markEvent('snapshots');
      expect(watchdog.lastHealthyAt('snapshots'),
          start.add(const Duration(seconds: 20)));
    });

    test('does not reconnect healthy channels on tick', () {
      var reconnectCount = 0;
      watchdog.register(
        'snapshots',
        reconnect: () async {
          reconnectCount++;
        },
      );

      // Less than unhealthyAfter (30s) → no reconnect should be scheduled.
      clock.advance(const Duration(seconds: 25));
      watchdog.tick();

      expect(timers.created, isEmpty);
      expect(watchdog.hasPendingReconnect('snapshots'), isFalse);
      expect(reconnectCount, 0);

      // Just before threshold (29s additional ≠ but we already moved 25, so
      // total age = 25s) — confirm tick does not schedule.
      watchdog.markEvent('snapshots'); // refresh lastHealthyAt
      clock.advance(const Duration(seconds: 29));
      watchdog.tick();
      expect(timers.created, isEmpty);
    });

    test('tick reconnects channel when it goes unhealthy (>30s)', () {
      watchdog.register('snapshots', reconnect: () async {});

      // Push past the unhealthy threshold (30s).
      clock.advance(const Duration(seconds: 31));
      watchdog.tick();

      expect(timers.created, hasLength(1));
      expect(timers.created.last.delay, const Duration(seconds: 5));
      expect(watchdog.hasPendingReconnect('snapshots'), isTrue);
    });

    test('max backoff does not exceed 60s — even after many errors', () {
      watchdog.register('snapshots', reconnect: () async {});

      // 10 consecutive errors should still cap at 60s.
      for (var i = 0; i < 10; i++) {
        watchdog.markError('snapshots');
      }
      expect(timers.created.last.delay, const Duration(seconds: 60));

      // Sanity: nextBackoffFor(99) also stays at 60s.
      expect(watchdog.nextBackoffFor(99), const Duration(seconds: 60));
      expect(watchdog.nextBackoffFor(0), const Duration(seconds: 5));
      expect(watchdog.nextBackoffFor(1), const Duration(seconds: 10));
      expect(watchdog.nextBackoffFor(2), const Duration(seconds: 20));
      expect(watchdog.nextBackoffFor(3), const Duration(seconds: 40));
      expect(watchdog.nextBackoffFor(4), const Duration(seconds: 60));
    });

    test('markError on unregistered channel is a no-op', () {
      expect(() => watchdog.markError('does-not-exist'), returnsNormally);
      expect(timers.created, isEmpty);
    });

    test('markEvent on unregistered channel is a no-op', () {
      expect(() => watchdog.markEvent('does-not-exist'), returnsNormally);
      expect(watchdog.lastHealthyAt('does-not-exist'), isNull);
    });

    test('unregister cancels any pending reconnect timer', () {
      watchdog.register('snapshots', reconnect: () async {});
      watchdog.markError('snapshots');

      final pending = timers.created.last;
      expect(pending.isActive, isTrue);

      watchdog.unregister('snapshots');
      expect(pending.isActive, isFalse);
      expect(watchdog.registeredLabels, isNot(contains('snapshots')));
    });

    test('multiple channels are tracked independently', () {
      watchdog.register('a', reconnect: () async {});
      watchdog.register('b', reconnect: () async {});

      watchdog.markError('a');
      watchdog.markError('a');
      watchdog.markError('b');

      expect(watchdog.consecutiveErrors('a'), 2);
      expect(watchdog.consecutiveErrors('b'), 1);
      // Last timer in `created` is for 'b' at base backoff.
      expect(timers.created.last.delay, const Duration(seconds: 5));
      // Pre-last is the second error of 'a' → 10s.
      expect(timers.created[timers.created.length - 2].delay,
          const Duration(seconds: 10));
    });

    test('successful reconnect call does not auto-reset error counter', () async {
      // Justification: reconnect() returning successfully doesn't guarantee the
      // server side accepted the subscribe. We only reset when markHealthy()
      // fires from the SUBSCRIBED status callback. Otherwise an immediate
      // success would mask repeated failures.
      var calls = 0;
      watchdog.register(
        'snapshots',
        reconnect: () async {
          calls++;
        },
      );

      watchdog.markError('snapshots');
      expect(watchdog.consecutiveErrors('snapshots'), 1);
      timers.fireLast();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      // Counter must NOT be reset just because reconnect() resolved.
      expect(watchdog.consecutiveErrors('snapshots'), 1);

      // Now imagine the subscribe truly succeeded → markHealthy clears it.
      watchdog.markHealthy('snapshots');
      expect(watchdog.consecutiveErrors('snapshots'), 0);
    });

    test('reconnect callback that throws is caught and the next tick retries',
        () async {
      var calls = 0;
      watchdog.register(
        'snapshots',
        reconnect: () async {
          calls++;
          throw StateError('network down');
        },
      );

      watchdog.markError('snapshots');
      expect(timers.created, hasLength(1));

      // Firing the timer should NOT propagate the exception.
      expect(() => timers.fireLast(), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      // Channel is still considered unhealthy (no markHealthy has been
      // called) — a tick after threshold should re-schedule another reconnect.
      clock.advance(const Duration(seconds: 31));
      watchdog.tick();
      // A second timer must have been created with the next backoff (10s).
      expect(timers.created, hasLength(2));
      expect(timers.created.last.delay, const Duration(seconds: 10));
    });

    test('markError replaces an existing pending reconnect timer', () {
      watchdog.register('snapshots', reconnect: () async {});

      watchdog.markError('snapshots');
      final first = timers.created.last;
      expect(first.isActive, isTrue);

      // A second markError before the first fires should cancel the first
      // and schedule a new one with the next backoff.
      watchdog.markError('snapshots');
      expect(first.isActive, isFalse);
      expect(timers.created, hasLength(2));
      expect(timers.created.last.delay, const Duration(seconds: 10));
      expect(timers.created.last.isActive, isTrue);
    });

    test('tick skips channels that already have a pending reconnect', () {
      watchdog.register('snapshots', reconnect: () async {});

      // Trigger an error → pending reconnect scheduled.
      watchdog.markError('snapshots');
      expect(timers.created, hasLength(1));

      // Advance past unhealthy threshold and tick — must NOT schedule another
      // (would otherwise double-reconnect).
      clock.advance(const Duration(seconds: 60));
      watchdog.tick();
      expect(timers.created, hasLength(1));
    });

    test('stop() cancels all pending reconnects and the periodic timer', () {
      watchdog.register('a', reconnect: () async {});
      watchdog.register('b', reconnect: () async {});

      watchdog.markError('a');
      watchdog.markError('b');
      expect(timers.created, hasLength(2));
      expect(timers.created.every((t) => t.isActive), isTrue);

      watchdog.stop();
      expect(timers.created.every((t) => !t.isActive), isTrue);
    });
  });

  group('RealtimeWatchdog defaults', () {
    test('uses real DateTime.now when no clock is injected', () {
      final w = RealtimeWatchdog();
      w.register('x', reconnect: () async {});
      final at = w.lastHealthyAt('x');
      expect(at, isNotNull);
      // Just sanity: must be close to now.
      expect(DateTime.now().difference(at!).inSeconds.abs(), lessThan(5));
      w.stop();
    });

    test('start() schedules a real periodic timer that drives tick()', () async {
      // Use a tiny check interval so the test stays fast.
      final clock = _FakeClock();
      final w = RealtimeWatchdog(
        checkInterval: const Duration(milliseconds: 30),
        unhealthyAfter: const Duration(milliseconds: 10),
        baseBackoff: const Duration(seconds: 5),
        maxBackoff: const Duration(seconds: 60),
        clock: clock.call,
      );
      w.register('x', reconnect: () async {});

      // Make the channel "stale" relative to the fake clock.
      clock.advance(const Duration(seconds: 1));

      w.start();
      // Wait long enough for the periodic timer to fire at least once.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(w.consecutiveErrors('x'), greaterThanOrEqualTo(1));
      expect(w.scheduledBackoff('x'), isNotNull);
      w.stop();
    });
  });
}
