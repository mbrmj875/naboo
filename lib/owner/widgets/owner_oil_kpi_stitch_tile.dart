import 'package:flutter/material.dart';

import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../models/owner_kpi_models.dart';
import '../models/owner_section_result.dart';
import '../owner_dashboard_card_builder.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card_skeleton.dart';

/// مقاسات Stitch — KPI Bento (هاتف).
abstract final class OwnerOilKpiStitchMetrics {
  OwnerOilKpiStitchMetrics._();

  static const double gap = 12;
  static const double padding = 14;
  static const double heroHeight = 120;
  static const double compactHeight = 96;
  static const double inventoryHeight = 96;
  static const Color navy = Color(0xFF1B2B4B);
  static const Color alertAmber = Color(0xFFFFBF00);
}

/// يبني بطاقة KPI واحدة بأسلوب Stitch — ارتفاع ثابت.
class OwnerOilKpiStitchTile extends StatelessWidget {
  const OwnerOilKpiStitchTile({
    super.key,
    required this.catalogId,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    this.icon,
    this.onTap,
    this.layout = OwnerOilKpiStitchLayout.compact,
    this.alertWhen,
  });

  final String catalogId;
  final String title;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final IconData? icon;
  final VoidCallback? onTap;
  final OwnerOilKpiStitchLayout layout;
  final bool Function(dynamic data)? alertWhen;

  @override
  Widget build(BuildContext context) {
    final iconData = icon ?? OwnerDashboardCardBuilder.iconFor(catalogId);

    if (layout == OwnerOilKpiStitchLayout.inventoryRow) {
      return _InventoryRowTile(
        title: title,
        icon: iconData,
        section: section,
        sectionId: sectionId,
        onRetry: onRetry,
        onTap: onTap,
        valueBuilder: _valueForCatalog,
        subtitleBuilder: _subtitleForCatalog,
      );
    }

    if (layout == OwnerOilKpiStitchLayout.hero) {
      return _HeroTile(
        title: title,
        icon: iconData,
        section: section,
        sectionId: sectionId,
        onRetry: onRetry,
        onTap: onTap,
        valueBuilder: _valueForCatalog,
        subtitleBuilder: _subtitleForCatalog,
      );
    }

    return _CompactTile(
      title: title,
      icon: iconData,
      section: section,
      sectionId: sectionId,
      onRetry: onRetry,
      onTap: onTap,
      alertWhen: alertWhen,
      valueBuilder: _valueForCatalog,
      subtitleBuilder: _subtitleForCatalog,
    );
  }

  String _valueForCatalog(dynamic data) {
    switch (catalogId) {
      case OwnerCatalogIds.oilActiveCars:
        return '${(data as OilActiveCarsKpi).activeCount}';
      case OwnerCatalogIds.oilChangesPeriod:
        return '${(data as OilChangesKpi).changeCount}';
      case OwnerCatalogIds.oilStockShortages:
        final n = (data as InventoryAlert).shortageCount;
        if (n <= 0) return '0';
        return '$n';
      case OwnerCatalogIds.oilAvgTicket:
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as OilAvgTicketKpi).avgTicketFils),
        );
      case OwnerCatalogIds.openShifts:
        final items = (data as OpenShiftsKpi).items;
        return items.isEmpty ? '0' : '${items.length}';
      case OwnerCatalogIds.inventoryValue:
        final v = data as InventoryValueKpi;
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(v.totalCostFils),
        );
      case OwnerCatalogIds.debtsSummary:
        final d = data as DebtSummary;
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(d.totalReceivableFils),
        );
      default:
        return OwnerDashboardCardBuilder.valueForCatalogId(catalogId, data);
    }
  }

  String? _subtitleForCatalog(dynamic data) {
    switch (catalogId) {
      case OwnerCatalogIds.oilActiveCars:
        final n = (data as OilActiveCarsKpi).activeCount;
        if (n <= 0) return 'الورشة فارغة';
        return n == 1 ? 'سيارة واحدة قيد العمل' : '$n سيارات قيد العمل';
      case OwnerCatalogIds.openShifts:
        final items = (data as OpenShiftsKpi).items;
        if (items.isEmpty) return 'لا ورديات مفتوحة';
        return items.map((e) => e.staffName.trim()).where((n) => n.isNotEmpty).join('، ');
      case OwnerCatalogIds.oilStockShortages:
        final n = (data as InventoryAlert).shortageCount;
        if (n <= 0) return null;
        return n == 1 ? 'صنف واحد' : '$n صنف';
      case OwnerCatalogIds.inventoryValue:
        final v = data as InventoryValueKpi;
        return '${v.productCount} صنف';
      case OwnerCatalogIds.debtsSummary:
        final d = data as DebtSummary;
        return '${d.indebtedCustomerCount} عميل';
      default:
        return null;
    }
  }
}

