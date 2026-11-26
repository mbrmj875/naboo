import 'package:flutter/material.dart';
import '../theme/erp_input_constants.dart';
import '../theme/design_tokens.dart';

/// انتقالات متسقة عبر المنصات.
const _kTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
  },
);

class AppTheme {
  /// للتوافق مع الشاشات التي تستخدم `AppTheme.primaryColor`.
  static const Color primaryColor = AppColors.primary;

  static ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scaffoldBg: AppColors.surfaceLight,
    surface: AppColors.cardLight,
    onSurface: const Color(0xFF0F172A),
    onSurfaceVariant: const Color(0xFF475569),
    outline: AppColors.borderLight,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    cardShape: AppShape.sharpCardLight,
  );

  static ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scaffoldBg: AppColors.surfaceDark,
    surface: AppColors.cardDark,
    onSurface: const Color(0xFFF8FAFC),
    onSurfaceVariant: const Color(0xFF94A3B8),
    outline: AppColors.borderDark,
    primary: const Color(0xFF3B82F6),
    onPrimary: Colors.white,
    cardShape: AppShape.sharpCardDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffoldBg,
    required Color surface,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
    required Color primary,
    required Color onPrimary,
    required ShapeBorder cardShape,
  }) {
    final cs = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: const Color(0xFFB91C1C),
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      outline: outline,
      outlineVariant: outline.withValues(alpha: 0.85),
      surfaceContainerHighest: brightness == Brightness.light
          ? const Color(0xFFE2E8F0)
          : const Color(0xFF334155),
    );

    final inputFill = brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF0F172A);

    final inputBorderThin = OutlineInputBorder(
      borderRadius: ErpInputConstants.borderRadius,
      borderSide: BorderSide(
        color: outline,
        width: ErpInputConstants.borderWidthDefault,
      ),
    );

    final inputBorderFocus = OutlineInputBorder(
      borderRadius: ErpInputConstants.borderRadius,
      borderSide: BorderSide(
        color: primary,
        width: ErpInputConstants.borderWidthFocus,
      ),
    );

    final inputBorderError = OutlineInputBorder(
      borderRadius: ErpInputConstants.borderRadius,
      borderSide: BorderSide(color: cs.error, width: ErpInputConstants.borderWidthDefault),
    );

    final inputBorderErrFocus = OutlineInputBorder(
      borderRadius: ErpInputConstants.borderRadius,
      borderSide: BorderSide(color: cs.error, width: ErpInputConstants.borderWidthFocus),
    );

    final inputBorderDis = OutlineInputBorder(
      borderRadius: ErpInputConstants.borderRadius,
      borderSide: BorderSide(
        color: outline.withValues(alpha: 0.5),
        width: ErpInputConstants.borderWidthDefault,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      /// خط عربي مُسجَّل — بدونه قد لا يُرسَم النص داخل بعض البطاقات على الويب.
      fontFamily: 'Tajawal',
      colorScheme: cs,
      scaffoldBackgroundColor: scaffoldBg,
      dividerColor: outline,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 22),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        elevation: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF1E293B)
            : const Color(0xFF334155),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        showDragHandle: false,
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        iconColor: onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: ErpInputConstants.contentPadding,
        border: inputBorderThin,
        enabledBorder: inputBorderThin,
        focusedBorder: inputBorderFocus,
        errorBorder: inputBorderError,
        focusedErrorBorder: inputBorderErrFocus,
        disabledBorder: inputBorderDis,
        labelStyle: TextStyle(color: onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: onSurfaceVariant.withValues(alpha: 0.82), fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          foregroundColor: onPrimary,
          iconColor: onPrimary,
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              brightness == Brightness.light ? primary : onSurface,
          iconColor: brightness == Brightness.light ? primary : onSurface,
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          side: BorderSide(color: outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppShape.none),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        side: BorderSide(color: outline),
        labelStyle: TextStyle(color: onSurface, fontSize: 13),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.primary,
        indicatorColor: Colors.white24,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      pageTransitionsTheme: _kTransitions,
    );
  }
}
