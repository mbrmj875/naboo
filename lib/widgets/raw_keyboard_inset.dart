
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// قناة أندرويد: ارتفاع IME بالبكسل الفعلي (قبل تصفير insets عن FlutterView).
const _kImeInsetsChannel = 'naboo/ime_insets';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// مصدر ارتفاع الكيبورد على أندرويد حيث يُصفَّر [View.viewInsets].
class AndroidImeInset {
  AndroidImeInset._();

  static final ValueNotifier<double> bottomLogical = ValueNotifier<double>(0);
  static bool _started = false;

  static void ensureStarted() {
    if (_started || !_isAndroid) return;
    _started = true;
    const EventChannel(_kImeInsetsChannel)
        .receiveBroadcastStream()
        .listen(_onEvent, onError: (_) {});
  }

  static void _onEvent(dynamic event) {
    final physical = (event is num) ? event.toDouble() : 0.0;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    // الإغلاق يجب أن يصل 0 دائماً حتى يعود الشريط السفلي.
    final logical =
        physical <= 0 ? 0.0 : (dpr <= 0 ? physical : physical / dpr);
    if ((logical - bottomLogical.value).abs() < 0.5) return;
    bottomLogical.value = logical;
  }
}

/// ارتفاع الكيبورد من [FlutterView] مباشرة — وعلى أندرويد من القناة الأصلية
/// لأن التطبيق يصفّر IME عن FlutterView عمداً.
///
/// على أندرويد نعتمد القناة فقط: [View.viewInsets] بعد التصفير غالباً 0،
/// وأحياناً يبقى قيمة قديمة بعد الإغلاق فتخفي الشريط السفلي إلى الأبد.
double rawKeyboardBottomInset(BuildContext context) {
  AndroidImeInset.ensureStarted();
  if (_isAndroid) return AndroidImeInset.bottomLogical.value;
  final view = View.of(context);
  return view.viewInsets.bottom / view.devicePixelRatio;
}

/// يعيد البناء عند تغيّر مقاييس النافذة أو ارتفاع IME من أندرويد.
class RawKeyboardInsetBuilder extends StatefulWidget {
  const RawKeyboardInsetBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, double keyboardBottom) builder;

  @override
  State<RawKeyboardInsetBuilder> createState() =>
      _RawKeyboardInsetBuilderState();
}

class _RawKeyboardInsetBuilderState extends State<RawKeyboardInsetBuilder>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidImeInset.ensureStarted();
    AndroidImeInset.bottomLogical.addListener(_onAndroidIme);
  }

  @override
  void dispose() {
    AndroidImeInset.bottomLogical.removeListener(_onAndroidIme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAndroidIme() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, rawKeyboardBottomInset(context));
  }
}
