/// إعداد طول رمز OTP البريدي — يجب أن يطابق إعداد Supabase (قالب البريد).
///
/// للتغيير: `--dart-define=EMAIL_OTP_LENGTH=6` (يجب أن يطابق Supabase OTP length).
class OtpConfig {
  OtpConfig._();

  static const int emailOtpLength =
      int.fromEnvironment('EMAIL_OTP_LENGTH', defaultValue: 6);
}
