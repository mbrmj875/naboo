import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// يُرجع `true` إذا كانت نتائج [Connectivity] تشير إلى وجود رابط شبكة
/// (Wi‑Fi، خلوي، إيثرنت، VPN، …). القائمة `[none]` فقط تعني عدم الاتصال.
bool connectivityResultsOnline(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}

/// يجدول استدعاءً واحداً بعد [debounce] عند الانتقال **من غير متصل إلى متصل**
/// فقط. لا يُفعَّل عند أول إرسال «متصل» عندما يكون السابق غير معروف (`null`)
/// حتى لا نُزامن عند بدء التطبيق والجهاز أصلاً على الشبكة.
///
/// عند فقدان الشبكة يُلغى أي مؤقت قيد الانتظار (لا مزامنة أثناء التقطّع).
class ConnectivityResumeScheduler {
  ConnectivityResumeScheduler({
    required this.onOfflineToOnlineDebounced,
    this.debounce = const Duration(seconds: 1),
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  }) : _timerFactory = timerFactory ?? ((d, cb) => Timer(d, cb));

  final void Function() onOfflineToOnlineDebounced;
  final Duration debounce;
  final Timer Function(Duration, void Function()) _timerFactory;

  bool? _lastOnline;
  Timer? _debounceTimer;

  void handle(List<ConnectivityResult> results) {
    final online = connectivityResultsOnline(results);
    if (!online) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _lastOnline = false;
      return;
    }

    final transitionedFromOffline = _lastOnline == false;
    _lastOnline = true;
    if (!transitionedFromOffline) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = _timerFactory(debounce, () {
      _debounceTimer = null;
      onOfflineToOnlineDebounced();
    });
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  @visibleForTesting
  bool? get debugLastOnline => _lastOnline;
}
