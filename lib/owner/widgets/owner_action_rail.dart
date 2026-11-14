import 'package:flutter/material.dart';

import '../utils/owner_dashboard_gold_border.dart';
import '../models/owner_action_alert.dart';

/// شريط Action Rail — تنبيهات query-driven مع إجراء واحد لكل تنبيه.
class OwnerActionRail extends StatelessWidget {
  const OwnerActionRail({
    super.key,
    required this.alerts,
    required this.isLoading,
    required this.onAction,
  });

  final List<OwnerActionAlert> alerts;
  final bool isLoading;
  final void Function(OwnerActionKind kind) onAction;

  @override
  Widget build(BuildContext context) {
    if (isLoading && alerts.isEmpty) {
      return const _ActionRailSkeleton();
    }
    if (alerts.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: 'شريط الإجراءات — ${alerts.length} تنبيه',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, bottom: 8),
            child: Text(
              'إجراءات مطلوبة',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return _ActionAlertTile(
                  alert: alerts[index],
                  onPressed: () => onAction(alerts[index].actionKind),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionAlertTile extends StatelessWidget {
  const _ActionAlertTile({
    required this.alert,
    required this.onPressed,
  });

  final OwnerActionAlert alert;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _priorityColor(cs, alert.priority);

    return Semantics(
      label: '${alert.titleAr} — ${alert.messageAr}',
      button: true,
      child: Material(
        color: OwnerDashboardGoldBorder.fillColor(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            width: 248,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: OwnerDashboardGoldBorder.borderColor(cs: cs),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(_priorityIcon(alert.priority), color: accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alert.titleAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    alert.messageAr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: accent.withValues(alpha: 0.14),
                      foregroundColor: accent,
                    ),
                    onPressed: onPressed,
                    child: Text(alert.ctaLabelAr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _priorityColor(ColorScheme cs, OwnerAlertPriority priority) {
    switch (priority) {
      case OwnerAlertPriority.critical:
        return cs.error;
      case OwnerAlertPriority.high:
        return cs.tertiary;
      case OwnerAlertPriority.medium:
        return cs.primary;
    }
  }

  static IconData _priorityIcon(OwnerAlertPriority priority) {
    switch (priority) {
      case OwnerAlertPriority.critical:
        return Icons.priority_high_rounded;
      case OwnerAlertPriority.high:
        return Icons.notifications_active_outlined;
      case OwnerAlertPriority.medium:
        return Icons.info_outline;
    }
  }
}

class _ActionRailSkeleton extends StatelessWidget {
  const _ActionRailSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 14,
          width: 96,
          margin: const EdgeInsetsDirectional.only(bottom: 8),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) {
              return Container(
                width: 248,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
