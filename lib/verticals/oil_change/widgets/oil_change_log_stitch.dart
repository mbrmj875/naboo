import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../utils/oil_change_log_format.dart';
import '../utils/oil_change_log_grouping.dart';

/// ألوان ومقاسات Stitch — سجل غيارات الزيت (Premium + Desktop).
abstract final class OilChangeLogStitchMetrics {
  OilChangeLogStitchMetrics._();

  static const double pagePadding = 16;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double cardRadius = 12;
  static const double pillRadius = 999;
  static const double actionHeight = 56;

  static const Color background = Color(0xFFFBF8FC);
  static const Color surface = Color(0xFFFBF8FC);
  static const Color surfaceContainerLow = Color(0xFFF6F2F7);
  static const Color surfaceContainerHigh = Color(0xFFEAE7EB);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF081B37);
  static const Color onPrimaryContainer = Color(0xFF7484A5);
  static const Color secondaryContainer = Color(0xFFFED752);
  static const Color onSecondaryContainer = Color(0xFF735D00);
  static const Color outline = Color(0xFF75777E);
  static const Color outlineVariant = Color(0xFFC5C6CE);
  static const Color textPrimary = Color(0xFF1B1B1E);
  static const Color textMuted = Color(0xFF44474D);
  static const Color error = Color(0xFFBA1A1A);
  static const Color success = Color(0xFF16A34A);

  static BoxDecoration panelDecoration({double radius = 12}) => BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: secondaryContainer.withValues(alpha: 0.52),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryContainer.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  static BoxDecoration cardDecoration({bool selected = false}) => BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(
          color: selected
              ? secondaryContainer
              : secondaryContainer.withValues(alpha: 0.50),
          width: selected ? 2 : 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryContainer.withValues(alpha: selected ? 0.18 : 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  static BoxDecoration glassCardDecoration() => BoxDecoration(
        color: surfaceWhite.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: outlineVariant.withValues(alpha: 0.35)),
      );
}

String oilFormatLogDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  final time = DateFormat('hh:mm a', 'en').format(local);
  return '${local.year}/${local.month}/${local.day} - $time';
}

String oilFormatVehicleLine(Map<String, dynamic> row) {
  final car = (row['deviceName'] ?? '').toString().trim();
  final model = (row['carModel'] ?? '').toString().trim();
  if (car.isEmpty) return model;
  if (model.isEmpty) return car;
  return '$car $model';
}

String oilFormatOilChip(Map<String, dynamic> row) {
  final oilType = (row['oilType'] ?? '').toString().trim();
  final viscosity = (row['oilViscosity'] ?? '').toString().trim();
  return [oilType, viscosity].where((s) => s.isNotEmpty).join(' ');
}

Color oilTypeAccentColor(String oilLabel) {
  if (oilLabel.isEmpty) return OilChangeLogStitchMetrics.outline;
  final hash = oilLabel.codeUnits.fold<int>(0, (a, b) => a + b);
  const palette = [
    Color(0xFFEAB308),
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFF7C3AED),
  ];
  return palette[hash % palette.length];
}

