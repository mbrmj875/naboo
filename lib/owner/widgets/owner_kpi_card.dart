import 'package:flutter/material.dart';

import '../models/owner_kpi_trend.dart';
import '../models/owner_section_result.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_kpi_card_skeleton.dart';
import 'owner_kpi_micro_animations.dart';
import 'owner_kpi_trend_line.dart';

/// شارة «آخر تحديث» للبيانات القديمة أو offline.
class OwnerStaleBadge extends StatelessWidget {
  const OwnerStaleBadge({super.key, required this.fetchedAt});

  final DateTime fetchedAt;

  String _label() {
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inMinutes < 1) return 'آخر تحديث: الآن';
    if (diff.inMinutes < 60) return 'آخر تحديث: منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'آخر تحديث: منذ ${diff.inHours} س';
    return 'آخر تحديث: منذ ${diff.inDays} ي';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.tertiary,
          ),
    );
  }
}

/// فراغ صريح — لا بيانات أو offline بدون cache (v1.1.2 §6).
class OwnerSectionEmpty extends StatelessWidget {
  const OwnerSectionEmpty({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Semantics(
                label: 'إعادة المحاولة',
                child: const Text('إعادة المحاولة'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// خطأ قسم واحد مع إعادة محاولة — لا تُسقط اللوحة.
class OwnerSectionError extends StatelessWidget {
  const OwnerSectionError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Semantics(
            label: 'إعادة المحاولة',
            child: const Text('إعادة المحاولة'),
          ),
        ),
      ],
    );
  }
}

const kOwnerKpiOfflineEmptyMessage = ownerKpiOfflineEmptyMessage;

/// جسم موحّد لحالات KPI — loading / empty / error / success (S5a).
class OwnerKpiSectionBody extends StatelessWidget {
  const OwnerKpiSectionBody({
    super.key,
    required this.section,
    required this.sectionId,
    required this.onRetry,
    required this.valueBuilder,
    this.trend,
    this.isEmpty,
    this.emptyMessage,
    this.inlineSkeletonHeight = 48,
    this.valueTextStyle,
    this.subtitleBuilder,
  });

  final OwnerSectionResult<dynamic> section;
  final String sectionId;
  final VoidCallback onRetry;
  final String Function(dynamic data) valueBuilder;
  final OwnerKpiTrend? trend;
  final bool Function(dynamic data)? isEmpty;
  final String? emptyMessage;
  final double inlineSkeletonHeight;
  final TextStyle? valueTextStyle;
  final String Function(dynamic data)? subtitleBuilder;

  @override
  Widget build(BuildContext context) {
    if (section.isLoading && !section.hasData) {
      return OwnerKpiInlineSkeleton(height: inlineSkeletonHeight);
    }

    if (!section.hasData && section.isOffline) {
      return OwnerSectionEmpty(
        message: kOwnerKpiOfflineEmptyMessage,
        icon: Icons.cloud_off_outlined,
        onRetry: onRetry,
      );
    }

    if (section.isError && !section.hasData) {
      return OwnerSectionError(
        message: section.errorMessage ?? 'تعذّر تحميل هذا القسم',
        onRetry: onRetry,
      );
    }

    final data = section.data;
    if (data != null &&
        isEmpty != null &&
        emptyMessage != null &&
        isEmpty!(data)) {
      return OwnerSectionEmpty(message: emptyMessage!);
    }

    final display = data != null ? valueBuilder(data) : '—';
    final subtitle =
        data != null && subtitleBuilder != null ? subtitleBuilder!(data) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OwnerAnimatedKpiValue(
          valueKey:
              '${section.fetchedAt?.millisecondsSinceEpoch ?? 0}_$display',
          text: display,
          style: valueTextStyle,
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (trend != null) OwnerKpiTrendLine(trend: trend!),
        if (section.isError && section.hasData)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OwnerSectionError(
              message: section.errorMessage ?? '',
              onRetry: onRetry,
            ),
          )
        else if (section.isAgeStale(sectionId) && section.fetchedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'البيانات قديمة — جارٍ التحديث…',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error.withValues(
                          alpha: 0.75,
                        ),
                  ),
            ),
          )
        else if (section.isStale && section.fetchedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OwnerStaleBadge(fetchedAt: section.fetchedAt!),
          ),
      ],
    );
  }
}

/// بطاقة KPI مع Semantics ودعم loading/error/empty.
class OwnerKpiCard extends StatelessWidget {
  const OwnerKpiCard({
    super.key,
    required this.title,
    required this.section,
    required this.sectionId,
    required this.valueBuilder,
    required this.onRetry,
    this.icon = Icons.insights_outlined,
    this.trailing,
    this.trend,
    this.isEmpty,
    this.emptyMessage,
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
  final OwnerKpiTrend? trend;
  final bool Function(dynamic data)? isEmpty;
  final String? emptyMessage;
  final Color? backgroundColor;
  final Color? iconColor;

  /// عند true — توهج تحذيري حول البطاقة (S5c).
  final bool Function(dynamic data)? warningGlowWhen;

  /// عند التعيين — البطاقة بالكامل تفتح الصفحة المرتبطة (بدون سهم).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = section.data;
    final contentKey = section.isLoading && !section.hasData
        ? 'loading'
        : '${section.status.name}_${section.fetchedAt?.millisecondsSinceEpoch ?? 0}_${data != null ? valueBuilder(data) : ''}';
    final warnGlow = warningGlowWhen != null &&
        section.hasData &&
        data != null &&
        warningGlowWhen!(data);

    final semanticsLabel = section.hasData && data != null
        ? trend != null
            ? '$title: ${valueBuilder(data)}. ${trend!.displayLineAr}'
            : '$title: ${valueBuilder(data)}'
        : title;

    final cardBody = Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 200;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (trailing != null && !compact) ...[
                        const SizedBox(width: 4),
                        trailing!,
                      ],
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (iconColor ?? cs.primary).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          color: iconColor ?? cs.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              OwnerKpiContentFade(
                contentKey: contentKey,
                child: OwnerKpiSectionBody(
                  section: section,
                  sectionId: sectionId,
                  onRetry: onRetry,
                  valueBuilder: valueBuilder,
                  trend: trend,
                  isEmpty: isEmpty,
                  emptyMessage: emptyMessage,
                  valueTextStyle: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );

    final borderRadius = BorderRadius.circular(OwnerDashboardGoldBorder.radius);
    final cardShape = OwnerDashboardGoldBorder.cardShape(
      context,
      warning: warnGlow,
    );

    Widget card = Card(
      color: backgroundColor ?? OwnerDashboardGoldBorder.fillColor(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: cardShape,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: cardBody,
            )
          : cardBody,
    );

    card = Semantics(
      label: onTap != null ? '$semanticsLabel — اضغط للفتح' : semanticsLabel,
      button: onTap != null,
      child: card,
    );

    return OwnerKpiWarningGlow(active: warnGlow, child: card);
  }
}

/// خطأ أو فراغ offline — للبطاقات المخصصة (top sellers، hybrid، …).
Widget ownerKpiSectionErrorOrEmpty(
  OwnerSectionResult<dynamic> section,
  VoidCallback onRetry, {
  String? fallbackMessage,
}) {
  if (!section.hasData && section.isOffline) {
    return OwnerSectionEmpty(
      message: kOwnerKpiOfflineEmptyMessage,
      icon: Icons.cloud_off_outlined,
      onRetry: onRetry,
    );
  }
  return OwnerSectionError(
    message: section.errorMessage ?? fallbackMessage ?? 'تعذّر تحميل هذا القسم',
    onRetry: onRetry,
  );
}
