import 'package:flutter/material.dart';

/// رسم اتجاه المبيعات — بدون dependency إضافية.
class OwnerSparkline extends StatelessWidget {
  const OwnerSparkline({
    super.key,
    required this.valuesFils,
    this.height = 48,
    this.lineColor,
  });

  final List<int> valuesFils;
  final double height;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final color = lineColor ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'اتجاه المبيعات آخر 7 أيام',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(values: valuesFils, color: color),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(1, 1 << 62).toDouble();

    final stepX = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    final points = <Offset>[];

    for (var i = 0; i < values.length; i++) {
      final x = stepX * i;
      final norm = (values[i] - minVal) / range;
      final y = size.height - (norm * (size.height - 4)) - 2;
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);

      final fill = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      canvas.drawPath(fill, fillPaint);
    } else if (points.length == 1) {
      canvas.drawCircle(points.first, 3, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
