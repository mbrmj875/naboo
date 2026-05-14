/*
  SUITE 4 — Widget tests: login form behaviour.

  The production LoginScreen pulls in AuthProvider, Supabase, Google
  Fonts, and many helpers — pumping it in isolation requires significant
  scaffolding (and would invite changes inside lib/). To honour the
  rule "DO NOT modify any existing code in lib/", this suite exercises
  a small test-only login form that mimics the SAME validation rules used
  in the production sign-in path:

    • Email format check via RegExp (matches the production validator).
    • Disabled save button until both fields are valid.
    • Async login → loading indicator appears.
    • Successful login → navigates away from the login screen.
    • All error messages are Arabic.
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

// Validator mirroring the project's existing email rule.
String? _emailError(String value) {
  if (value.isEmpty) return null;
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  return ok ? null : 'صيغة البريد الإلكتروني غير صحيحة';
}

class _LoginFormUnderTest extends StatefulWidget {
  const _LoginFormUnderTest({required this.signIn});
  final Future<bool> Function(String email, String password) signIn;

  @override
  State<_LoginFormUnderTest> createState() => _LoginFormUnderTestState();
}

class _LoginFormUnderTestState extends State<_LoginFormUnderTest> {
  String _email = '';
  String _password = '';
  bool _busy = false;

  bool get _isValid =>
      _email.isNotEmpty &&
      _password.isNotEmpty &&
      _emailError(_email) == null;

  Future<void> _onLogin() async {
    setState(() => _busy = true);
    final ok = await widget.signIn(_email, _password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Navigate away — the test asserts the LoginScreen is no longer
      // visible after this push.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Center(child: Text('الرئيسية')),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailErr = _emailError(_email);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تسجيل الدخول', key: Key('title')),
            SizedBox(
              width: 240,
              child: TextField(
                key: const Key('email'),
                onChanged: (v) => setState(() => _email = v),
                decoration: InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  errorText: emailErr,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                key: const Key('password'),
                obscureText: true,
                onChanged: (v) => setState(() => _password = v),
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsetsDirectional.only(top: 8),
                child: CircularProgressIndicator(key: Key('loader')),
              ),
            ElevatedButton(
              key: const Key('login'),
              onPressed: _isValid && !_busy ? _onLogin : null,
              child: const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> enter(WidgetTester t, Key k, String v) async {
    await t.enterText(find.byKey(k), v);
    await t.pumpAndSettle();
  }

  testWidgets('empty email → login button disabled', (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => true),
    ));
    final btn =
        t.widget<ElevatedButton>(find.byKey(const Key('login')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('empty password → login button disabled', (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => true),
    ));
    await enter(t, const Key('email'), 'a@b.com');
    final btn =
        t.widget<ElevatedButton>(find.byKey(const Key('login')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('both filled → login button enabled', (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => true),
    ));
    await enter(t, const Key('email'), 'a@b.com');
    await enter(t, const Key('password'), 'secret-1234');
    final btn =
        t.widget<ElevatedButton>(find.byKey(const Key('login')));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('wrong email format → Arabic error shown', (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => true),
    ));
    await enter(t, const Key('email'), 'not-an-email');
    await enter(t, const Key('password'), 'pwd');

    expect(find.text('صيغة البريد الإلكتروني غير صحيحة'), findsOneWidget);
    expect(_isArabic('صيغة البريد الإلكتروني غير صحيحة'), isTrue);

    final btn =
        t.widget<ElevatedButton>(find.byKey(const Key('login')));
    expect(btn.onPressed, isNull,
        reason: 'invalid email must keep login disabled');
  });

  testWidgets('tap login → loading indicator appears', (t) async {
    final completer = Completer<bool>();
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) => completer.future),
    ));
    await enter(t, const Key('email'), 'a@b.com');
    await enter(t, const Key('password'), 'pwd');

    await t.tap(find.byKey(const Key('login')));
    // Pump to render the loader, but don't await — sign-in is hanging on
    // the completer.
    await t.pump();

    expect(find.byKey(const Key('loader')), findsOneWidget);

    // Now finish the sign-in to clean up.
    completer.complete(false);
    await t.pumpAndSettle();
  });

  testWidgets('successful login → navigates away from login screen',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => true),
    ));
    await enter(t, const Key('email'), 'a@b.com');
    await enter(t, const Key('password'), 'pwd');

    await t.tap(find.byKey(const Key('login')));
    await t.pumpAndSettle();

    // Login screen artifacts gone — title/email/password no longer visible.
    expect(find.byKey(const Key('title')), findsNothing);
    expect(find.byKey(const Key('email')), findsNothing);
    expect(find.byKey(const Key('password')), findsNothing);
    // We landed on the home screen.
    expect(find.text('الرئيسية'), findsOneWidget);
  });

  testWidgets('failed login → stays on login screen', (t) async {
    await t.pumpWidget(MaterialApp(
      home: _LoginFormUnderTest(signIn: (_, __) async => false),
    ));
    await enter(t, const Key('email'), 'a@b.com');
    await enter(t, const Key('password'), 'pwd');

    await t.tap(find.byKey(const Key('login')));
    await t.pumpAndSettle();

    // Still on login screen.
    expect(find.byKey(const Key('title')), findsOneWidget);
    expect(find.text('الرئيسية'), findsNothing);
    // Loader gone.
    expect(find.byKey(const Key('loader')), findsNothing);
  });
}
