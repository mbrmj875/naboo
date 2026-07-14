import 'native_google_id_token_sign_in_result.dart';

/// على الويب: لا منتقي أصلي — يُستخدم مسار ID token/redirect الخاص بالويب.
Future<NativeGoogleIdTokenSignInResult> signInWithGoogleNativeIdToken() async {
  return NativeGoogleIdTokenSignInResult.notConfigured();
}

Future<bool> tryRestoreGoogleSupabaseSessionViaIdToken({
  bool interactiveIfNeeded = true,
}) async =>
    false;
