import 'package:flutter/material.dart';

import '../utils/owner_dashboard_gold_border.dart';

/// صندوق نبضي — يُستخدم داخل Skeleton البطاقة.
class OwnerKpiPulseBox extends StatelessWidget {
  const OwnerKpiPulseBox({
    super.key,
    required this.t,
    required this.height,
    this.width,
    this.borderRadius = 4,
  });

  final double t;
  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final color = Color.lerp(
      base.withValues(alpha: 0.45),
      base.withValues(alpha: 0.95),
      t,
    )!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// غلاف نبض متكرر لـ Skeleton.
class OwnerKpiPulseScope extends StatefulWidget {
  const OwnerKpiPulseScope({super.key, required this.builder});

  final Widget Function(BuildContext context, double t) builder;

  @override
  State<OwnerKpiPulseScope> createState() => _OwnerKpiPulseScopeState();
}

class _OwnerKpiPulseScopeState extends State<OwnerKpiPulseScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => widget.builder(context, _pulse.value),
    );
  }
}

/// هيكل تحميل نبضي — بطاقة KPI كاملة.
class OwnerKpiCardSkeleton extends StatelessWidget {
  const OwnerKpiCardSkeleton({
    super.key,
    this.height = 88,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OwnerDashboardGoldBorder.themedCard(
      context: context,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: OwnerKpiPulseScope(
            builder: (context, t) => Row(
              children: [
                OwnerKpiPulseBox(t: t, height: 36, width: 36, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OwnerKpiPulseBox(t: t, height: 12, width: 120),
                      const SizedBox(height: 10),
                      OwnerKpiPulseBox(t: t, height: 18),
                    ],
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

/// Skeleton مضغوط داخل بطاقة موجودة (Header + body).
class OwnerKpiInlineSkeleton extends StatelessWidget {
  const OwnerKpiInlineSkeleton({super.key, this.height = 48});

  final double height;

  /// ارتفاع التصميم المرجعي — يُصغَّر تلقائياً إن كان [height] أقل (مثل بطاقات الملخص).
  static const double _designHeight = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: constraints.maxWidth,
              height: _designHeight,
              child: OwnerKpiPulseScope(
                builder: (context, t) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OwnerKpiPulseBox(t: t, height: 22),
                    const SizedBox(height: 10),
                    OwnerKpiPulseBox(t: t, height: 12, width: 140),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
