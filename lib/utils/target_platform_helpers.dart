import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// بناء تطبيق لنظام هاتف/لوحي (Android أو iOS أو Fuchsia) — **ليس** إصدارات
/// Windows / macOS / Linux من Flutter.
///
/// يُستخدم لتمييز «الهاتف» عن «شاشة الحاسوب» حتى لو كانت النافذة صغيرة.
bool get isMobileOsBuild {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia =>
      true,
    _ => false,
  };
}

/// اهتزاز خفيف — مناسب فقط عندما يكون الجهاز هاتفاً/لوحياً (لا يُستدعى على سطح المكتب).
void hapticLightIfMobileOs(void Function() haptic) {
  if (isMobileOsBuild) haptic();
}

/// نقرة اختيار — للهاتف فقط.
void hapticSelectionIfMobileOs(void Function() haptic) {
  if (isMobileOsBuild) haptic();
}

/// اهتزاز متوسط — للهاتف فقط.
void hapticMediumIfMobileOs(void Function() haptic) {
  if (isMobileOsBuild) haptic();
}

/// اهتزاز قوي — للهاتف فقط.
void hapticHeavyIfMobileOs(void Function() haptic) {
  if (isMobileOsBuild) haptic();
}
