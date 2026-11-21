import 'package:flutter/material.dart';

import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../models/owner_kpi_models.dart';
import '../models/owner_section_result.dart';
import '../specs/owner_dashboard_l10n_keys.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';

/// بطاقة أعلى 5 أصناف — قائمة مُجمّعة من SQL.
class OwnerTopSellersKpiCard extends StatelessWidget {
  const OwnerTopSellersKpiCard({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    this.emptyMessageKey = OwnerDashboardL10nKeys.retailTopSellersEmpty,
  });

  final String title;
  final OwnerSectionResult<RetailTopSellersKpi> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String emptyMessageKey;

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

    if (data.items.isEmpty) {
      return Semantics(
        label: ownerDashboardL10n(emptyMessageKey),
        child: OwnerDashboardGoldBorder.themedCard(
          context: context,
          child: ListTile(
            leading: Icon(Icons.leaderboard_outlined, color: cs.primary),
            title: Text(title),
            subtitle: Text(
              ownerDashboardL10n(emptyMessageKey),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '$title — ${data.items.length} أصناف',
      child: OwnerDashboardGoldBorder.themedCard(
        context: context,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.leaderboard_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < data.items.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _TopSellerRowTile(rank: i + 1, row: data.items[i]),
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

class _TopSellerRowTile extends StatelessWidget {
  const _TopSellerRowTile({required this.rank, required this.row});

  final int rank;
  final TopSellerRow row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(row.revenueFils),
    );
    final qtyLabel = row.qtySold == row.qtySold.roundToDouble()
        ? '${row.qtySold.round()}'
        : row.qtySold.toStringAsFixed(1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: rank == 1 ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                row.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$amount · $qtyLabel وحدة',
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
