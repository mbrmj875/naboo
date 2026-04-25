import 'dart:math';
import 'package:flutter/material.dart';

class CurvedMovingText extends StatefulWidget {
  final String text;
  final Duration duration;
  final TextStyle textStyle;
  final Curve curve; // Bezier curve for the path shape

  const CurvedMovingText({
    super.key,
    required this.text,
    this.duration = const Duration(seconds: 3),
    this.textStyle = const TextStyle(fontSize: 24, color: Colors.white),
    this.curve = Curves.easeInOutCubic,
  });

  @override
  State<CurvedMovingText> createState() => _CurvedMovingTextState();
}

class _CurvedMovingTextState extends State<CurvedMovingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  // Define a cubic Bézier path: start (left off-screen), end (center), with two control points for a nice curve
  Offset _getPosition(double t, Size screenSize) {
    // Start point: just left of screen, at 1/3 height
    final start = Offset(-screenSize.width * 0.5, screenSize.height * 0.3);
    // End point: center horizontally, slightly above center
    final end = Offset(screenSize.width * 0.5, screenSize.height * 0.45);
    // Control points to create a smooth curve
    final cp1 = Offset(screenSize.width * 0.2, screenSize.height * 0.2);
    final cp2 = Offset(screenSize.width * 0.4, screenSize.height * 0.6);

    // Cubic Bézier formula
    final x = pow(1 - t, 3) * start.dx +
        3 * pow(1 - t, 2) * t * cp1.dx +
        3 * (1 - t) * pow(t, 2) * cp2.dx +
        pow(t, 3) * end.dx;
    final y = pow(1 - t, 3) * start.dy +
        3 * pow(1 - t, 2) * t * cp1.dy +
        3 * (1 - t) * pow(t, 2) * cp2.dy +
        pow(t, 3) * end.dy;
    return Offset(x, y);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = _controller.drive(CurveTween(curve: widget.curve));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final screenSize = MediaQuery.of(context).size;
        final position = _getPosition(_animation.value, screenSize);
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: Opacity(
            opacity: 1.0 - _animation.value * 0.5, // fade slightly
            child: Text(widget.text, style: widget.textStyle),
          ),
        );
      },
    );
  }
}