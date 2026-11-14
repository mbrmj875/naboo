import 'package:naboo/services/auth/email_otp_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('مهلة طلب رمز البريد', () {
    test('تقرأ الثواني من رد الخادم الحقيقي', () {
      expect(
        emailOtpCooldownSeconds(
          'For security purposes, you can only request this after 31 seconds.',
        ),
        31,
      );
    });

    test('حد الإرسال العام ليس مهلة قصيرة', () {
      expect(emailOtpCooldownSeconds('email rate limit exceeded'), isNull);
      expect(emailOtpCooldownSeconds(''), isNull);
    });

    test('قيمة غير معقولة تُهمل', () {
      expect(emailOtpCooldownSeconds('after 0 seconds'), isNull);
      expect(emailOtpCooldownSeconds('after 99999 seconds'), isNull);
    });

    test('الرسالة تذكر الثواني وأن الرمز السابق صالح', () {
      final m = emailOtpCooldownMessageAr(22);
      expect(m, contains('22'));
      expect(m, contains('صالح'));
    });
  });
}
