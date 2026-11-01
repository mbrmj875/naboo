import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/auth_session_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<MapEntry<String, Map<String, dynamic>>> reported;
  late bool hasSession;
  late DateTime now;
  late AuthSessionDiagnostics diag;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reported = [];
    hasSession = false;
    now = DateTime.utc(2026, 11, 1, 12);
    diag = AuthSessionDiagnostics.forTesting(
      reporter: (event, context) async {
        reported.add(MapEntry(event, context));
      },
      hasSession: () => hasSession,
      clock: () => now,
    );
  });

  Future<List<String>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(AuthSessionDiagnostics.prefsKey) ?? const [];
  }

  test('خروج المكتبة يُحفظ بلا جلسة ويُرسل عند أول جلسة لاحقة', () async {
    await diag.handleAuthEvent(AuthChangeEvent.signedIn, 'abcdef12-3456');
    diag.noteRefreshFailure('refresh_token_not_found');
    await diag.handleAuthEvent(AuthChangeEvent.signedOut, null);

    expect(reported, isEmpty);
    expect(await pending(), hasLength(1));

    hasSession = true;
    await diag.handleAuthEvent(AuthChangeEvent.signedIn, 'abcdef12-3456');

    expect(await pending(), isEmpty);
    expect(reported, hasLength(1));
    final context = reported.single.value;
    expect(reported.single.key, 'auth_session_signed_out');
    expect(context['expected'], isFalse);
    expect(context['source'], 'library_or_unknown');
    expect(context['refresh_failure'], 'refresh_token_not_found');
    expect(context['lost_user'], 'abcdef12');
  });

  test('الخروج المطلوب من الشيفرة يُميَّز بمصدره', () async {
    diag.noteExpectedSignOut('logout');
    now = now.add(const Duration(seconds: 1));
    await diag.handleAuthEvent(AuthChangeEvent.signedOut, null);

    final entry = jsonDecode((await pending()).single) as Map<String, dynamic>;
    expect(entry['expected'], isTrue);
    expect(entry['source'], 'logout');
  });

  test('علامة الخروج المطلوب تنتهي بعد المهلة', () async {
    diag.noteExpectedSignOut('logout');
    now = now.add(
      AuthSessionDiagnostics.expectedSignOutWindow +
          const Duration(seconds: 1),
    );
    await diag.handleAuthEvent(AuthChangeEvent.signedOut, null);

    final entry = jsonDecode((await pending()).single) as Map<String, dynamic>;
    expect(entry['expected'], isFalse);
    expect(entry['source'], 'library_or_unknown');
  });

  test('التجديد الناجح يمسح آخر فشل ويحسب المدة', () async {
    diag.noteRefreshFailure('over_request_rate_limit');
    await diag.handleAuthEvent(AuthChangeEvent.tokenRefreshed, 'user-1');
    now = now.add(const Duration(seconds: 90));
    await diag.handleAuthEvent(AuthChangeEvent.signedOut, null);

    final entry = jsonDecode((await pending()).single) as Map<String, dynamic>;
    expect(entry['refresh_failure'], isNull);
    expect(entry['seconds_since_refresh'], 90);
  });

  test('الأحداث المسمّاة تُرسل فوراً عند وجود جلسة', () async {
    hasSession = true;
    diag.noteEvent('internal_password_rotation', source: 'email_pin_login');
    await pumpEventQueue();

    expect(reported.single.key, 'internal_password_rotation');
    expect(reported.single.value['source'], 'email_pin_login');
  });

  test('الأحداث المعلّقة محدودة والأقدم يُهمل', () async {
    for (var i = 0; i < AuthSessionDiagnostics.maxPendingEvents + 3; i++) {
      await diag.handleAuthEvent(AuthChangeEvent.signedOut, null);
    }
    expect(await pending(), hasLength(AuthSessionDiagnostics.maxPendingEvents));
  });

  test('event_tier يطابق قيد security_audit_logs', () {
    final source = File(
      'lib/services/auth/auth_session_diagnostics.dart',
    ).readAsStringSync();
    expect(source, contains("eventTier: 'routine'"));
  });

  test('لا تُسجَّل مفاتيح حساسة', () {
    final source = File(
      'lib/services/auth/auth_session_diagnostics.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('refreshToken')));
    expect(source, isNot(contains('accessToken')));
    expect(source, isNot(contains('.email')));
  });
}
