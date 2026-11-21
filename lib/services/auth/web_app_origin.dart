import 'package:flutter/foundation.dart' show kIsWeb;

/// أصل موقع الويب المُنشَر — يُستخدم لروابط OAuth (لا تعتمد على localhost بالخطأ).
abstract class WebAppOrigin {
  static const _fromEnv = String.fromEnvironment('WEB_APP_ORIGIN');
  static const productionDefault = 'https://naboo-93580.web.app';

  /// أصول مُسجَّلة فعلياً في Google Cloud → Authorized JavaScript origins
  /// لمسار GIS / `google_sign_in` (ID token). غيرها يسبب `origin_mismatch`.
  ///
  /// عند إضافة `https://naboo.fun` في Console، أضفه هنا أيضاً لتفعيل المسار السريع.
  static const gisAuthorizedOrigins = <String>{
    'https://naboo-93580.web.app',
    'https://naboo-93580.firebaseapp.com',
    'https://naboo.fun',
    'http://localhost',
    'http://127.0.0.1',
  };

  /// أصل ثابت من dart-define / افتراضي — للبناء والأدوات، ليس لإعادة توجيه OAuth الحي.
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

  /// أصل نافذة المتصفح الحالية. على الويب يجب أن يطابق عنوان الشريط
  /// وإلا يضيع `localStorage` بين `naboo.fun` و `naboo-93580.web.app`
  /// (جلسة + نية OAuth + OTP).
  static String get runtimeOrigin {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty) {
        return Uri.base.origin;
      }
    }
    return origin;
  }

  /// هل مسار Google ID token (GIS) آمن على الأصل الحالي؟
  /// إن كان `false` نستخدم إعادة توجيه Supabase OAuth بدل نافذة origin_mismatch.
  static bool get supportsGoogleIdTokenGis {
    if (!kIsWeb) return false;
    final o = Uri.base.origin;
    if (gisAuthorizedOrigins.contains(o)) return true;
    // localhost بأي منفذ
    final host = Uri.base.host;
    return host == 'localhost' || host == '127.0.0.1';
  }

  static String oauthCompleteUrl() => '$runtimeOrigin/app/oauth_complete.html';

  static String appRootUrl() => '$runtimeOrigin/app/';
}
