/**
 * جسر Auth SMTP — معطّل نهائياً.
 *
 * سابقاً كان يستبدل قالب magic link مؤقتاً لإرسال تنبيهات واتساب عبر
 * قناة OTP، فعلق القالب على رسالة «انقطع اتصال واتساب» بدون {{ .Token }}
 * وتعطّل رمز الدخول المكوّن من 8 أرقام في التطبيق.
 *
 * لا تُعِد تفعيل هذا الجسر. استخدم OPS_MAIL_RELAY أو Resend فقط.
 */
export async function sendViaAuthSmtpBridge(_args: {
  to: string;
  subject: string;
  text: string;
}): Promise<{ ok: boolean; detail: string }> {
  return {
    ok: false,
    detail: 'auth_smtp_bridge_disabled_protects_login_otp',
  };
}
