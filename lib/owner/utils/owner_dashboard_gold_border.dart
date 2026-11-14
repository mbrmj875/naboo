import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// إطار ذهبي موحّد — مطابق لبطاقات صفحة الصندوق (فاتح/داكن).
abstract final class OwnerDashboardGoldBorder {
  OwnerDashboardGoldBorder._();

  static const double radius = 16;

  static Color borderColor({bool warning = false, ColorScheme? cs}) {
    if (warning && cs != null) {
      return cs.error.withValues(alpha: 0.45);
    }
    return AppColors.accentGold.withValues(alpha: 0.35);
  }

  static List<BoxShadow> fintechShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: const Color(0xFF1B2B4B).withValues(alpha: isDark ? 0.35 : 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static Color fillColor(BuildContext context, {Color? override}) {
    if (override != null) return override;
    final cs = Theme.of(context).colorScheme;
    return cs.brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : cs.surfaceContainerLowest;
  }

  static BorderSide side(BuildContext context, {bool warning = false}) {
    final cs = Theme.of(context).colorScheme;
    return BorderSide(color: borderColor(warning: warning, cs: cs));
  }

  static RoundedRectangleBorder cardShape(
    BuildContext context, {
    bool warning = false,
    double borderRadius = radius,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: side(context, warning: warning),
    );
  }

  static BoxDecoration boxDecoration(
    BuildContext context, {
    Color? backgroundColor,
    bool warning = false,
    double borderRadius = radius,
    List<BoxShadow>? boxShadow,
  }) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: fillColor(context, override: backgroundColor),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor(warning: warning, cs: cs)),
      boxShadow: boxShadow ?? fintechShadow(context),
    );
  }

  static Card themedCard({
    required BuildContext context,
    required Widget child,
    Color? color,
    bool warning = false,
    double borderRadius = radius,
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      margin: margin ?? EdgeInsets.zero,
      color: fillColor(context, override: color),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: cardShape(context, warning: warning, borderRadius: borderRadius),
      child: child,
    );
  }
}
