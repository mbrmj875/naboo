import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../../utils/screen_layout.dart';

/// بانر معلومات حالة وردية المستخدم وصلاحياته.
///
/// يتصرف بشكل مختلف حسب [DeviceVariant]:
/// - [DeviceVariant.phoneXS]: لا يظهر (المعلومة تنتقل لأيقونة في الـ AppBar).
/// - [DeviceVariant.phoneSM], [DeviceVariant.tabletSM], [DeviceVariant.tabletLG]:
///   شريط نحيف (32dp تقريباً) بمحتوى مختصر.
/// - [DeviceVariant.desktopSM], [DeviceVariant.desktopLG]:
///   شريط كامل تحت الـ AppBar مع نص توضيحي.
///
/// يُستخدم في `AdaptiveScaffold.bottomBanner` slot.
class ShiftPermissionBanner extends StatelessWidget {
  const ShiftPermissionBanner({
    super.key,
    required this.userName,
    this.roleName,
    this.onTap,
    this.icon = Icons.shield_outlined,
  });

  /// اسم المستخدم الفعّال.
  final String userName;

  /// اسم الدور (اختياري، مثل "مدير" / "كاشير").
  final String? roleName;

  /// عند النقر — يفتح تفاصيل الصلاحيات/الوردية.
  final VoidCallback? onTap;

  /// أيقونة الشريط.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;

    if (variant == DeviceVariant.phoneXS) {
      // في phoneXS البانر يختفي — المعلومة تظهر كأيقونة في الـ AppBar
      // (يدير ذلك الـ HomeScreen عبر appBarActions).
      return const SizedBox.shrink();
    }

    final isDesktop = variant == DeviceVariant.desktopSM ||
        variant == DeviceVariant.desktopLG;

    if (isDesktop) {
      return _buildDesktopBanner(context);
    }
    return _buildCompactBanner(context);
  }

  /// بانر مضغوط للموبايل (phoneSM) والتابلت.
  Widget _buildCompactBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _compactText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_left,
                    size: 16,
                    color: cs.onPrimaryContainer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بانر كامل للديسكتوب — نص توضيحي + رمز + تفاصيل.
  Widget _buildDesktopBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _fullText(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onTap != null)
                TextButton.icon(
                  onPressed: onTap,
                  icon: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: cs.onPrimaryContainer,
                  ),
                  label: Text(
                    'تفاصيل',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _compactText() {
    if (roleName != null && roleName!.isNotEmpty) {
      return 'وردية $userName - $roleName';
    }
    return 'وردية $userName';
  }

  String _fullText() {
    if (roleName != null && roleName!.isNotEmpty) {
      return 'صلاحيات التشغيل مرتبطة بنوبة الوردية - $userName ($roleName)';
    }
    return 'صلاحيات التشغيل مرتبطة بنوبة الوردية - $userName';
  }
}
