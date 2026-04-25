import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/sale_pos_settings_data.dart';

/// نصف أقطار الواجهة المستمدة من [SalePosSettingsData.panelCornerStyle] —
/// تُحقَن في الثيم وتُقرأ عبر [Theme.of(context).extension].
@immutable
class AppCornerStyle extends ThemeExtension<AppCornerStyle> {
  const AppCornerStyle({
    required this.isRounded,
    required this.rSm,
    required this.rMd,
    required this.rLg,
    required this.rFab,
  });

  /// زوايا حادة (0) أو مستديرة حسب الإعداد.
  final bool isRounded;
  final double rSm;
  final double rMd;
  final double rLg;
  final double rFab;

  factory AppCornerStyle.fromPanelStyle(SalePanelCornerStyle style) {
    final rounded = style == SalePanelCornerStyle.rounded;
    return AppCornerStyle(
      isRounded: rounded,
      rSm: rounded ? 8 : 0,
      rMd: rounded ? 12 : 0,
      rLg: rounded ? 14 : 0,
      rFab: rounded ? 16 : 0,
    );
  }

  /// عند غياب الامتداد (اختبارات / شاشات خارج المادة).
  static const AppCornerStyle sharp = AppCornerStyle(
    isRounded: false,
    rSm: 0,
    rMd: 0,
    rLg: 0,
    rFab: 0,
  );

  static AppCornerStyle of(BuildContext context) {
    return Theme.of(context).extension<AppCornerStyle>() ?? sharp;
  }

  BorderRadius radius(double r) =>
      BorderRadius.circular(isRounded ? r.clamp(0, 999) : 0);

  BorderRadius get sm => radius(rSm);
  BorderRadius get md => radius(rMd);
  BorderRadius get lg => radius(rLg);

  @override
  AppCornerStyle copyWith({
    bool? isRounded,
    double? rSm,
    double? rMd,
    double? rLg,
    double? rFab,
  }) {
    return AppCornerStyle(
      isRounded: isRounded ?? this.isRounded,
      rSm: rSm ?? this.rSm,
      rMd: rMd ?? this.rMd,
      rLg: rLg ?? this.rLg,
      rFab: rFab ?? this.rFab,
    );
  }

  @override
  AppCornerStyle lerp(ThemeExtension<AppCornerStyle>? other, double t) {
    if (other is! AppCornerStyle) return this;
    return AppCornerStyle(
      isRounded: t < 0.5 ? isRounded : other.isRounded,
      rSm: lerpDouble(rSm, other.rSm, t)!,
      rMd: lerpDouble(rMd, other.rMd, t)!,
      rLg: lerpDouble(rLg, other.rLg, t)!,
      rFab: lerpDouble(rFab, other.rFab, t)!,
    );
  }
}

extension AppCornerStyleX on BuildContext {
  AppCornerStyle get appCorners => AppCornerStyle.of(this);
}
