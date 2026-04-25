import 'package:flutter/material.dart';

import '../navigation/content_navigation.dart';
import '../theme/app_corner_style.dart';

/// شريط فتات خبز حديث — يتبع مسار [Navigator] ويعرض عنواناً عربياً لكل صفحة.
class AppBreadcrumbStrip extends StatelessWidget {
  const AppBreadcrumbStrip({
    super.key,
    required this.segments,
    required this.onSegmentTap,
    required this.surfaceColor,
    required this.dividerColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  final List<BreadcrumbSegment> segments;
  final void Function(BreadcrumbSegment segment) onSegmentTap;

  final Color surfaceColor;
  final Color dividerColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  String _pathTooltip(int upToInclusive) {
    if (segments.isEmpty) return '';
    final parts = <String>[];
    for (var i = 0; i <= upToInclusive && i < segments.length; i++) {
      parts.add(segments[i].title);
    }
    return parts.join(' ← ');
  }

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sl = MediaQuery.sizeOf(context);
    final compact = sl.width < 400;

    return Material(
      color: surfaceColor,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface.withValues(alpha: isDark ? 0.2 : 0.5),
              surfaceColor,
            ],
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: 'مسار التنقل — اضغط خطوة سابقة للرجوع',
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: ac.sm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.account_tree_rounded,
                        size: compact ? 17 : 19,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Row(
                      key: ValueKey<String>(
                        segments.map((e) => e.id).join('|'),
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < segments.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                Icons.chevron_left_rounded,
                                size: 16,
                                color: secondaryTextColor.withValues(alpha: 0.75),
                              ),
                            ),
                          Tooltip(
                            message: _pathTooltip(i),
                            waitDuration: const Duration(milliseconds: 400),
                            child: _BreadcrumbChip(
                              title: segments[i].title,
                              icon: breadcrumbIconForRouteId(segments[i].id),
                              isCurrent: i == segments.length - 1,
                              compact: compact,
                              colorScheme: cs,
                              borderRadius: ac.sm,
                              onTap: i == segments.length - 1
                                  ? null
                                  : () => onSegmentTap(segments[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.title,
    required this.icon,
    required this.isCurrent,
    required this.compact,
    required this.colorScheme,
    required this.borderRadius,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isCurrent;
  final bool compact;
  final ColorScheme colorScheme;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 11,
      vertical: compact ? 5 : 7,
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: compact ? 14 : 15,
          color: isCurrent ? colorScheme.onPrimary : colorScheme.primary,
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 120 : 200),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              height: 1.1,
              color: isCurrent ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );

    if (isCurrent) {
      return Semantics(
        label: 'الصفحة الحالية: $title',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                Color.lerp(colorScheme.primary, colorScheme.secondary, 0.15)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(padding: pad, child: child),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(padding: pad, child: child),
        ),
      ),
    );
  }
}
