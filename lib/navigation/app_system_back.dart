import 'package:flutter/material.dart';

import 'app_root_navigator_key.dart';

/// مفتاح ملاح المحتوى داخل [HomeScreen] (التنقّل الداخلي).
final GlobalKey<NavigatorState> appHomeContentNavigatorKey =
    GlobalKey<NavigatorState>();

/// اعتراضات رجوع مؤقتة (مثلاً إغلاق لوحة PIN قبل الخروج).
/// تُستدعى من الأحدث إلى الأقدم؛ أول من يُرجع `true` يستهلك الحدث.
abstract final class AppSystemBack {
  static final List<bool Function()> _handlers = <bool Function()>[];

  static void register(bool Function() handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
    }
  }

  static void unregister(bool Function() handler) {
    _handlers.remove(handler);
  }

  /// معالجات + ملاح المحتوى (`maybePop` يحترم PopScope للشاشات الداخلية).
  static Future<bool> tryPopNested() async {
    for (var i = _handlers.length - 1; i >= 0; i--) {
      if (_handlers[i]()) return true;
    }

    final content = appHomeContentNavigatorKey.currentState;
    if (content == null) return false;
    // true = تم التعامل (pop أو حوار منع). false = لا يوجد ما يُرجع إليه.
    return content.maybePop();
  }

  /// رجوع داخلي ثم مسارات الجذر (حوارات / شاشات فوق الرئيسية).
  static Future<bool> tryPopAny() async {
    if (await tryPopNested()) return true;

    final root = appRootNavigatorKey.currentState;
    if (root == null || !root.canPop()) return false;
    return root.maybePop();
  }
}
