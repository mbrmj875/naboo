import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/sale_brand.dart';

/// إطار ذهبي ملكي موحّد لبطاقات غيار الزيت (النموذج، الكتالوج، السجل، الخدمات).
abstract final class OilChangeRoyalCard {
  OilChangeRoyalCard._();

  static const Color gold = SaleBrandColors.gold;

  static BoxDecoration decoration(
    ColorScheme cs, {
    double radius = 16,
    Color? backgroundColor,
    double borderWidth = 2,
    double borderAlpha = 0.82,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? cs.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: gold.withValues(alpha: borderAlpha),
        width: borderWidth,
      ),
      boxShadow: const [
        BoxShadow(
          color: AppGlass.goldGlow,
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration sectionHeaderDecoration() {
    return BoxDecoration(
      color: gold.withValues(alpha: 0.10),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      border: Border(
        bottom: BorderSide(
          color: gold.withValues(alpha: 0.38),
          width: 1,
        ),
      ),
    );
  }

  /// بطاقة قسم (عنوان + محتوى) بإطار ذهبي ملكي.
  static Widget section({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      decoration: decoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: sectionHeaderDecoration(),
            child: Row(
              children: [
                Icon(icon, color: gold, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: gold,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// قسم اختياري قابل للطي — للإضافات (فلاتر، هيدروليك، …) في نموذج الغيار.
  ///
  /// عند الطي يبقى الإطار مستطيلاً واضحاً (رأس البطاقة فقط) مع ملخص اختياري.
  static Widget collapsibleSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    String? collapsedHint,
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hint = collapsedHint?.trim();
    final hasHint = !expanded && hint != null && hint.isNotEmpty;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      constraints: BoxConstraints(
        minHeight: expanded ? 0 : (hasHint ? 64 : 52),
      ),
      decoration: decoration(
        cs,
        backgroundColor: expanded
            ? cs.surface
            : cs.surfaceContainerHighest.withValues(alpha: 0.42),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Container(
                padding: EdgeInsetsDirectional.fromSTEB(
                  14,
                  hasHint ? 10 : 12,
                  14,
                  hasHint ? 10 : 12,
                ),
                decoration: expanded ? sectionHeaderDecoration() : null,
                child: Row(
                  children: [
                    Icon(icon, color: gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              color: gold,
                            ),
                            textAlign: TextAlign.start,
                          ),
                          if (hasHint) ...[
                            const SizedBox(height: 3),
                            Text(
                              hint,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                height: 1.25,
                              ),
                              textAlign: TextAlign.start,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: gold,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  /// بطاقة قائمة (صف لزوجة، خدمة، …).
  static Widget listTileCard({
    required ColorScheme cs,
    required Widget child,
    EdgeInsetsGeometry? margin,
    double radius = 12,
    VoidCallback? onTap,
  }) {
    final tile = Material(
      color: Colors.transparent,
      child: child,
    );
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 6),
      decoration: decoration(cs, radius: radius),
      child: onTap == null
          ? tile
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: tile,
            ),
    );
  }
}
