import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// على الهاتف: الضغط الأول على زر الرجوع يُظهر تنبيهاً،
/// والثاني خلال [interval] يغلق التطبيق نهائياً.
class DoubleBackToExitScope extends StatefulWidget {
  const DoubleBackToExitScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.message = 'اضغط مرة أخرى للخروج من التطبيق',
    this.interval = const Duration(seconds: 2),
    this.onBackPressed,
  });

  final Widget child;
  final bool enabled;
  final String message;
  final Duration interval;

  /// إن أعاد `true` فُسِّر الضغط كرجوع داخلي ولا يُحسب للخروج.
  final bool Function()? onBackPressed;

  @override
  State<DoubleBackToExitScope> createState() => _DoubleBackToExitScopeState();
}

class _DoubleBackToExitScopeState extends State<DoubleBackToExitScope> {
  DateTime? _lastPromptAt;

  void _handleBack() {
    if (!widget.enabled) {
      SystemNavigator.pop();
      return;
    }

    if (widget.onBackPressed?.call() == true) return;

    final now = DateTime.now();
    final last = _lastPromptAt;
    if (last != null && now.difference(last) <= widget.interval) {
      SystemNavigator.pop();
      return;
    }

    _lastPromptAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.message),
          duration: widget.interval,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
