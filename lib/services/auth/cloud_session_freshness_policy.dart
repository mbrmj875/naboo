import 'ensure_fresh_session.dart';

/// سياسة موحّدة: هل يُسمح باستدعاء `auth.signOut()` بعد فشل [ensureFreshSession]؟
///
/// - [SessionExpiredException]: نعم — جلسة مفقودة أو رفض تجديد نهائي.
/// - [SessionRefreshTransientException]: **لا** — مهلة/شبكة؛ الرمز قد يبقى صالحاً.
/// - أي خطأ آخر: لا (الأسلم عدم قتل الجلسة).
bool shouldSignOutAfterEnsureFreshFailure(Object error) {
  if (error is SessionRefreshTransientException) return false;
  return error is SessionExpiredException;
}

/// مهلة واحدة لرعاية الجلسة (استعادة + نبضة جهاز) حتى لا تتجمّد سلسلة النبضات.
const Duration kCloudSessionCareTimeout = Duration(seconds: 25);
