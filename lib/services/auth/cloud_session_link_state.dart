import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../connectivity_resume_sync.dart';

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
/// إعادة الربط إجبارية: لا زر «متابعة بدون سحابة». الاستثناء الوحيد انقطاع
/// الإنترنت، فيستمر البيع مع شريط ثابت حتى تعود الشبكة ثم يعود الحاجز.
/// [localContinue] يُستعمل فقط أثناء فتح شاشة الدخول بالبريد من الحاجز.
bool shouldShowCloudReconnectGate({
  required CloudSessionLinkPhase phase,
  required bool localContinue,
  required bool deviceOwnerBound,
  bool offline = false,
}) {
  return phase == CloudSessionLinkPhase.locked &&
      !localContinue &&
      !offline &&
      deviceOwnerBound;
}

/// الجلسة مفقودة والإنترنت مقطوع: البيع مستمر مع شريط أحمر ثابت.
bool shouldShowCloudOfflineLockedBanner({
  required CloudSessionLinkPhase phase,
  required bool deviceOwnerBound,
  required bool offline,
}) {
  return phase == CloudSessionLinkPhase.locked && offline && deviceOwnerBound;
}

/// إعادة الربط تقبل حساب مالك هذا الجهاز فقط — لا يُربط جهاز متجر بحساب آخر.
bool cloudReconnectAccountMatches({
  required String deviceOwnerUid,
  required String signedInUid,
}) {
  final owner = deviceOwnerUid.trim();
  return owner.isNotEmpty && owner == signedInUid.trim();
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

  /// لا يوجد رابط شبكة على الجهاز الآن.
  bool offline = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// يتابع حالة الشبكة مرة واحدة طوال عمر التطبيق.
  void watchConnectivity() {
    if (_connectivitySub != null) return;
    try {
      final connectivity = Connectivity();
      unawaited(
        connectivity
            .checkConnectivity()
            .then(_onConnectivity)
            .catchError((_) {}),
      );
      _connectivitySub = connectivity.onConnectivityChanged.listen(
        _onConnectivity,
        onError: (_) {},
      );
    } catch (_) {
      // منصة بلا دعم للشبكة: نعدّها متصلة فيظهر الحاجز كالمعتاد.
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    setOffline(!connectivityResultsOnline(results));
  }

  void setOffline(bool value) {
    if (offline == value) return;
    offline = value;
    notifyListeners();
  }

  /// انتهت شاشة الدخول بالبريد دون ربط: يعود الحاجز.
  void endEmailSignInDetour() {
    if (!localContinue) return;
    localContinue = false;
    notifyListeners();
  }

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

  /// يُرفع الحاجز مؤقتاً أثناء شاشة الدخول بالبريد فقط.
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
    offline = false;
  }
}
