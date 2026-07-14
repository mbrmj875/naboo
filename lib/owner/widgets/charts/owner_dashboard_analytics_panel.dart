import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../models/owner_command_center_snapshot.dart';
import '../../models/owner_kpi_models.dart';
import '../../models/owner_section_result.dart';
import '../../providers/owner_command_center_provider.dart';
import '../../models/owner_section_ttl.dart';
import '../owner_kpi_micro_animations.dart';
import '../owner_kpi_card.dart';
import '../owner_kpi_card_skeleton.dart';
import '../../utils/owner_dashboard_gold_border.dart';
import 'owner_chart_models.dart';
import 'owner_donut_chart.dart';
import 'owner_weekly_bar_chart.dart';

/// صف تحليلات — أعمدة أسبوعية + دائرة توزيع (مستوحى من لوحات e-commerce).
class OwnerDashboardAnalyticsPanel extends StatelessWidget {
  const OwnerDashboardAnalyticsPanel({
    super.key,
    required this.snapshot,
    required this.center,
    this.compact = false,
  });

  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final bool compact;

  double get _chartPlotSize =>
      compact ? kOwnerAnalyticsChartPlotSizeCompact : kOwnerAnalyticsChartPlotSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;

        final barCard = OwnerSalesBarChartCard(
          snapshot: snapshot,
          center: center,
          stretchChartArea: wide,
          chartPlotSize: _chartPlotSize,
          compact: compact,
        );
        final donutCard = OwnerRevenueDonutChartCard(
          snapshot: snapshot,
          center: center,
          stretchChartArea: wide,
          chartPlotSize: _chartPlotSize,
          compact: compact,
        );

