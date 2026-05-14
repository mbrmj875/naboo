import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../../utils/screen_layout.dart';

/// قائمة المستخدم المنسدلة في الـ AppBar للشاشة الرئيسية.
///
/// تجمع داخل dropdown واحد:
/// - معلومات المستخدم (الاسم + الدور)
/// - تبديل المظهر (Theme Toggle)
/// - الإعدادات
/// - الحاسبة
/// - تبديل لوحة Mac (Desktop فقط — onToggleMacPanel == null في الباقي)
/// - تبديل وضع التحرير (tabletLG+ فقط — يظهر فقط حين `showEditMode == true`)
/// - تسجيل الخروج
///
/// **مظهر الزر**:
/// - `phoneXS`, `phoneSM`, `tabletSM`: أيقونة دائرية فقط (28dp) بحرف من الاسم.
/// - `tabletLG`, `desktopSM`, `desktopLG`: أيقونة + اسم المستخدم + سهم.
class HomeUserMenu extends StatelessWidget {
  const HomeUserMenu({
    super.key,
    required this.userName,
    required this.userRole,
    required this.isDarkMode,
    required this.isEditMode,
    required this.macPanelEnabled,
    required this.onShowUserInfo,
    required this.onToggleTheme,
    required this.onOpenSettings,
    required this.onShowCalculator,
    required this.onToggleEditMode,
    required this.onLogout,
    this.onToggleMacPanel,
    this.showEditMode = false,
  });

  /// اسم المستخدم الفعّال (للعرض في tabletLG+ والـ tooltip).
  final String userName;

  /// دور المستخدم (مدير/كاشير/إلخ).
  final String userRole;

  /// الحالة الحالية للوضع الليلي — لاختيار التسمية والأيقونة.
  final bool isDarkMode;

  /// الحالة الحالية لوضع تحرير الوحدات.
  final bool isEditMode;

  /// الحالة الحالية للوحة Mac (مفعّلة/معطّلة).
  final bool macPanelEnabled;

  /// عند الضغط على معلومات المستخدم — يفتح Dialog التفاصيل.
  final VoidCallback onShowUserInfo;

  /// تبديل الوضع الليلي/النهاري.
  final VoidCallback onToggleTheme;

  /// فتح شاشة الإعدادات.
  final VoidCallback onOpenSettings;

  /// عرض الحاسبة العائمة.
  final VoidCallback onShowCalculator;

  /// تبديل وضع تحرير الوحدات (إعادة الترتيب).
  final VoidCallback onToggleEditMode;

  /// تسجيل الخروج.
  final VoidCallback onLogout;

  /// تبديل لوحة Mac الجانبية. **null على غير الديسكتوب** ⇒ الخيار يختفي تماماً.
  final VoidCallback? onToggleMacPanel;

  /// هل يظهر خيار "وضع التحرير"؟ true فقط في tabletLG+ (Home يتحكم به).
  final bool showEditMode;

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;
    final isWide = variant.index >= DeviceVariant.tabletLG.index;
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<_HomeUserMenuAction>(
      tooltip: userName.isNotEmpty ? userName : 'الحساب',
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      offset: const Offset(0, 44),
      onSelected: (action) => _handle(action),
      itemBuilder: (_) => _items(context),
      child: _buildButtonChild(context, isWide),
    );
  }

  Widget _buildButtonChild(BuildContext context, bool isWide) {
    final cs = Theme.of(context).colorScheme;
    final onPrimary = cs.onPrimary;
    final initial = _initial();

    final avatar = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
          color: onPrimary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (!isWide) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.xs,
        ),
        child: avatar,
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              userName.isEmpty ? 'الحساب' : userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: onPrimary.withValues(alpha: 0.78),
          ),
        ],
      ),
    );
  }

  String _initial() {
    final name = userName.trim();
    if (name.isEmpty) return '?';
    final firstChar = name.characters.first;
    return firstChar.toUpperCase();
  }

  void _handle(_HomeUserMenuAction action) {
    switch (action) {
      case _HomeUserMenuAction.profile:
        onShowUserInfo();
      case _HomeUserMenuAction.theme:
        onToggleTheme();
      case _HomeUserMenuAction.settings:
        onOpenSettings();
      case _HomeUserMenuAction.calculator:
        onShowCalculator();
      case _HomeUserMenuAction.macPanel:
        onToggleMacPanel?.call();
      case _HomeUserMenuAction.editMode:
        onToggleEditMode();
      case _HomeUserMenuAction.logout:
        onLogout();
    }
  }

  List<PopupMenuEntry<_HomeUserMenuAction>> _items(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <PopupMenuEntry<_HomeUserMenuAction>>[
      // معلومات المستخدم (Header)
      PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.profile,
        child: _MenuRow(
          icon: Icons.person_outline_rounded,
          title: userName.isEmpty ? 'الحساب' : userName,
          subtitle: userRole.isEmpty ? null : userRole,
          color: cs.primary,
        ),
      ),
      const PopupMenuDivider(),
      // تبديل المظهر
      PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.theme,
        child: _MenuRow(
          icon: isDarkMode
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
          title: isDarkMode ? 'الوضع النهاري' : 'الوضع الليلي',
        ),
      ),
      const PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.calculator,
        child: _MenuRow(
          icon: Icons.calculate_rounded,
          title: 'حاسبة',
        ),
      ),
      const PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.settings,
        child: _MenuRow(
          icon: Icons.settings_rounded,
          title: 'الإعدادات',
        ),
      ),
    ];

    // لوحة Mac — على الديسكتوب فقط (onToggleMacPanel == null في الباقي)
    if (onToggleMacPanel != null) {
      entries.add(
        PopupMenuItem<_HomeUserMenuAction>(
          value: _HomeUserMenuAction.macPanel,
          child: _MenuRow(
            icon: macPanelEnabled
                ? Icons.dashboard_customize_rounded
                : Icons.dashboard_customize_outlined,
            title: macPanelEnabled
                ? 'إخفاء لوحة Mac'
                : 'إظهار لوحة Mac',
          ),
        ),
      );
    }

    // وضع التحرير — على tabletLG+ فقط (Home يمرر showEditMode = true)
    if (showEditMode) {
      entries.add(
        PopupMenuItem<_HomeUserMenuAction>(
          value: _HomeUserMenuAction.editMode,
          child: _MenuRow(
            icon: isEditMode ? Icons.check_rounded : Icons.edit_rounded,
            title: isEditMode ? 'إنهاء التحرير' : 'تخصيص الوحدات',
          ),
        ),
      );
    }

    entries.add(const PopupMenuDivider());
    entries.add(
      PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.logout,
        child: _MenuRow(
          icon: Icons.logout_rounded,
          title: 'تسجيل الخروج',
          color: cs.error,
        ),
      ),
    );

    return entries;
  }
}

enum _HomeUserMenuAction {
  profile,
  theme,
  settings,
  calculator,
  macPanel,
  editMode,
  logout,
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(icon, size: 18, color: effectiveColor),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: effectiveColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