String topOilLabelFromRows(List<Map<String, dynamic>> rows) {
  final counts = <String, int>{};
  for (final r in rows) {
    final label = oilFormatOilChip(r);
    if (label.isEmpty) continue;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  if (counts.isEmpty) return '—';
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// إحصائيات اليوم.
class OilChangeLogStitchTodayStats {
  const OilChangeLogStitchTodayStats({
    required this.visitCount,
    required this.shopLiters,
    required this.revenueLabel,
    required this.invoicedCount,
    required this.topOilLabel,
  });

  final int visitCount;
  final double shopLiters;
  final String revenueLabel;
  final int invoicedCount;
  final String topOilLabel;

  static OilChangeLogStitchTodayStats fromDayGroups(
    List<OilChangeDayGroup> groups,
  ) {
    final now = DateTime.now();
    for (final g in groups) {
      if (g.isToday(now)) {
        return OilChangeLogStitchTodayStats(
          visitCount: g.summary.visitCount,
          shopLiters: g.summary.shopLiters,
          revenueLabel: g.summary.servicesLabel(),
          invoicedCount: g.summary.invoicedCount,
          topOilLabel: topOilLabelFromRows(g.rows),
        );
      }
    }
    return const OilChangeLogStitchTodayStats(
      visitCount: 0,
      shopLiters: 0,
      revenueLabel: '0',
      invoicedCount: 0,
      topOilLabel: '—',
    );
  }
}

/// أزرار «بطاقة جديدة» + «واتساب» — Premium pill grid.
class OilChangeLogStitchActionButtons extends StatelessWidget {
  const OilChangeLogStitchActionButtons({
    super.key,
    required this.onNewCard,
    required this.onWhatsApp,
    this.stacked = false,
    this.compactWhatsAppLabel = false,
  });

  final VoidCallback onNewCard;
  final VoidCallback onWhatsApp;
  final bool stacked;
  final bool compactWhatsAppLabel;

  @override
  Widget build(BuildContext context) {
    final waLabel = compactWhatsAppLabel ? 'واتساب' : 'إرسال واتساب';

    final newBtn = SizedBox(
      height: OilChangeLogStitchMetrics.actionHeight,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onNewCard,
        style: FilledButton.styleFrom(
          backgroundColor: OilChangeLogStitchMetrics.secondaryContainer,
          foregroundColor: OilChangeLogStitchMetrics.onSecondaryContainer,
          elevation: 2,
          shadowColor:
              OilChangeLogStitchMetrics.secondaryContainer.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.pillRadius),
          ),
        ),
        icon: const Icon(Icons.add_circle_rounded),
        label: const Text(
          'بطاقة غيار زيت جديدة',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );

    final waBtn = SizedBox(
      height: OilChangeLogStitchMetrics.actionHeight,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onWhatsApp,
        style: FilledButton.styleFrom(
          backgroundColor: OilChangeLogStitchMetrics.primaryContainer,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor:
              OilChangeLogStitchMetrics.primaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.pillRadius),
          ),
        ),
        icon: const Icon(Icons.chat_rounded),
        label: Text(waLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          newBtn,
          const SizedBox(height: OilChangeLogStitchMetrics.gapMd),
          waBtn,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: newBtn),
        const SizedBox(width: OilChangeLogStitchMetrics.gapMd),
        Expanded(child: waBtn),
      ],
    );
  }
}

InputDecoration oilChangeLogStitchSearchDecoration({
  required bool hasText,
  required VoidCallback onClear,
}) {
  const gold = OilChangeLogStitchMetrics.secondaryContainer;
  final radius = BorderRadius.circular(OilChangeLogStitchMetrics.pillRadius);
  final enabledBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: gold.withValues(alpha: 0.55),
      width: 1.25,
    ),
  );

  return InputDecoration(
    hintText: 'ابحث برقم اللوحة أو اسم العميل…',
    prefixIcon: Icon(
      Icons.search_rounded,
      color: gold.withValues(alpha: 0.92),
    ),
    suffixIcon: hasText
        ? IconButton(
            icon: Icon(
              Icons.clear_rounded,
              color: OilChangeLogStitchMetrics.textMuted,
            ),
            onPressed: onClear,
          )
        : null,
    filled: true,
    fillColor: OilChangeLogStitchMetrics.surfaceContainerLow,
    contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
    border: enabledBorder,
    enabledBorder: enabledBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: gold.withValues(alpha: 0.88),
        width: 1.5,
      ),
    ),
  );
}

/// رأس مجموعة يوم — Premium (نص بسيط).
class OilChangeLogStitchDayHeader extends StatelessWidget {
  const OilChangeLogStitchDayHeader({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggle,
    this.compact = false,
  });

