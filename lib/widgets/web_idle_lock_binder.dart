import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/sync_queue_service.dart';
import '../services/web_runtime_policy.dart';
import '../utils/app_logger.dart';

/// على الويب: خمول 15 دقيقة **لا يُقفل ولا يمسح الجلسة** (بقاء الدخول بعد
/// إغلاق التبويب/PWA). المنصات الأصلية لا تستخدم هذا الـ binder أصلاً.
///
/// الإبقاء على الويدجت كغلاف شفاف حتى لا نكسر استدعاءات `main.dart`.
class WebIdleLockBinder extends StatefulWidget {
  const WebIdleLockBinder({super.key, required this.child});

  final Widget child;

  @override
  State<WebIdleLockBinder> createState() => _WebIdleLockBinderState();
}

class _WebIdleLockBinderState extends State<WebIdleLockBinder>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  bool _locking = false;

  /// سياسة بقاء الجلسة على الويب: لا قفل خمول.
  static const bool _idleLockEnabledOnWeb = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && _idleLockEnabledOnWeb) {
      WidgetsBinding.instance.addObserver(this);
      _armIdleTimer();
    }
  }

  @override
  void dispose() {
    if (kIsWeb && _idleLockEnabledOnWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _idleTimer?.cancel();
    super.dispose();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!kIsWeb || !_idleLockEnabledOnWeb) return;
    _idleTimer = Timer(WebRuntimePolicy.webIdleLockAfter, _onIdle);
  }

  Future<void> _onIdle() async {
    if (!mounted || _locking || !_idleLockEnabledOnWeb) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    _locking = true;
    try {
      var pendingNote = false;
      try {
        pendingNote =
            await SyncQueueService.instance.hasBlockingMutations();
      } catch (_) {}
      if (pendingNote && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'يوجد عمل غير مرفوع — سيتم قفل الشاشة دون حذف البيانات المحلية.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      AppLogger.info('WebIdleLock', 'idle lock — UI only, DB kept');
      await auth.lockSession();
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      unawaited(nav.pushNamedAndRemoveUntil('/employee-gate', (_) => false));
    } catch (e, st) {
      AppLogger.error('WebIdleLock', 'idle lock failed', e, st);
    } finally {
      _locking = false;
      _armIdleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb || !_idleLockEnabledOnWeb) return;
    if (state == AppLifecycleState.resumed) {
      _armIdleTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_idleLockEnabledOnWeb) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _armIdleTimer(),
      onPointerSignal: (_) => _armIdleTimer(),
      child: widget.child,
    );
  }
}
