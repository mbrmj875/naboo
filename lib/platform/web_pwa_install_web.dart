import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// نتيجة محاولة تثبيت PWA من المتصفح.
class WebPwaInstallResult {
  const WebPwaInstallResult({
    required this.ok,
    this.reason = '',
  });

  final bool ok;
  final String reason;
}

enum WebPwaPlatformHint {
  ios,
  android,
  desktop,
}

/// جسر إلى `window.nabooPwa` المعرّف في `web/index.html`.
class WebPwaInstall {
  WebPwaInstall._();

  static bool get isWebSupported => true;

  static Object? get _api {
    try {
      return js_util.getProperty(html.window, 'nabooPwa');
    } catch (_) {
      return null;
    }
  }

  static bool isStandalone() {
    final api = _api;
    if (api == null) {
      return html.window.matchMedia('(display-mode: standalone)').matches ||
          js_util.getProperty(html.window.navigator, 'standalone') == true;
    }
    try {
      return js_util.callMethod(api, 'isStandalone', []) == true;
    } catch (_) {
      return false;
    }
  }

  static bool canInstall() {
    final api = _api;
    if (api == null) return false;
    try {
      return js_util.callMethod(api, 'canInstall', []) == true;
    } catch (_) {
      return false;
    }
  }

  static WebPwaPlatformHint platformHint() {
    final api = _api;
    String raw = 'desktop';
    if (api != null) {
      try {
        raw = (js_util.callMethod(api, 'platformHint', []) ?? 'desktop')
            .toString();
      } catch (_) {}
    }
    switch (raw) {
      case 'ios':
        return WebPwaPlatformHint.ios;
      case 'android':
        return WebPwaPlatformHint.android;
      default:
        return WebPwaPlatformHint.desktop;
    }
  }

  static bool isBannerDismissed() {
    final api = _api;
    if (api == null) return false;
    try {
      return js_util.callMethod(api, 'isBannerDismissed', []) == true;
    } catch (_) {
      return false;
    }
  }

  static void dismissBannerForDays([int days = 14]) {
    final api = _api;
    if (api == null) return;
    try {
      js_util.callMethod(api, 'dismissDismissedForDays', [days]);
    } catch (_) {}
  }

  static void clearBannerDismiss() {
    final api = _api;
    if (api == null) return;
    try {
      js_util.callMethod(api, 'clearBannerDismiss', []);
    } catch (_) {}
  }

  static Future<WebPwaInstallResult> promptInstall() async {
    final api = _api;
    if (api == null) {
      return const WebPwaInstallResult(ok: false, reason: 'no_api');
    }
    try {
      final promise = js_util.callMethod(api, 'promptInstall', []);
      final raw = await js_util.promiseToFuture<Object?>(promise);
      if (raw == null) {
        return const WebPwaInstallResult(ok: false, reason: 'empty');
      }
      final ok = js_util.getProperty(raw, 'ok') == true;
      final reason = (js_util.getProperty(raw, 'reason') ?? '').toString();
      return WebPwaInstallResult(ok: ok, reason: reason);
    } catch (e) {
      return WebPwaInstallResult(ok: false, reason: e.toString());
    }
  }

  static StreamSubscription<html.Event>? _installableSub;
  static StreamSubscription<html.Event>? _installedSub;

  static void listenInstallable(void Function() onReady) {
    _installableSub?.cancel();
    _installableSub = html.window.on['naboo-pwa-installable'].listen((_) {
      onReady();
    });
  }

  static void listenInstalled(void Function() onInstalled) {
    _installedSub?.cancel();
    _installedSub = html.window.on['naboo-pwa-installed'].listen((_) {
      onInstalled();
    });
  }
}
