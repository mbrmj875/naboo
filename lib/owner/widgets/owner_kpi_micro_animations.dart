import 'package:flutter/material.dart';

import '../models/owner_date_range.dart';

/// انتقال fade خفيف — S5c (بدون BackdropFilter).
class OwnerKpiFadeTransition extends StatelessWidget {
  const OwnerKpiFadeTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// قيمة KPI مع micro-animation عند التحديث — S5c.
class OwnerAnimatedKpiValue extends StatelessWidget {
  const OwnerAnimatedKpiValue({
    super.key,
    required this.valueKey,
    required this.text,
    this.style,
  });

  final String valueKey;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(valueKey),
        style: style ??
            TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
      ),
    );
  }
}

/// توهج تحذيري خفيف لبطاقات نواقص المخزون — S5c.
class OwnerKpiWarningGlow extends StatelessWidget {
  const OwnerKpiWarningGlow({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.error.withValues(alpha: 0.28),
            blurRadius: 14,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// fade عند استبدال محتوى بطاقة (loading → success) — S5c.
class OwnerKpiContentFade extends StatelessWidget {
  const OwnerKpiContentFade({
    super.key,
    required this.contentKey,
    required this.child,
  });

  final Object contentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) {
        if (current != null) return current;
        return previous.isNotEmpty ? previous.last : const SizedBox.shrink();
      },
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(contentKey),
        child: child,
      ),
    );
  }
}

/// morph خفيف للرسوم عند تغيير الفترة — S5c.
class OwnerChartMorphSwitcher extends StatelessWidget {
  const OwnerChartMorphSwitcher({
    super.key,
    required this.morphKey,
    required this.child,
  });

  final Object morphKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) {
        if (current != null) return current;
        return previous.isNotEmpty ? previous.last : const SizedBox.shrink();
      },
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(morphKey),
        child: child,
      ),
    );
  }
}

String ownerDateRangeMorphKey(OwnerDateRange range) {
  return '${range.kind.name}_'
      '${range.customStart?.millisecondsSinceEpoch ?? 0}_'
      '${range.customEnd?.millisecondsSinceEpoch ?? 0}';
}
