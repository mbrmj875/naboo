import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'assistant_view_models.dart';

/// رمز «مساعد نابو» (ق17، م2-11).
///
/// معيّن بلون التطبيق الأساسي، وفي وسطه نجمة رباعية بالذهبي. الحالات الأربع:
/// ساكن، يستمع (حلقة)، يفكر (النجمة تدور)، يتكلم (النجمة تنبض). مع «تقليل
/// الحركة» يبقى ساكناً ويُميَّز الحال بالحلقة فقط.
class AssistantMark extends StatefulWidget {
  const AssistantMark({super.key, this.size = 28, this.state = AssistantMarkState.idle, this.animate = true});

  final double size;
  final AssistantMarkState state;

  /// الإطارات والاختبارات تطفئه لصورة ثابتة.
  final bool animate;

  @override
  State<AssistantMark> createState() => _AssistantMarkState();
}

class _AssistantMarkState extends State<AssistantMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _moving => widget.animate && widget.state != AssistantMarkState.idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AssistantMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_moving && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
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
    final label = switch (widget.state) {
      AssistantMarkState.idle => 'مساعد نابو',
      AssistantMarkState.listening => 'مساعد نابو يستمع',
      AssistantMarkState.thinking => 'مساعد نابو يفكر',
      AssistantMarkState.speaking => 'مساعد نابو يتكلم',
    };
    return Semantics(
      label: label,
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _MarkPainter(
              body: cs.brightness == Brightness.dark ? cs.surfaceContainerHighest : cs.primary,
              spark: cs.secondary,
              ring: cs.secondary,
              state: widget.state,
              t: _c.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.body, required this.spark, required this.ring, required this.state, required this.t});

  final Color body;
  final Color spark;
  final Color ring;
  final AssistantMarkState state;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // المعيّن.
    final d = r * (state == AssistantMarkState.listening ? 0.78 : 0.92);
    final diamond = Path()
      ..moveTo(c.dx, c.dy - d)
      ..lineTo(c.dx + d, c.dy)
      ..lineTo(c.dx, c.dy + d)
      ..lineTo(c.dx - d, c.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = body);

    // حلقة الاستماع.
    if (state == AssistantMarkState.listening) {
      final rr = r * (0.9 + 0.08 * math.sin(t * math.pi * 2));
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.08)
          ..color = ring,
      );
    }

    // النجمة الرباعية.
    var s = d * 0.62;
    var angle = 0.0;
    if (state == AssistantMarkState.thinking) angle = t * math.pi / 2;
    if (state == AssistantMarkState.speaking) s *= 0.85 + 0.2 * math.sin(t * math.pi * 4).abs();
    final w = s * 0.26;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final star = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(w * 0.35, -w * 0.35, s, 0)
      ..quadraticBezierTo(w * 0.35, w * 0.35, 0, s)
      ..quadraticBezierTo(-w * 0.35, w * 0.35, -s, 0)
      ..quadraticBezierTo(-w * 0.35, -w * 0.35, 0, -s)
      ..close();
    canvas.drawPath(star, Paint()..color = spark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.state != state || old.body != body || old.spark != spark;
}
