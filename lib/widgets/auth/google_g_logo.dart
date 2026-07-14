import 'package:flutter/material.dart';

/// شعار Google «G» الرسمي (ألوان العلامة التجارية).
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 20});

  final double size;

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleGLogoPainter(
          blue: _blue,
          red: _red,
          yellow: _yellow,
          green: _green,
        ),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  _GoogleGLogoPainter({
    required this.blue,
    required this.red,
    required this.yellow,
    required this.green,
  });

  final Color blue;
  final Color red;
  final Color yellow;
  final Color green;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.18;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    void drawArc(Color color, double start, double sweep) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        arcPaint..color = color,
      );
    }

    drawArc(blue, -0.55 * 3.1415926535, 1.05 * 3.1415926535);
    drawArc(green, 0.50 * 3.1415926535, 0.55 * 3.1415926535);
    drawArc(yellow, 1.05 * 3.1415926535, 0.55 * 3.1415926535);
    drawArc(red, 1.60 * 3.1415926535, 0.55 * 3.1415926535);

    final bar = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.44, w * 0.42, stroke),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
