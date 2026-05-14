import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/connectivity_resume_sync.dart';

/// Fake timer — لا يُشغَّل تلقائياً؛ تستدعي [fire] يدوياً في الاختبار.
class _FakeTimer implements Timer {
  _FakeTimer(this.callback, this.duration);
  final void Function() callback;
  final Duration duration;
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

  Timer create(Duration d, void Function() cb) {
    final t = _FakeTimer(cb, d);
    created.add(t);
    return t;
  }
}

void main() {
  group('connectivityResultsOnline', () {
    test('none only → offline', () {
      expect(
        connectivityResultsOnline([ConnectivityResult.none]),
        isFalse,
      );
    });

    test('wifi → online', () {
      expect(
        connectivityResultsOnline([ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });

  group('ConnectivityResumeScheduler', () {
    late _FakeTimerFactory timers;
    late List<Map<String, dynamic>> syncCalls;

    setUp(() {
      timers = _FakeTimerFactory();
      syncCalls = [];
    });

    test('triggers callback once on offline→online (after debounce)', () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({'forcePull': true});
        },
      );

      s.handle([ConnectivityResult.none]);
      expect(s.debugLastOnline, isFalse);
      expect(syncCalls, isEmpty);

      s.handle([ConnectivityResult.wifi]);
      expect(timers.created, hasLength(1));
      expect(timers.created.first.duration, const Duration(seconds: 1));
      expect(syncCalls, isEmpty);

      timers.created.first.fire();
      expect(syncCalls, hasLength(1));
      s.dispose();
    });

    test('does NOT trigger on online→online', () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({});
        },
      );

      s.handle([ConnectivityResult.wifi]);
      expect(s.debugLastOnline, isTrue);
      expect(timers.created, isEmpty);
      expect(syncCalls, isEmpty);

      s.handle([ConnectivityResult.mobile]);
      expect(timers.created, isEmpty);
      expect(syncCalls, isEmpty);
      s.dispose();
    });

    test('does NOT trigger on offline→offline', () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({});
        },
      );

      s.handle([ConnectivityResult.none]);
      s.handle([ConnectivityResult.none]);
      expect(timers.created, isEmpty);
      expect(syncCalls, isEmpty);
      s.dispose();
    });

    test('does NOT trigger on online→offline', () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({});
        },
      );

      s.handle([ConnectivityResult.wifi]);
      s.handle([ConnectivityResult.none]);
      expect(s.debugLastOnline, isFalse);
      expect(timers.created, isEmpty);
      expect(syncCalls, isEmpty);
      s.dispose();
    });

    test('debounces rapid connectivity changes — single callback after last offline→online',
        () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({'t': DateTime.now()});
        },
      );

      s.handle([ConnectivityResult.none]);
      s.handle([ConnectivityResult.wifi]);
      expect(timers.created, hasLength(1));

      // قبل انتهاء الثانية: انقطاع ثم عودة → يُلغى المؤقت السابق ويُنشأ واحد جديد.
      s.handle([ConnectivityResult.none]);
      expect(timers.created.first.isActive, isFalse);

      s.handle([ConnectivityResult.wifi]);
      expect(timers.created, hasLength(2));
      expect(syncCalls, isEmpty);

      timers.created.last.fire();
      expect(syncCalls, hasLength(1));
      s.dispose();
    });

    test('debounce cancels previous pending timer when going offline before fire',
        () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({});
        },
      );

      s.handle([ConnectivityResult.none]);
      s.handle([ConnectivityResult.wifi]);
      final first = timers.created.first;
      expect(first.isActive, isTrue);

      s.handle([ConnectivityResult.none]);
      expect(first.isActive, isFalse);
      expect(() => first.fire(), throwsStateError);

      expect(syncCalls, isEmpty);
      s.dispose();
    });

    test('first emission online does NOT sync (unknown → online, not offline→online)', () {
      final s = ConnectivityResumeScheduler(
        debounce: const Duration(seconds: 1),
        timerFactory: timers.create,
        onOfflineToOnlineDebounced: () {
          syncCalls.add({});
        },
      );

      s.handle([ConnectivityResult.wifi]);
      expect(timers.created, isEmpty);
      expect(syncCalls, isEmpty);
      expect(s.debugLastOnline, isTrue);
      s.dispose();
    });
  });

  group('CloudSync — connectivity wiring (documentary)', () {
    test('syncNow(forcePull: true) is used for connectivity resume', () {
      final src = File('lib/services/cloud_sync_service.dart').readAsStringSync();
      expect(
        src.contains('unawaited(syncNow(forcePull: true))'),
        isTrue,
        reason: 'Connectivity resume must pull after reconnect',
      );
      expect(
        src.contains('Connectivity().onConnectivityChanged'),
        isTrue,
        reason: 'Must listen to Connectivity().onConnectivityChanged',
      );
      expect(
        src.contains('connectivityStreamOverrideForTesting'),
        isTrue,
        reason: 'Test override stream must exist',
      );
    });
  });
}
