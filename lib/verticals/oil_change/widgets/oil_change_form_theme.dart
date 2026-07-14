import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/erp_input_constants.dart';
import '../../../theme/sale_brand.dart';

/// ألوان وحقول الشاشات الملكية (غيار الزيت، المصروفات، …) — ذهبي بدل الكحلي.
abstract final class OilChangeFormTheme {
  OilChangeFormTheme._();

  static const Color gold = AppColors.accentGold;
  static const Color navy = SaleBrandColors.navy;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// لون النص البارز (عناوين، أسماء منتجات).
  static Color emphasisText(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF0F172A);

  /// نص ثانوي (تلميحات، رموز).
  static Color secondaryText(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.72)
      : const Color(0xFF64748B);

  /// لون التمييز — ذهبي في كل الأوضاع.
  static Color accentText(BuildContext context) => gold;

  static ThemeData wrap(BuildContext context, ThemeData base) {
    final dark = isDark(context);
    final fill = dark ? const Color(0xFF0F172A) : Colors.white;
    final borderIdle = gold.withValues(alpha: 0.48);
    final borderFocus = gold;

    OutlineInputBorder outline(Color color, [double w = 1.5]) =>
        OutlineInputBorder(
          borderRadius: ErpInputConstants.borderRadius,
          borderSide: BorderSide(color: color, width: w),
        );

    final inputTheme = base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: fill,
      contentPadding: ErpInputConstants.contentPadding,
      labelStyle: TextStyle(
        color: gold,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: secondaryText(context).withValues(alpha: 0.9),
        fontSize: 13,
      ),
      helperStyle: TextStyle(
        color: secondaryText(context),
        fontSize: 12,
      ),
      border: outline(borderIdle),
      enabledBorder: outline(borderIdle),
      focusedBorder: outline(borderFocus, ErpInputConstants.borderWidthFocus),
      errorBorder: outline(base.colorScheme.error),
      focusedErrorBorder: outline(
        base.colorScheme.error,
        ErpInputConstants.borderWidthFocus,
      ),
      disabledBorder: outline(
        base.dividerColor.withValues(alpha: 0.45),
      ),
    );

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: gold,
        onPrimary: dark ? navy : Colors.white,
        tertiary: gold,
      ),
      inputDecorationTheme: inputTheme,
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: gold,
        selectionColor: gold.withValues(alpha: 0.28),
      ),
    );
  }

  static PreferredSizeWidget appBar({
    required BuildContext context,
    required String title,
    required List<Widget> actions,
    PreferredSizeWidget? bottom,
  }) {
    final dark = isDark(context);
    final bg = dark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = dark ? gold : navy;
    final iconColor = dark ? gold : navy;

    return AppBar(
      backgroundColor: bg,
      foregroundColor: titleColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: iconColor, size: 22),
      actionsIconTheme: IconThemeData(color: gold, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: titleColor,
        ),
      ),
      actions: actions,
      bottom: bottom ??
          PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: gold.withValues(alpha: 0.35),
            ),
          ),
    );
  }

  /// إطار ذهبي موحّد لقوائم منسدلة أو محتوى داخل بطاقة.
  static BoxDecoration fieldContainerDecoration(
    BuildContext context, {
    double radius = 12,
  }) {
    return BoxDecoration(
      color: isDark(context)
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: gold.withValues(alpha: 0.48),
      ),
    );
  }

  static InputDecoration field({
    required BuildContext context,
    required String labelText,
    String? hintText,
    String? helperText,
    Widget? suffixIcon,
    Widget? prefixIcon,
    bool isDense = false,
    int? helperMaxLines,
  }) {
    final borderIdle = gold.withValues(alpha: 0.48);
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: ErpInputConstants.borderRadius,
          borderSide: BorderSide(color: c, width: w),
        );

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      isDense: isDense,
      labelStyle: TextStyle(
        color: gold,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: secondaryText(context)),
      helperStyle: TextStyle(color: secondaryText(context), fontSize: 12),
      filled: true,
      fillColor: isDark(context) ? const Color(0xFF0F172A) : Colors.white,
      border: border(borderIdle),
      enabledBorder: border(borderIdle),
      focusedBorder: border(gold, ErpInputConstants.borderWidthFocus),
    );
  }
}
