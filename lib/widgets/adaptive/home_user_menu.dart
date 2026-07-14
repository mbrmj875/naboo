import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';

/// قائمة المستخدم المنسدلة في الـ AppBar للشاشة الرئيسية.
///
/// تجمع داخل dropdown واحد:
/// - معلومات المستخدم (الاسم + الدور)
/// - تبديل المظهر (Theme Toggle)
/// - الإعدادات
/// - الحاسبة
/// - تبديل وضع التحرير (tabletLG+ فقط — يظهر فقط حين `showEditMode == true`)
/// - قفل الجلسة (العودة لبوابة الموظفين — لا فصل من السيرفر)
class HomeUserMenu extends StatelessWidget {
  const HomeUserMenu({
    super.key,
    required this.userName,
    required this.userRole,
    required this.isDarkMode,
    required this.isEditMode,
    required this.onShowUserInfo,
    required this.onToggleTheme,
    required this.onOpenSettings,
    required this.onShowCalculator,
    required this.onToggleEditMode,
    required this.onLogout,
    this.showEditMode = false,
  });

  final String userName;
  final String userRole;
  final bool isDarkMode;
  final bool isEditMode;
  final VoidCallback onShowUserInfo;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowCalculator;
  final VoidCallback onToggleEditMode;
  final VoidCallback onLogout;
  final bool showEditMode;

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;
    final isWide = variant.index >= DeviceVariant.tabletLG.index;
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<_HomeUserMenuAction>(
      tooltip: userName.isNotEmpty ? userName : 'الحساب',
      color: isDarkMode ? const Color(0xFF1E293B) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
      ),
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
        color: AppColors.accentGold.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.accentGold,
          fontSize: initial.length > 1 ? 11 : 13,
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
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0].characters.first}${parts[1].characters.first}'.toUpperCase();
    }
    final chars = name.characters;
    return chars.take(chars.length >= 2 ? 2 : 1).toString().toUpperCase();
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
      case _HomeUserMenuAction.editMode:
        onToggleEditMode();
      case _HomeUserMenuAction.logout:
        onLogout();
    }
  }

  List<PopupMenuEntry<_HomeUserMenuAction>> _items(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <PopupMenuEntry<_HomeUserMenuAction>>[
      PopupMenuItem<_HomeUserMenuAction>(
        value: _HomeUserMenuAction.profile,
        child: _MenuRow(
          icon: Icons.person_outline_rounded,
          title: userName.isEmpty ? 'الحساب' : userName,
          subtitle: userRole.isEmpty ? null : userRole,
          color: AppColors.accentGold,
        ),
      ),
      const PopupMenuDivider(),
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
          title: 'قفل الجلسة',
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
    final effectiveColor = color ?? AppColors.accentGold;
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
                  fontWeight: FontWeight.w600,
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
