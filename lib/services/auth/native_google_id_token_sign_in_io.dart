import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/google_oauth_config.dart';
import '../../utils/app_logger.dart';
import 'auth_user_messages.dart';
import 'native_google_id_token_sign_in_result.dart';

bool get _isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Windows/Linux فقط: لا يوجد منتقي حسابات أصلي في google_sign_in الرسمي.
/// macOS يستخدم المنتقي الأصلي بعد ضبط GIDClientID + keychain.
bool get _noOfficialNativeGooglePicker =>
    Platform.isWindows || Platform.isLinux;

GoogleSignIn _buildGoogleSignIn() {
  return GoogleSignIn(
    clientId: _isApplePlatform
        ? GoogleOAuthConfig.resolvedIosClientId
        : null,
    // نفس جمهور Firebase على أندرويد وiPhone وmacOS.
    serverClientId: GoogleOAuthConfig.firebaseWebClientId,
    scopes: const ['email', 'profile'],
  );
}

Future<bool> _exchangeGoogleIdTokenForSupabaseSession(
  GoogleSignInAuthentication googleAuth,
) async {
  final idToken = googleAuth.idToken;
  if (idToken == null || idToken.isEmpty) {
    AppLogger.warn(
      'NativeGoogleIdToken',
      'idToken empty after Google account selection',
    );
    return false;
  }

  try {
    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    // يُثبّت refresh token في التخزين الآمن — يمنع فقدان الجلسة قبل «إكمال الحساب».
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (e) {
      AppLogger.warn('NativeGoogleIdToken', 'post-signIn refreshSession: $e');
    }
    return Supabase.instance.client.auth.currentUser != null;
  } on AuthException catch (e) {
    AppLogger.warn('NativeGoogleIdToken', 'signInWithIdToken: ${e.message}');
    return false;
  } catch (e, st) {
    AppLogger.error('NativeGoogleIdToken', 'signInWithIdToken failed', e, st);
    return false;
  }
}

/// تسجيل Google عبر منتقي الحسابات الأصلي (مثل Talabat) — بدون متصفح خارجي.
Future<NativeGoogleIdTokenSignInResult> signInWithGoogleNativeIdToken() async {
  final serverClientId = GoogleOAuthConfig.resolvedWebClientId;
  if (serverClientId.isEmpty) {
    return NativeGoogleIdTokenSignInResult.notConfigured();
  }

  // Windows/Linux: لا منتقي أصلي رسمي — AuthProvider يفتح المتصفح (اختيار حساب).
  if (_noOfficialNativeGooglePicker) {
    AppLogger.info(
      'NativeGoogleIdToken',
      'Windows/Linux — no official native picker; browser OAuth',
    );
    return NativeGoogleIdTokenSignInResult.notConfigured();
  }

  final googleSignIn = _buildGoogleSignIn();

  // يُظهر قائمة الحسابات (وليس الدخول الصامت بحساب واحد).
  try {
    await googleSignIn.signOut();
  } catch (e) {
    AppLogger.warn('NativeGoogleIdToken', 'pre-signOut: $e');
  }

  GoogleSignInAccount? account;
  try {
    account = await googleSignIn.signIn();
  } on PlatformException catch (e) {
    if (e.code == 'sign_in_canceled' || e.code == 'CANCELED') {
      return NativeGoogleIdTokenSignInResult.cancelled();
    }
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();
    final networkIssue = code.contains('network') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('host lookup') ||
        msg.contains('timeout');
    AppLogger.warn(
      'NativeGoogleIdToken',
      'GoogleSignIn.signIn platform error: ${e.code}',
    );
    if (networkIssue) {
      return NativeGoogleIdTokenSignInResult.error(
        AuthUserMessages.networkUnavailable,
      );
    }
    return NativeGoogleIdTokenSignInResult.error(
      AuthUserMessages.googleUnavailable,
    );
  } catch (e, st) {
    AppLogger.error('NativeGoogleIdToken', 'GoogleSignIn.signIn failed', e, st);
    final text = e.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('timeout')) {
      return NativeGoogleIdTokenSignInResult.error(
        AuthUserMessages.networkUnavailable,
      );
    }
    return NativeGoogleIdTokenSignInResult.error(
      AuthUserMessages.serverUnreachable,
    );
  }

  if (account == null) {
    return NativeGoogleIdTokenSignInResult.cancelled();
  }

  var googleAuth = await account.authentication;
  if ((googleAuth.idToken ?? '').isEmpty) {
    AppLogger.warn(
      'NativeGoogleIdToken',
      'idToken empty after picker; retrying silent sign-in',
    );
    try {
      final silent = await googleSignIn.signInSilently();
      if (silent != null) {
        googleAuth = await silent.authentication;
      }
    } catch (e) {
      AppLogger.warn('NativeGoogleIdToken', 'silent idToken retry: $e');
    }
  }
  final ok = await _exchangeGoogleIdTokenForSupabaseSession(googleAuth);
  if (!ok) {
    return NativeGoogleIdTokenSignInResult.error(
      'تعذر إكمال الدخول عبر Google. حاول مرة أخرى.',
    );
  }
  return NativeGoogleIdTokenSignInResult.success();
}

/// يُعيد جلسة Supabase عبر Google (صامت ثم منتقي) — لشاشة «إكمال الحساب».
Future<bool> tryRestoreGoogleSupabaseSessionViaIdToken({
  bool interactiveIfNeeded = true,
}) async {
  if (GoogleOAuthConfig.resolvedWebClientId.isEmpty) return false;

  final googleSignIn = _buildGoogleSignIn();
  GoogleSignInAccount? account;

  try {
    account = await googleSignIn.signInSilently();
  } catch (e) {
    AppLogger.warn('NativeGoogleIdToken', 'signInSilently: $e');
  }

  if (account == null && interactiveIfNeeded) {
    try {
      account = await googleSignIn.signIn();
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'CANCELED') {
        return false;
      }
      AppLogger.warn(
        'NativeGoogleIdToken',
        'interactive restore signIn: ${e.code}',
      );
      return false;
    } catch (e) {
      AppLogger.warn('NativeGoogleIdToken', 'interactive restore: $e');
      return false;
    }
  }

  if (account == null) return false;

  final googleAuth = await account.authentication;
  return _exchangeGoogleIdTokenForSupabaseSession(googleAuth);
}