enum OwnerOilKpiStitchLayout { compact, hero, inventoryRow }

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.title,
    required this.icon,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.valueBuilder,
    required this.subtitleBuilder,
    this.onTap,
    this.alertWhen,
  });

  final String title;
  final IconData icon;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String Function(dynamic data) valueBuilder;
  final String? Function(dynamic data) subtitleBuilder;
  final VoidCallback? onTap;
  final bool Function(dynamic data)? alertWhen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = section.data;
    final alert = alertWhen != null && data != null && alertWhen!(data);

    final radius = OwnerDashboardGoldBorder.radius;
    final borderRadius = BorderRadius.circular(radius);
    final alertBorderColor =
        OwnerOilKpiStitchMetrics.alertAmber.withValues(alpha: 0.55);

    final decoration = OwnerDashboardGoldBorder.boxDecoration(context).copyWith(
      color: alert
          ? cs.errorContainer.withValues(alpha: 0.15)
          : OwnerDashboardGoldBorder.fillColor(context),
      border: alert
          ? Border.all(color: alertBorderColor)
          : Border.all(color: OwnerDashboardGoldBorder.borderColor(cs: cs)),
    );

    final iconColor = alert ? cs.error : cs.primary;
    final iconBoxColor = alert
        ? cs.error.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.65);

    final body = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.all(OwnerOilKpiStitchMetrics.padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 36),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: alert
                        ? OwnerOilKpiStitchMetrics.navy
                        : cs.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ),
              _StitchBody(
                section: section,
                sectionId: sectionId,
                onRetry: onRetry,
                valueBuilder: valueBuilder,
                subtitleBuilder: subtitleBuilder,
                valueStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: alert ? cs.error : OwnerOilKpiStitchMetrics.navy,
                  height: 1.1,
                ),
                subtitleStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: alert
                      ? OwnerOilKpiStitchMetrics.navy.withValues(alpha: 0.75)
                      : cs.onSurfaceVariant,
                ),
                skeletonHeight: 28,
              ),
            ],
          ),
        ),
        PositionedDirectional(
          top: OwnerOilKpiStitchMetrics.padding,
          end: OwnerOilKpiStitchMetrics.padding,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBoxColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ),
      ],
    );

    Widget card = DecoratedBox(decoration: decoration, child: body);
    if (alert) {
      card = ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            card,
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: OwnerOilKpiStitchMetrics.alertAmber,
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: Radius.circular(radius),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: OwnerOilKpiStitchMetrics.compactHeight,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: card,
        ),
      ),
    );
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.title,
    required this.icon,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.valueBuilder,
    required this.subtitleBuilder,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String Function(dynamic data) valueBuilder;
  final String? Function(dynamic data) subtitleBuilder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final body = Padding(
      padding: const EdgeInsets.all(OwnerOilKpiStitchMetrics.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: cs.primary),
              ),
            ],
          ),
          const Spacer(),
          _StitchBody(
            section: section,
            sectionId: sectionId,
            onRetry: onRetry,
            valueBuilder: valueBuilder,
            subtitleBuilder: subtitleBuilder,
            valueStyle: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: OwnerOilKpiStitchMetrics.navy,
              height: 1,
            ),
            subtitleStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
            skeletonHeight: 36,
          ),
        ],
      ),
    );

    return SizedBox(
      height: OwnerOilKpiStitchMetrics.heroHeight,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OwnerDashboardGoldBorder.radius),
          child: DecoratedBox(
            decoration: OwnerDashboardGoldBorder.boxDecoration(context),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _InventoryRowTile extends StatelessWidget {
  const _InventoryRowTile({
    required this.title,
    required this.icon,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.valueBuilder,
    required this.subtitleBuilder,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String Function(dynamic data) valueBuilder;
  final String? Function(dynamic data) subtitleBuilder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: OwnerOilKpiStitchMetrics.inventoryHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OwnerDashboardGoldBorder.radius),
          child: DecoratedBox(
            decoration: OwnerDashboardGoldBorder.boxDecoration(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OwnerOilKpiStitchMetrics.padding,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: OwnerOilKpiStitchMetrics.navy,
                      ),
                    ),
                  ),
                  Flexible(
                    child: _StitchBody(
                      section: section,
                      sectionId: sectionId,
                      onRetry: onRetry,
                      valueBuilder: valueBuilder,
                      subtitleBuilder: subtitleBuilder,
                      alignEnd: true,
                      valueStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: OwnerOilKpiStitchMetrics.navy,
                      ),
                      subtitleStyle: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      skeletonHeight: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StitchBody extends StatelessWidget {
  const _StitchBody({
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.valueBuilder,
    required this.subtitleBuilder,
    required this.valueStyle,
    required this.subtitleStyle,
    required this.skeletonHeight,
    this.alignEnd = false,
  });

  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String Function(dynamic data) valueBuilder;
  final String? Function(dynamic data) subtitleBuilder;
  final TextStyle valueStyle;
  final TextStyle subtitleStyle;
  final double skeletonHeight;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (section.isLoading && !section.hasData) {
      return OwnerKpiInlineSkeleton(height: skeletonHeight);
    }
    if (section.isError && !section.hasData) {
      return Align(
        alignment: alignEnd
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: onRetry,
          child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 11)),
        ),
      );
    }

    final data = section.data;
    final value = data != null ? valueBuilder(data) : '—';
    final subtitle = data != null ? subtitleBuilder(data) : null;

    final column = Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
      ],
    );

    return alignEnd ? column : column;
  }
}
