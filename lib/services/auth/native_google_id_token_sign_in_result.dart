/// نتيجة محاولة تسجيل Google عبر المنتقي الأصلي (google_sign_in + signInWithIdToken).
enum NativeGoogleIdTokenSignInStatus {
  /// جلسة Supabase أُنشئت بنجاح من ID token.
  success,

  /// المستخدم أغلق منتقي الحسابات دون اختيار.
  cancelled,

  /// خطأ منصة/خادم — [NativeGoogleIdTokenSignInResult.message] يحوي رسالة عربية.
  error,

  /// `GOOGLE_WEB_CLIENT_ID` غير مضبوط — يجب fallback للمتصفح الخارجي.
  notConfigured,
}

class NativeGoogleIdTokenSignInResult {
  const NativeGoogleIdTokenSignInResult._(this.status, [this.message]);

  final NativeGoogleIdTokenSignInStatus status;
  final String? message;

  factory NativeGoogleIdTokenSignInResult.success() =>
      const NativeGoogleIdTokenSignInResult._(
        NativeGoogleIdTokenSignInStatus.success,
      );

  factory NativeGoogleIdTokenSignInResult.cancelled() =>
      const NativeGoogleIdTokenSignInResult._(
        NativeGoogleIdTokenSignInStatus.cancelled,
      );

  factory NativeGoogleIdTokenSignInResult.error(String message) =>
      NativeGoogleIdTokenSignInResult._(
        NativeGoogleIdTokenSignInStatus.error,
        message,
      );

  factory NativeGoogleIdTokenSignInResult.notConfigured() =>
      const NativeGoogleIdTokenSignInResult._(
        NativeGoogleIdTokenSignInStatus.notConfigured,
      );
}
