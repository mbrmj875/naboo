import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/app_logger.dart';
import 'desktop_oauth_loopback_result.dart';

const windowsOAuthLoopbackPort = 47821;
const windowsOAuthBridgeUrl = 'https://naboo.fun/app/desktop-oauth.html';

Future<DesktopOAuthLoopbackResult> completeGoogleOAuthViaLoopback(
  GoTrueClient auth,
) async {
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return DesktopOAuthLoopbackResult.failed();
  }

  HttpServer? server;
  try {
    server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      windowsOAuthLoopbackPort,
    );
  } on Object catch (e) {
    AppLogger.warn('DesktopOAuth', 'loopback bind failed: $e');
    return DesktopOAuthLoopbackResult.failed();
  }

  try {
    final res = await auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: windowsOAuthBridgeUrl,
    );
    final launched = await launchUrl(
      Uri.parse(res.url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      AppLogger.warn('DesktopOAuth', 'could not launch Google OAuth URL');
      return DesktopOAuthLoopbackResult.failed();
    }

    final request = await _waitForCallback(server).timeout(
      const Duration(seconds: 110),
    );
    if (request == null) {
      return DesktopOAuthLoopbackResult.cancelled();
    }

    final callback = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: windowsOAuthLoopbackPort,
      path: request.uri.path,
      query: request.uri.query.isEmpty ? null : request.uri.query,
    );

    final error = callback.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      await _writeHtml(
        request,
        error == 'access_denied'
            ? 'تم إلغاء تسجيل الدخول. يمكنك إغلاق هذه النافذة.'
            : 'تعذّر إكمال الدخول. أعد المحاولة من تطبيق نبو.',
      );
      return error == 'access_denied'
          ? DesktopOAuthLoopbackResult.cancelled()
          : DesktopOAuthLoopbackResult.failed();
    }

    try {
      await auth.getSessionFromUrl(callback);
    } catch (e, st) {
      AppLogger.error('DesktopOAuth', 'getSessionFromUrl', e, st);
      await _writeHtml(
        request,
        'تعذّر إكمال الدخول. أعد المحاولة من تطبيق نبو.',
      );
      return DesktopOAuthLoopbackResult.failed();
    }

    final ok = auth.currentSession != null && auth.currentUser != null;
    await _writeHtml(
      request,
      ok
          ? 'تم تسجيل الدخول. يمكنك إغلاق هذه النافذة والعودة إلى نبو.'
          : 'تعذّر إكمال الدخول. أعد المحاولة من تطبيق نبو.',
    );
    return ok
        ? DesktopOAuthLoopbackResult.ok()
        : DesktopOAuthLoopbackResult.failed();
  } on TimeoutException {
    AppLogger.warn('DesktopOAuth', 'loopback wait timed out');
    return DesktopOAuthLoopbackResult.failed();
  } catch (e, st) {
    AppLogger.error('DesktopOAuth', 'loopback failed', e, st);
    return DesktopOAuthLoopbackResult.failed();
  } finally {
    try {
      await server.close(force: true);
    } catch (_) {}
  }
}

Future<HttpRequest?> _waitForCallback(HttpServer server) async {
  await for (final request in server) {
    final path = request.uri.path.toLowerCase();
    if (path == '/favicon.ico') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    return request;
  }
  return null;
}

Future<void> _writeHtml(HttpRequest request, String message) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.html;
  request.response.headers.set('Cache-Control', 'no-store');
  request.response.write(
    '<!DOCTYPE html><html lang="ar" dir="rtl"><head>'
    '<meta charset="utf-8"/>'
    '<title>نبو</title>'
    '<style>body{margin:0;min-height:100vh;display:flex;align-items:center;'
    'justify-content:center;background:#071A36;color:#f5f3ee;'
    'font-family:system-ui,sans-serif;padding:24px;text-align:center}</style>'
    '</head><body><p>$message</p></body></html>',
  );
  await request.response.close();
}
