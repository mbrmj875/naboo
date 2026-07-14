/// معرّف عميل Google للويب — عبر `--dart-define=GOOGLE_WEB_CLIENT_ID=...`
/// أو القيمة المضمّنة الافتراضية لمشروع naboo (عامة — ليست سرّاً).
///
/// يُستخدم على Android/iOS كـ [GoogleSignIn.serverClientId] لمنتقي الحسابات
/// الأصلي (بدون متصفح خارجي) ثم `signInWithIdToken` في Supabase.
abstract class GoogleOAuthConfig {
  /// Web client ID المُسجَّل في Supabase → Authentication → Google.
  /// نفس المعرّف في `.vscode/settings.json` و Google Cloud Console.
  static const _defaultWebClientId =
      '281392172783-ngr4g28b2c4cap8mvfdav60t9b62pj13.apps.googleusercontent.com';

  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: _defaultWebClientId,
  );

  /// المعرّف الفعلي — يعود للافتراضي إذا مُرِّر dart-define فارغاً بالخطأ.
  static String get resolvedWebClientId {
    final id = webClientId.trim();
    return id.isNotEmpty ? id : _defaultWebClientId;
  }

  static bool get isWebIdTokenEnabled => resolvedWebClientId.isNotEmpty;

  /// هل المعرّف من dart-define صريح (وليس الافتراضي المضمّن)؟
  static bool get isExplicitDartDefine =>
      const bool.hasEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// جاهز لمسار المنتقي الأصلي على الموبايل/الديسكتوب.
  static bool get isNativeIdTokenEnabled => isWebIdTokenEnabled;
}
