import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/content_navigation.dart';
import '../providers/business_features_provider.dart';
import '../theme/app_corner_style.dart';
import '../theme/design_tokens.dart';
import '../theme/sale_brand.dart';

/// شريط فتات خبز حديث ومؤمن — يتبع مسار [Navigator] الهيكلي الشجري ويعرض عنواناً عربياً لكل صفحة مع طي ذكي.
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


  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final featuresProv = context.watch<BusinessFeaturesProvider>();
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sl = MediaQuery.sizeOf(context);
    final compact = sl.width < 400;
    final isDesktop = sl.width >= 1024;

    // بناء قائمة الشرائحAdaptively مع الطي إذا تجاوزت 3 مستويات
    final List<Widget> segmentChips = [];

    if (segments.length <= 3) {
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final isBlocked = isContentRouteBlocked(segment.id, featuresProv.data);

        if (i > 0) {
          segmentChips.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 16,
                color: secondaryTextColor.withValues(alpha: 0.75),
              ),
            ),
          );
        }

        segmentChips.add(
          _BreadcrumbChip(
            title: segment.title,
            icon: breadcrumbIconForRouteId(segment.id),
            isCurrent: i == segments.length - 1,
            compact: compact,
            colorScheme: cs,
            primaryTextColor: primaryTextColor,
            borderRadius: ac.sm,
            isBlocked: isBlocked,
            onTap: i == segments.length - 1
                ? null
                : () => onSegmentTap(segment),
          ),
        );
      }
    } else {
      // 1. عرض العنصر الأول (غالباً الرئيسية)
      final firstSegment = segments.first;
      final firstBlocked = isContentRouteBlocked(firstSegment.id, featuresProv.data);
      segmentChips.add(
        _BreadcrumbChip(
          title: firstSegment.title,
          icon: breadcrumbIconForRouteId(firstSegment.id),
          isCurrent: false,
          compact: compact,
          colorScheme: cs,
          primaryTextColor: primaryTextColor,
          borderRadius: ac.sm,
          isBlocked: firstBlocked,
          onTap: () => onSegmentTap(firstSegment),
        ),
      );

      // فاصل
      segmentChips.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            Icons.chevron_left_rounded,
            size: 16,
            color: secondaryTextColor.withValues(alpha: 0.75),
          ),
        ),
      );

      // 2. طي العناصر المتوسطة خلف زر تفاعلي
      final intermediateSegments = segments.sublist(1, segments.length - 1);
      segmentChips.add(
        _CollapsibleDropdownChip(
          segments: intermediateSegments,
          onSegmentTap: onSegmentTap,
          compact: compact,
          colorScheme: cs,
          primaryTextColor: primaryTextColor,
          borderRadius: ac.sm,
          features: featuresProv,
          isDesktop: isDesktop,
        ),
      );

      // فاصل
      segmentChips.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            Icons.chevron_left_rounded,
            size: 16,
            color: secondaryTextColor.withValues(alpha: 0.75),
          ),
        ),
      );

      // 3. عرض العنصر الأخير (الحالي)
      final lastSegment = segments.last;
      final lastBlocked = isContentRouteBlocked(lastSegment.id, featuresProv.data);
      segmentChips.add(
        _BreadcrumbChip(
          title: lastSegment.title,
          icon: breadcrumbIconForRouteId(lastSegment.id),
          isCurrent: true,
          compact: compact,
          colorScheme: cs,
          primaryTextColor: primaryTextColor,
          borderRadius: ac.sm,
          isBlocked: lastBlocked,
          onTap: null,
        ),
      );
    }

    final double borderThickness = 0.5;
    final Color thinBorderColor = AppColors.accentGold.withValues(alpha: 0.2);

    final Widget content = Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDesktop ? thinBorderColor : dividerColor,
              width: isDesktop ? borderThickness : 1.0,
            ),
          ),
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
                      color: AppColors.accentGold.withValues(alpha: 0.14),
                      borderRadius: ac.sm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.account_tree_rounded,
                        size: compact ? 17 : 19,
                        color: AppColors.accentGold,
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
                      children: segmentChips,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isDesktop) {
      // زجاج بلوري فاخر على الديسكتوب والتابلت العريض
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: content,
        ),
      );
    }

    // واجهة مسطحة Flat رشيقة وسريعة للأداء على الهاتف لتجنب البطء
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: content,
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
    required this.primaryTextColor,
    required this.borderRadius,
    this.onTap,
    this.isBlocked = false,
  });

  final String title;
  final IconData icon;
  final bool isCurrent;
  final bool compact;
  final ColorScheme colorScheme;
  final Color primaryTextColor;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final bool isBlocked;

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
          color: isBlocked
              ? primaryTextColor.withValues(alpha: 0.3)
              : (isCurrent ? AppColors.accentGold : primaryTextColor),
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
              color: isBlocked
                  ? primaryTextColor.withValues(alpha: 0.3)
                  : (isCurrent ? AppColors.accentGold : primaryTextColor),
              decoration: isBlocked ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (isBlocked) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.lock_outline_rounded,
            size: compact ? 11 : 13,
            color: primaryTextColor.withValues(alpha: 0.35),
          ),
        ],
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
                isBlocked
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : SaleBrandColors.navy,
                isBlocked
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : Color.lerp(
                        SaleBrandColors.navy,
                        AppColors.accentGold,
                        0.22,
                      )!,
              ],
            ),
            boxShadow: isBlocked
                ? null
                : [
                    BoxShadow(
                      color: AppColors.accentGold.withValues(alpha: 0.28),
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
        onTap: isBlocked ? null : onTap,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(padding: pad, child: child),
        ),
      ),
    );
  }
}

class _CollapsibleDropdownChip extends StatelessWidget {
  const _CollapsibleDropdownChip({
    required this.segments,
    required this.onSegmentTap,
    required this.compact,
    required this.colorScheme,
    required this.primaryTextColor,
    required this.borderRadius,
    required this.features,
    required this.isDesktop,
  });

  final List<BreadcrumbSegment> segments;
  final void Function(BreadcrumbSegment segment) onSegmentTap;
  final bool compact;
  final ColorScheme colorScheme;
  final Color primaryTextColor;
  final BorderRadius borderRadius;
  final BusinessFeaturesProvider features;
  final bool isDesktop;

  void _showDropdown(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<BreadcrumbSegment>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: segments.map((segment) {
        final isBlocked = isContentRouteBlocked(segment.id, features.data);
        return PopupMenuItem<BreadcrumbSegment>(
          value: segment,
          enabled: !isBlocked,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  breadcrumbIconForRouteId(segment.id),
                  size: 16,
                  color: isBlocked
                      ? primaryTextColor.withValues(alpha: 0.3)
                      : AppColors.accentGold,
                ),
                const SizedBox(width: 8),
                Text(
                  segment.title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isBlocked
                        ? primaryTextColor.withValues(alpha: 0.3)
                        : primaryTextColor,
                    decoration: isBlocked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (isBlocked) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      elevation: 6,
    ).then((selected) {
      if (selected != null) {
        onSegmentTap(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 11,
      vertical: compact ? 5 : 7,
    );

    final Widget chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDropdown(context),
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: pad,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.more_horiz_rounded,
                  size: compact ? 14 : 15,
                  color: AppColors.accentGold,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: compact ? 12 : 14,
                  color: AppColors.accentGold,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isDesktop) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: chip,
      );
    }

    return chip;
  }
}
