import 'package:flutter/widgets.dart';

/// للوحدات التي يبقيها الإطار حيّة مخفية (الصندوق، سجل الغيارات…):
/// حين تعود ظاهرة بعد إخفاء، يُستدعى [onShownAgain] لتعيد جلب بياناتها،
/// فلا يرى المستخدم رصيداً أو سجلاً قديماً بعد عملية تمت في شاشة أخرى.
///
/// الإطار يطفئ [TickerMode] للوحدة المخفية ويشغّله للظاهرة، فنعتمد عليه.
mixin ReloadWhenShown<T extends StatefulWidget> on State<T> {
  bool? _shownLast;

  /// يُستدعى مرة عند كل عودة للظهور (لا عند البناء الأول).
  void onShownAgain();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.of(context);
    final wasHidden = _shownLast == false;
    _shownLast = shown;
    if (wasHidden && shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onShownAgain();
      });
    }
  }
}
