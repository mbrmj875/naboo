import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root_navigator_key.dart';
import 'app_system_back.dart';

/// منطق موحّد: تنبيه → حوار تأكيد → خروج نهائي.
abstract final class AppExitBack {
  static DateTime? _lastPromptAt;
  static bool _dialogOpen = false;
  static const _interval = Duration(seconds: 2);
  static const _hint = 'اضغط مرة أخرى للخروج من التطبيق';

  /// يُستدعى عندما لا يمكن الرجوع لأي شاشة داخل التطبيق.
  static Future<void> onRootBackAttempt() async {
    if (kIsWeb) return;
    if (_dialogOpen) return;

    final now = DateTime.now();
    final last = _lastPromptAt;
    final within = last != null && now.difference(last) <= _interval;

    if (!within) {
      _lastPromptAt = now;
      _showHint();
      return;
    }

    _lastPromptAt = null;
    _hideHint();
    await _confirmAndExit();
  }

  /// للمراقب العام: رجوع إن أمكن، وإلا مسار الخروج. دائماً `true` خارج الويب.
  static Future<bool> handleSystemBack() async {
    if (kIsWeb) return false;
    if (_dialogOpen) return true;

    if (await AppSystemBack.tryPopAny()) {
      _lastPromptAt = null;
      return true;
    }

    await onRootBackAttempt();
    return true;
  }

  static void _showHint() {
    final messenger = _messenger();
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(_hint),
          duration: _interval,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static void _hideHint() {
    _messenger()?.hideCurrentSnackBar();
  }

  static ScaffoldMessengerState? _messenger() {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null) return null;
    return ScaffoldMessenger.maybeOf(ctx);
  }

  static Future<void> _confirmAndExit() async {
    if (_dialogOpen) return;
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null) {
      await SystemNavigator.pop();
      return;
    }

    _dialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('الخروج من التطبيق'),
          content: const Text('هل تريد الخروج من التطبيق نهائياً؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('رفض'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
    _dialogOpen = false;

    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }
}

/// يلتقط زر الرجوع بعد فشل الملاح الجذر (أو بدل الخروج المباشر).
///
/// يُسجَّل بعد [WidgetsApp] فيحسب الرجوع الداخلي عبر [AppSystemBack]
/// ثم مسار التأكيد — ويمنع [SystemNavigator.pop] بدون موافقة.
class AppExitBackBinder extends StatefulWidget {
  const AppExitBackBinder({super.key, required this.child});

  final Widget child;

  @override
  State<AppExitBackBinder> createState() => _AppExitBackBinderState();
}

class _AppExitBackBinderState extends State<AppExitBackBinder>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() => AppExitBack.handleSystemBack();

  @override
  Widget build(BuildContext context) => widget.child;
}
