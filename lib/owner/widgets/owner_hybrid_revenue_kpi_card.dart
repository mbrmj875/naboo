import 'package:flutter/material.dart';

import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../models/owner_kpi_models.dart';
import '../models/owner_section_result.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';
import 'owner_kpi_micro_animations.dart';

/// بطاقة إيرادات hybrid — غيار الزيت vs تجزئة POS بألوان واضحة.
class OwnerHybridRevenueKpiCard extends StatelessWidget {
  const OwnerHybridRevenueKpiCard({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    this.isHero = false,
  });

  final String title;
  final OwnerSectionResult<HybridRevenueKpi> section;
  final String sectionId;
  final VoidCallback onRetry;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (section.isLoading && !section.hasData) {
      return OwnerKpiCardSkeleton(height: isHero ? 120 : 96);
    }

    if (section.isError && !section.hasData) {
      return OwnerDashboardGoldBorder.themedCard(
        context: context,
        color: isHero
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : null,
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

    final kpi = section.data;
    if (kpi == null) {
      return const SizedBox.shrink();
    }

    final totalText = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(kpi.totalFils),
    );
    final semanticsLabel = kpi.totalFils <= 0
        ? '$title — لا إيرادات'
        : _semanticsFor(kpi, title, totalText);

    return Semantics(
      label: semanticsLabel,
      child: OwnerDashboardGoldBorder.themedCard(
        context: context,
        color: isHero
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : null,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            isHero ? 20 : 16,
            isHero ? 18 : 14,
            isHero ? 20 : 16,
            isHero ? 18 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.donut_large_outlined,
                    size: isHero ? 36 : 28,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: isHero ? 15 : 14,
                            color: isHero ? cs.onPrimaryContainer : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OwnerAnimatedKpiValue(
                          valueKey:
                              '${section.fetchedAt?.millisecondsSinceEpoch ?? 0}_$totalText',
                          text: totalText,
                          style: TextStyle(
                            fontSize: isHero ? 32 : 22,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _HybridRevenueSplitBar(kpi: kpi),
              if (section.isError)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OwnerSectionError(
                    message: section.errorMessage ?? '',
                    onRetry: onRetry,
                  ),
                )
              else if (section.isStale && section.fetchedAt != null)
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

  static String _semanticsFor(
    HybridRevenueKpi kpi,
    String title,
    String totalText,
  ) {
    final servicePct = (100 * kpi.serviceFils / kpi.totalFils).round();
    final posPct = 100 - servicePct;
    return '$title: $totalText — غيار الزيت $servicePct%، تجزئة POS $posPct%';
  }
}

class _HybridRevenueSplitBar extends StatelessWidget {
  const _HybridRevenueSplitBar({required this.kpi});

  final HybridRevenueKpi kpi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = kpi.totalFils;

    if (total <= 0) {
      return Text(
        'لا إيرادات في هذه الفترة',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final serviceColor = cs.primary;
    final posColor = cs.tertiary;
    final serviceFlex = _flexWeight(kpi.serviceFils, total);
    final posFlex = _flexWeight(kpi.posRetailFils, total);
    final servicePct = (100 * kpi.serviceFils / total).round();
    final posPct = 100 - servicePct;
    final serviceAmount = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(kpi.serviceFils),
    );
    final posAmount = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(kpi.posRetailFils),
    );
    final serviceLeads = kpi.serviceFils >= kpi.posRetailFils;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              if (serviceFlex > 0)
                Expanded(
                  flex: serviceFlex,
                  child: ColoredBox(
                    color: serviceColor,
                    child: const SizedBox(height: 14),
                  ),
                ),
              if (posFlex > 0)
                Expanded(
                  flex: posFlex,
                  child: ColoredBox(
                    color: posColor,
                    child: const SizedBox(height: 14),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SplitLegendItem(
                color: serviceColor,
                label: 'غيار الزيت',
                amount: serviceAmount,
                percent: servicePct,
                emphasized: serviceLeads,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SplitLegendItem(
                color: posColor,
                label: 'تجزئة POS',
                amount: posAmount,
                percent: posPct,
                emphasized: !serviceLeads,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static int _flexWeight(int partFils, int totalFils) {
    if (partFils <= 0 || totalFils <= 0) return 0;
    final pct = partFils / totalFils;
    return (pct * 1000).round().clamp(1, 1000);
  }
}

class _SplitLegendItem extends StatelessWidget {
  const _SplitLegendItem({
    required this.color,
    required this.label,
    required this.amount,
    required this.percent,
    required this.emphasized,
  });

  final Color color;
  final String label;
  final String amount;
  final int percent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 4),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                  color: emphasized ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$amount · $percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                  color: emphasized ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
