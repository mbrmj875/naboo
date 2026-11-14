import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/cloud_session_freshness_policy.dart';
import 'package:naboo/services/auth/ensure_fresh_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _fakeJwt({required int expEpochSec}) {
  String b64(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'none', 'typ': 'JWT'})}.'
      '${b64({'exp': expEpochSec, 'sub': 'user-1'})}.sig';
}

Session _sessionExpiringIn(Duration remaining, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final exp = clock.add(remaining).millisecondsSinceEpoch ~/ 1000;
  return Session(
    accessToken: _fakeJwt(expEpochSec: exp),
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    user: const User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
    ),
  );
}

void main() {
  group('shouldSignOutAfterEnsureFreshFailure (policy)', () {
    test('timeout/transient MUST NOT authorize signOut', () {
      expect(
        shouldSignOutAfterEnsureFreshFailure(
          const SessionRefreshTransientException(
            'انتهت مهلة تجديد الجلسة السحابية',
          ),
        ),
        isFalse,
      );
    });

    test('true expiry MAY authorize signOut', () {
      expect(
        shouldSignOutAfterEnsureFreshFailure(const SessionExpiredException()),
        isTrue,
      );
    });

    test('unknown errors MUST NOT authorize signOut', () {
      expect(shouldSignOutAfterEnsureFreshFailure(Exception('x')), isFalse);
    });
  });

  group('ensureFreshSession — contracts against silent session death', () {
    test('no session → SessionExpiredException (terminal)', () async {
      await expectLater(
        ensureFreshSession(readSession: () => null),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test(
      'SCENARIO: refresh hangs past timeout → Transient, NOT SessionExpired',
      () async {
        final session = _sessionExpiringIn(const Duration(minutes: 2));
        Object? caught;
        try {
          await ensureFreshSession(
            readSession: () => session,
            refreshTimeout: const Duration(milliseconds: 40),
            refreshSession: () async {
              await Future<void>.delayed(const Duration(seconds: 2));
              return AuthResponse(session: session);
            },
          );
        } catch (e) {
          caught = e;
        }

        // يفشل إن عاد السلوك القديم: timeout → SessionExpiredException → signOut.
        expect(caught, isA<SessionRefreshTransientException>());
        expect(caught, isNot(isA<SessionExpiredException>()));
        expect(
          shouldSignOutAfterEnsureFreshFailure(caught!),
          isFalse,
          reason: 'مهلة التجديد لا يجوز أن تفتح باب signOut',
        );
      },
    );

    test(
      'SCENARIO: AuthRetryableFetchException → Transient (no signOut)',
      () async {
        final session = _sessionExpiringIn(const Duration(minutes: 1));
        Object? caught;
        try {
          await ensureFreshSession(
            readSession: () => session,
            refreshSession: () async {
              throw AuthRetryableFetchException(message: 'network blip');
            },
          );
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<SessionRefreshTransientException>());
        expect(shouldSignOutAfterEnsureFreshFailure(caught!), isFalse);
      },
    );

    test(
      'SCENARIO: non-retryable AuthException → SessionExpired (signOut allowed)',
      () async {
        final session = _sessionExpiringIn(const Duration(minutes: 1));
        Object? caught;
        try {
          await ensureFreshSession(
            readSession: () => session,
            refreshSession: () async {
              throw const AuthException(
                'Invalid Refresh Token',
                statusCode: '400',
              );
            },
          );
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<SessionExpiredException>());
        expect(shouldSignOutAfterEnsureFreshFailure(caught!), isTrue);
      },
    );

    test('token still fresh (>10m) → no refresh call', () async {
      var refreshCalls = 0;
      final session = _sessionExpiringIn(const Duration(minutes: 30));
      await ensureFreshSession(
        readSession: () => session,
        refreshSession: () async {
          refreshCalls++;
          return AuthResponse(session: session);
        },
      );
      expect(refreshCalls, 0);
    });

    test('successful refresh near expiry → completes', () async {
      final oldSession = _sessionExpiringIn(const Duration(minutes: 2));
      final newSession = _sessionExpiringIn(const Duration(hours: 1));
      await ensureFreshSession(
        readSession: () => oldSession,
        refreshSession: () async => AuthResponse(session: newSession),
      );
    });

    test('refresh returns null session → SessionExpiredException', () async {
      final session = _sessionExpiringIn(const Duration(minutes: 1));
      await expectLater(
        ensureFreshSession(
          readSession: () => session,
          refreshSession: () async => AuthResponse(session: null),
        ),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('source guards — production wiring', () {
    test(
      'onTimeout must throw SessionRefreshTransientException, not SessionExpired',
      () {
        final fresh =
            File('lib/services/auth/ensure_fresh_session.dart').readAsStringSync();
        expect(fresh, contains('SessionRefreshTransientException'));
        expect(fresh, contains('onTimeout:'));
        final timeoutBlock = fresh.split('onTimeout:').last.split('},').first;
        expect(timeoutBlock, contains('SessionRefreshTransientException'));
        expect(timeoutBlock, isNot(contains('SessionExpiredException')));
      },
    );

    test(
      'tryRestoreCloudSessionSilently: Transient catch exists BEFORE signOut path',
      () {
        final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
        final fn = auth
            .split('Future<bool> tryRestoreCloudSessionSilently()')
            .last
            .split('Future<bool> _hasStoredOwnerPassword')
            .first;

        expect(
          fn,
          contains('SessionRefreshTransientException'),
          reason: 'مسار المهلة/الشبكة يجب أن يُلتقط صراحةً',
        );
        expect(fn, contains('shouldSignOutAfterEnsureFreshFailure'));

        final transientIdx = fn.indexOf('SessionRefreshTransientException');
        final signOutIdx = fn.indexOf('auth.signOut()');
        expect(transientIdx, greaterThanOrEqualTo(0));
        expect(signOutIdx, greaterThan(transientIdx));

        // داخل كتلة Transient يجب ألا يوجد signOut.
        final transientBlock = fn
            .split('on session_freshness.SessionRefreshTransientException')
            .last
            .split('on session_freshness.SessionExpiredException')
            .first;
        expect(
          transientBlock,
          isNot(contains('signOut(')),
          reason: 'فشل إن بقي signOut على مسار المهلة',
        );
      },
    );

    test(
      'CloudSessionResumeBridge reschedules heartbeat in finally of tick',
      () {
        final bridge =
            File('lib/widgets/cloud_session_resume_bridge.dart').readAsStringSync();
        expect(bridge, contains('_heartbeatTick'));
        expect(bridge, contains('kCloudSessionCareTimeout'));
        final tick = bridge
            .split('Future<void> _heartbeatTick()')
            .last
            .split('void didChangeAppLifecycleState')
            .first;
        expect(tick, contains('finally'));
        expect(tick, contains('_scheduleNextHeartbeat()'));
      },
    );

    test('WhatsApp gateway treats Transient as temporary, not session_expired', () {
      final wa = File(
        'lib/verticals/oil_change/services/oil_change_whatsapp_gateway_service.dart',
      ).readAsStringSync();
      expect(wa, contains('SessionRefreshTransientException'));
      expect(wa, contains('session_refresh_deferred'));
    });
  });
}
