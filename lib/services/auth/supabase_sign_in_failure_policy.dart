/// هل رفض `signInWithPassword` نهائي لكلمة السر الداخلية المحفوظة؟
///
/// - `invalid_credentials`، أو 400 برسالة بيانات دخول خاطئة: نعم.
/// - أي شيء آخر (429، 5xx، قاعدة معطلة، خطأ غير مصنّف): لا — فشل مؤقت،
///   فيجب ألا تُحذف الكلمة ولا يُفك ربط الجهاز.
bool isDefinitiveCredentialRejection({
  required String? code,
  required String? statusCode,
  required String message,
}) {
  if (code == 'invalid_credentials') return true;
  if (statusCode != '400') return false;
  return message.toLowerCase().contains('invalid login credentials');
}

/// هل تُنهى جلسة التحقق بعد تغيير PIN؟
///
/// بلا كلمة داخلية محفوظة، يعني إنهاؤها طلب رمز البريد مرة ثانية فوراً.
bool shouldEndSessionAfterPinReset({
  required bool signOutAfterReset,
  required bool hasStoredPassword,
}) {
  return signOutAfterReset && hasStoredPassword;
}
