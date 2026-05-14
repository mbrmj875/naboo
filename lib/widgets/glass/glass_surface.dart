import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// سطح زجاجي خفيف للاستخدام في الحاويات الثابتة (مثل تسجيل الدخول/الحوارات).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.blurSigma = AppGlass.blurSigma,
    this.tintColor = AppGlass.surfaceTint,
    this.strokeColor = AppGlass.stroke,
    this.strokeWidth = 1,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color tintColor;
  final Color strokeColor;
  final double strokeWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor,
            borderRadius: borderRadius,
            border: Border.all(color: strokeColor, width: strokeWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

