import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Contrast-safe fill/ink for search & form fields on public menu surfaces.
class MenuContrastInputTokens {
  const MenuContrastInputTokens({
    required this.fill,
    required this.ink,
    required this.placeholder,
    required this.border,
  });

  final Color fill;
  final Color ink;
  final Color placeholder;
  final Color border;

  static double _relLum(Color c) {
    double chan(int v) {
      final s = v / 255.0;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * chan(c.red) +
        0.7152 * chan(c.green) +
        0.0722 * chan(c.blue);
  }

  static double _ratio(Color a, Color b) {
    final l1 = _relLum(a);
    final l2 = _relLum(b);
    final hi = math.max(l1, l2);
    final lo = math.min(l1, l2);
    return (hi + 0.05) / (lo + 0.05);
  }

  factory MenuContrastInputTokens.fromTheme({
    required Color bg,
    required Color text,
  }) {
    final bgL = _relLum(bg);
    var fill = bgL > 0.55 ? const Color(0xFFFFFFFF) : const Color(0xFF0B1220);
    var ink = bgL > 0.55 ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    if (_ratio(bg, text) < 3) {
      fill = bgL > 0.5 ? const Color(0xFFFFFFFF) : const Color(0xFF0B1220);
      ink = bgL > 0.5 ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    } else if (_ratio(fill, text) >= 4.5) {
      ink = text;
      fill = bgL > 0.45
          ? const Color(0xFFFFFFFF)
          : Color.lerp(bg, Colors.black, 0.18)!;
    }

    if (_ratio(fill, ink) < 4.5) {
      final textL = _relLum(text);
      fill = textL > 0.5 ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);
      ink = textL > 0.5 ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    }

    return MenuContrastInputTokens(
      fill: fill,
      ink: ink,
      placeholder: ink.withValues(alpha: 0.52),
      border: ink.withValues(alpha: 0.28),
    );
  }
}
