import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sale_pos_settings_data.dart';
import '../../providers/sale_pos_settings_provider.dart';

/// عناصر الـ Brand DNA الموحَّدة عبر التطبيق — انظر `docs/screen_migration_playbook.md`
/// §12 "Brand DNA & Visual Identity".
///
/// `AppInlineToastController` يَحفظ آخر toast يَجب عرضه فوق Scaffold معيَّن.
/// تَستضيفه `AppInlineToastHost` ك`InheritedWidget`، ويَستهلكه `AppInlineToastBar`
/// لرسم الشريط نفسه.
///
/// **لماذا**: SnackBar الكلاسيكي يُغطّي الـ FAB ويَختفي خلف لوحة المفاتيح،
/// خاصة على شاشات الديسكتوب. الـ Inline Toast يُلصق فوق الـ footer (أو حيث
/// يَضعه الـ host) ويَختفي بنفسه — يَحترم الـ Brand (Navy + Gold edge).
class AppInlineToastController extends ChangeNotifier {
  AppInlineToastController();

  String? _message;
  Color? _backgroundOverride;
  IconData? _icon;
  Timer? _timer;

  String? get message => _message;
  Color? get backgroundOverride => _backgroundOverride;
  IconData? get icon => _icon;
  bool get hasMessage => _message != null && _message!.isNotEmpty;

  /// يُظهر toast جديداً ويُلغي الـ timer السابق إن وُجد.
  /// [duration] الافتراضي 4 ثوانٍ، يُمكن تَخصيصه لكل toast.
  void show(
    String message, {
    Color? backgroundColor,
    IconData icon = Icons.notifications_active_outlined,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (message.trim().isEmpty) return;
    _timer?.cancel();
    _message = message.trim();
    _backgroundOverride = backgroundColor;
    _icon = icon;
    notifyListeners();
    _timer = Timer(duration, dismiss);
  }

  /// يَمسح الـ toast الحالي فوراً (للنقر يدوياً أو عند انتهاء الـ timer).
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_message == null) return;
    _message = null;
    _backgroundOverride = null;
    _icon = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// يُتيح Widgets أبناء الوصول إلى `AppInlineToastController` المحلي للـ Scaffold.
/// كل شاشة تَلفّ محتواها بـ `AppInlineToastHost` وتَستهلك الـ controller من السياق.
class AppInlineToastHost extends StatefulWidget {
  const AppInlineToastHost({
    super.key,
    required this.child,
    this.controller,
  });

  /// المحتوى الذي يَستضيف الـ toast.
  final Widget child;

  /// تَخصيص اختياري لـ controller من الخارج (مفيد لاختبارات widget).
  /// لو null، تُنشئ الـ widget controller داخلي مدارة دورة حياته داخلياً.
  final AppInlineToastController? controller;

  /// يَجلب أقرب controller من السياق. يَطرح لو لم يَجد host في الشجرة.
  static AppInlineToastController of(BuildContext context) {
    final inh = context
        .dependOnInheritedWidgetOfExactType<_AppInlineToastScope>();
    assert(
      inh != null,
      'AppInlineToastHost.of() called outside an AppInlineToastHost widget.',
    );
    return inh!.controller;
  }

  /// نسخة آمنة من `of` تُرجع null لو لم يُوجد host (مفيدة لـ AppMessenger).
  static AppInlineToastController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AppInlineToastScope>()
        ?.controller;
  }

  @override
  State<AppInlineToastHost> createState() => _AppInlineToastHostState();
}

class _AppInlineToastHostState extends State<AppInlineToastHost> {
  AppInlineToastController? _ownedController;

  AppInlineToastController get _effectiveController =>
      widget.controller ?? (_ownedController ??= AppInlineToastController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppInlineToastScope(
      controller: _effectiveController,
      child: widget.child,
    );
  }
}

class _AppInlineToastScope extends InheritedWidget {
  const _AppInlineToastScope({
    required this.controller,
    required super.child,
  });

  final AppInlineToastController controller;

  @override
  bool updateShouldNotify(_AppInlineToastScope oldWidget) =>
      controller != oldWidget.controller;
}

/// شريط الـ Inline Toast — يُلصق عادةً فوق الـ footer / الـ BottomBar.
/// يَستهلك أقرب `AppInlineToastController` ويَختفي تلقائياً عند عدم وجود رسالة.
///
/// تَصميمه يَتبع Brand DNA:
/// - الخلفية: `palette.navy` بـ alpha 0.96 (أو override).
/// - الحافة: `palette.gold` بـ alpha 0.45 — 1px.
/// - الأيقونة: ذهبية.
/// - النص: contrast-aware (أبيض على navy، أسود على ذهبي/فاتح).
class AppInlineToastBar extends StatelessWidget {
  const AppInlineToastBar({
    super.key,
    this.maxWidth = 440,
    this.horizontalGap = 14,
    this.verticalPadding = 10,
    this.bottomMargin = 10,
  });

  /// أقصى عرض للشريط — يَمنع تَمدُّده القبيح على الديسكتوب.
  final double maxWidth;

  /// هامش جانبي للحاوية (يُحترم لو الشاشة أضيق من `maxWidth`).
  final double horizontalGap;

  /// padding عمودي داخل الـ Material.
  final double verticalPadding;

  /// مسافة سفلية تَفصل الـ toast عمَّن تحته (مثل زر FAB أو footer).
  final double bottomMargin;

  @override
  Widget build(BuildContext context) {
    final controller = AppInlineToastHost.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.hasMessage) return const SizedBox.shrink();
        final palette = SalePalette.fromSettings(
          context.read<SalePosSettingsProvider>().data,
          Theme.of(context),
        );
        final bg = controller.backgroundOverride ??
            palette.navy.withValues(alpha: 0.96);
        final textColor =
            bg.computeLuminance() > 0.55 ? const Color(0xFF0F172A) : Colors.white;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomMargin),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalGap),
                child: Material(
                  color: bg,
                  elevation: 3,
                  shadowColor: palette.navy.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: palette.gold.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: controller.dismiss,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        verticalPadding,
                        12,
                        verticalPadding,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            controller.icon ??
                                Icons.notifications_active_outlined,
                            size: 20,
                            color: palette.gold,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              controller.message!,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
