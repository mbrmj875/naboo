/// معرّفات عميل Google — عبر `--dart-define=...` أو القيم المضمّنة (عامة — ليست سرّاً).
///
/// - Web: [GoogleSignIn.serverClientId] + Supabase Google provider
/// - iOS/macOS: [GoogleSignIn.clientId] + `GIDClientID` في Info.plist
abstract class GoogleOAuthConfig {
  /// Web client ID المُسجَّل في Supabase → Authentication → Google.
  /// نفس المعرّف في `.vscode/settings.json` و Google Cloud Console.
  static const _defaultWebClientId =
      '281392172783-ngr4g28b2c4cap8mvfdav60t9b62pj13.apps.googleusercontent.com';

  /// iOS client ID (نفسه في `ios/Runner/GoogleService-Info.plist`).
  static const _defaultIosClientId =
      '281392172783-rpnh4q1n0vuvjb3lv96sl48rkg1iu8ld.apps.googleusercontent.com';

  /// عميل الويب الذي أنشأه Firebase للمشروع (client_type 3).
  /// أندرويد وiPhone وmacOS يطلبون idToken بهذا المعرّف حتى يتطابق الجمهور.
  /// معرّف المتصفح أعلاه يبقى أول عميل في Supabase لأن لديه رابط الرجوع.
  static const firebaseWebClientId =
      '281392172783-s4hvsidll33hgvt75tilm0okg5epb0ep.apps.googleusercontent.com';

  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: _defaultWebClientId,
  );

  static const iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: _defaultIosClientId,
  );

  /// المعرّف الفعلي — يعود للافتراضي إذا مُرِّر dart-define فارغاً بالخطأ.
  static String get resolvedWebClientId {
    final id = webClientId.trim();
    return id.isNotEmpty ? id : _defaultWebClientId;
  }

  static String get resolvedIosClientId {
    final id = iosClientId.trim();
    return id.isNotEmpty ? id : _defaultIosClientId;
  }

  static bool get isWebIdTokenEnabled => resolvedWebClientId.isNotEmpty;

  /// هل المعرّف من dart-define صريح (وليس الافتراضي المضمّن)؟
  static bool get isExplicitDartDefine =>
      const bool.hasEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// جاهز لمسار المنتقي الأصلي على الموبايل.
  static bool get isNativeIdTokenEnabled => isWebIdTokenEnabled;
}
