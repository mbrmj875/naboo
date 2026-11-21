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
        return items
            .map((e) => e.staffName.trim())
            .where((n) => n.isNotEmpty)
            .join('، ');
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
    final alertBorderColor = OwnerOilKpiStitchMetrics.alertAmber.withValues(
      alpha: 0.55,
    );

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

    // عنوان يلتف على سطرين أو أكثر بين الكلمات — لا قص ولا كسر وسط الكلمة.
    final body = Padding(
      padding: const EdgeInsets.all(OwnerOilKpiStitchMetrics.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
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
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBoxColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
    );

    Widget card = DecoratedBox(decoration: decoration, child: body);
    if (alert) {
      card = ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
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

    // ارتفاع أدنى فقط: البطاقة تكبر مع الخط الكبير بدل قص الرقم.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: OwnerOilKpiStitchMetrics.compactHeight,
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, borderRadius: borderRadius, child: card),
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
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 12),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: OwnerOilKpiStitchMetrics.heroHeight,
      ),
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

    const titleStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: OwnerOilKpiStitchMetrics.navy,
      height: 1.25,
    );
    const valueStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: OwnerOilKpiStitchMetrics.navy,
    );
    final subtitleStyle = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);

    final iconBox = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 22, color: cs.primary),
    );

    final data = section.data;
    final valueText = data != null ? valueBuilder(data) : '—';

    final content = LayoutBuilder(
      builder: (context, constraints) {
        // سطر واحد فقط إن اتسع للعنوان والرقم كاملين؛ وإلا يُرصّ عمودياً
        // (في نصف عرض الهاتف أو مع الخط الكبير) بدل «624,…» و«المخزو/ن».
        final scaler = MediaQuery.textScalerOf(context);
        final dir = Directionality.of(context);
        double widthOf(String text, TextStyle style) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: dir,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          return tp.width;
        }

        const iconWidth = 38.0;
        final needed =
            iconWidth +
            10 +
            widthOf(title, titleStyle) +
            12 +
            widthOf(valueText, valueStyle);
        final oneLine = needed <= constraints.maxWidth;

        final body = _StitchBody(
          section: section,
          sectionId: sectionId,
          onRetry: onRetry,
          valueBuilder: valueBuilder,
          subtitleBuilder: subtitleBuilder,
          alignEnd: oneLine,
          valueStyle: valueStyle,
          subtitleStyle: subtitleStyle,
          skeletonHeight: 24,
        );

        if (oneLine) {
          return Row(
            children: [
              iconBox,
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: titleStyle)),
              const SizedBox(width: 12),
              body,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                iconBox,
                const SizedBox(width: 10),
                Expanded(child: Text(title, softWrap: true, style: titleStyle)),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        );
      },
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: OwnerOilKpiStitchMetrics.inventoryHeight,
      ),
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
                vertical: 12,
              ),
              child: Center(widthFactor: 1, child: content),
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
        // الرقم كاملاً دائماً: يلتف عند المسافة (قبل «د.ع») ولا يُقص.
        Text(
          value,
          softWrap: true,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: valueStyle,
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: subtitleStyle,
          ),
      ],
    );

    return column;
  }
}