  final OilChangeDayGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: OilChangeLogStitchMetrics.gapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: OilChangeLogStitchMetrics.textPrimary,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Divider(
              height: 1,
              color: OilChangeLogStitchMetrics.secondaryContainer
                  .withValues(alpha: 0.40),
            ),
          ],
        ),
      );
    }

    final s = group.summary;
    final badge = '${s.visitCount} ${s.visitCount == 1 ? 'زيارة' : 'زيارات'}';

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: OilChangeLogStitchMetrics.textPrimary,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: OilChangeLogStitchMetrics.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: OilChangeLogStitchMetrics.textMuted,
              ),
            ),
          ),
          IconButton(
            onPressed: onToggle,
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: OilChangeLogStitchMetrics.primaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class OilChangeLogStitchPlateBadge extends StatelessWidget {
  const OilChangeLogStitchPlateBadge({super.key, required this.plate});

  final String plate;

  @override
  Widget build(BuildContext context) {
    if (plate.isEmpty || plate == '—') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: OilChangeLogStitchMetrics.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        plate,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: OilChangeLogStitchMetrics.textPrimary,
        ),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}

class OilChangeLogStitchInfoChip extends StatelessWidget {
  const OilChangeLogStitchInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: OilChangeLogStitchMetrics.surfaceContainerLow,
        borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: OilChangeLogStitchMetrics.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: OilChangeLogStitchMetrics.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة زيارة — Premium Management.
class OilChangeLogStitchVisitCard extends StatelessWidget {
  const OilChangeLogStitchVisitCard({
    super.key,
    required this.row,
    required this.selected,
    required this.showSuspended,
    required this.onTap,
    required this.onDetail,
    this.onResume,
  });

  final Map<String, dynamic> row;
  final bool selected;
  final bool showSuspended;
  final VoidCallback onTap;
  final VoidCallback onDetail;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final name = (row['customerNameSnapshot'] ?? '').toString().trim();
    final vehicle = oilFormatVehicleLine(row);
    final plate = oilFormatPlate(row);
    final price = oilFormatPrice(row);
    final odoCurrent = oilFormatOdo((row['odometerCurrent'] ?? '').toString());
    final oilChip = oilFormatOilChip(row);

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: OilChangeLogStitchMetrics.gapMd),
      child: DecoratedBox(
        decoration: OilChangeLogStitchMetrics.cardDecoration(selected: selected),
        child: Material(
          color: selected
              ? OilChangeLogStitchMetrics.secondaryContainer.withValues(alpha: 0.08)
              : OilChangeLogStitchMetrics.surfaceWhite,
          borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.cardRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'عميل' : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: OilChangeLogStitchMetrics.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.start,
                            ),
                            if (vehicle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                vehicle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: OilChangeLogStitchMetrics.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OilChangeLogStitchPlateBadge(plate: plate),
                    ],
                  ),
                  if (oilChip.isNotEmpty || (odoCurrent.isNotEmpty && odoCurrent != '—')) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (oilChip.isNotEmpty)
                          OilChangeLogStitchInfoChip(
                            icon: Icons.oil_barrel_outlined,
                            label: oilChip,
                          ),
                        if (odoCurrent.isNotEmpty && odoCurrent != '—')
                          OilChangeLogStitchInfoChip(
                            icon: Icons.speed_rounded,
                            label: '$odoCurrent كم',
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    color: OilChangeLogStitchMetrics.secondaryContainer
                        .withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: OilChangeLogStitchMetrics.textPrimary,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onDetail,
                        style: TextButton.styleFrom(
                          foregroundColor: OilChangeLogStitchMetrics.primaryContainer,
                          padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'التفاصيل',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            Icon(Icons.chevron_left_rounded, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (showSuspended && onResume != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.tonalIcon(
                        onPressed: onResume,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              OilChangeLogStitchMetrics.primaryContainer.withValues(alpha: 0.08),
                          foregroundColor: OilChangeLogStitchMetrics.primaryContainer,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('استكمال'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OilChangeLogStitchEmptyView extends StatelessWidget {
  const OilChangeLogStitchEmptyView({
    super.key,
    required this.searching,
    required this.showSuspended,
    required this.onNewCard,
  });

  final bool searching;
  final bool showSuspended;
  final VoidCallback onNewCard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: OilChangeLogStitchMetrics.secondaryContainer.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.oil_barrel_outlined,
                size: 44,
                color: OilChangeLogStitchMetrics.primaryContainer.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? 'لا توجد نتائج مطابقة للبحث.'
                  : (showSuspended
                      ? 'لا توجد فواتير معلّقة.'
                      : 'لا توجد بطاقات غيار زيت بعد.'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: OilChangeLogStitchMetrics.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'جرّب اسماً أو رقم لوحة مختلفاً.'
                  : (showSuspended
                      ? 'عند تعليق الفاتورة من بطاقة جديدة تظهر هنا — اضغط «استكمال» لإتمام البيع.'
                      : 'أنشئ أول بطاقة من الزر أعلاه.'),
              style: const TextStyle(
                color: OilChangeLogStitchMetrics.textMuted,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            if (!searching && !showSuspended) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNewCard,
                  style: FilledButton.styleFrom(
                    backgroundColor: OilChangeLogStitchMetrics.secondaryContainer,
                    foregroundColor: OilChangeLogStitchMetrics.onSecondaryContainer,
                    minimumSize: const Size.fromHeight(OilChangeLogStitchMetrics.actionHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(OilChangeLogStitchMetrics.pillRadius),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('بطاقة غيار زيت جديدة'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OilChangeLogStitchDesktopKpiRow extends StatelessWidget {
  const OilChangeLogStitchDesktopKpiRow({super.key, required this.stats});

  final OilChangeLogStitchTodayStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1100
            ? 4
            : (constraints.maxWidth >= 720 ? 2 : 1);
        final tiles = [
          _KpiTile(
            label: 'إجمالي الخدمات اليوم',
            value: '${stats.visitCount}',
            trailing: stats.visitCount > 0
                ? const _TrendBadge(label: 'اليوم', positive: true)
                : null,
          ),
          _KpiTile(
            label: 'إيرادات اليوم',
            value: '${stats.revenueLabel} د.ع',
            trailing: stats.visitCount > 0
                ? const _TrendBadge(label: 'اليوم', positive: true)
                : null,
          ),
          _KpiTile(
            label: 'الزيوت الأكثر طلباً',
            value: stats.topOilLabel,
            trailing: stats.topOilLabel != '—'
                ? Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: OilChangeLogStitchMetrics.secondaryContainer
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'الأعلى',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: OilChangeLogStitchMetrics.onSecondaryContainer,
                      ),
                    ),
                  )
                : null,
          ),
          _KpiTile(
            label: 'فواتير مُصدَّرة اليوم',
            value: '${stats.invoicedCount}',
            trailing: stats.invoicedCount > 0
                ? const Icon(Icons.receipt_long_rounded, color: OilChangeLogStitchMetrics.success)
                : const Icon(Icons.receipt_long_outlined, color: OilChangeLogStitchMetrics.outline),
          ),
        ];

        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: OilChangeLogStitchMetrics.gapMd,
          crossAxisSpacing: OilChangeLogStitchMetrics.gapMd,
          childAspectRatio: cols == 1 ? 3.2 : (cols >= 4 ? 1.95 : 2.2),
          children: tiles,
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
      decoration: OilChangeLogStitchMetrics.glassCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: OilChangeLogStitchMetrics.textMuted,
              height: 1.2,
            ),
            textAlign: TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: OilChangeLogStitchMetrics.textPrimary,
                    height: 1.15,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 14,
          color: positive ? OilChangeLogStitchMetrics.success : OilChangeLogStitchMetrics.error,
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: positive ? OilChangeLogStitchMetrics.success : OilChangeLogStitchMetrics.error,
          ),
        ),
      ],
    );
  }
}

class OilChangeLogStitchDesktopTableCard extends StatelessWidget {
  const OilChangeLogStitchDesktopTableCard({
    super.key,
    required this.rows,
    required this.highlightedId,
    required this.loadingMore,
    required this.loadedCount,
    required this.onRowTap,
    required this.onRowDetail,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rows;
  final int? highlightedId;
  final bool loadingMore;
  final int loadedCount;
  final void Function(Map<String, dynamic> row) onRowTap;
  final void Function(Map<String, dynamic> row) onRowDetail;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OilChangeLogStitchMetrics.panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'سجل عمليات تبديل الزيت الأخيرة',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: OilChangeLogStitchMetrics.textPrimary,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OilChangeLogStitchMetrics.textPrimary,
                    side: const BorderSide(color: OilChangeLogStitchMetrics.outline),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: OilChangeLogStitchMetrics.surfaceContainerHigh),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 960),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  OilChangeLogStitchMetrics.surfaceContainerLow,
                ),
                dataRowMinHeight: 52,
                dataRowMaxHeight: 56,
                columnSpacing: 16,
                horizontalMargin: 16,
                columns: const [
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('المركبة')),
                  DataColumn(label: Text('رقم اللوحة')),
                  DataColumn(label: Text('نوع الزيت')),
                  DataColumn(label: Text('المسافة الحالية (كم)')),
                  DataColumn(label: Text('السعر')),
                  DataColumn(label: Text('إجراءات')),
                ],
                rows: [
                  for (final r in rows)
                    _buildRow(context, r),
                ],
              ),
            ),
          ),
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
            color: OilChangeLogStitchMetrics.surfaceContainerLow,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows.isEmpty
                        ? 'لا توجد عمليات'
                        : 'عرض ${rows.length} من أصل $loadedCount+ عملية',
                    style: const TextStyle(
                      fontSize: 12,
                      color: OilChangeLogStitchMetrics.textMuted,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(BuildContext context, Map<String, dynamic> r) {
    final id = (r['id'] as num?)?.toInt();
    final selected = id != null && id == highlightedId;
    final oilLabel = oilFormatOilChip(r);
    final accent = oilTypeAccentColor(oilLabel);

    return DataRow(
      selected: selected,
      onSelectChanged: (_) => onRowTap(r),
      cells: [
        DataCell(
          Text(
            oilFormatLogDateTime((r['createdAt'] ?? '').toString()),
            style: const TextStyle(
              fontSize: 12,
              color: OilChangeLogStitchMetrics.textMuted,
            ),
          ),
        ),
        DataCell(
          Text(
            (r['customerNameSnapshot'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(Text(oilFormatVehicleLine(r))),
        DataCell(OilChangeLogStitchPlateBadge(plate: oilFormatPlate(r))),
        DataCell(
          Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(oilLabel.isEmpty ? '—' : oilLabel)),
            ],
          ),
        ),
        DataCell(
          Text(
            oilFormatOdo((r['odometerCurrent'] ?? '').toString()),
            textDirection: TextDirection.ltr,
          ),
        ),
        DataCell(
          Text(
            oilFormatPrice(r),
            style: const TextStyle(fontWeight: FontWeight.w800),
            textDirection: TextDirection.ltr,
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'عرض التفاصيل',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => onRowDetail(r),
          ),
        ),
      ],
    );
  }
}

class OilChangeLogStitchLogPanelHeader extends StatelessWidget {
  const OilChangeLogStitchLogPanelHeader({
    super.key,
    required this.showSuspended,
    required this.mobile,
    this.showHint = true,
  });

  final bool showSuspended;
  final bool mobile;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: OilChangeLogStitchMetrics.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: OilChangeLogStitchMetrics.secondaryContainer
                .withValues(alpha: 0.40),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_rounded,
            size: 20,
            color: OilChangeLogStitchMetrics.primaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            showSuspended ? 'فواتير معلّقة' : 'سجل الغيارات',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              color: OilChangeLogStitchMetrics.textPrimary,
            ),
            textAlign: TextAlign.start,
          ),
          if (showHint && !mobile) ...[
            const Spacer(),
            Flexible(
              child: Text(
                showSuspended
                    ? 'اضغط على الصف لاستكمال البيع'
                    : 'اضغط على الصف لبطاقة جديدة بنفس البيانات',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: OilChangeLogStitchMetrics.textMuted,
                ),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
