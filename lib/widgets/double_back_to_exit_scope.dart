import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../navigation/app_exit_back.dart';
import '../navigation/app_system_back.dart';

/// يمنع الخروج المباشر من مسار الجذر: رجوع داخلي أولاً ثم تأكيد الخروج.
///
/// يُفضَّل على الشاشات الجذرية. الملاح الداخلي عبر [AppSystemBack].
class DoubleBackToExitScope extends StatelessWidget {
  const DoubleBackToExitScope({
    super.key,
    required this.child,
    this.enabled = true,
    @Deprecated('Ignored — use AppSystemBack.register') this.onBackPressed,
    @Deprecated('Ignored — fixed copy in AppExitBack') this.message,
    @Deprecated('Ignored — fixed interval in AppExitBack') this.interval,
  });

  final Widget child;
  final bool enabled;
  final bool Function()? onBackPressed;
  final String? message;
  final Duration? interval;

  @override
  Widget build(BuildContext context) {
    if (!enabled || kIsWeb) return child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handle();
      },
      child: child,
    );
  }

  Future<void> _handle() async {
    if (onBackPressed?.call() == true) return;
    if (await AppSystemBack.tryPopNested()) return;
    await AppExitBack.onRootBackAttempt();
  }
}
