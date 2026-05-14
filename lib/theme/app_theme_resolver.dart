import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sale_pos_settings_data.dart';
import '../utils/theme.dart';
import 'app_corner_style.dart';

/// يدمج [SalePosSettingsData] (هوية بصرية + زوايا + خط) مع ثيم التطبيق الأساسي
/// ليُطبَّق عبر [MaterialApp] على **كل** الواجهات.
abstract final class AppThemeResolver {
  AppThemeResolver._();

  static TextStyle? _mergeTextColor(
    TextStyle? style,
    int? textArgb,
    Color surface, {
    bool hint = false,
  }) {
    if (style == null) return null;
    if (textArgb == null) return style;
    final c = Color(textArgb);
    if (hint) {
      return style.copyWith(color: Color.lerp(c, surface, 0.42));
    }
    return style.copyWith(color: c);
  }

  static (TextTheme, TextTheme) _textThemesForFontChoice(
    ThemeData base,
    String familyKey,
  ) {
    switch (familyKey) {
      case AppFontFamilies.tajawal:
        return (
          base.textTheme.apply(fontFamily: AppFontFamilies.tajawal),
          base.primaryTextTheme.apply(fontFamily: AppFontFamilies.tajawal),
        );
      case AppFontFamilies.notoNaskhArabic:
        return (
          base.textTheme.apply(fontFamily: AppFontFamilies.notoNaskhArabic),
          base.primaryTextTheme.apply(
            fontFamily: AppFontFamilies.notoNaskhArabic,
          ),
        );
      case AppFontFamilies.cairo:
        return (
          GoogleFonts.cairoTextTheme(base.textTheme),
          GoogleFonts.cairoTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.almarai:
        return (
          GoogleFonts.almaraiTextTheme(base.textTheme),
          GoogleFonts.almaraiTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.amiri:
        return (
          GoogleFonts.amiriTextTheme(base.textTheme),
          GoogleFonts.amiriTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.lateef:
        return (
          GoogleFonts.lateefTextTheme(base.textTheme),
          GoogleFonts.lateefTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.scheherazadeNew:
        return (
          GoogleFonts.scheherazadeNewTextTheme(base.textTheme),
          GoogleFonts.scheherazadeNewTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.ibmPlexSansArabic:
        return (
          GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme),
          GoogleFonts.ibmPlexSansArabicTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.elMessiri:
        return (
          GoogleFonts.elMessiriTextTheme(base.textTheme),
          GoogleFonts.elMessiriTextTheme(base.primaryTextTheme),
        );
      case AppFontFamilies.changa:
        return (
          GoogleFonts.changaTextTheme(base.textTheme),
          GoogleFonts.changaTextTheme(base.primaryTextTheme),
        );
      default:
        return (
          base.textTheme.apply(fontFamily: AppFontFamilies.tajawal),
          base.primaryTextTheme.apply(fontFamily: AppFontFamilies.tajawal),
        );
    }
  }

  static ThemeData _applyAppTypography(
    ThemeData base,
    SalePosSettingsData settings,
  ) {
    final ff = AppFontFamilies.normalize(settings.appFontFamily);
    final textArgb = base.brightness == Brightness.dark
        ? settings.appTextColorDarkArgb
        : settings.appTextColorLightArgb;

    final (tt0, pt0) = _textThemesForFontChoice(base, ff);
    final resolvedFamily = tt0.bodyLarge?.fontFamily ?? ff;
    TextStyle? withFf(TextStyle? s) =>
        s?.copyWith(fontFamily: resolvedFamily);

    ColorScheme cs = base.colorScheme;
    TextTheme tt = tt0;
    TextTheme pt = pt0;

    if (textArgb != null) {
      final c = Color(textArgb);
      final variant = Color.lerp(c, cs.surface, 0.38) ?? c;
      cs = cs.copyWith(
        onSurface: c,
        onSurfaceVariant: variant,
      );
      tt = tt.apply(bodyColor: c, displayColor: c);
      pt = pt.apply(bodyColor: c, displayColor: c);
    }

    final navPrev =
        base.navigationBarTheme.labelTextStyle?.resolve(<WidgetState>{});
    final navBase =
        (navPrev ?? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))
            .copyWith(fontFamily: resolvedFamily);
    final navStyle = textArgb != null
        ? navBase.copyWith(color: Color(textArgb))
        : navBase;

    return base.copyWith(
      colorScheme: cs,
      textTheme: tt,
      primaryTextTheme: pt,
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: withFf(base.appBarTheme.titleTextStyle),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: withFf(base.snackBarTheme.contentTextStyle),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: _mergeTextColor(
          withFf(base.inputDecorationTheme.labelStyle),
          textArgb,
          cs.surface,
        ),
        hintStyle: _mergeTextColor(
          withFf(base.inputDecorationTheme.hintStyle),
          textArgb,
          cs.surface,
          hint: true,
        ),
        helperStyle: withFf(base.inputDecorationTheme.helperStyle),
        errorStyle: withFf(base.inputDecorationTheme.errorStyle),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: _mergeTextColor(
          withFf(base.chipTheme.labelStyle),
          textArgb,
          cs.surface,
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(navStyle),
      ),
    );
  }

  static ThemeData mergeForBrightness({
    required ThemeData base,
    required SalePosSettingsData settings,
    required Brightness brightness,
  }) {
    final ac = AppCornerStyle.fromPanelStyle(settings.panelCornerStyle);
    final cs = base.colorScheme;
    final outline = cs.outline;

    OutlineInputBorder outlineBorder(Color borderColor, double w) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor, width: w),
      );
    }

    final inputBase = outlineBorder(outline, 1.5);
    final themedBase = _applyAppTypography(
      base.copyWith(
        extensions: <ThemeExtension<dynamic>>[ac],
        cardTheme: base.cardTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.lg),
        ),
        dialogTheme: base.dialogTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.lg),
        ),
        snackBarTheme: base.snackBarTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.lg),
        ),
        listTileTheme: base.listTileTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ),
        popupMenuTheme: base.popupMenuTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ),
        chipTheme: base.chipTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: ac.sm),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          border: inputBase,
          enabledBorder: inputBase,
          focusedBorder: outlineBorder(cs.primary, 2),
          errorBorder: outlineBorder(cs.error, 1.5),
          focusedErrorBorder: outlineBorder(cs.error, 2),
          disabledBorder: outlineBorder(outline.withValues(alpha: 0.5), 1.5),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: ac.md),
          ).merge(base.textButtonTheme.style),
        ),
        floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ac.rFab),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: ac.md),
          ).merge(base.elevatedButtonTheme.style),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: ac.md),
          ).merge(base.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: ac.md),
          ).merge(base.outlinedButtonTheme.style),
        ),
      ),
      settings,
    );

    if (!settings.useSaleBrandSkin) {
      return themedBase;
    }

    final palette = SalePalette.fromSettings(settings, themedBase);
    var mergedScheme = cs.copyWith(
      primary: palette.navy,
      onPrimary: Colors.white,
      secondary: palette.gold,
      onSecondary: _readableOn(palette.gold),
      tertiary: palette.gold,
      surface: brightness == Brightness.dark
          ? palette.ivoryDark
          : palette.ivory,
      surfaceContainerHighest: brightness == Brightness.dark
          ? palette.ivoryDark.withValues(alpha: 0.92)
          : palette.ivory.withValues(alpha: 0.95),
    );

    final textArgb = brightness == Brightness.dark
        ? settings.appTextColorDarkArgb
        : settings.appTextColorLightArgb;
    if (textArgb != null) {
      final c = Color(textArgb);
      mergedScheme = mergedScheme.copyWith(
        onSurface: c,
        onSurfaceVariant: Color.lerp(c, mergedScheme.surface, 0.38) ?? c,
      );
    }

    return themedBase.copyWith(
      colorScheme: mergedScheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF1F5F9),
      appBarTheme: themedBase.appBarTheme.copyWith(
        backgroundColor: palette.navy,
        foregroundColor: Colors.white,
        // أيقونة `leading` (رجوع/Drawer) تبقى بيضاء — لأنها navigation أساسية.
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        // أيقونات `actions` ذهبية — تَتطابق مع DNA شاشة البيع وتُكوِّن
        // تباينا بصرياً واضحاً يَلفت الانتباه للأفعال السريعة في كل الشاشات.
        // الشاشات التي تَفرض لوناً صريحاً على IconButton (`color: ...`) ستَتجاوز هذا.
        actionsIconTheme: IconThemeData(color: palette.gold, size: 22),
        titleTextStyle: themedBase.appBarTheme.titleTextStyle?.copyWith(
          color: Colors.white,
        ),
      ),
      cardTheme: themedBase.cardTheme.copyWith(
        color: brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
      ),
      dialogTheme: themedBase.dialogTheme.copyWith(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
      ),
      navigationBarTheme: themedBase.navigationBarTheme.copyWith(
        backgroundColor: palette.navy,
        indicatorColor: Colors.white24,
      ),
      floatingActionButtonTheme: themedBase.floatingActionButtonTheme.copyWith(
        backgroundColor: palette.navy,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ).merge(themedBase.elevatedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ).merge(themedBase.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.navy,
          side: BorderSide(color: palette.navy.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(borderRadius: ac.md),
        ).merge(themedBase.outlinedButtonTheme.style),
      ),
      inputDecorationTheme: themedBase.inputDecorationTheme.copyWith(
        border: outlineBorder(mergedScheme.outline, 1.5),
        enabledBorder: outlineBorder(mergedScheme.outline, 1.5),
        focusedBorder: outlineBorder(palette.navy, 2),
        errorBorder: outlineBorder(mergedScheme.error, 1.5),
        focusedErrorBorder: outlineBorder(mergedScheme.error, 2),
        disabledBorder: outlineBorder(
          mergedScheme.outline.withValues(alpha: 0.5),
          1.5,
        ),
      ),
      progressIndicatorTheme: themedBase.progressIndicatorTheme.copyWith(
        color: palette.navy,
      ),
    );
  }

  static ThemeData light(SalePosSettingsData settings) => mergeForBrightness(
    base: AppTheme.lightTheme,
    settings: settings,
    brightness: Brightness.light,
  );

  static ThemeData dark(SalePosSettingsData settings) => mergeForBrightness(
    base: AppTheme.darkTheme,
    settings: settings,
    brightness: Brightness.dark,
  );

  static Color _readableOn(Color bg) {
    return bg.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : Colors.white;
  }
}
