import 'package:flutter/foundation.dart' show kIsWeb;

/// أصل موقع الويب المُنشَر — يُستخدم لروابط OAuth (لا تعتمد على localhost بالخطأ).
abstract class WebAppOrigin {
  static const _fromEnv = String.fromEnvironment('WEB_APP_ORIGIN');
  static const productionDefault = 'https://naboo-93580.web.app';

  static String get origin {
    final env = _fromEnv.trim();
    if (env.isNotEmpty) {
      return env.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty &&
          host != 'localhost' &&
          host != '127.0.0.1' &&
          !host.endsWith('.local')) {
        return Uri.base.origin;
      }
    }
    return productionDefault;
  }

  static String oauthCompleteUrl() => '$origin/app/oauth_complete.html';

  static String appRootUrl() => '$origin/app/';
}
