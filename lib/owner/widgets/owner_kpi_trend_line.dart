import 'package:flutter/material.dart';

import '../models/owner_kpi_trend.dart';

/// سطر trend تحت قيمة KPI — 🔺/🔻 + نص مقارنة.
class OwnerKpiTrendLine extends StatelessWidget {
  const OwnerKpiTrendLine({super.key, required this.trend});

  final OwnerKpiTrend trend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (trend.direction) {
      OwnerTrendDirection.up => ('🔺', cs.primary),
      OwnerTrendDirection.down => ('🔻', cs.error),
      OwnerTrendDirection.flat => ('—', cs.onSurfaceVariant),
    };

    return Semantics(
      label: trend.displayLineAr,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$icon ',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: trend.displayLineAr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
