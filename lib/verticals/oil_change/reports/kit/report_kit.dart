import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/app_corner_style.dart';
import '../../../../utils/iraqi_currency_format.dart';
import '../../../../utils/screen_layout.dart';
import 'report_math.dart';

/// ألوان التقارير: لكل نشاط لون واحد يتكرر في مؤشراته ومخططاته.
abstract final class ReportAccents {
  static const oil = Color(0xFF2563EB);
  static const directSale = Color(0xFF7C3AED);
  static const carWash = Color(0xFF0D9488);
  static const products = Color(0xFFEA580C);
  static const positive = Color(0xFF059669);
  static const negative = Color(0xFFDC2626);
}

String reportMoney(int fils) => IraqiCurrencyFormat.formatIqd(fils / 1000.0);

String reportNumber(num v) => IraqiCurrencyFormat.formatInt(v);

/// عدد قد يكون كسراً (متوسط يومي): لا يُقرَّب 0.3 إلى صفر.
String reportCount(double v, String unit) {
  if (v == 0) return '0 $unit';
  if (v < 0.1) return 'أقل من 0.1 $unit';
  if (v < 10 && v != v.roundToDouble()) {
    return '${v.toStringAsFixed(1)} $unit';
  }
  return '${reportNumber(v.round())} $unit';
}

/// مبلغ مختصر للمحاور والحلقات (1.5M د.ع).
String reportMoneyCompact(int fils) =>
    IraqiCurrencyFormat.formatCompactWarehouseValue(fils / 1000.0);

/// صفحة تقرير: مقدمة، ثم المحتوى، ثم ملاحظات الدقة.
/// حدود التخطيط المشتركة بين التقارير.
abstract final class ReportLayout {
  /// أقصى عرض للمحتوى؛ أعرض من ذلك تصير الأسطر والمخططات صعبة القراءة.
  static const double maxWidth = 1440;

  /// تحت هذا العرض تُرصّ البطاقات المزدوجة فوق بعض.
  static const double twoUpMin = 720;
}

class ReportPage extends StatelessWidget {
  const ReportPage({
    super.key,
    required this.intro,
    required this.children,
    this.accuracyNotes = const [],
  });