        final charts = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: barCard),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: donutCard),
                ],
              )
            : Column(
                children: [
                  barCard,
                  const SizedBox(height: 12),
                  donutCard,
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            charts,
          ],
        );
      },
    );
  }

  static _DonutResolved resolveDonut(
    OwnerCommandCenterSnapshot snapshot,
    ColorScheme cs,
    OwnerCommandCenterProvider center,
  ) {
    final hybrid = snapshot.hybridRevenueSplit;
    if (hybrid != null && (hybrid.hasData || hybrid.isLoading || hybrid.isError)) {
      final kpi = hybrid.data;
      if (hybrid.isLoading && kpi == null) {
        return _DonutResolved(
          title: 'توزيع الإيراد',
          subtitle: 'حسب مصدر الدخل',
          isLoading: true,
          onRetry: null,
          slices: const [],
        );
      }
      if (hybrid.isError && kpi == null) {
        return _DonutResolved(
          title: 'توزيع الإيراد',
          subtitle: 'حسب مصدر الدخل',
          isError: true,
          errorMessage: hybrid.errorMessage,
          onRetry: () =>
              center.refreshSection(OwnerSectionIds.hybridRevenueSplit),
          slices: const [],
        );
      }
      if (kpi != null && kpi.totalFils > 0) {
        return _DonutResolved(
          title: 'توزيع الإيراد',
          subtitle: 'خدمة غيار vs تجزئة',
          slices: [
            OwnerChartSlice(
              label: 'غيار الزيت',
              value: kpi.serviceFils.toDouble(),
              color: cs.primary,
            ),
            OwnerChartSlice(
              label: 'تجزئة POS',
              value: kpi.posRetailFils.toDouble(),
              color: cs.tertiary,
            ),
          ],
          centerLabel: 'الإجمالي',
          centerValue: IraqiCurrencyFormat.formatIqd(
            IqdMoney.fromFils(kpi.totalFils),
          ),
        );
      }
    }

    final top = snapshot.retailTopSellers;
    if (top != null && top.data != null && top.data!.items.isNotEmpty) {
      final items = top.data!.items.take(5).toList();
      final topFiveFils =
          items.fold<int>(0, (s, e) => s + e.revenueFils);
      if (topFiveFils > 0) {
        final periodSalesFils = snapshot.sales?.data?.salesFils;
        final periodTotal = (periodSalesFils != null && periodSalesFils > 0)
            ? periodSalesFils
            : topFiveFils;
        final otherFils = periodTotal > topFiveFils
            ? periodTotal - topFiveFils
            : 0;

        final palette = [
          cs.primary,
          cs.tertiary,
          AppSemanticColors.info,
          AppSemanticColors.warning,
          AppSemanticColors.success,
        ];
        final slices = <OwnerChartSlice>[
          for (var i = 0; i < items.length; i++)
            OwnerChartSlice(
              label: items[i].productName,
              value: items[i].revenueFils.toDouble(),
              color: palette[i % palette.length],
            ),
        ];
        if (otherFils > 0) {
          slices.add(
            OwnerChartSlice(
              label: 'أخرى (باقي الفترة)',
              value: otherFils.toDouble(),
              color: cs.outline.withValues(alpha: 0.55),
            ),
          );
        }

        return _DonutResolved(
          title: 'أعلى الأصناف مبيعاً',
          subtitle: otherFils > 0
              ? 'أعلى 5 أصناف + باقي مبيعات الفترة'
              : 'حصة من مبيعات الفترة',
          slices: slices,
          centerLabel: 'مبيعات الفترة',
          centerValue: IraqiCurrencyFormat.formatIqd(
            IqdMoney.fromFils(periodTotal),
          ),
        );
      }
    }

    final cash = snapshot.cash;
    if (cash != null && cash.data != null) {
      final c = cash.data!;
      final inF = c.todayInFils;
      final outF = c.todayOutFils;
      if (inF > 0 || outF > 0) {
        return _DonutResolved(
          title: 'حركة الصندوق اليوم',
          subtitle: 'وارد vs صادر',
          slices: [
            if (inF > 0)
              OwnerChartSlice(
                label: 'وارد',
                value: inF.toDouble(),
                color: AppSemanticColors.success,
              ),
            if (outF > 0)
              OwnerChartSlice(
                label: 'صادر',
                value: outF.toDouble(),
                color: AppSemanticColors.danger,
              ),
          ],
          centerLabel: 'الرصيد',
          centerValue: IraqiCurrencyFormat.formatIqd(
            IqdMoney.fromFils(c.balanceFils),
          ),
        );
      }
    }

    return const _DonutResolved(
      title: 'توزيع الإيراد',
      subtitle: 'حسب النشاط',
      slices: [],
    );
  }
}

class OwnerSalesBarChartCard extends StatelessWidget {
  const OwnerSalesBarChartCard({
    super.key,
    required this.snapshot,
    required this.center,
    this.stretchChartArea = false,
    this.chartPlotSize = kOwnerAnalyticsChartPlotSize,
    this.compact = false,
  });

  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final bool stretchChartArea;
  final double chartPlotSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spark = snapshot.salesSparkline;
    final rangeKey = ownerDateRangeMorphKey(center.dateRange);
    final barValues = spark?.data ?? const <int>[];
    final barEmpty =
        barValues.isEmpty || barValues.every((value) => value <= 0);

    return _AnalyticsChartCard(
      title: 'المبيعات — آخر 7 أيام',
      subtitle: 'اتجاه يومي (أعمدة)',
      icon: Icons.bar_chart_rounded,
      stretchChartArea: stretchChartArea,
      chartPlotSize: chartPlotSize,
      compact: compact,
      isLoading: spark != null && spark.isLoading && !spark.hasData,
      isError: spark != null && spark.isError && !spark.hasData,
      errorMessage: spark?.errorMessage,
      onRetry: spark != null
          ? () => center.refreshSection(OwnerSectionIds.salesSparkline)
          : null,
      child: barEmpty
          ? const OwnerSectionEmpty(
              message: 'لا مبيعات مسجلة في هذه الفترة',
              icon: Icons.bar_chart_rounded,
            )
          : OwnerChartMorphSwitcher(
              morphKey: '${rangeKey}_${barValues.join('|')}',
              child: OwnerWeeklyBarChart(
                valuesFils: barValues,
                height: chartPlotSize,
                fillAvailableHeight: stretchChartArea,
              ),
            ),
    );
  }
}

