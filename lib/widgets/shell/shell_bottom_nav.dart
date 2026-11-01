import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../navigation/shell/shell_nav_item.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';
import '../raw_keyboard_inset.dart';

/// الشريط السفلي: عائم زجاجي على الهاتف، وثابت على التابلت.
class ShellBottomNavBar extends StatelessWidget {
  const ShellBottomNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onItemTap,
    required this.onReorder,
    this.openSubMenuRouteId,
  });

  final List<ShellNavItem> items;
  final int activeIndex;
  final String? openSubMenuRouteId;
  final ValueChanged<ShellNavItem> onItemTap;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final sl = ScreenLayout.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPhoneDock = sl.isHandsetForLayout;
    final barBg = isDark ? cs.surfaceContainerHigh : const Color(0xFFF7F4EF);
    final height = sl.isVeryShort ? 56.0 : (sl.isCompactHeight ? 60.0 : 64.0);
    final idx = activeIndex.clamp(0, items.length - 1);

    void onBottomModuleTap(int i, ShellNavItem m) {
      HapticFeedback.lightImpact();
      // أزل تركيز أي حقل نص حتى لا يبقى الكيبورد/التركيز حاجزاً للقائمة.
      FocusManager.instance.primaryFocus?.unfocus();
      onItemTap(m);
    }

    Widget reorderableBar({required Color effectiveBarColor}) {
      return ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        proxyDecorator: (child, index, anim) {
          return Material(
            color: Colors.transparent,
            elevation: isPhoneDock ? 10 : 6,
            shadowColor: Colors.black.withValues(
              alpha: isPhoneDock ? 0.24 : 0.18,
            ),
            child: child,
          );
        },
        onReorder: onReorder,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final m = items[i];
          final selected = i == idx;
          return ReorderableDelayedDragStartListener(
            key: ValueKey(m.routeId),
            index: i,
            child: _ShellBottomNavTile(
              module: m,
              selected: selected,
              barColor: effectiveBarColor,
              useGlassDock: isPhoneDock,
              subMenuOpen: openSubMenuRouteId == m.routeId,
              onTap: () => onBottomModuleTap(i, m),
            ),
          );
        },
      );
    }

    if (isPhoneDock) {
      final dockBg = isDark
          ? cs.surfaceContainerHigh.withValues(alpha: 0.58)
          : cs.surface.withValues(alpha: 0.72);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.07);
      final topHighlight = Colors.white.withValues(alpha: isDark ? 0.10 : 0.44);
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final bottomPad = math.max(10.0, safeBottom);
      final dock = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: dockBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: borderColor, width: 1.1),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topHighlight, topHighlight.withValues(alpha: 0)],
                  stops: const [0, 0.18],
                ),
              ),
              child: reorderableBar(effectiveBarColor: dockBg),
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottomPad),
        child: dock,
      );
    }

    return Material(
      color: barBg,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: reorderableBar(effectiveBarColor: barBg),
        ),
      ),
    );
  }
}

/// قائمة فرعية منبثقة فوق الشريط السفلي.
class ShellSubMenuPopover extends StatelessWidget {
  const ShellSubMenuPopover({
    super.key,
    required this.module,
    required this.onSelectSub,
    required this.onSelectAll,
    required this.onDismiss,
  });

  final ShellNavItem module;
  final ValueChanged<ShellNavSubItem> onSelectSub;
  final VoidCallback onSelectAll;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subs = module.subItems ?? const <ShellNavSubItem>[];
    if (subs.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A2332) : cs.surface;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : cs.onSurfaceVariant;

    void onSubTap(ShellNavSubItem sub) {
      HapticFeedback.selectionClick();
      onSelectSub(sub);
    }

