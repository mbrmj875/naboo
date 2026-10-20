import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/app_logger.dart';
import 'desktop_oauth_loopback_result.dart';

const windowsOAuthLoopbackPort = 47821;
const windowsOAuthLoopbackRedirect =
    'http://127.0.0.1:$windowsOAuthLoopbackPort/login-callback';

/// تسجيل Google على ويندوز: المتصفح يرجع إلى التطبيق نفسه على 127.0.0.1.
///
/// Supabase يضع الجلسة بعد علامة # في العنوان. الخادم لا يراها، لذلك أول رد
/// صفحة محلية تقرأ العنوان وتعيد إرساله في الاستعلام، ثم تُحفظ الجلسة.
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
    return DesktopOAuthLoopbackResult.failed(
      'تطبيق نبو مفتوح أكثر من مرة. أغلقه بالكامل ثم أعد فتحه.',
    );
  }

  try {
    final res = await auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: windowsOAuthLoopbackRedirect,
    );
    final launched = await launchUrl(
      Uri.parse(res.url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      return DesktopOAuthLoopbackResult.failed(
        'تعذر فتح صفحة Google.',
      );
    }

    return await _serveUntilSession(server, auth).timeout(
      const Duration(seconds: 110),
    );
  } on TimeoutException {
    AppLogger.warn('DesktopOAuth', 'loopback wait timed out');
    return DesktopOAuthLoopbackResult.failed(
      'انتهت مهلة تسجيل الدخول. أعد المحاولة.',
    );
  } catch (e, st) {
    AppLogger.error('DesktopOAuth', 'loopback failed', e, st);
    return DesktopOAuthLoopbackResult.failed(
      'تعذّر إكمال الدخول عبر Google على ويندوز. أعد المحاولة.',
    );
  } finally {
    try {
      await server.close(force: true);
    } catch (_) {}
  }
}

Future<DesktopOAuthLoopbackResult> _serveUntilSession(
  HttpServer server,
  GoTrueClient auth,
) async {
  await for (final request in server) {
    final params = request.uri.queryParameters;
    if (!_hasOAuthPayload(params)) {
      await _writeCollectorPage(request);
      continue;
    }

    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      final cancelled = error == 'access_denied';
      await _writeHtml(
        request,
        cancelled
            ? 'تم إلغاء تسجيل الدخول. يمكنك إغلاق هذه النافذة.'
            : 'تعذّر إكمال الدخول. أعد المحاولة من تطبيق نبو.',
      );
      return cancelled
          ? DesktopOAuthLoopbackResult.cancelled()
          : DesktopOAuthLoopbackResult.failed(
              'تعذّر إكمال الدخول عبر Google على ويندوز. أعد المحاولة.',
            );
    }

    try {
      final access = params['access_token'];
      final refresh = params['refresh_token'];
      if (access != null &&
          access.isNotEmpty &&
          refresh != null &&
          refresh.isNotEmpty) {
        await auth
            .setSession(refresh, accessToken: access)
            .timeout(const Duration(seconds: 20));
      } else {
        final callback = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: windowsOAuthLoopbackPort,
          path: request.uri.path,
          queryParameters: params,
        );
        await auth
            .getSessionFromUrl(callback)
            .timeout(const Duration(seconds: 20));
      }
    } catch (e, st) {
      AppLogger.error('DesktopOAuth', 'session exchange failed', e, st);
      await _writeHtml(
        request,
        'تعذّر إكمال الدخول. أعد المحاولة من تطبيق نبو.',
      );
      return DesktopOAuthLoopbackResult.failed(
        'تعذّر إكمال الدخول عبر Google على ويندوز. أعد المحاولة.',
      );
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
        : DesktopOAuthLoopbackResult.failed(
            'تعذّر إكمال الدخول عبر Google على ويندوز. أعد المحاولة.',
          );
  }
  return DesktopOAuthLoopbackResult.failed(
    'تعذّر إكمال الدخول عبر Google على ويندوز. أعد المحاولة.',
  );
}

bool _hasOAuthPayload(Map<String, String> params) {
  return (params['code']?.isNotEmpty ?? false) ||
      (params['access_token']?.isNotEmpty ?? false) ||
      (params['error']?.isNotEmpty ?? false) ||
      (params['error_description']?.isNotEmpty ?? false);
}

Future<void> _writeCollectorPage(HttpRequest request) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.html;
  request.response.headers.set('Cache-Control', 'no-store');
  request.response.write('''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8" />
  <title>نبو</title>
  <style>
    body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#071A36;color:#f5f3ee;font-family:system-ui,sans-serif;padding:24px;text-align:center}
  </style>
</head>
<body>
  <p id="m">جاري إكمال تسجيل الدخول في نبو…</p>
  <script>
    (function () {
      var q = location.search.length > 1 ? location.search.substring(1) : '';
      var h = location.hash.length > 1 ? location.hash.substring(1) : '';
      var p = q;
      if (h) p = p ? (p + '&' + h) : h;
      if (!p) {
        var el = document.getElementById('m');
        if (el) el.textContent = 'لم تصل جلسة الدخول. أعد المحاولة من تطبيق نبو.';
        return;
      }
      location.replace('/login-callback?' + p);
    })();
  </script>
</body>
</html>
''');
  await request.response.close();
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
