import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/sale_brand.dart';

/// هوية تشغيل المطاعم — نفس نابو (كحلي + ذهبي)، بطابع ضيافة راقية.
/// الأسماء (amber/charcoal) ثابتة للتوافق؛ القيم من هوية التطبيق.
abstract final class RestaurantOsTokens {
  RestaurantOsTokens._();

  static const Color charcoal = AppColors.surfaceDark;
  static const Color charcoalElevated = AppColors.cardDark;
  static const Color charcoalHigh = AppColors.borderDark;
  static const Color amber = AppColors.accentGold;
  static const Color amberSoft = SaleBrandColors.gold;
  static const Color bone = Color(0xFFF1F5F9);
  static const Color boneMuted = Color(0xFF94A3B8);
  static const Color danger = AppSemanticColors.danger;
  static const Color success = AppSemanticColors.success;

  static const double radiusSm = 0;
  static const double radiusMd = 4;
  static const double gutter = 16;

  static ThemeData darkTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: charcoal,
      colorScheme: ColorScheme.dark(
        surface: charcoal,
        onSurface: bone,
        primary: amber,
        onPrimary: AppColors.primaryDark,
        secondary: charcoalElevated,
        onSecondary: bone,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: charcoal,
        foregroundColor: bone,
        elevation: 0,
        centerTitle: false,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: charcoalElevated,
        selectedColor: amber.withValues(alpha: 0.22),
        labelStyle: const TextStyle(color: bone, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: bone),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: bone.withValues(alpha: 0.12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: AppColors.primaryDark,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