class OwnerRevenueDonutChartCard extends StatelessWidget {
  const OwnerRevenueDonutChartCard({
    super.key,
    required this.snapshot,
    required this.center,
    this.stretchChartArea = false,
    this.chartPlotSize = kOwnerAnalyticsChartPlotSize,
    this.compact = false,
  });

  final OwnerCommandCenterSnapshot snapshot;
  final OwnerCommandCenterProvider center;
  final bool stretchChartArea;
  final double chartPlotSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rangeKey = ownerDateRangeMorphKey(center.dateRange);
    final donut = OwnerDashboardAnalyticsPanel.resolveDonut(snapshot, cs, center);
    final donutMorphKey =
        '${rangeKey}_${donut.slices.map((s) => '${s.label}:${s.value}').join('|')}';

    return _AnalyticsChartCard(
      title: donut.title,
      subtitle: donut.subtitle,
      icon: Icons.pie_chart_rounded,
      stretchChartArea: stretchChartArea,
      chartPlotSize: chartPlotSize,
      compact: compact,
      isLoading: donut.isLoading,
      isError: donut.isError,
      errorMessage: donut.errorMessage,
      onRetry: donut.onRetry,
      child: donut.slices.isEmpty && !donut.isLoading
          ? const OwnerSectionEmpty(
              message: 'لا توزيع كافٍ في هذه الفترة',
              icon: Icons.pie_chart_outline,
            )
          : OwnerChartMorphSwitcher(
              morphKey: donutMorphKey,
              child: OwnerDonutChart(
                slices: donut.slices,
                size: chartPlotSize,
                centerLabel: donut.centerLabel,
                centerValue: donut.centerValue,
                fillAvailableHeight: stretchChartArea,
              ),
            ),
    );
  }
}

class _DonutResolved {
  const _DonutResolved({
    required this.title,
    required this.subtitle,
    this.slices = const [],
    this.centerLabel,
    this.centerValue,
    this.isLoading = false,
    this.isError = false,
    this.errorMessage,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final List<OwnerChartSlice> slices;
  final String? centerLabel;
  final String? centerValue;
  final bool isLoading;
  final bool isError;
  final String? errorMessage;
  final VoidCallback? onRetry;
}

class _AnalyticsChartCard extends StatelessWidget {
  const _AnalyticsChartCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.isLoading = false,
    this.isError = false,
    this.errorMessage,
    this.onRetry,
    this.stretchChartArea = false,
    this.chartPlotSize = kOwnerAnalyticsChartPlotSize,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final bool isLoading;
  final bool isError;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// يمدّد منطقة الرسم لمحاذاة بطاقة المخطط المجاور (نفس الارتفاع).
  final bool stretchChartArea;
  final double chartPlotSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pad = compact ? 14.0 : 16.0;
    final headerGap = compact ? 8.0 : 16.0;
    return Container(
      decoration: OwnerDashboardGoldBorder.boxDecoration(
        context,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: compact ? 20 : 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 14 : 15,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: headerGap),
            if (isLoading)
              OwnerKpiCardSkeleton(height: chartPlotSize)
            else if (isError)
              OwnerSectionError(
                message: errorMessage ?? title,
                onRetry: onRetry ?? () {},
              )
            else if (stretchChartArea)
              SizedBox(
                height: kOwnerAnalyticsChartBodyHeight,
                width: double.infinity,
                child: child,
              )
            else
              SizedBox(
                height: compact
                    ? kOwnerAnalyticsChartBodyHeightCompact
                    : ownerAnalyticsBarChartBodyHeight(chartPlotSize),
                width: double.infinity,
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}
