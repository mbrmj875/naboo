import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/auth/supabase_sign_in_failure_policy.dart';

void main() {
  group('isDefinitiveCredentialRejection', () {
    test('invalid_credentials نهائي', () {
      expect(
        isDefinitiveCredentialRejection(
          code: 'invalid_credentials',
          statusCode: '400',
          message: 'Invalid login credentials',
        ),
        isTrue,
      );
    });

    test('400 برسالة صحيحة بلا رمز يبقى نهائياً', () {
      expect(
        isDefinitiveCredentialRejection(
          code: null,
          statusCode: '400',
          message: 'Invalid login credentials',
        ),
        isTrue,
      );
    });

    test('تعطل القاعدة بـ 400 ليس نهائياً', () {
      expect(
        isDefinitiveCredentialRejection(
          code: null,
          statusCode: '400',
          message: "couldn't start a new transaction",
        ),
        isFalse,
      );
    });

    test('429 و5xx والمجهول ليست نهائية', () {
      for (final (code, status) in [
        ('over_request_rate_limit', '429'),
        ('unexpected_failure', '500'),
        ('request_timeout', '504'),
        (null, null),
      ]) {
        expect(
          isDefinitiveCredentialRejection(
            code: code,
            statusCode: status,
            message: 'failure',
          ),
          isFalse,
        );
      }
    });
  });

  group('shouldEndSessionAfterPinReset', () {
    test('بلا كلمة محفوظة تبقى الجلسة فلا يُطلب الرمز مرتين', () {
      expect(
        shouldEndSessionAfterPinReset(
          signOutAfterReset: true,
          hasStoredPassword: false,
        ),
        isFalse,
      );
    });

    test('مع كلمة محفوظة تُنهى كما كانت', () {
      expect(
        shouldEndSessionAfterPinReset(
          signOutAfterReset: true,
          hasStoredPassword: true,
        ),
        isTrue,
      );
    });

    test('بوابة الموظفين لا تنهي الجلسة', () {
      expect(
        shouldEndSessionAfterPinReset(
          signOutAfterReset: false,
          hasStoredPassword: true,
        ),
        isFalse,
      );
    });
  });

  group('حراسة المصدر', () {
    final auth = File('lib/providers/auth_provider.dart').readAsStringSync();

    String body(String start, String end) =>
        auth.split(start).last.split(end).first;

    test('الدخول بالبريد والرمز لا يغيّر كلمة السر', () {
      final fn = body(
        'Future<String?> completeEmailPinLoginAfterOtp(',
        'Future<String?> resendEmailPinReauthOtp(',
      );
      expect(fn, isNot(contains('UserAttributes(password')));
    });

    test('تغيير PIN لا يغيّر كلمة السر', () {
      final fn = body(
        'Future<String?> resetLocalAndServerPassword(',
        'Future<String?> _assertIdentityLinkAllowed(',
      );
      expect(fn, contains('shouldEndSessionAfterPinReset'));
      expect(fn, isNot(contains('UserAttributes(password')));
    });

    test('دخول Google لحساب مكتمل لا يولّد كلمة سر', () {
      final fn = body(
        'Future<String?> continueGoogleOwnerSessionAfterHydrate(',
        'Future<String?> completeGoogleOwnerProfile(',
      );
      expect(fn, isNot(contains('_ensureInternalSupabasePasswordPersisted')));
    });

    test('لا يوجد مسار يغيّر كلمة السر بعد إنشاء الحساب', () {
      expect(
        '_ensureInternalSupabasePasswordPersisted('.allMatches(auth).length,
        0,
        reason: 'إكمال ملف Google كان يغيّرها فيُخرج بقية الأجهزة',
      );
    });
  });
}
