import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/idle_timeout_provider.dart';
import 'idle_screensaver.dart';
import 'invoice_deep_link_listener.dart';

/// يكتشف عدم النشاط ويعرض شاشة السكون عند انتهاء المهلة (عند تسجيل الدخول فقط).
class IdleSessionShell extends StatefulWidget {
  const IdleSessionShell({
    super.key,
    required this.child,
    required this.isDark,
    required this.userLabel,
  });

  final Widget child;
  final bool isDark;
  final String userLabel;

  @override
  State<IdleSessionShell> createState() => _IdleSessionShellState();
}

class _IdleSessionShellState extends State<IdleSessionShell> {
  Timer? _timer;
  bool _idleVisible = false;
  IdleTimeoutProvider? _idleSub;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.read<IdleTimeoutProvider>();
    if (!identical(_idleSub, p)) {
      _idleSub?.removeListener(_onIdleSettingsChanged);
      _idleSub = p;
      _idleSub!.addListener(_onIdleSettingsChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleTimer();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idleSub?.removeListener(_onIdleSettingsChanged);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    _bump();
    return false;
  }

  void _onIdleSettingsChanged() {
    final idle = _idleSub;
    if (idle == null) return;
    if (!idle.enabled) {
      _timer?.cancel();
      if (_idleVisible) setState(() => _idleVisible = false);
      return;
    }
    if (_idleVisible) return;
    _scheduleTimer();
  }

  void _bump() {
    if (_idleVisible) {
      setState(() => _idleVisible = false);
    }
    _scheduleTimer();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    final idle = _idleSub;
    if (idle == null || !idle.enabled) {
      if (_idleVisible) setState(() => _idleVisible = false);
      return;
    }
    _timer = Timer(idle.duration, () {
      if (!mounted) return;
      setState(() => _idleVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _bump(),
      onPointerSignal: (_) => _bump(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _bump();
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            InvoiceDeepLinkListener(child: widget.child),
            if (_idleVisible)
              Positioned.fill(
                child: IdleScreensaver(
                  isDark: widget.isDark,
                  userLabel: widget.userLabel,
                  onWake: () {
                    setState(() => _idleVisible = false);
                    _scheduleTimer();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
