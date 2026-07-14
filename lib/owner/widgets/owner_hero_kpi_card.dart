import 'package:flutter/material.dart';

import '../models/owner_section_result.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_micro_animations.dart';

/// بطاقة Hero — KPI رئيسي في أعلى لوحة v3.
class OwnerHeroKpiCard extends StatelessWidget {
  const OwnerHeroKpiCard({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.valueBuilder,
    required this.onRetry,
    this.subtitleBuilder,
    this.icon = Icons.insights_outlined,
    this.isEmpty,
    this.emptyMessage,
  });

  final String title;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final String Function(dynamic data) valueBuilder;
  final String Function(dynamic data)? subtitleBuilder;
  final VoidCallback onRetry;
  final IconData icon;
  final bool Function(dynamic data)? isEmpty;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = section.data;
    final contentKey = section.isLoading && !section.hasData
        ? 'loading'
        : '${section.status.name}_${section.fetchedAt?.millisecondsSinceEpoch ?? 0}_${data != null ? valueBuilder(data) : ''}';

    final heroFill = OwnerDashboardGoldBorder.fillColor(context);

    return Semantics(
      label: section.hasData && section.data != null
          ? '$title: ${valueBuilder(section.data!)}'
          : title,
      child: Card(
        color: heroFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: OwnerDashboardGoldBorder.cardShape(context),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 36, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OwnerKpiContentFade(
                      contentKey: contentKey,
                      child: OwnerKpiSectionBody(
                        section: section,
                        sectionId: sectionId,
                        onRetry: onRetry,
                        valueBuilder: valueBuilder,
                        subtitleBuilder: subtitleBuilder,
                        isEmpty: isEmpty,
                        emptyMessage: emptyMessage,
                        inlineSkeletonHeight: 72,
                        valueTextStyle: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
