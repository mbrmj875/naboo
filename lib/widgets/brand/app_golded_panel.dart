import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sale_pos_settings_data.dart';
import '../../providers/sale_pos_settings_provider.dart';
import '../../utils/screen_layout.dart';

/// لوحة (Section Panel) بنمط Brand DNA — **حد ذهبي يميني سميك** + حدود رقيقة
/// على الجوانب الثلاث الأخرى. انظر `docs/screen_migration_playbook.md` §12.5.
///
/// **التَّصميم**:
/// - الخلفية: `ivory` (light) / `ivoryDark` (dark) من الـ Palette الفعَّالة.
/// - الحد الأيمن: ذهبي سميك (2.5-3 px).
/// - الحدود الأخرى: navy.alpha(0.2) (light) / gold.alpha(0.4) (dark).
/// - الزوايا: مستديرة (يُمكن جَعلها حادة عبر [forceSharpCorners]).
///
/// **مثال**:
/// ```dart
/// AppGoldedPanel(
///   child: Column(children: [
///     AppSectionTitle(title: 'الإجمالي'),
///     // ...محتوى القسم
///   ]),
/// )
/// ```
class AppGoldedPanel extends StatelessWidget {
  const AppGoldedPanel({
    super.key,
    required this.child,
    this.padding,
    this.dense = false,
    this.forceSharpCorners = false,
    this.borderRadius,
  });

  final Widget child;

  /// الـ padding الداخلي. الافتراضي: 16 (wide) / 13 (narrow).
  final EdgeInsetsGeometry? padding;

  /// عرض/ارتفاع/حدود أقل (للاستخدام داخل قوائم كثيفة).
  final bool dense;

  /// يَتجاوز إعداد `panelCornerStyle` للمستخدم ويَفرض زوايا حادة.
  /// نادراً ما يُستخدم — فقط للحالات الخاصة كـ Banners ممتدّة بعرض الشاشة.
  final bool forceSharpCorners;

  /// تَخصيص radius اختياري (يَتجاوز إعداد المستخدم لو مُمرَّر).
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final pos = context.read<SalePosSettingsProvider>().data;
    final palette = SalePalette.fromSettings(pos, theme);
    final wide = !ScreenLayout.of(context).showSaleBarcodeShortcut && !dense;
    final bg = dark ? palette.ivoryDark : palette.ivory;
    final edge = dark
        ? palette.gold.withValues(alpha: 0.4)
        : palette.navy.withValues(alpha: 0.2);
    final goldEdgeWidth = wide ? 3.0 : 2.5;
    final innerPad =
        padding ?? EdgeInsets.all(wide ? 16 : (dense ? 11 : 13));
    // لا تَضع borderRadius على BoxDecoration مع حدود غير متساوية (اليمين أعرض) —
    // قد لا يُرسم المحتوى على الويب. القصّ بـ ClipRRect أكثر أماناً.
    final panel = Container(
      width: double.infinity,
      padding: innerPad,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: edge),
          bottom: BorderSide(color: edge),
          left: BorderSide(color: edge),
          right: BorderSide(color: palette.gold, width: goldEdgeWidth),
        ),
      ),
      child: child,
    );
    final sharp = forceSharpCorners ||
        pos.panelCornerStyle == SalePanelCornerStyle.sharp;
    if (sharp) return panel;
    return ClipRRect(
      borderRadius: borderRadius ?? pos.saleFlowBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: panel,
    );
  }
}
