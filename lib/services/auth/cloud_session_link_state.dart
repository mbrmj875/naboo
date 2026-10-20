import 'package:flutter/foundation.dart';

/// حالة ربط السحابة الظاهرة للمستخدم — عقد `cloud-soft-gate`.
enum CloudSessionLinkPhase {
  /// لم يُقيَّم بعد (إقلاع) — لا حاجز.
  unknown,

  /// الجلسة صالحة.
  connected,

  /// فشل مؤقت (مهلة/شبكة). التطبيق يبقى. شريط فقط.
  degraded,

  /// فقدان نهائي. حاجز إعادة الربط دون مسح البيانات ودون شاشة الدخول.
  locked,
}

/// هل يُعرض حاجز إعادة الربط؟
///
/// لا يُعرض أثناء [CloudSessionLinkPhase.unknown] ولا عند اختيار المتابعة المحلية
/// ولا قبل ربط الجهاز بمالك.
bool shouldShowCloudReconnectGate({
  required CloudSessionLinkPhase phase,
  required bool localContinue,
  required bool deviceOwnerBound,
}) {
  return phase == CloudSessionLinkPhase.locked &&
      !localContinue &&
      deviceOwnerBound;
}

bool shouldShowCloudDegradedBanner({
  required CloudSessionLinkPhase phase,
  required bool deviceOwnerBound,
  required bool gateVisible,
}) {
  return phase == CloudSessionLinkPhase.degraded &&
      deviceOwnerBound &&
      !gateVisible;
}

/// حالة عملية واحدة للتطبيق. الواجهة تستمع؛ منطق الدخول ينشر.
class CloudSessionLinkController extends ChangeNotifier {
  CloudSessionLinkController._();

  static final CloudSessionLinkController instance =
      CloudSessionLinkController._();

  CloudSessionLinkPhase phase = CloudSessionLinkPhase.unknown;
  bool localContinue = false;
  bool reconnecting = false;

  void markConnected() {
    phase = CloudSessionLinkPhase.connected;
    localContinue = false;
    reconnecting = false;
    notifyListeners();
  }

  void markDegraded() {
    phase = CloudSessionLinkPhase.degraded;
    reconnecting = false;
    notifyListeners();
  }

  void markLocked() {
    phase = CloudSessionLinkPhase.locked;
    reconnecting = false;
    notifyListeners();
  }

  /// المستخدم اختار البيع المحلي. الحاجز يُرفع؛ السحابة تبقى مقفولة حتى الربط.
  void continueLocally() {
    localContinue = true;
    reconnecting = false;
    notifyListeners();
  }

  void setReconnecting(bool value) {
    reconnecting = value;
    notifyListeners();
  }

  /// خروج مقصود: لا نُظهر الحاجز بين signOut ومحاولة الاستعادة التالية.
  void pauseAfterIntentionalSignOut() {
    phase = CloudSessionLinkPhase.unknown;
    localContinue = false;
    reconnecting = false;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    phase = CloudSessionLinkPhase.unknown;
    localContinue = false;
    reconnecting = false;
  }
}
