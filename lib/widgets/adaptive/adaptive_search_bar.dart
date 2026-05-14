import 'package:flutter/material.dart';
import '../../utils/screen_layout.dart';
import '../../theme/app_spacing.dart';

/// شريط بحث متجاوب يتغير شكله وسلوكه حسب حجم الشاشة.
/// 
/// - في الهواتف: يختفي مع التمرير (إذا وُضع داخل Sliver) أو يظهر كأيقونة.
/// - في التابلت: شريط علوي دائم.
/// - في الكمبيوتر: شريط وسطي مع اختصارات لوحة مفاتيح (Ctrl+K).
class AdaptiveSearchBar extends StatelessWidget {
  const AdaptiveSearchBar({
    super.key,
    this.hintText = 'بحث...',
    this.onChanged,
    this.onSubmitted,
    this.controller,
  });

  static const double _desktopSearchWidth = 480.0;

  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;

    final isDesktop = variant == DeviceVariant.desktopSM || variant == DeviceVariant.desktopLG;

    return Center(
      child: Container(
        // تحديد أقصى عرض لشريط البحث في الديسكتوب
        width: isDesktop ? _desktopSearchWidth : double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: isDesktop 
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Ctrl+K',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  )
                : null,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
      ),
    );
  }
}
