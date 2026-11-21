import 'package:flutter/foundation.dart' show kIsWeb;

/// سياسات تشغيل الويب فقط — المنصات الأصلية لا تقرأ هذه الحدود لسلوك الأوفلاين.
abstract final class WebRuntimePolicy {
  WebRuntimePolicy._();

  /// جهاز ويب جديد لكل حساب خلال هذه النافذة.
  static const Duration webNewDeviceRateLimit = Duration(hours: 24);

  /// أقصى أجهزة ويب جديدة في النافذة (لكل حساب).
  static const int webNewDevicesPerWindow = 1;

  /// جهاز ويب خامد يُستبدل بدل slot جديد.
  static const Duration webDeviceStaleForReuse = Duration(days: 7);

  /// خمول بلا تفاعل → قفل واجهة فقط (بدون مسح DB).
  /// على الويب مُعطّل في WebIdleLockBinder (بقاء تسجيل الدخول).
  static const Duration webIdleLockAfter = Duration(minutes: 15);

  /// عمر آخر pull ناجح قبل السماح بكتابة مالية على الويب.
  static const Duration webWriteRequiresFreshPullWithin = Duration(minutes: 5);

  /// بيع ينقص المخزون من المتصفح — بعد دمج أحداث المخزون (خط أساس + بنود محلية).
  static const bool allowStockDecrementingSalesOnWeb = true;

  static bool get isWebRuntime => kIsWeb;
}
