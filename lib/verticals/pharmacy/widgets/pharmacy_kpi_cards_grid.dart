import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';

/// شبكة 12 بطاقة KPI للمالك.
class PharmacyKpiCardsGrid extends StatelessWidget {
  const PharmacyKpiCardsGrid({
    super.key,
    required this.dashboard,
  });

  final VerticalPharmacyOwnerDashboardSnapshot dashboard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dashboard.kpiEntries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: crossAxisCount == 1 ? 2.8 : 1.8,
          ),
          itemBuilder: (context, i) {
            final kpi = dashboard.kpiEntries[i];
            return Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsetsDirectional.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kpi.titleAr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      kpi.valueText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    if (kpi.subtitleAr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        kpi.subtitleAr!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
