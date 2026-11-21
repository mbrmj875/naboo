import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'owner_chart_models.dart';

/// رسم دائري (دونات) — legend تفاعلي (S5b).
class OwnerDonutChart extends StatefulWidget {
  const OwnerDonutChart({
    super.key,
    required this.slices,
    this.size = kOwnerAnalyticsChartPlotSize,
    this.strokeWidth = 22,
    this.centerLabel,
    this.centerValue,
    this.fillAvailableHeight = false,
  });

  final List<OwnerChartSlice> slices;
  final double size;
  final double strokeWidth;
  final String? centerLabel;
  final String? centerValue;

  /// يملأ [kOwnerAnalyticsChartBodyHeight] مع وسيلة إيضاح قابلة للتمرير.
  final bool fillAvailableHeight;

  @override
  State<OwnerDonutChart> createState() => _OwnerDonutChartState();
}

class _OwnerDonutChartState extends State<OwnerDonutChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<double>(0, (s, e) => s + e.value);
    final legend = <({OwnerChartSlice slice, int index})>[];
    for (var i = 0; i < widget.slices.length; i++) {
      if (widget.slices[i].value > 0) {
        legend.add((slice: widget.slices[i], index: i));
      }
    }

    final donutPlot = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _DonutPainter(
              slices: widget.slices,
              strokeWidth: widget.strokeWidth,
              highlightedIndex: _selectedIndex,
            ),
          ),
          if (widget.centerValue != null)
            Padding(
              padding: EdgeInsets.all(widget.strokeWidth + 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.centerLabel != null)
                    Text(
                      widget.centerLabel!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    widget.centerValue!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final legendWidgets = legend.isEmpty
        ? const <Widget>[]
        : [
            const SizedBox(height: 14),
            ...legend.map((entry) {
            final s = entry.slice;
            final selected = _selectedIndex == entry.index;
            final pct = total <= 0 ? 0 : (100 * s.value / total).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      _selectedIndex =
                          selected ? null : entry.index;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color.withValues(
                              alpha: selected || _selectedIndex == null ? 1 : 0.35,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          ];

    if (widget.fillAvailableHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kOwnerAnalyticsChartPlotSize,
            child: Center(child: donutPlot),
          ),
          if (legendWidgets.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: legendWidgets,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        donutPlot,
        ...legendWidgets,
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.strokeWidth,
    this.highlightedIndex,
  });

  final List<OwnerChartSlice> slices;
  final double strokeWidth;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      final track = Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth,
            size.height - strokeWidth),
        0,
        math.pi * 2,
        false,
        track,
      );
      return;
    }

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      if (slice.value <= 0) continue;
      final sweep = (slice.value / total) * math.pi * 2;
      final dimmed = highlightedIndex != null && highlightedIndex != i;
      final paint = Paint()
        ..color = slice.color.withValues(alpha: dimmed ? 0.28 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.highlightedIndex != highlightedIndex;
  }
}
