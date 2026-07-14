import 'package:flutter/material.dart';

import '../utils/owner_dashboard_gold_border.dart';
import '../models/owner_kpi_trend.dart';
import '../models/owner_section_result.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';

/// حالة فارغة ذكية — رسالة + CTA.
class OwnerKpiEmptyState {
  const OwnerKpiEmptyState({
    required this.message,
    required this.ctaLabel,
    required this.onCta,
  });

  final String message;
  final String ctaLabel;
  final VoidCallback onCta;

  bool matches(dynamic data, bool Function(dynamic data) isEmpty) {
    return isEmpty(data);
  }
}

/// بطاقة KPI v3 — empty state + Semantics (trend في S4).
class OwnerKpiCardV3 extends StatelessWidget {
  const OwnerKpiCardV3({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.valueBuilder,
    required this.onRetry,
    this.icon = Icons.insights_outlined,
    this.trailing,
    this.emptyState,
    this.isEmpty,
    this.trend,
    this.warningGlowWhen,
    this.backgroundColor,
    this.iconColor,
    this.onTap,
  });

  final String title;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final String Function(dynamic data) valueBuilder;
  final VoidCallback onRetry;
  final IconData icon;
  final Widget? trailing;
  final OwnerKpiEmptyState? emptyState;
  final bool Function(dynamic data)? isEmpty;
  final OwnerKpiTrend? trend;
  final bool Function(dynamic data)? warningGlowWhen;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (section.isLoading && !section.hasData) {
      return OwnerKpiCardSkeleton();
    }

    final data = section.data;
    final showEmpty = emptyState != null &&
        isEmpty != null &&
        section.hasData &&
        data != null &&
        isEmpty!(data);

    if (showEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Semantics(
        label: '${emptyState!.message} — ${emptyState!.ctaLabel}',
        child: OwnerDashboardGoldBorder.themedCard(
          context: context,
          color: backgroundColor,
          child: ListTile(
            leading: Icon(icon, color: iconColor ?? cs.primary),
            title: Text(title),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    emptyState!.message,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: emptyState!.onCta,
                    child: Text(emptyState!.ctaLabel),
                  ),
                ],
              ),
            ),
            trailing: trailing,
          ),
        ),
      );
    }

    return OwnerKpiCard(
      title: title,
      section: section,
      sectionId: sectionId,
      valueBuilder: valueBuilder,
      onRetry: onRetry,
      icon: icon,
      trailing: trailing,
      trend: trend,
      isEmpty: isEmpty,
      emptyMessage: emptyState?.message,
      warningGlowWhen: warningGlowWhen,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      onTap: onTap,
    );
  }
}
