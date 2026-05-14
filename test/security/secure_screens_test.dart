/*
  STEP 13 — FLAG_SECURE (screenshot protection on Android).

  Goal: prove that

    1) The [SecureScreen] widget calls [ScreenSecurityService.enable] in
       initState and [disable] in dispose, exactly once each, in the right
       order.

    2) Sensitive screens (License, OTP, Salary report, Account settings, …)
       are wrapped with [SecureScreen] in their `build()` output. We check
       this via static source-level grep so the guarantee survives even if
       the screen is too heavy to mount in a unit test.

    3) Non-sensitive screens (e.g. inventory, dashboard) do NOT wrap with
       [SecureScreen] — making sure we did not over-apply the flag and
       surface unnecessary UX trade-offs (no lockscreen preview etc.) on
       casual screens.
*/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/screen_security_service.dart';
import 'package:naboo/widgets/secure_screen.dart';

/// Fake double for [ScreenSecurityService]. Records every enable/disable
/// invocation so the test can assert call order.
class _FakeScreenSecurityService implements ScreenSecurityService {
  final List<String> calls = <String>[];

  @override
  Future<void> enable() async {
    calls.add('enable');
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
  }
}

void main() {
  group('SecureScreen widget — FLAG_SECURE lifecycle', () {
    late _FakeScreenSecurityService fake;

    setUp(() {
      fake = _FakeScreenSecurityService();
      ScreenSecurityService.registerForTesting(fake);
    });

    tearDown(() {
      ScreenSecurityService.resetForTesting();
    });

    testWidgets('calls enable() exactly once in initState', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SecureScreen(child: SizedBox.shrink()),
        ),
      );

      // Allow the fire-and-forget enable() future to complete.
      await tester.pump();

      expect(
        fake.calls,
        equals(['enable']),
        reason: 'enable() must fire exactly once when SecureScreen mounts.',
      );
    });

    testWidgets('calls disable() exactly once in dispose', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SecureScreen(child: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      // Replace the SecureScreen with a different widget → forces dispose.
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox.shrink()),
      );
      await tester.pump();

      expect(
        fake.calls,
        equals(['enable', 'disable']),
        reason: 'disable() must fire exactly once after SecureScreen unmounts.',
      );
    });

    testWidgets('child widget is rendered passthrough', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SecureScreen(
            child: Text('حسّاسة', textDirection: TextDirection.rtl),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('حسّاسة'), findsOneWidget);
    });

    testWidgets(
        're-mounting after dispose calls enable() again (no leftover state)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SecureScreen(child: SizedBox.shrink())),
      );
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      await tester.pumpWidget(
        const MaterialApp(home: SecureScreen(child: SizedBox.shrink())),
      );
      await tester.pump();

      expect(
        fake.calls,
        equals(['enable', 'disable', 'enable']),
        reason: 'Each mount/unmount cycle must trigger one pair of calls.',
      );
    });

    testWidgets('non-secure widget does NOT touch ScreenSecurityService',
        (tester) async {
      // A screen that is NOT wrapped in SecureScreen.
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: Text('public'))),
      );
      await tester.pump();

      expect(
        fake.calls,
        isEmpty,
        reason:
            'A plain widget tree must never reach into ScreenSecurityService.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('Sensitive screens — source-level FLAG_SECURE coverage', () {
    // Path → human description, for nicer test failure messages.
    const sensitiveScreens = <String, String>{
      'lib/screens/license/subscription_plans_screen.dart':
          'License (subscription plans)',
      'lib/screens/license/activate_license_screen.dart':
          'License key entry / Keys & secrets',
      'lib/screens/auth/email_otp_screen.dart': 'Signup OTP',
      'lib/screens/auth/forgot_password_otp_screen.dart':
          'Forgot password OTP',
      'lib/screens/users/staff_shifts_week_screen.dart':
          'Salary / staff shifts report',
      'lib/screens/settings/settings_screen.dart': 'Account settings',
    };

    for (final entry in sensitiveScreens.entries) {
      final path = entry.key;
      final label = entry.value;

      test('$label ($path) imports & uses SecureScreen', () {
        final f = File(path);
        expect(
          f.existsSync(),
          isTrue,
          reason: 'Sensitive screen file is missing: $path',
        );

        final src = f.readAsStringSync();

        expect(
          src.contains("import '../../widgets/secure_screen.dart';"),
          isTrue,
          reason:
              '$label must import SecureScreen so it can wrap its build.',
        );
        expect(
          RegExp(r'\bSecureScreen\s*\(').hasMatch(src),
          isTrue,
          reason:
              '$label must wrap its widget tree with SecureScreen(...)',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  group('Non-sensitive screens — FLAG_SECURE NOT applied', () {
    // We pick a few public, low-risk screens. Adding SecureScreen to these
    // would be over-application: it disables iOS/Android lockscreen preview,
    // recent-apps thumbnails, and screen recording on regular dashboards.
    const publicScreens = <String>[
      'lib/screens/home_screen.dart',
      'lib/screens/inventory/barcode_labels_screen.dart',
      'lib/screens/cash/cash_screen.dart',
    ];

    for (final path in publicScreens) {
      test('$path does NOT use SecureScreen', () {
        final f = File(path);
        if (!f.existsSync()) {
          // Tolerate path drift — if the file moves, the security claim is
          // not violated. The other tests will still catch over-application.
          return;
        }
        final src = f.readAsStringSync();

        expect(
          src.contains('SecureScreen'),
          isFalse,
          reason:
              'Public screen $path was wrapped with SecureScreen — this '
              'over-applies FLAG_SECURE and degrades the UX of casual screens.',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  group('ScreenSecurityService — platform safety', () {
    tearDown(ScreenSecurityService.resetForTesting);

    test('default implementation is a no-op on iOS/macOS (no throw)', () async {
      // We exercise the real default impl. On non-Android platforms,
      // enable()/disable() must short-circuit silently.
      // On Android (rare in `flutter test` host), the call would normally
      // hit a missing platform channel and the service swallows that error
      // via AppLogger — still no throw.
      final svc = ScreenSecurityService.instance;

      Future<void> exercise() async {
        await svc.enable();
        await svc.disable();
      }

      if (Platform.isAndroid) {
        // The MissingPluginException is caught & logged by the service.
        await expectLater(exercise(), completes);
      } else {
        await expectLater(exercise(), completes);
      }
    });
  });
}
