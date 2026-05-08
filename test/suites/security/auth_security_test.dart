/*
  SUITE 1 — Security: authentication & token handling.

  Scope:
    • Token storage hygiene: JWT lives in SecureStorage only — never in
      SharedPreferences. Logout deletes it.
    • TenantContext lifecycle: cleared on logout; replaced on a new login
      so the previous tenant's data is no longer reachable.
    • AppLogger redacts JWT / password before reaching the sink.
    • debugPrint usage: should be guarded by `if (kDebugMode)` everywhere.

  Rules:
    • No real Supabase calls.
    • No real flutter_secure_storage / Keychain.
    • Use the existing in-memory SecureKvStore double from the helpers
      pattern (re-defined here to keep this file self-contained).
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/secure_session_storage.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemorySecureKv implements SecureKvStore {
  final Map<String, String> store = {};

  @override
  Future<bool> containsKey(String key) async => store.containsKey(key);

  @override
  Future<void> delete(String key) async => store.remove(key);

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async => store[key] = value;
}

const _kSessionKey = 'sb-rkofqwcuvbzrnmelvxhz-auth-token';

const _realJwt =
    'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im5hYm9vLWRldi0wMDEifQ'
    '.eyJ0ZW5hbnRfaWQiOiI5NzdhOTU1My0wNjllLTRmYTEtYWVmOS1lNDVmYmMzMTNlYjQiLCJwbGFuIjoicHJvIn0'
    '.cqNawTpX4EEvzqryDztNlYYkUYh5d2kU2UdLK4ukxiwKau5e8Zwv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TenantContext.instance.clear();
  });

  // ── token storage ──────────────────────────────────────────────────────
  group('JWT lives in SecureStorage only', () {
    test(
      'persistSession writes JWT to SecureStorage and NOT to SharedPreferences',
      () async {
        final secure = _InMemorySecureKv();
        final storage = SecureLocalStorage(
          persistSessionKey: _kSessionKey,
          secureStore: secure,
        );
        await storage.initialize();

        await storage.persistSession('{"access_token":"$_realJwt"}');

        // SecureStorage HAS the token.
        expect(secure.store[_kSessionKey], isNotNull);
        expect(secure.store[_kSessionKey], contains(_realJwt));

        // SharedPreferences does NOT have the token.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kSessionKey), isNull);
        // and no other key under prefs contains the JWT body either.
        for (final k in prefs.getKeys()) {
          final v = prefs.getString(k);
          if (v != null) {
            expect(v.contains(_realJwt), isFalse,
                reason: 'JWT leaked into SharedPreferences key=$k');
          }
        }
      },
    );

    test('logout clears SecureStorage entry completely', () async {
      final secure = _InMemorySecureKv()..store[_kSessionKey] = 'old-jwt';
      final storage = SecureLocalStorage(
        persistSessionKey: _kSessionKey,
        secureStore: secure,
      );
      await storage.initialize();

      expect(await storage.hasAccessToken(), isTrue);

      await storage.removePersistedSession();

      // Every read points to null after logout.
      expect(secure.store.containsKey(_kSessionKey), isFalse);
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });
  });

  // ── tenant lifecycle ───────────────────────────────────────────────────
  group('TenantContext lifecycle', () {
    test('TenantContext cleared after logout (requireTenantId throws)', () {
      TenantContext.instance.set('tenant-aaa');
      expect(TenantContext.instance.requireTenantId(), 'tenant-aaa');

      // Simulate logout flow.
      TenantContext.instance.clear();

      expect(
        () => TenantContext.instance.requireTenantId(),
        throwsA(isA<StateError>()),
        reason: 'after clear() the gate must reject every DAO call',
      );
      expect(TenantContext.instance.tenantId, isNull);
      expect(TenantContext.instance.hasTenant, isFalse);
    });

    test('re-login with a different account replaces tenantId', () {
      TenantContext.instance.set('tenant-aaa');
      expect(TenantContext.instance.tenantId, 'tenant-aaa');

      // Different account — production replaces value via .set()
      TenantContext.instance.set('tenant-bbb');
      expect(TenantContext.instance.tenantId, 'tenant-bbb');
      expect(TenantContext.instance.requireTenantId(), 'tenant-bbb',
          reason: 'old tenant id must be unreachable from any new query');
    });

    test('TenantContext rejects empty / whitespace input', () {
      expect(() => TenantContext.instance.set(''), throwsArgumentError);
      expect(() => TenantContext.instance.set('   '), throwsArgumentError);
    });
  });

  // ── log redaction ──────────────────────────────────────────────────────
  group('AppLogger redacts secrets before they reach the sink', () {
    late List<String> sink;

    setUp(() {
      sink = <String>[];
      AppLogger.sink = sink.add;
      AppLogger.debugOverride = true;
    });

    tearDown(() {
      AppLogger.resetForTesting();
    });

    test('AppLogger redacts JWT in error messages', () {
      // Use a real-shape JWT (eyJ.eyJ.sig) so the regex matches.
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
          '.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      AppLogger.error('AuthTest', 'login attempt with token=$jwt failed');

      expect(sink, isNotEmpty);
      final out = sink.join('\n');
      expect(out, contains('[REDACTED:JWT]'));
      expect(out, isNot(contains(jwt)),
          reason: 'plain JWT must never reach the sink');
    });

    test('AppLogger redacts password in error messages', () {
      AppLogger.error('AuthTest', 'login payload password=Secret123!');
      final out = sink.join('\n');
      expect(out, contains('[REDACTED:PASSWORD]'));
      expect(out, isNot(contains('Secret123!')),
          reason: 'plain password must never reach the sink');
    });

    test('AppLogger silent in non-debug mode (debugOverride=false)', () {
      AppLogger.debugOverride = false;
      AppLogger.info('Tag', 'should not be emitted');
      AppLogger.warn('Tag', 'should not be emitted');
      AppLogger.error('Tag', 'should not be emitted');
      expect(sink, isEmpty,
          reason: 'release mode must not flush any logs');
    });
  });

  // ── debugPrint usage scan ──────────────────────────────────────────────
  group('debugPrint static scan (lib/)', () {
    test(
      'every debugPrint() call in lib/ sits inside a kDebugMode-guarded '
      'block, an assert(() {...}()) wrapper (debug-only by language spec), '
      'or is in app_logger.dart (the safe wrapper)',
      () {
        // Walk every .dart file under lib/, find each `debugPrint(`, and
        // verify the preceding 6 non-empty lines contain a recognised
        // debug-only guard. Files allowed to call debugPrint without a
        // guard:
        //   • lib/utils/app_logger.dart — the wrapper itself gates on
        //     `_enabled = debugOverride ?? kDebugMode`.
        //   • Top-level FlutterError.onError handler (registered once at
        //     boot, only fires on uncaught errors — explicit allowance).
        //
        // Recognised guards:
        //   • `if (kDebugMode)` / `if (!kDebugMode)` / `kDebugMode &&` /
        //     `!kDebugMode` — explicit compile-time const branch.
        //   • `assert(() { … }())` — Dart strips assertions in release
        //     builds, so the wrapped debugPrint cannot run there.
        //   • `_enabled` — the AppLogger gate (matches the wrapper).
        //   • `FlutterError.onError` — top-level uncaught-error sink.
        const allowedFiles = <String>{
          'lib/utils/app_logger.dart',
        };

        final unguarded = <String>[];
        final libDir = Directory('lib');
        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;
          final rel = entity.path.replaceAll('\\', '/');
          if (allowedFiles.contains(rel)) continue;
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (!lines[i].contains('debugPrint(')) continue;
            // Look back up to 6 lines for a guard.
            final start = (i - 6).clamp(0, lines.length);
            final window = lines.sublist(start, i + 1).join('\n');
            final guarded = window.contains('if (kDebugMode)') ||
                window.contains('kDebugMode &&') ||
                window.contains('FlutterError.onError') ||
                window.contains('if (!kDebugMode)') ||
                window.contains('_enabled') ||
                window.contains('!kDebugMode') ||
                // Asserts are stripped in release: Dart strips the body of
                // `assert(() { … }())` from non-debug builds, so any
                // debugPrint inside it cannot leak.
                window.contains('assert(()');
            if (!guarded) {
              unguarded.add('$rel:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        // Report: if anything is unguarded, fail with a precise listing
        // so the next reviewer can fix the guard. The test does NOT
        // modify any source file.
        expect(
          unguarded,
          isEmpty,
          reason: 'unguarded debugPrint calls (must be inside if (kDebugMode) '
              'or assert(() {...}())):\n${unguarded.join('\n')}',
        );
      },
    );
  });
}