    void onViewAll() {
      HapticFeedback.selectionClick();
      onSelectAll();
    }

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.52,
        ),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: module.iconColor.withValues(alpha: isDark ? 0.45 : 0.35),
              width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
              blurRadius: 28,
                offset: const Offset(0, 12),
            ),
            BoxShadow(
                color: module.iconColor.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 4),
            ),
          ],
        ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                const SizedBox(height: 6),
                Semantics(
                  label: 'اسحب للأسفل للإغلاق',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 5,
                decoration: BoxDecoration(
                          color: muted.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 6, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: module.iconColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          module.icon,
                          color: module.iconColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          module.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onViewAll,
                        style: TextButton.styleFrom(
                          foregroundColor: module.iconColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'عرض الكل',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDismiss,
                        icon: Icon(Icons.close_rounded, size: 20, color: muted),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outline.withValues(alpha: 0.25),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  itemCount: subs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    return Material(
                        color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSubTap(sub),
                          borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              10,
                              11,
                              10,
                              11,
                          ),
                          child: Row(
                            children: [
                              Container(
                                  width: 34,
                                  height: 34,
                                decoration: BoxDecoration(
                                  color: module.iconColor.withValues(
                                      alpha: 0.12,
                                  ),
                                    borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                    sub.icon ?? Icons.arrow_outward_rounded,
                                  size: 17,
                                    color: module.iconColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sub.title,
                                  style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                  Icons.chevron_left_rounded,
                                  size: 20,
                                  color: muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellBottomNavIcon extends StatelessWidget {
  const _ShellBottomNavIcon({
    required this.module,
    required this.barColor,
    required this.useGlassDock,
    required this.iconColor,
    this.iconSize = 20,
  });

  final ShellNavItem module;
  final Color barColor;
  final bool useGlassDock;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final hasSub = module.subItems != null && module.subItems!.isNotEmpty;
    return SizedBox(
      width: 28,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(module.icon, size: iconSize, color: iconColor),
          if (hasSub)
            PositionedDirectional(
              top: -2,
              end: -3,
              child: Container(
                width: useGlassDock ? 7.5 : 7,
                height: useGlassDock ? 7.5 : 7,
                decoration: BoxDecoration(
                  color: module.iconColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: barColor, width: 1.4),
                  boxShadow: useGlassDock
                      ? [
                          BoxShadow(
                            color: module.iconColor.withValues(alpha: 0.62),
                            blurRadius: 7,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShellBottomNavTile extends StatefulWidget {
  const _ShellBottomNavTile({
    required this.module,
    required this.selected,
    required this.barColor,
    required this.useGlassDock,
    required this.subMenuOpen,
    required this.onTap,
  });

  final ShellNavItem module;
  final bool selected;
  final Color barColor;
  final bool useGlassDock;
  final bool subMenuOpen;
  final VoidCallback onTap;

  @override
  State<_ShellBottomNavTile> createState() => _ShellBottomNavTileState();
}

class _ShellBottomNavTileState extends State<_ShellBottomNavTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final tiny = sl.isVeryShort;
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final useGlassDock = widget.useGlassDock;
    final hasSub =
        widget.module.subItems != null && widget.module.subItems!.isNotEmpty;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    return SizedBox(
      width: 72,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerCancel: (_) => setState(() => _pressed = false),
        onPointerUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed && useGlassDock ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected
                      ? cs.onSurface.withValues(alpha: useGlassDock ? 0.05 : 0.04)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? AppColors.accentGold
                          : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ShellBottomNavIcon(
                      module: widget.module,
                      barColor: widget.barColor,
                      useGlassDock: useGlassDock,
                      iconSize: tiny ? 18 : 20,
                      iconColor: fg,
                    ),
                    SizedBox(height: tiny ? 2 : 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.module.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: tiny ? 9.5 : 10,
                              height: 1.1,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ),
                        if (hasSub) ...[
                          const SizedBox(width: 1),
                          Icon(
                            widget.subMenuOpen
                                ? Icons.expand_more
                                : Icons.expand_less,
                            size: 10,
                            color: fg.withValues(alpha: 0.75),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShellHideWhenKeyboardOpen extends StatefulWidget {
  const ShellHideWhenKeyboardOpen({
    super.key,
    required this.isHandset,
    required this.childBuilder,
  });

  final bool isHandset;
  final Widget Function() childBuilder;

  @override
  State<ShellHideWhenKeyboardOpen> createState() =>
      ShellHideWhenKeyboardOpenState();
}

class ShellHideWhenKeyboardOpenState
    extends State<ShellHideWhenKeyboardOpen>
    with WidgetsBindingObserver {
  bool _keyboardOpen = false;
  double _lastImeLogical = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // مع تصفير IME عن FlutterView: didChangeMetrics وحده لا يكفي —
    // نسمع قناة أندرويد حتى يعود الشريط عند الإغلاق.
    AndroidImeInset.ensureStarted();
    AndroidImeInset.bottomLogical.addListener(_onAndroidIme);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncKeyboard());
  }

  @override
  void dispose() {
    AndroidImeInset.bottomLogical.removeListener(_onAndroidIme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAndroidIme() {
    _syncKeyboard();
  }

  @override
  void didChangeMetrics() {
    _syncKeyboard();
  }

  void _syncKeyboard() {
    if (!mounted) return;
    if (!widget.isHandset) {
      if (_keyboardOpen) setState(() => _keyboardOpen = false);
      _lastImeLogical = 0;
      return;
    }
    final inset = rawKeyboardBottomInset(context);
    bool open;
    if (_keyboardOpen) {
      // إظهار الشريط فور بدء الانخفاض — لا ننتظر نهاية أنيميشن الكيبورد.
      if (inset + 6 < _lastImeLogical) {
        open = false;
      } else {
        open = inset > 32;
      }
    } else {
      // إخفاء فقط عند ظهور واضح للكيبورد (يتجنب الوميض).
      open = inset > 56;
    }
    _lastImeLogical = inset;
    if (open == _keyboardOpen) return;
    setState(() => _keyboardOpen = open);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHandset && _keyboardOpen) return const SizedBox.shrink();
    return widget.childBuilder();
  }
}

({double totalHeight, double horizontalInset, double barHeight})
_bottomNavLayoutMetricsOf(BuildContext context) {
  final sl = ScreenLayout.of(context);
  final isPhoneDock = sl.isHandsetForLayout;
  final barHeight = sl.isVeryShort ? 56.0 : (sl.isCompactHeight ? 60.0 : 64.0);
  final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
  if (isPhoneDock) {
    final bottomPad = math.max(10.0, safeBottom);
    return (
      totalHeight: barHeight + bottomPad,
      horizontalInset: 14.0,
      barHeight: barHeight,
    );
  }
  return (
    totalHeight: barHeight + safeBottom,
    horizontalInset: 16.0,
    barHeight: barHeight,
  );
}

/// قائمة فرعية فوق الشريط — ورقة سريعة + ضبابية للمحتوى فقط (الشريط العلوي يبقى واضحاً).
///
/// تُغلق تلقائياً عند ظهور الكيبورد، ولا تقرأ Focus في build بدون listener
/// (كان يترك حاجز لمس/حالة «مفتوحة» صامتة بعد إغلاق الـ IME).
class ShellSubMenuHost extends StatefulWidget {
  const ShellSubMenuHost({
    super.key,
    required this.module,
    required this.isDark,
    required this.buildPopover,
    required this.onDismiss,
  });

  final ShellNavItem? module;
  final bool isDark;
  final Widget Function(ShellNavItem module) buildPopover;
  final VoidCallback onDismiss;

  @override
  State<ShellSubMenuHost> createState() =>
      ShellSubMenuHostState();
}

class ShellSubMenuHostState extends State<ShellSubMenuHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// فتح ورقي سريع من الشريط إلى الأعلى.
  static const _duration = Duration(milliseconds: 220);
  static const _dismissDragPx = 96.0;
  static const _dismissVelocity = 900.0;

  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  ShellNavItem? _visibleModule;
  double _dragDy = 0;
  bool _keyboardWasOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidImeInset.ensureStarted();
    AndroidImeInset.bottomLogical.addListener(_onAndroidIme);
    _ctrl = AnimationController(vsync: this, duration: _duration);
    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.72),
      end: Offset.zero,
    ).animate(curve);
    _visibleModule = widget.module;
    if (_visibleModule != null) {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    AndroidImeInset.bottomLogical.removeListener(_onAndroidIme);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  void _onAndroidIme() => _syncKeyboardDismiss();

  @override
  void didChangeMetrics() => _syncKeyboardDismiss();

  void _syncKeyboardDismiss() {
    if (!mounted) return;
    final inset = rawKeyboardBottomInset(context);
    // اعتبر الكيبورد مفتوحاً مبكراً لإغلاق القائمة — لا تنتظر اكتمال الأنيميشن.
    final open = inset > 40;
    if (open && !_keyboardWasOpen && widget.module != null) {
      widget.onDismiss();
    }
    _keyboardWasOpen = open;
  }

  @override
  void didUpdateWidget(covariant ShellSubMenuHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.module;
    final prev = _visibleModule;

    if (next != null) {
      final switched = prev != null && prev.routeId != next.routeId;
      final opening = prev == null || _ctrl.value < 0.01;

      if (switched && !opening) {
        setState(() {
          _visibleModule = next;
          _dragDy = 0;
        });
        if (_ctrl.value < 1) {
          _ctrl.value = 1;
        }
        return;
      }

      _visibleModule = next;
      _dragDy = 0;
      if (opening || _ctrl.value < 1) {
        _ctrl.forward(from: opening ? 0 : _ctrl.value);
      }
      return;
    }

    if (prev != null && _ctrl.value > 0) {
      _ctrl.reverse().whenComplete(() {
        if (!mounted) return;
        if (widget.module == null) {
          setState(() {
            _visibleModule = null;
            _dragDy = 0;
          });
        }
      });
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0;
    if (dy == 0) return;
    // السحب للأسفل فقط لإغلاق الورقة.
    final next = (_dragDy + dy).clamp(0.0, 420.0);
    if (next == _dragDy) return;
    setState(() => _dragDy = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (_dragDy >= _dismissDragPx || v > _dismissVelocity) {
      HapticFeedback.lightImpact();
      widget.onDismiss();
      return;
    }
    // رجوع مرن إلى موضع الفتح.
    setState(() => _dragDy = 0);
  }

  @override
  Widget build(BuildContext context) {
    final module = _visibleModule;
    if (module == null) {
      return const IgnorePointer(
        ignoring: true,
        child: SizedBox.expand(),
      );
    }

    final variant = ScreenLayout.of(context).layoutVariant;
    if (variant.index >= DeviceVariant.tabletLG.index) {
      return const IgnorePointer(
        ignoring: true,
        child: SizedBox.expand(),
      );
    }

    final metrics = _bottomNavLayoutMetricsOf(context);
    final scrimAlpha = widget.isDark ? 0.45 : 0.32;
    final dragFade = (1.0 - (_dragDy / 280.0)).clamp(0.35, 1.0);
    // أثناء إغلاق الرسوم: لا تلتقط اللمس حتى يكتمل الاختفاء.
    final absorbHits = widget.module != null;

    return IgnorePointer(
      ignoring: !absorbHits,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: FadeTransition(
                opacity: _fade,
                child: Opacity(
                  opacity: dragFade,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: scrimAlpha),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: metrics.horizontalInset,
            right: metrics.horizontalInset,
            bottom: 8,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: AnimatedSlide(
                  duration: _dragDy == 0
                      ? const Duration(milliseconds: 180)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  offset:
                      Offset(0, _dragDy / MediaQuery.sizeOf(context).height),
                  child: GestureDetector(
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: widget.buildPopover(module),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
