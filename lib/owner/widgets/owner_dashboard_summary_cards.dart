import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../models/owner_command_center_snapshot.dart';
import '../models/owner_section_result.dart';
import '../models/owner_kpi_models.dart';
import '../models/owner_section_ttl.dart';
import '../providers/owner_command_center_provider.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';

/// أول بطاقتين في اللوحة — مبيعات الفترة + رصيد الصندوق (تمرّ مع المحتوى).
class OwnerDashboardSummaryCards extends StatelessWidget {
  const OwnerDashboardSummaryCards({
    super.key,
    required this.center,
    required this.snapshot,
    this.onOpenCash,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final VoidCallback? onOpenCash;

  /// بطاقات تُعرض أعلى الشبكة — لا تُكرَّر في catalog.
  static bool isSummaryCatalogId(String catalogId) {
    switch (catalogId) {
      case OwnerCatalogIds.cashSummary:
      case OwnerCatalogIds.retailCashSummary:
      case OwnerCatalogIds.clothingCashSummary:
      case OwnerCatalogIds.retailSalesPeriod:
      case OwnerCatalogIds.clothingSalesPeriod:
        return true;
      default:
        return false;
    }
  }

  /// تُغطى في «إجراءات مطلوبة» — لا تُكرَّر كبطاقة Hero أسفل اللوحة.
  static bool isActionRailCatalogId(String catalogId) {
    switch (catalogId) {
      case OwnerCatalogIds.retailStockShortages:
      case OwnerCatalogIds.oilStockShortages:
      case OwnerCatalogIds.clothingVariantShortages:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final range = center.dateRange;
    final sales = snapshot.sales;
    final cash = snapshot.cash;

    Widget salesCard() => _StitchMetricCard(
          title: range.salesTitleAr,
          section: sales,
          sectionId: OwnerSectionIds.sales,
          onRetry: () => center.refreshSection(OwnerSectionIds.sales),
          icon: Icons.trending_up_rounded,
          iconColor: AppSemanticColors.success,
          valueBuilder: (data) => IraqiCurrencyFormat.formatIqd(
            IqdMoney.fromFils((data as SalesKpi).salesFils),
          ),
          backgroundColor: OwnerDashboardGoldBorder.fillColor(context),
          titleColor: cs.onSurfaceVariant,
          valueColor: cs.primary,
        );

    Widget? cashCard() {
      if (cash == null) return null;
      return _StitchMetricCard(
        title: 'رصيد الصندوق',
        section: cash,
        sectionId: OwnerSectionIds.cash,
        onRetry: () => center.refreshSection(OwnerSectionIds.cash),
        onTap: onOpenCash,
        icon: Icons.account_balance_wallet_outlined,
        iconColor: AppColors.accentGold,
        valueBuilder: (data) => IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as CashSummary).balanceFils),
        ),
        backgroundColor: cs.primary,
        titleColor: cs.onPrimary.withValues(alpha: 0.72),
        valueColor: cs.onPrimary,
        borderGold: false,
        trailingAction: onOpenCash == null
            ? null
            : TextButton.icon(
                onPressed: onOpenCash,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentGold,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text(
                  'سحب',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackCards = constraints.maxWidth < 380;
        final cash = cashCard();

        if (stackCards) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              salesCard(),
              if (cash != null) ...[
                const SizedBox(height: 12),
                cash,
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: salesCard()),
            if (cash != null) ...[
              const SizedBox(width: 12),
              Expanded(child: cash),
            ],
          ],
        );
      },
    );
  }
}

class _StitchMetricCard extends StatelessWidget {
  const _StitchMetricCard({
    required this.title,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.icon,
    required this.iconColor,
    required this.valueBuilder,
    required this.backgroundColor,
    required this.titleColor,
    required this.valueColor,
    this.onTap,
    this.trailingAction,
    this.borderGold = true,
  });

  final String title;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final IconData icon;
  final Color iconColor;
  final String Function(dynamic data) valueBuilder;
  final Color backgroundColor;
  final Color titleColor;
  final Color valueColor;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  final bool borderGold;

  @override
  Widget build(BuildContext context) {
    final decoration = borderGold
        ? OwnerDashboardGoldBorder.boxDecoration(
            context,
            backgroundColor: backgroundColor,
          )
        : BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(OwnerDashboardGoldBorder.radius),
            boxShadow: OwnerDashboardGoldBorder.fintechShadow(context),
          );

    final child = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
              Icon(icon, size: 18, color: iconColor),
            ],
          ),
          const SizedBox(height: 8),
          if (section.isLoading && !section.hasData)
            const OwnerKpiInlineSkeleton(height: 28)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 160.0;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: maxW,
                    child: OwnerKpiSectionBody(
                      section: section,
                      sectionId: sectionId,
                      onRetry: onRetry,
                      valueBuilder: valueBuilder,
                      inlineSkeletonHeight: 28,
                      valueTextStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                        height: 1.15,
                      ),
                    ),
                  ),
                );
              },
            ),
          if (trailingAction != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: trailingAction,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: title,
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OwnerDashboardGoldBorder.radius),
          child: DecoratedBox(decoration: decoration, child: child),
        ),
      ),
    );
  }
}
