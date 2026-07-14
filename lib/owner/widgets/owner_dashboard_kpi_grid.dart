import 'package:flutter/material.dart';

/// شبكة بطاقات KPI — عمودان على الهاتف، ثلاثة على الشاشات العريضة.
class OwnerDashboardKpiGrid extends StatelessWidget {
  const OwnerDashboardKpiGrid({
    super.key,
    required this.children,
    this.gap = 12,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 1100 ? 3 : 2;
        final tileW = (w - (columns - 1) * gap) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((c) => SizedBox(width: tileW, child: c))
              .toList(growable: false),
        );
      },
    );
  }
}
