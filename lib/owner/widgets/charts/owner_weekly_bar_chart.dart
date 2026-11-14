import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../theme/design_tokens.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import 'owner_chart_models.dart';

/// يوم واحد على محور «آخر 7 أيام» — من الأقدم إلى الأحدث.
@immutable
class OwnerBarChartDay {
  const OwnerBarChartDay({
    required this.date,
    required this.weekdayLabel,
    required this.dateLabel,
  });

  final DateTime date;
  final String weekdayLabel;
  final String dateLabel;

  String get axisPrimary => weekdayLabel;

  String get axisSecondary => dateLabel;

  String get tooltipTitle => '$weekdayLabel · $dateLabel';
}

/// أعمدة مبيعات آخر 7 أيام — محور زمني LTR، أسماء أيام كاملة، ملء الارتفاع.
class OwnerWeeklyBarChart extends StatefulWidget {
  const OwnerWeeklyBarChart({
    super.key,
    required this.valuesFils,
    this.height = kOwnerAnalyticsChartPlotSize,
    this.fillAvailableHeight = false,
  });

  final List<int> valuesFils;

  /// ارتفاع منطقة الرسم عند عدم [fillAvailableHeight].
  final double height;

  /// يملأ ارتفاع البطاقة (مع تسميات محورية ثابتة في الأسفل).
  final bool fillAvailableHeight;

  @override
  State<OwnerWeeklyBarChart> createState() => _OwnerWeeklyBarChartState();

  static List<OwnerBarChartDay> buildLastSevenDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekdayFmt = DateFormat('EEEE', 'ar_SA');
    final dateFmt = DateFormat('d/M', 'ar_SA');
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return OwnerBarChartDay(
        date: d,
        weekdayLabel: weekdayFmt.format(d),
        dateLabel: dateFmt.format(d),
      );
    });
  }
}

class _OwnerWeeklyBarChartState extends State<OwnerWeeklyBarChart> {
  static const _axisRowHeight = 52.0;
  static const _summaryHeight = 24.0;

  int? _selectedDayIndex;
  int? _hoveredDayIndex;

  List<int> get _values {
    if (widget.valuesFils.length >= 7) {
      return widget.valuesFils.sublist(widget.valuesFils.length - 7);
    }
    return [
      ...List.filled(7 - widget.valuesFils.length, 0),
      ...widget.valuesFils,
    ];
  }

  List<OwnerBarChartDay> get _days => OwnerWeeklyBarChart.buildLastSevenDays();

  int? get _activeIndex => _hoveredDayIndex ?? _selectedDayIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final values = _values;
    final days = _days;
    final dayColors = _dayBarPalette(cs);
    final active = _activeIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final plotHeight = widget.fillAvailableHeight && bounded
            ? math.max(
                kOwnerAnalyticsChartPlotSize,
                constraints.maxHeight - _axisRowHeight - _summaryHeight,
              )
            : widget.height;

        final plot = _BarPlotLayer(
          height: plotHeight,
          valuesFils: values,
          days: days,
          dayColors: dayColors,
          selectedColor: cs.primary,
          activeIndex: active,
          selectedIndex: _selectedDayIndex,
          onDayHover: (i) => setState(() => _hoveredDayIndex = i),
          onDayExit: (i) {
            if (_hoveredDayIndex == i) {
              setState(() => _hoveredDayIndex = null);
            }
          },
          onDayTap: (i) {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedDayIndex = _selectedDayIndex == i ? null : i;
            });
          },
        );

        final axis = _AxisLabelRow(
          days: days,
          dayColors: dayColors,
          selectedIndex: _selectedDayIndex,
          hoveredIndex: _hoveredDayIndex,
          scheme: cs,
        );

        final summary = SizedBox(
          height: _summaryHeight,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: _ChartSummaryLabel(
              valuesFils: values,
              days: days,
              selectedDayIndex: _selectedDayIndex,
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            plot,
            SizedBox(height: _axisRowHeight, child: axis),
            summary,
          ],
        );
      },
    );
  }

  static List<Color> _dayBarPalette(ColorScheme cs) {
    return [
      const Color(0xFF5B5BD6),
      AppSemanticColors.success,
      AppSemanticColors.info,
      AppSemanticColors.warning,
      const Color(0xFF0D9488),
      AppSemanticColors.supplier,
      cs.tertiary,
    ];
  }
}

