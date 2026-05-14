/*
  STEP 12 — AppLogger redaction & release-mode suppression.

  Goal: prove that [AppLogger] (a) hides every sensitive value pattern listed
  in the security plan before it leaves the process, (b) suppresses output in
  release mode, and (c) carries enough metadata (level + tag + stack-trace
  marker) for an operator to triage issues without leaking secrets.

  These tests use [AppLogger.sink] to capture emitted lines and
  [AppLogger.debugOverride] to flip the kDebugMode gate without rebuilding
  the binary.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/app_logger.dart';

void main() {
  late List<String> captured;

  setUp(() {
    captured = <String>[];
    AppLogger.sink = captured.add;
    AppLogger.debugOverride = true;
  });

  tearDown(() {
    AppLogger.resetForTesting();
  });

  // ---------------------------------------------------------------------------
  group('AppLogger.redact() — sensitive value patterns', () {
    test('redacts JWT tokens (eyJ... → [REDACTED:JWT])', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ'
          '.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

      final out = AppLogger.redact('Authorization: Bearer $jwt now');
      expect(out, contains('[REDACTED:JWT]'));
      expect(out, isNot(contains(jwt)));
      // The non-secret context must remain visible for triage.
      expect(out, contains('Authorization: Bearer'));
      expect(out, contains('now'));
    });

    test('redacts password fields (= and : forms, with/without quotes)', () {
      const samples = <String>[
        'login attempt password=secret123 ok',
        'payload {"password":"secret123"}',
        'curl --data password : secret123 next',
        'Password=AnOther-Pass!',
      ];

      for (final s in samples) {
        final out = AppLogger.redact(s);
        expect(
          out,
          contains('[REDACTED:PASSWORD]'),
          reason: 'Password not redacted in: $s',
        );
        expect(
          out,
          isNot(contains('secret123')),
          reason: 'Plain password leaked from: $s',
        );
        expect(
          out,
          isNot(contains('AnOther-Pass!')),
          reason: 'Plain password leaked from: $s',
        );
      }
    });

    test('redacts OTP codes (4-8 digits near "otp")', () {
      const samples = <String>[
        'OTP: 1234 sent',
        'your otp 567890 has been generated',
        'OTP=12345678 expired',
        'one-time-code OTP code is 4321',
      ];

      for (final s in samples) {
        final out = AppLogger.redact(s);
        expect(
          out,
          contains('[REDACTED:OTP]'),
          reason: 'OTP not redacted in: $s',
        );
      }
    });

    test('does NOT redact arbitrary 4-digit numbers without "otp" context', () {
      const random = 'order id 4321 created at 2026';
      final out = AppLogger.redact(random);
      expect(out, equals(random));
      expect(out, isNot(contains('[REDACTED:OTP]')));
    });

    test('redacts license_key values', () {
      const samples = <String>[
        'license_key=ABC-DEF-GHIJ-1234 stored',
        'config {"license_key":"ABC-DEF-GHIJ-1234"}',
        'LICENSE_KEY: ABC-DEF-GHIJ-1234',
      ];

      for (final s in samples) {
        final out = AppLogger.redact(s);
        expect(
          out,
          contains('[REDACTED:LICENSE_KEY]'),
          reason: 'license_key not redacted in: $s',
        );
        expect(
          out,
          isNot(contains('ABC-DEF-GHIJ-1234')),
          reason: 'license value leaked from: $s',
        );
      }
    });

    test('redacts anonKey / anon_key values (covers Supabase JWT keys)', () {
      const supabaseAnon =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJpc3MiOiJzdXBhYmFzZSJ9'
          '.AbCdEfGhIjKlMnOpQrStUvWxYz1234567890';

      const samples = <String>[
        'anonKey=$supabaseAnon active',
        'anon_key=$supabaseAnon active',
        'config {"anonKey":"$supabaseAnon"}',
      ];

      for (final s in samples) {
        final out = AppLogger.redact(s);
        expect(
          out.contains('[REDACTED:ANON_KEY]') ||
              out.contains('[REDACTED:JWT]'),
          isTrue,
          reason: 'anon key not redacted in: $s',
        );
        expect(
          out,
          isNot(contains(supabaseAnon)),
          reason: 'anon key leaked from: $s',
        );
      }
    });

    test('non-sensitive messages pass unchanged', () {
      const benign = <String>[
        'Saved invoice #1024 successfully',
        'Sync queue processed 5 mutations',
        'مرحباً، تمت المزامنة بنجاح',
        'tenant_uuid=abc-123 (this is a uuid, not a key)',
        'DB PATH: /var/data/business_app.db',
      ];

      for (final s in benign) {
        expect(
          AppLogger.redact(s),
          equals(s),
          reason: 'Benign message was modified: $s',
        );
      }
    });

    test('redacts multiple secrets in the same message', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiJhZG1pbiJ9'
          '.SIGNATURE-FOR-TEST-1234';
      const composite =
          'Bearer $jwt and password=hunter2 with otp 9876 and license_key=XYZ';

      final out = AppLogger.redact(composite);

      expect(out, contains('[REDACTED:JWT]'));
      expect(out, contains('[REDACTED:PASSWORD]'));
      expect(out, contains('[REDACTED:OTP]'));
      expect(out, contains('[REDACTED:LICENSE_KEY]'));
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('9876')));
      expect(out, isNot(contains(jwt)));
      expect(out, isNot(contains('XYZ')));
    });
  });

  // ---------------------------------------------------------------------------
  group('AppLogger emission — levels and metadata', () {
    test('info() emits with [INFO] tag and redacted body', () {
      AppLogger.info('SyncQueue', 'attempt password=secret123');
      expect(captured, hasLength(1));
      expect(captured.single, startsWith('[INFO][SyncQueue]'));
      expect(captured.single, contains('[REDACTED:PASSWORD]'));
      expect(captured.single, isNot(contains('secret123')));
    });

    test('warn() emits with [WARN] tag', () {
      AppLogger.warn('Cloud', 'realtime status flapping');
      expect(captured.single, startsWith('[WARN][Cloud]'));
    });

    test('error() emits with [ERROR] tag and redacts the err object', () {
      AppLogger.error(
        'Cloud',
        'rpc failed',
        Exception('payload had password=oops!'),
      );
      expect(captured, hasLength(1));
      expect(captured.single, startsWith('[ERROR][Cloud]'));
      expect(captured.single, contains('rpc failed'));
      expect(captured.single, contains('[REDACTED:PASSWORD]'));
      expect(captured.single, isNot(contains('oops!')));
    });

    test('error() emits a separate [stack] line when StackTrace is provided', () {
      try {
        throw StateError('boom');
      } catch (e, st) {
        AppLogger.error('Cloud', 'caught', e, st);
      }

      expect(
        captured.length,
        greaterThanOrEqualTo(2),
        reason: 'error() with stack trace must emit two lines',
      );
      expect(captured.first, startsWith('[ERROR][Cloud]'));
      expect(
        captured[1],
        startsWith('[ERROR][Cloud][stack]'),
        reason: 'Second line must carry the [stack] tag for log search.',
      );
      expect(
        captured[1],
        contains('app_logger_test.dart'),
        reason: 'Stack frame should reference the test file.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('AppLogger release-mode suppression', () {
    test('debug logs are suppressed when debugOverride=false (release sim)', () {
      AppLogger.debugOverride = false;

      AppLogger.info('T', 'visible-info-message');
      AppLogger.warn('T', 'visible-warn-message');
      AppLogger.error('T', 'visible-error-message',
          Exception('e'), StackTrace.current);

      expect(
        captured,
        isEmpty,
        reason: 'No log lines must reach the sink when kDebugMode is false.',
      );
    });

    test(
        'release-mode suppression also blocks redaction work on the sink — '
        'no token bypasses through error()', () {
      AppLogger.debugOverride = false;

      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiJhZG1pbiJ9'
          '.signature-XYZ-1234';

      AppLogger.error('Cloud', 'session $jwt');

      expect(captured, isEmpty);
    });
  });
}
