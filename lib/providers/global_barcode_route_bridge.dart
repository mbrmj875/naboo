import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../navigation/app_root_navigator_key.dart';
import 'auth_provider.dart';

/// جسر يُسجَّل من [HomeScreen] لتوجيه مسح الباركود (HID) إلى منطق البيع/إضافة المنتج
/// داخل النافذة الداخلية للمحتوى. يمكن لشاشة أخرى تسجيل [setBarcodePriorityHandler]
/// لاعتراض المسح أولاً (مثل «تحديث منتج موجود»).
///
/// عند عدم ربط المعالج (مثلاً المستخدم ما زال على [OpenShiftScreen] وليس على `/home`)
/// يُخزَّن المسح ويُفتح `/home` تلقائياً ثم تُنفَّذ المعالجة بعد تركيب [HomeScreen].
class GlobalBarcodeRouteBridge {
  Future<void> Function(String scanned)? _handler;

  /// يُستهلك المسح قبل [attach] (مثلاً شاشة «تحديث منتج موجود»).
  /// [owner] يُمرَّر لضمان أن [clearBarcodePriorityHandler] لا يزيل معالج شاشة أخرى.
  Object? _priorityOwner;
  Future<bool> Function(String scanned)? _priorityHandler;

  static String? _pendingScan;

  bool get isAttached => _handler != null;

  void attach(Future<void> Function(String scanned) handler) {
    _handler = handler;
  }

  void detach() {
    _handler = null;
  }

  /// إذا عادت [true] لا تُنفَّذ معالجة [HomeScreen] الافتراضية (بيع / إضافة منتج).
  void setBarcodePriorityHandler(
    Object owner,
    Future<bool> Function(String scanned) handler,
  ) {
    _priorityOwner = owner;
    _priorityHandler = handler;
  }

  void clearBarcodePriorityHandler(Object owner) {
    if (_priorityOwner == owner) {
      _priorityOwner = null;
      _priorityHandler = null;
    }
  }

  /// تُستدعى من [HomeScreen] بعد [attach] لتنفيذ مسح وُضع في الانتظار.
  static String? takePendingScan() {
    final s = _pendingScan;
    _pendingScan = null;
    return s;
  }

  Future<void> dispatch(String scanned) async {
    final p = _priorityHandler;
    if (p != null) {
      try {
        if (await p(scanned)) return;
      } catch (_) {}
    }
    final h = _handler;
    if (h != null) {
      await h(scanned);
      return;
    }
    _pendingScan = scanned;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredWhenNoHandler();
    });
  }

  void _deferredWhenNoHandler() {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null) return;

    final h = _handler;
    if (h != null) {
      final code = takePendingScan();
      if (code != null) {
        unawaited(h(code));
      }
      return;
    }

    if (!Provider.of<AuthProvider>(ctx, listen: false).isLoggedIn) {
      takePendingScan();
      return;
    }

    final name = ModalRoute.of(ctx)?.settings.name;
    // شاشة فتح الوردية: لا يوجد [HomeScreen] ولا جسر — ننتقل للرئيسية ويُكمَل المسح لاحقاً.
    if (name == '/open-shift') {
      Navigator.of(ctx).pushReplacementNamed('/home');
      return;
    }
    // مسار آخر بدون جسر (نادر): إبقاء الانتظار حتى يُرفق [HomeScreen].
  }
}
