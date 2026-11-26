import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/sale_pos_settings_data.dart';
import '../../../providers/sale_pos_settings_provider.dart';
import '../../../theme/app_corner_style.dart';
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

  /// ألوان العلامة من «إعدادات شاشة البيع» (ق-24)؛ الثابتان [gold] و[navy]
  /// للسياق الذي لا إعدادات فيه (اختبارات، شاشات قبل التهيئة).
  static SalePalette? _palette(BuildContext context) {
    try {
      final data = Provider.of<SalePosSettingsProvider>(context, listen: true)
          .data;
      return SalePalette.fromSettings(data, Theme.of(context));
    } catch (_) {
      return null;
    }
  }

  static Color goldOf(BuildContext context) => _palette(context)?.gold ?? gold;

  static Color navyOf(BuildContext context) => _palette(context)?.navy ?? navy;

  /// زوايا الحقول والصناديق من إعداد الزوايا (حادة أو مستديرة).
  static BorderRadius radiusOf(BuildContext context) {
    final ext = Theme.of(context).extension<AppCornerStyle>();
    return ext == null ? ErpInputConstants.borderRadius : ext.md;
  }

  /// لون النص البارز (عناوين، أسماء منتجات).
  static Color emphasisText(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF0F172A);

  /// نص ثانوي (تلميحات، رموز).
  static Color secondaryText(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.72)
      : const Color(0xFF64748B);

  /// لون التمييز — ذهبي في كل الأوضاع.
  static Color accentText(BuildContext context) => goldOf(context);

  static ThemeData wrap(BuildContext context, ThemeData base) {
    final dark = isDark(context);
    final gold = goldOf(context);
    final navy = navyOf(context);
    final fill = dark ? const Color(0xFF0F172A) : Colors.white;
    final borderIdle = gold.withValues(alpha: 0.48);
    final borderFocus = gold;
    final radius = radiusOf(context);

    OutlineInputBorder outline(Color color, [double w = 1.5]) =>
        OutlineInputBorder(
          borderRadius: radius,
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
    final gold = goldOf(context);
    final navy = navyOf(context);
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
        // الخط من ثيم التطبيق (Tajawal أو Noto حسب الإعداد).
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
    double? radius,
  }) {
    final corners = Theme.of(context).extension<AppCornerStyle>();
    return BoxDecoration(
      color: isDark(context)
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.white,
      borderRadius: corners == null
          ? BorderRadius.circular(radius ?? 12)
          : (radius == null ? corners.md : corners.radius(radius)),
      border: Border.all(
        color: goldOf(context).withValues(alpha: 0.48),
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
    final gold = goldOf(context);
    final borderIdle = gold.withValues(alpha: 0.48);
    final radius = radiusOf(context);
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: radius,
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
