import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'connectivity_resume_sync.dart';

/// حالة الشبكة الفعلية للجهاز (Wi‑Fi / خلوي / …) — لا علاقة لها بحالة الاشتراك.
///
/// [online] تكون `null` قبل أول قراءة، فلا نُظهر «بلا اتصال» قبل أن نعرف.
class NetworkStatusService extends ChangeNotifier {
  NetworkStatusService._();

  static final NetworkStatusService instance = NetworkStatusService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool? _online;
  bool _started = false;

  bool? get online => _online;

  /// `true` فقط حين نعرف يقيناً أن الجهاز بلا شبكة.
  bool get isOffline => _online == false;

  /// يبدأ الاستماع مرة واحدة؛ آمن للاستدعاء المتكرر.
  void ensureStarted({
    Stream<List<ConnectivityResult>>? stream,
    Future<List<ConnectivityResult>> Function()? initialCheck,
  }) {
    if (_started) return;
    _started = true;
    try {
      final connectivity = (stream == null || initialCheck == null)
          ? Connectivity()
          : null;
      _sub = (stream ?? connectivity!.onConnectivityChanged).listen(
        _apply,
        onError: (Object e) =>
            AppLogger.warn('NetworkStatus', 'connectivity stream: $e'),
      );
      unawaited(
        (initialCheck ?? connectivity!.checkConnectivity)()
            .then(_apply)
            .catchError((Object e) {
              AppLogger.warn('NetworkStatus', 'checkConnectivity: $e');
            }),
      );
    } catch (e) {
      // منصات بلا إضافة الشبكة (اختبارات/ويب قديم) — نبقى «غير معروف».
      AppLogger.warn('NetworkStatus', 'start failed: $e');
    }
  }

  void _apply(List<ConnectivityResult> results) {
    _set(connectivityResultsOnline(results));
  }

  void _set(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }

  /// للاختبارات فقط.
  @visibleForTesting
  void debugSetOnline(bool? value) {
    _started = true;
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }

  /// للاختبارات فقط — يعيد الخدمة لحالتها الأولى.
  @visibleForTesting
  Future<void> debugReset() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    _online = null;
  }
}
