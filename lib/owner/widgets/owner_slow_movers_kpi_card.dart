import 'package:flutter/material.dart';

import '../models/owner_kpi_models.dart';
import '../models/owner_section_result.dart';
import '../specs/owner_dashboard_l10n_keys.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';

/// بطاقة أرصدة بطيئة الحركة — متغيّرات بمخzون دون مبيعات حديثة.
class OwnerSlowMoversKpiCard extends StatelessWidget {
  const OwnerSlowMoversKpiCard({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.onRetry,
  });

  final String title;
  final OwnerSectionResult<ClothingSlowMoversKpi> section;
  final String sectionId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (section.isLoading && !section.hasData) {
      return const OwnerKpiCardSkeleton(height: 160);
    }

    if (section.isError && !section.hasData) {
      return OwnerDashboardGoldBorder.themedCard(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ownerKpiSectionErrorOrEmpty(
            section,
            onRetry,
            fallbackMessage: section.errorMessage ?? title,
          ),
        ),
      );
    }

    final data = section.data;
    if (data == null) return const SizedBox.shrink();

    if (data.slowCount <= 0) {
      return Semantics(
        label: ownerDashboardL10n(OwnerDashboardL10nKeys.clothingSlowMoversEmpty),
        child: OwnerDashboardGoldBorder.themedCard(
          context: context,
          child: ListTile(
            leading: Icon(Icons.hourglass_empty_outlined, color: cs.primary),
            title: Text(title),
            subtitle: Text(
              ownerDashboardL10n(OwnerDashboardL10nKeys.clothingSlowMoversEmpty),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '$title — ${data.slowCount} متغيّر',
      child: OwnerDashboardGoldBorder.themedCard(
        context: context,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.hourglass_empty_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${data.slowCount}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'بدون مبيعات منذ ${data.daysThreshold} يوماً أو أكثر',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (data.items.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var i = 0; i < data.items.length; i++) ...[
                  if (i > 0) const Divider(height: 12),
                  _SlowMoverRowTile(row: data.items[i]),
                ],
              ],
              if (section.isStale && section.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OwnerStaleBadge(fetchedAt: section.fetchedAt!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlowMoverRowTile extends StatelessWidget {
  const _SlowMoverRowTile({required this.row});

  final ClothingSlowMoverRow row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysLabel = row.daysWithoutSale >= 9999
        ? 'لم يُبَع بعد'
        : '${row.daysWithoutSale} يوم';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                row.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '$daysLabel · ${row.quantity} قطعة',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