  final String intro;
  final List<Widget> children;
  final List<String> accuracyNotes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(gap, 8, gap, 28),
      // على الشاشات الكبيرة جداً تبقى الصفحة بعرض مقروء في المنتصف.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ReportLayout.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                intro,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                children[i],
              ],
              if (accuracyNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                ReportAccuracyNote(lines: accuracyNotes),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReportKpiGrid extends StatelessWidget {
  const ReportKpiGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // 4 أعمدة متى اتسع كل عمود لـ 200 بكسل، وإلا عمودان، وعمود واحد
        // على الشاشات الضيقة جداً حتى لا تُضغط الأرقام الكبيرة.
        final cols = c.maxWidth >= 4 * 200 + 30
            ? 4
            : c.maxWidth >= 300
            ? 2
            : 1;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// مؤشر رئيسي مع مقارنة بالفترة السابقة.
class ReportKpi extends StatelessWidget {
  const ReportKpi({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.metric,
    this.higherIsBetter = true,
    this.caption,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final ReportMetric? metric;
  final bool higherIsBetter;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = metric?.changePct;
    Widget? delta;
    if (pct != null && pct.isFinite) {
      final up = pct >= 0;
      final good = up == higherIsBetter;
      final color = pct.abs() < 0.5
          ? cs.onSurfaceVariant
          : (good ? ReportAccents.positive : ReportAccents.negative);
      delta = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 13,
            color: color,
          ),
          Text(
            '${pct.abs().toStringAsFixed(0)}%',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'عن الفترة السابقة',
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (metric != null) {
      delta = Text(
        'لا بيانات في الفترة السابقة',
        style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.appCorners.md,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
          if (delta != null) ...[const SizedBox(height: 4), delta],
        ],
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.title,
    required this.child,
    required this.accent,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.appCorners.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// بطاقتان جنباً إلى جنب على الشاشات العريضة، وفوق بعض على الهاتف.
class ReportTwoUp extends StatelessWidget {
  const ReportTwoUp({super.key, required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < ReportLayout.twoUpMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 14), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      'لا بيانات في هذه الفترة',
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// مخطط أعمدة يومي: محور، خطوط شبكة، خط المتوسط، ولمس العمود يعرض قيمته.
class ReportDailyChart extends StatefulWidget {
  const ReportDailyChart({
    super.key,
    required this.points,
    required this.accent,
    required this.valueOf,
    required this.format,
  });

  final List<ReportDayPoint> points;
  final Color accent;
  final double Function(ReportDayPoint) valueOf;
  final String Function(double) format;

  @override
  State<ReportDailyChart> createState() => _ReportDailyChartState();
}

class _ReportDailyChartState extends State<ReportDailyChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final values = pts.map(widget.valueOf).toList();
    if (pts.isEmpty || values.every((v) => v <= 0)) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final active = values.where((v) => v > 0).length;
    final total = values.fold<double>(0, (a, b) => a + b);
    final avg = total / values.length;
    final sel = _selected;
    final p = sel == null ? null : pts[sel];
    final header = p == null
        ? 'المتوسط اليومي ${widget.format(avg)} · أيام بحركة $active من ${pts.length}'
        : '${p.day.day}/${p.day.month} · ${widget.format(values[sel!])}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          header,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: p == null ? cs.onSurfaceVariant : widget.accent,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: LayoutBuilder(
            builder: (context, c) {
              int? hit(Offset o) {
                final x = rtl ? c.maxWidth - o.dx : o.dx;
                final i = (x / c.maxWidth * pts.length).floor();
                return i.clamp(0, pts.length - 1);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setState(() {
                  final i = hit(d.localPosition);
                  _selected = _selected == i ? null : i;
                }),
                onHorizontalDragUpdate: (d) =>
                    setState(() => _selected = hit(d.localPosition)),
                child: CustomPaint(
                  size: Size(c.maxWidth, 170),
                  painter: _DailyBarsPainter(
                    values: values,
                    labels: [
                      for (final q in pts) '${q.day.day}/${q.day.month}',
                    ],
                    accent: widget.accent,
                    grid: cs.outlineVariant.withValues(alpha: 0.5),
                    text: cs.onSurfaceVariant,
                    average: avg,
                    selected: sel,
                    rtl: rtl,
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  _DailyBarsPainter({
    required this.values,
    required this.labels,
    required this.accent,
    required this.grid,
    required this.text,
    required this.average,
    required this.selected,
    required this.rtl,
    this.fontFamily,
  });

  /// خط التطبيق — الرسام لا يرث النمط من الشجرة.
  final String? fontFamily;
  final List<double> values;
  final List<String> labels;
  final Color accent;
  final Color grid;
  final Color text;
  final double average;
  final int? selected;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    final chartH = size.height - bottom;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = chartH - chartH * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final n = values.length;
    final slot = size.width / n;
    final barW = math.max(2.0, math.min(22.0, slot * 0.68));
    double xOf(int i) {
      final x = slot * i + slot / 2;
      return rtl ? size.width - x : x;
    }

    for (var i = 0; i < n; i++) {
      final h = values[i] / maxV * (chartH - 6);
      if (h <= 0) continue;
      final isSel = selected == i;
      final paint = Paint()
        ..color = accent.withValues(
          alpha: selected == null || isSel ? 0.9 : 0.35,
        );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(xOf(i) - barW / 2, chartH - h, barW, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        paint,
      );
    }

    // خط المتوسط المتقطع.
    final avgY = chartH - average / maxV * (chartH - 6);
    final dash = Paint()
      ..color = text.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, avgY), Offset(x + 4, avgY), dash);
    }

    // تسميات قليلة على المحور حتى لا تتزاحم.
    final step = math.max(1, (n / 7).ceil());
    for (var i = 0; i < n; i += step) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(fontSize: 9.5, color: text, fontFamily: fontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (xOf(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _DailyBarsPainter old) =>
      old.values != values || old.selected != selected || old.accent != accent;
}

class ReportSlice {
  const ReportSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// حلقة نسب مع مفتاح يذكر القيمة والنسبة.
class ReportDonut extends StatelessWidget {
  const ReportDonut({
    super.key,
    required this.slices,
    required this.format,
    this.centerLabel,
  });

  final List<ReportSlice> slices;
  final String Function(double) format;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 118,
          height: 118,
          child: CustomPaint(
            painter: _DonutPainter(slices, total, cs.surfaceContainerHighest),
            child: Center(
              child: Text(
                centerLabel ?? format(total),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // الاسم فوق القيمة حتى لا يضيق السطر على الهاتف.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              style: const TextStyle(fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${format(s.value)} · ${(s.value / total * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.total, this.track);
  final List<ReportSlice> slices;
  final double total;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(10);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16,
    );
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = s.value / total * math.pi * 2;
      // فاصل صغير بين الشرائح لتبقى قابلة للتمييز دون الاعتماد على اللون.
      final gap = slices.length > 1 ? 0.03 : 0.0;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.0, sweep - gap),
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total;
}

/// أعمدة أفقية مرتبة: الاسم، العمود، القيمة، ونص إضافي.
class ReportRankBars extends StatelessWidget {
  const ReportRankBars({
    super.key,
    required this.rows,
    required this.accent,
    this.limit = 8,
  });

  /// (الاسم، القيمة التي يُرسم بها العمود، النص الظاهر).
  final List<(String, double, String)> rows;
  final Color accent;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final maxV = rows.fold<double>(0, (a, b) => math.max(a, b.$2));
    return Column(
      children: [
        for (final r in rows.take(limit))
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      r.$3,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxV <= 0 ? 0 : (r.$2 / maxV).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// باريتو: أعمدة القيمة مرتبة، وخط النسبة التراكمية، وخط 80%.
class ReportParetoChart extends StatelessWidget {
  const ReportParetoChart({
    super.key,
    required this.rows,
    required this.accent,
    this.limit = 12,
  });

  final List<ReportRankRow> rows;
  final Color accent;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final list = rows.where((r) => r.amountFils > 0).toList();
    if (list.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final total = list.fold<int>(0, (a, b) => a + b.amountFils);
    var running = 0;
    var top80 = 0;
    for (final r in list) {
      running += r.amountFils;
      top80++;
      if (running >= total * 0.8) break;
    }
    final shown = list.take(limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$top80 من ${list.length} صنفاً تصنع 80% من الإيراد',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: CustomPaint(
            size: const Size(double.infinity, 160),
            painter: _ParetoPainter(
              values: [for (final r in shown) r.amountFils.toDouble()],
              total: total.toDouble(),
              accent: accent,
              line: cs.onSurface,
              grid: cs.outlineVariant.withValues(alpha: 0.5),
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (var i = 0; i < shown.length; i++)
              Text(
                '${i + 1}. ${shown[i].label}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

class _ParetoPainter extends CustomPainter {
  _ParetoPainter({
    required this.values,
    required this.total,
    required this.accent,
    required this.line,
    required this.grid,
    required this.rtl,
  });

  final List<double> values;
  final double total;
  final Color accent;
  final Color line;
  final Color grid;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || total <= 0) return;
    final h = size.height;
    final slot = size.width / values.length;
    double xOf(int i) {
      final x = slot * i + slot / 2;
      return rtl ? size.width - x : x;
    }

    // خط 80%.
    final y80 = h - h * 0.8;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y80), Offset(x + 3.5, y80), g);
    }

    final barW = math.min(26.0, slot * 0.6);
    for (var i = 0; i < values.length; i++) {
      // العمود والخط على المحور نفسه (نسبة من الإجمالي)، فرأس العمود الأول
      // يلتقي بأول نقطة على الخط.
      final bh = values[i] / total * h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(xOf(i) - barW / 2, h - bh, barW, bh),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = accent.withValues(alpha: 0.75),
      );
    }

    final path = Path();
    var cum = 0.0;
    for (var i = 0; i < values.length; i++) {
      cum += values[i];
      final p = Offset(xOf(i), h - cum / total * h);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 2.6, Paint()..color = line);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _ParetoPainter old) =>
      old.values != values || old.total != total;
}

/// خريطة حرارية: أيام الأسبوع × الساعات، تُظهر أوقات الذروة.
class ReportHeatmap extends StatelessWidget {
  const ReportHeatmap({super.key, required this.grid, required this.accent});

  /// 7 صفوف (السبت…الجمعة) × 24 ساعة.
  final List<List<int>> grid;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var maxV = 0;
    var firstHour = 24;
    var lastHour = -1;
    for (final row in grid) {
      for (var h = 0; h < 24; h++) {
        if (row[h] > 0) {
          maxV = math.max(maxV, row[h]);
          firstHour = math.min(firstHour, h);
          lastHour = math.max(lastHour, h);
        }
      }
    }
    if (maxV == 0) return const _Empty();
    final hours = [for (var h = firstHour; h <= lastHour; h++) h];

    var peakDay = 0;
    var peakHour = firstHour;
    for (var d = 0; d < 7; d++) {
      for (final h in hours) {
        if (grid[d][h] > grid[peakDay][peakHour]) {
          peakDay = d;
          peakHour = h;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الذروة: ${ReportMath.weekdayLabels[peakDay]} الساعة $peakHour:00 '
          '(${grid[peakDay][peakHour]})',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            const labelW = 58.0;
            final cell = math.min(
              28.0,
              (c.maxWidth - labelW) / hours.length - 2,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var d = 0; d < 7; d++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: labelW,
                            child: Text(
                              ReportMath.weekdayLabels[d],
                              style: const TextStyle(fontSize: 10.5),
                            ),
                          ),
                          for (final h in hours)
                            Tooltip(
                              message:
                                  '${ReportMath.weekdayLabels[d]} $h:00 — ${grid[d][h]}',
                              child: Container(
                                width: math.max(10.0, cell),
                                height: 18,
                                margin: const EdgeInsetsDirectional.only(
                                  end: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: grid[d][h] == 0
                                      ? cs.surfaceContainerHighest
                                      : accent.withValues(
                                          alpha:
                                              0.18 + 0.82 * grid[d][h] / maxV,
                                        ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      const SizedBox(width: labelW),
                      for (final h in hours)
                        SizedBox(
                          width: math.max(10.0, cell) + 2,
                          child: Text(
                            h % 2 == 0 ? '$h' : '',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// جدول بسيط بعناوين، يتمرر أفقياً على الهاتف.
/// جدول تفصيلي: يملأ العرض على الشاشات الواسعة، ويُسحب أفقياً على الضيقة
/// مع تنبيه بوجود أعمدة مخفية، ويعرض أول [pageRows] صفاً مع زر لعرض البقية.
class ReportTable extends StatefulWidget {
  const ReportTable({
    super.key,
    required this.headers,
    required this.rows,
    this.pageRows = 10,
    this.textColumns = const {0},
  });

  final List<String> headers;
  final List<List<String>> rows;
  final int pageRows;

  /// أعمدة النص؛ البقية أرقام تُحاذى لنهاية الخلية بأرقام متساوية العرض.
  final Set<int> textColumns;

  @override
  State<ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<ReportTable> {
  final _scroll = ScrollController();
  bool _expanded = false;
  bool _hasHidden = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final hidden = p.maxScrollExtent - p.pixels > 4;
    if (hidden != _hasHidden) setState(() => _hasHidden = hidden);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final limit = _expanded ? rows.length : widget.pageRows;
    final shown = rows.take(limit).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: DataTable(
                    headingRowHeight: 38,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 44,
                    columnSpacing: 18,
                    horizontalMargin: 10,
                    headingRowColor: WidgetStateProperty.all(
                      cs.surfaceContainerHighest,
                    ),
                    columns: [
                      for (var i = 0; i < widget.headers.length; i++)
                        DataColumn(
                          numeric: !widget.textColumns.contains(i),
                          label: Text(
                            widget.headers[i],
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                    rows: [
                      for (final r in shown)
                        DataRow(
                          cells: [
                            for (var i = 0; i < r.length; i++)
                              DataCell(
                                Text(
                                  r[i],
                                  style: !widget.textColumns.contains(i)
                                      ? const TextStyle(
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              // تظليل عند الطرف يدل على أعمدة خارج الشاشة.
              if (_hasHidden)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [cs.surface.withValues(alpha: 0), cs.surface],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_hasHidden || rows.length > widget.pageRows)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                if (_hasHidden)
                  Text(
                    'اسحب الجدول جانباً لرؤية بقية الأعمدة',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                if (rows.length > widget.pageRows)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? 'عرض أقل' : 'عرض الكل (${rows.length})',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ملاحظات تشرح مصدر الأرقام وحدود دقتها.
class ReportAccuracyNote extends StatelessWidget {
  const ReportAccuracyNote({super.key, required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: context.appCorners.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              const Text(
                'كيف تُحسب الأرقام',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $l',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// نص تغطية التكلفة لملاحظات الدقة.
/// نص الهامش تحت بطاقة الربح؛ ينبّه إن نقصت تكلفة بعض السطور فصار الربح أعلى من حقيقته.
String? reportMarginCaption(double? marginPct, ReportCostCoverage c) {
  if (marginPct == null) return null;
  final m = 'هامش ${marginPct.toStringAsFixed(1)}%';
  if (c.missing == 0) return m;
  return '$m تقديري · ${c.missing} بلا تكلفة';
}

String? reportCostCoverageNote(ReportCostCoverage c) {
  if (c.total == 0) return null;
  if (c.isExact) return 'تكلفة كل السطور (${c.total}) مثبّتة لحظة البيع.';
  if (c.missing == 0 && c.stamped == 0) {
    return 'التكلفة بسعر الشراء الحالي لكل البنود (${c.total}).';
  }
  final parts = <String>[];
  if (c.fallback > 0) {
    parts.add('${c.fallback} بسعر الشراء الحالي');
  }
  if (c.missing > 0)
    parts.add('${c.missing} بلا تكلفة معروفة (حُسب ربحها كاملاً)');
  return 'الربح تقديري جزئياً: ${parts.join('، ')} من ${c.total}.';
}

/// شريط أفقي مكدّس لكل صف: يبيّن من أي قناة جاء كل جزء.
class ReportStackedBars extends StatelessWidget {
  const ReportStackedBars({
    super.key,
    required this.rows,
    required this.legend,
    this.limit = 8,
  });

  /// (الاسم، الأجزاء بترتيب [legend]، النص الظاهر).
  final List<(String, List<double>, String)> rows;
  final List<(String, Color)> legend;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    final maxV = rows.fold<double>(
      0,
      (a, r) => math.max(a, r.$2.fold<double>(0, (x, y) => x + math.max(0, y))),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final l in legend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: l.$2,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(l.$1, style: const TextStyle(fontSize: 11.5)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in rows.take(limit))
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      r.$3,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, c) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 10,
                      color: cs.surfaceContainerHighest,
                      child: Row(
                        children: [
                          for (var i = 0; i < r.$2.length; i++)
                            if (r.$2[i] > 0 && maxV > 0)
                              Container(
                                width: c.maxWidth * r.$2[i] / maxV,
                                color: legend[i].$2,
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// أيام تغطية المخزون: كم يوماً يكفي كل صنف، مع حدّي الخطر والانتباه.
class ReportCoverBars extends StatelessWidget {
  const ReportCoverBars({
    super.key,
    required this.rows,
    this.danger = 7,
    this.warn = 14,
    this.cap = 60,
    this.limit = 10,
  });

  /// (الاسم، الأيام).
  final List<(String, double)> rows;
  final double danger;
  final double warn;
  final double cap;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _Empty();
    final cs = Theme.of(context).colorScheme;
    Color colorOf(double d) => d <= danger
        ? ReportAccents.negative
        : d <= warn
        ? const Color(0xFFF59E0B)
        : ReportAccents.positive;
    return Column(
      children: [
        for (final r in rows.take(limit))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    r.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 12,
                          width: c.maxWidth * (r.$2.clamp(0, cap) / cap),
                          decoration: BoxDecoration(
                            color: colorOf(r.$2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // علامتا حدّي الخطر والانتباه.
                        for (final t in [danger, warn])
                          PositionedDirectional(
                            start: c.maxWidth * t / cap,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 1.5, color: cs.onSurface),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 54,
                  child: Text(
                    r.$2 < 0.5
                        ? 'نفد'
                        : r.$2 >= cap
                        ? '+${cap.round()} يوم'
                        : '${r.$2.round()} يوم',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: colorOf(r.$2),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
