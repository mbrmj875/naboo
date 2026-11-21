import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// ألوان لوحة المالك — من هوية أيقونة التطبيق (كحلي الدرع + ذهبي القلم).
///
/// مصدر واحد لكل ودجات `lib/owner/widgets/v4/`. لا ألوان مكتوبة يدوياً داخلها.
/// الذهبي للتمييز فقط (التبويب المختار، خط القسم، عمود اليوم) — لا خلفيات ذهبية.
@immutable
class OwnerDashboardTokens extends ThemeExtension<OwnerDashboardTokens> {
  const OwnerDashboardTokens({
    required this.background,
    required this.card,
    required this.cardBorder,
    required this.ink,
    required this.inkMuted,
    required this.gold,
    required this.goldSoft,
    required this.navySoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.warningSoft,
  });

  final Color background;
  final Color card;
  final Color cardBorder;

  /// الأرقام والعناوين.
  final Color ink;

  /// النصوص الثانوية — تباين ≥ 4.5:1 على [card].
  final Color inkMuted;

  /// ذهبي الهوية (تمييز فقط).
  final Color gold;

  /// خلفية خفيفة جداً للعنصر المختار.
  final Color goldSoft;

  /// خلفية الأيقونات وأعمدة المخطط غير المختارة.
  final Color navySoft;

  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color warningSoft;

  static const light = OwnerDashboardTokens(
    background: Color(0xFFF6F4EF),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE4E0D6),
    ink: AppColors.primary,
    inkMuted: Color(0xFF4A5568),
    gold: AppColors.accentGold,
    goldSoft: Color(0xFFF7F0D9),
    navySoft: Color(0xFFE8ECF3),
    success: AppSemanticColors.success,
    warning: Color(0xFFB45309),
    danger: AppSemanticColors.danger,
    dangerSoft: Color(0xFFFDECEC),
    warningSoft: Color(0xFFFFF4E0),
  );

  static const dark = OwnerDashboardTokens(
    background: Color(0xFF08111F),
    card: Color(0xFF111C2E),
    cardBorder: Color(0xFF22324A),
    ink: Color(0xFFF1F4F9),
    inkMuted: Color(0xFFA9B4C4),
    gold: Color(0xFFD9B84A),
    goldSoft: Color(0xFF2A2716),
    navySoft: Color(0xFF1B2A42),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1A1F),
    warningSoft: Color(0xFF33280F),
  );

  /// يقرأ الامتداد من الثيم، وإلا يختار حسب سطوع الثيم الحالي.
  static OwnerDashboardTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<OwnerDashboardTokens>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// نمط الأرقام الكبيرة — عرض ثابت للأرقام حتى لا تقفز عند التحديث.
  TextStyle numberStyle(double size) => TextStyle(
    color: ink,
    fontSize: size,
    fontWeight: FontWeight.w800,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  OwnerDashboardTokens copyWith({
    Color? background,
    Color? card,
    Color? cardBorder,
    Color? ink,
    Color? inkMuted,
    Color? gold,
    Color? goldSoft,
    Color? navySoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerSoft,
    Color? warningSoft,
  }) {
    return OwnerDashboardTokens(
      background: background ?? this.background,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      gold: gold ?? this.gold,
      goldSoft: goldSoft ?? this.goldSoft,
      navySoft: navySoft ?? this.navySoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  OwnerDashboardTokens lerp(OwnerDashboardTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return OwnerDashboardTokens(
      background: l(background, other.background),
      card: l(card, other.card),
      cardBorder: l(cardBorder, other.cardBorder),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      gold: l(gold, other.gold),
      goldSoft: l(goldSoft, other.goldSoft),
      navySoft: l(navySoft, other.navySoft),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      warningSoft: l(warningSoft, other.warningSoft),
    );
  }
}
