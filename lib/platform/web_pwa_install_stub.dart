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

/// على المنصات غير الويب: لا يوجد تثبيت PWA.
class WebPwaInstall {
  WebPwaInstall._();

  static bool get isWebSupported => false;

  static bool isStandalone() => false;

  static bool canInstall() => false;

  static WebPwaPlatformHint platformHint() => WebPwaPlatformHint.desktop;

  static bool isBannerDismissed() => true;

  static void dismissBannerForDays([int days = 14]) {}

  static void clearBannerDismiss() {}

  static Future<WebPwaInstallResult> promptInstall() async {
    return const WebPwaInstallResult(ok: false, reason: 'not_web');
  }

  static void listenInstallable(void Function() onReady) {}

  static void listenInstalled(void Function() onInstalled) {}
}
