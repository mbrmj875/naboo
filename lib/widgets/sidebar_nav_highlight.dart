import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_corner_style.dart';

/// تمييز صف نشط في الشريط الجانبي الثابت: لون من [ColorScheme.surface]
/// وزوايا كبيرة نحو **اليسار** (جهة المحتوى) لتقليد شكل «اللسان» المنحني.
///
/// الإحداثيات محلية للشريط: اليسار = نحو منطقة المحتوى (حتى مع RTL).
class SidebarActiveRowBackground extends StatelessWidget {
  const SidebarActiveRowBackground({
    super.key,
    required this.child,
    required this.highlightColor,
    required this.colorScheme,
    this.margin = const EdgeInsetsDirectional.only(end: 10, top: 5, bottom: 5),
  });

  final Widget child;
  final Color highlightColor;
  final ColorScheme colorScheme;
  final EdgeInsetsDirectional margin;

  @override
  Widget build(BuildContext context) {
    final ac = context.appCorners;
    final towardContent = math.max(ac.rLg + 6, 18.0);
    final inward = math.max(ac.rSm, 6.0);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlightColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(towardContent),
            bottomLeft: Radius.circular(towardContent),
            topRight: Radius.circular(inward),
            bottomRight: Radius.circular(inward),
          ),
          boxShadow: [
            if (ac.isRounded)
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(-4, 3),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

/// زر تسجيل خروج بشكل حبة (مرجع واجهات حديثة) — ألوان من الثيم.
class SidebarLogoutPill extends StatelessWidget {
  const SidebarLogoutPill({
    super.key,
    required this.onTap,
    required this.label,
    required this.colorScheme,
  });

  final VoidCallback onTap;
  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final ac = context.appCorners;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: LayoutBuilder(
        builder: (context, c) {
          // أثناء تحريك عرض الشريط الجانب يقل العرض مؤقتاً — أيقونة فقط دون نص.
          final narrow = c.maxWidth < 96;
          return Material(
            color: colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(ac.rFab > 0 ? ac.rFab : 20),
            elevation: ac.isRounded ? 1 : 0,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(ac.rFab > 0 ? ac.rFab : 20),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 6 : 10,
                  vertical: 10,
                ),
                child: narrow
                    ? Center(
                        child: Icon(
                          Icons.logout_rounded,
                          color: colorScheme.error,
                          size: 22,
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