/// منطقة الرسم — محور زمني من اليسار لليمين (LTR) لمحاذاة الأعمدة مع التسميات.
class _BarPlotLayer extends StatelessWidget {
  const _BarPlotLayer({
    required this.height,
    required this.valuesFils,
    required this.days,
    required this.dayColors,
    required this.selectedColor,
    required this.activeIndex,
    required this.selectedIndex,
    required this.onDayHover,
    required this.onDayExit,
    required this.onDayTap,
  });

  final double height;
  final List<int> valuesFils;
  final List<OwnerBarChartDay> days;
  final List<Color> dayColors;
  final Color selectedColor;
  final int? activeIndex;
  final int? selectedIndex;
  final ValueChanged<int> onDayHover;
  final ValueChanged<int> onDayExit;
  final ValueChanged<int> onDayTap;

  @override
  Widget build(BuildContext context) {
    final gridColor = Theme.of(context)
        .colorScheme
        .outlineVariant
        .withValues(alpha: 0.35);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final active = activeIndex;
            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  size: size,
                  painter: _BarChartPainter(
                    valuesFils: valuesFils,
                    dayColors: dayColors,
                    selectedColor: selectedColor,
                    gridColor: gridColor,
                    highlightedIndex: active,
                    selectedIndex: selectedIndex,
                  ),
                ),
                for (var i = 0; i < 7; i++)
                  Positioned.fromRect(
                    rect: _barSlotRect(size, i),
                    child: MouseRegion(
                      onEnter: (_) => onDayHover(i),
                      onExit: (_) => onDayExit(i),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onDayTap(i),
                          splashColor: dayColors[i].withValues(alpha: 0.2),
                          highlightColor:
                              dayColors[i].withValues(alpha: 0.12),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                if (active != null &&
                    active >= 0 &&
                    active < 7 &&
                    valuesFils[active] > 0)
                  _BarValueTooltip(
                    anchor: _barTopCenter(size, active, valuesFils),
                    title: days[active].tooltipTitle,
                    amountLabel: IraqiCurrencyFormat.formatIqd(
                      IqdMoney.fromFils(valuesFils[active]),
                    ),
                    accent: selectedIndex == active
                        ? selectedColor
                        : dayColors[active % dayColors.length],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Rect _barSlotRect(Size size, int index) {
    const bars = 7;
    final slot = size.width / bars;
    return Rect.fromLTWH(slot * index, 0, slot, size.height);
  }

  static Offset _barTopCenter(Size size, int index, List<int> values) {
    const bars = 7;
    const chartTop = 6.0;
    const chartBottomPad = 2.0;
    final chartBottomY = size.height - chartBottomPad;
    final chartH = chartBottomY - chartTop;
    final maxVal = values.fold<int>(0, (m, v) => math.max(m, v));
    final v = index < values.length ? values[index] : 0;
    final barH = maxVal <= 0 ? 0.0 : (v / maxVal) * chartH;
    final slot = size.width / bars;
    final x = slot * index + slot / 2;
    final y = chartBottomY - barH - 48;
    return Offset(x, math.max(chartTop, y));
  }
}

class _AxisLabelRow extends StatelessWidget {
  const _AxisLabelRow({
    required this.days,
    required this.dayColors,
    required this.selectedIndex,
    required this.hoveredIndex,
    required this.scheme,
  });

  final List<OwnerBarChartDay> days;
  final List<Color> dayColors;
  final int? selectedIndex;
  final int? hoveredIndex;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(7, (i) {
          final d = days[i];
          final selected = selectedIndex == i;
          final hovered = hoveredIndex == i;
          final accent = selected
              ? scheme.primary
              : (hovered
                  ? dayColors[i % dayColors.length]
                  : scheme.onSurfaceVariant);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.axisPrimary,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.15,
                      fontWeight: (selected || hovered)
                          ? FontWeight.w800
                          : FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  Text(
                    d.axisSecondary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: accent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BarValueTooltip extends StatelessWidget {
  const _BarValueTooltip({
    required this.anchor,
    required this.title,
    required this.amountLabel,
    required this.accent,
  });

  final Offset anchor;
  final String title;
  final String amountLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const w = 148.0;

    return Positioned(
      left: (anchor.dx - w / 2).clamp(4.0, double.infinity),
      top: anchor.dy,
      width: w,
      child: Material(
        elevation: 3,
        shadowColor: Colors.black26,
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                amountLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartSummaryLabel extends StatelessWidget {
  const _ChartSummaryLabel({
    required this.valuesFils,
    required this.days,
    required this.selectedDayIndex,
  });

  final List<int> valuesFils;
  final List<OwnerBarChartDay> days;
  final int? selectedDayIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (valuesFils.isEmpty || valuesFils.every((v) => v <= 0)) {
      return Text(
        'لا مبيعات مسجّلة في آخر 7 أيام',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      );
    }

    if (selectedDayIndex != null &&
        selectedDayIndex! >= 0 &&
        selectedDayIndex! < valuesFils.length) {
      final v = valuesFils[selectedDayIndex!];
      final day = days[selectedDayIndex!];
      if (v <= 0) {
        return Text(
          '${day.weekdayLabel}: لا مبيعات',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        );
      }
      final amount =
          IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(v));
      return Text(
        '${day.weekdayLabel}: $amount',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      );
    }

    var maxI = 0;
    for (var i = 1; i < valuesFils.length; i++) {
      if (valuesFils[i] > valuesFils[maxI]) maxI = i;
    }
    final peak =
        IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(valuesFils[maxI]));
    return Text(
      'أعلى يوم (${days[maxI].weekdayLabel}): $peak',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.valuesFils,
    required this.dayColors,
    required this.selectedColor,
    required this.gridColor,
    this.highlightedIndex,
    this.selectedIndex,
  });

  final List<int> valuesFils;
  final List<Color> dayColors;
  final Color selectedColor;
  final Color gridColor;
  final int? highlightedIndex;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 7;
    final maxVal = valuesFils.fold<int>(0, (m, v) => math.max(m, v));
    const chartTop = 6.0;
    const chartBottomPad = 2.0;
    final chartBottomY = size.height - chartBottomPad;
    final chartH = chartBottomY - chartTop;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartTop + chartH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (maxVal <= 0) return;

    final slot = size.width / bars;
    final barW = slot * 0.48;

    for (var i = 0; i < bars; i++) {
      final v = i < valuesFils.length ? valuesFils[i] : 0;
      if (v <= 0) continue;
      final h = (v / maxVal) * chartH;
      final x = slot * i + (slot - barW) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartBottomY - h, barW, h),
        const Radius.circular(6),
      );

      final isSelected = selectedIndex == i;
      final isHighlighted = highlightedIndex == i;
      final hasFocus = highlightedIndex != null;
      final base = dayColors[i % dayColors.length];

      Color fill;
      if (isSelected) {
        fill = selectedColor;
      } else if (isHighlighted) {
        fill = Color.lerp(base, Colors.white, 0.12)!;
      } else if (hasFocus) {
        fill = base.withValues(alpha: 0.3);
      } else {
        fill = base.withValues(alpha: 0.9);
      }

      canvas.drawRRect(rect, Paint()..color = fill);

      if (isSelected || isHighlighted) {
        final stroke = Paint()
          ..color = isSelected ? selectedColor : base
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.5 : 1.5;
        canvas.drawRRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.valuesFils != valuesFils ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
