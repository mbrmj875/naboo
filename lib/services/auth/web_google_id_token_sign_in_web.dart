import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/google_oauth_config.dart';
import '../../utils/app_logger.dart';

/// تسجيل Google عبر ID token — بدون إعادة توجيه (يتجاوز Site URL = localhost في Supabase).
Future<bool> signInWithGoogleIdTokenOnWeb() async {
  final clientId = GoogleOAuthConfig.resolvedWebClientId;
  if (clientId.isEmpty) return false;

  final googleSignIn = GoogleSignIn(
    clientId: clientId,
    scopes: const ['email', 'profile', 'openid'],
  );

  try {
    await googleSignIn.signOut();
  } catch (_) {}

  GoogleSignInAccount? account;
  try {
    account = await googleSignIn.signIn();
  } catch (e) {
    AppLogger.warn('WebGoogleIdToken', 'GoogleSignIn.signIn failed: $e');
    return false;
  }
  if (account == null) return false;

  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null || idToken.isEmpty) {
    AppLogger.warn('WebGoogleIdToken', 'missing idToken from Google');
    return false;
  }

  try {
    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    return true;
  } on AuthException catch (e) {
    AppLogger.warn('WebGoogleIdToken', 'signInWithIdToken: ${e.message}');
    return false;
  }
}
