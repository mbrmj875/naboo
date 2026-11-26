import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ما يفعله المساعد الآن (ط3، ط7): لكل حالة أيقونة متحركة مرسومة بالكود، بلا ملفات.
enum AssistantActivity { thinking, searching, writing, done }

/// أيقونة متحركة لحالة المساعد. مع «تقليل الحركة» تبقى ساكنة (ق17).
class AssistantActivityIcon extends StatefulWidget {
  const AssistantActivityIcon(this.activity, {super.key, this.size = 22});

  final AssistantActivity activity;
  final double size;

  @override
  State<AssistantActivityIcon> createState() => _AssistantActivityIconState();
}

class _AssistantActivityIconState extends State<AssistantActivityIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period(widget.activity),
  );

  static Duration _period(AssistantActivity a) => switch (a) {
    AssistantActivity.thinking => const Duration(milliseconds: 1100),
    AssistantActivity.searching => const Duration(milliseconds: 1400),
    AssistantActivity.writing => const Duration(milliseconds: 900),
    AssistantActivity.done => const Duration(milliseconds: 450),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AssistantActivityIcon old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) {
      _c.duration = _period(widget.activity);
      _c.reset();
      _sync();
    }
  }

  void _sync() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = widget.activity == AssistantActivity.done ? 1 : 0.25;
      _c.stop();
      return;
    }
    if (widget.activity == AssistantActivity.done) {
      if (_c.value < 1 && !_c.isAnimating) _c.forward();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.brightness == Brightness.dark ? cs.secondary : cs.primary;
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            switch (widget.activity) {
              case AssistantActivity.thinking:
                return CustomPaint(
                  painter: _SpinnerPainter(t, accent, cs.secondary),
                );
              case AssistantActivity.searching:
                final a = t * 2 * math.pi;
                return Transform.translate(
                  offset: Offset(
                    math.cos(a) * s * 0.14,
                    math.sin(a) * s * 0.14,
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    size: s * 0.82,
                    color: accent,
                  ),
                );
              case AssistantActivity.writing:
                final w = math.sin(t * 2 * math.pi);
                return Transform.translate(
                  offset: Offset(w * s * 0.12, -w.abs() * s * 0.06),
                  child: Transform.rotate(
                    angle: w * 0.18,
                    child: Icon(
                      Icons.edit_rounded,
                      size: s * 0.8,
                      color: accent,
                    ),
                  ),
                );
              case AssistantActivity.done:
                return CustomPaint(
                  painter: _CheckPainter(Curves.easeOut.transform(t), accent),
                );
            }
          },
        ),
      ),
    );
  }
}

/// حلقة تدور بذيل متدرّج ونقطة تنبض في الوسط: «يفكر».
class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.t, this.color, this.dot);
  final double t;
  final Color color;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(c, r, track);
    final start = t * 2 * math.pi;
    final sweep = math.pi * (0.55 + 0.35 * math.sin(t * 2 * math.pi).abs());
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [color.withValues(alpha: 0.1), color],
        transform: GradientRotation(start - 0.01),
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, arc);
    final pulse = 0.18 + 0.08 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(c, size.shortestSide * pulse, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.t != t || old.color != color;
}

/// علامة صح تُرسم من البداية للنهاية: «تم».
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawCircle(
      size.center(Offset.zero),
      w / 2 - 1,
      Paint()..color = color.withValues(alpha: 0.14 * t),
    );
    final path = Path()
      ..moveTo(w * 0.27, h * 0.52)
      ..lineTo(w * 0.44, h * 0.68)
      ..lineTo(w * 0.74, h * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// سطر الحالة الحي: أيقونة متحركة ونص «أفكّر…» بنقاط تتتابع.
class AssistantActivityLine extends StatelessWidget {
  const AssistantActivityLine({
    super.key,
    required this.activity,
    required this.text,
  });

  final AssistantActivity activity;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: text,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AssistantActivityIcon(activity),
            const SizedBox(width: 10),
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  text,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
