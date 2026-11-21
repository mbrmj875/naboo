import 'package:flutter/material.dart';

import '../../navigation/shell/shell_nav_item.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/screen_layout.dart';
import '../sidebar_nav_highlight.dart';

/// الشريط الجانبي للحاسبة: مطوي 56 وموسّع 220 مع قوائم فرعية وقفل الجلسة.
class ShellSidebar extends StatefulWidget {
  const ShellSidebar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.userName,
    required this.userRole,
    required this.onItemTap,
    required this.onSubItemTap,
    required this.onLockSession,
  });

  static const double collapsedWidth = 56;
  static const double expandedWidth = 220;

  final List<ShellNavItem> items;
  final int activeIndex;
  final String userName;
  final String userRole;
  final ValueChanged<ShellNavItem> onItemTap;
  final ValueChanged<ShellNavSubItem> onSubItemTap;
  final VoidCallback onLockSession;

  @override
  State<ShellSidebar> createState() => _ShellSidebarState();
}

class _ShellSidebarState extends State<ShellSidebar> {
  bool _expanded = false;
  final Set<String> _openSubmenus = {};

  void _toggleItem(ShellNavItem item) {
    setState(() {
      if (!_openSubmenus.remove(item.routeId)) {
        _openSubmenus.add(item.routeId);
        _expanded = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? Color.lerp(cs.primary, Colors.black, 0.45)!
        : cs.primary;
    final panelCurve = Radius.circular(ac.isRounded ? ac.rLg + 10 : 0);

    return AnimatedContainer(
      key: const ValueKey('shell-sidebar'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      width: _expanded ? ShellSidebar.expandedWidth : ShellSidebar.collapsedWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: panelCurve,
          bottomLeft: panelCurve,
        ),
        child: ColoredBox(
          color: background,
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: IconButton(
                  tooltip: _expanded ? 'طي القائمة' : 'توسيع القائمة',
                  padding: const EdgeInsets.all(10),
                  style: IconButton.styleFrom(foregroundColor: cs.onPrimary),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: const Icon(Icons.menu_rounded, size: 22),
                ),
              ),
              if (_expanded)
                Container(
                  width: double.infinity,
                  padding: EdgeInsetsDirectional.only(
                    start: sl.pageHorizontalGap,
                    end: sl.pageHorizontalGap,
                    top: 8,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.userRole.isNotEmpty ? widget.userRole : 'NaBoo',
                        style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.72),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              Divider(
                color: cs.onPrimary.withValues(alpha: 0.18),
                height: 1,
                thickness: 1,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      _buildItem(
                        widget.items[i],
                        isActive: i == widget.activeIndex,
                      ),
                    Divider(
                      color: cs.onPrimary.withValues(alpha: 0.18),
                      height: 16,
                      thickness: 1,
                    ),
                    if (_expanded)
                      SidebarLogoutPill(
                        colorScheme: cs,
                        label: 'قفل الجلسة',
                        onTap: widget.onLockSession,
                      )
                    else
                      IconButton(
                        tooltip: 'قفل الجلسة',
                        onPressed: widget.onLockSession,
                        icon: const Icon(Icons.logout, color: Colors.red),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(ShellNavItem item, {required bool isActive}) {
    final cs = Theme.of(context).colorScheme;
    final hasSubmenu = item.hasSubItems;
    final isOpen = _openSubmenus.contains(item.routeId);
    final enabled = hasSubmenu || !item.disabled;

    return Column(
      children: [
        Tooltip(
          message: item.disabled
              ? 'غير متاح في الوضع المقيّد'
              : (_expanded ? '' : item.title),
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              splashColor: cs.onPrimary.withValues(alpha: 0.14),
              highlightColor: cs.onPrimary.withValues(alpha: 0.07),
              onTap: !enabled
                  ? null
                  : () => hasSubmenu
                        ? _toggleItem(item)
                        : widget.onItemTap(item),
              child: SizedBox(
                height: 48,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showRow = _expanded && constraints.maxWidth >= 140;
                    if (!showRow) {
                      return Center(child: _collapsedIcon(item, isActive));
                    }
                    return _expandedRow(item, isActive, isOpen);
                  },
                ),
              ),
            ),
          ),
        ),
        if (hasSubmenu && isOpen && _expanded)
          ColoredBox(
            color: cs.onPrimary.withValues(alpha: 0.1),
            child: Column(
              children: [
                for (final sub in item.subItems!)
                  InkWell(
                    onTap: sub.disabled ? null : () => widget.onSubItemTap(sub),
                    splashColor: cs.onPrimary.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 10,
                        end: 14,
                      ),
                      child: SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            if (sub.icon != null) ...[
                              Icon(
                                sub.icon,
                                size: 17,
                                color: cs.onPrimary.withValues(alpha: 0.88),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                sub.title,
                                style: TextStyle(
                                  color: cs.onPrimary.withValues(alpha: 0.95),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _collapsedIcon(ShellNavItem item, bool isActive) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive
            ? cs.surface.withValues(alpha: 0.95)
            : Colors.transparent,
        border: isActive
            ? Border.all(color: cs.onPrimary.withValues(alpha: 0.35))
            : null,
        boxShadow: isActive
            ? [BoxShadow(color: cs.shadow.withValues(alpha: 0.2), blurRadius: 8)]
            : null,
      ),
      child: Icon(
        item.icon,
        size: 22,
        color: item.disabled
            ? cs.onPrimary.withValues(alpha: 0.35)
            : (isActive ? cs.primary : item.iconColor),
      ),
    );
  }

  Widget _expandedRow(ShellNavItem item, bool isActive, bool isOpen) {
    final cs = Theme.of(context).colorScheme;
    final row = Padding(
      padding: EdgeInsetsDirectional.only(start: isActive ? 2 : 4, end: 12),
      child: Row(
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: isActive ? 1.06 : 1,
            child: Icon(
              item.icon,
              size: 22,
              color: item.iconColor.withValues(alpha: isActive ? 1 : 0.85),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                color: isActive ? cs.onSurface : cs.onPrimary,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.hasSubItems)
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: isActive
                    ? cs.onSurface.withValues(alpha: 0.55)
                    : cs.onPrimary.withValues(alpha: 0.65),
                size: 18,
              ),
            ),
        ],
      ),
    );
    if (!isActive) return row;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Material(
        color: cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        child: row,
      ),
    );
  }
}
