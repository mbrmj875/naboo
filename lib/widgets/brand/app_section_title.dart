import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sale_pos_settings_data.dart';
import '../../providers/sale_pos_settings_provider.dart';
import '../../utils/screen_layout.dart';

/// عنوان قسم مع **شريط ذهبي عمودي** على اليمين — جزء من Brand DNA
/// (انظر `docs/screen_migration_playbook.md` §12.4).
///
/// **مثال للاستخدام**:
/// ```dart
/// AppSectionTitle(
///   title: 'تفاصيل العميل',
///   caption: 'البيانات الأساسية وأرقام الاتصال',
///   trailing: IconButton(icon: Icon(Icons.edit), onPressed: ...),
/// )
/// ```
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.dense = false,
  });

  /// النص الأساسي للعنوان (وزن خط 800).
  final String title;

  /// نص فرعي اختياري — يَظهر تحت العنوان بـ alpha 0.62.
  final String? caption;

  /// widget اختياري على يسار العنوان (زر إجراء، tag، إلخ).
  final Widget? trailing;

  /// كثافة الترسيم — `true` للقوائم المكدَّسة (font أصغر، شريط أقصر).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final palette = SalePalette.fromSettings(
      context.read<SalePosSettingsProvider>().data,
      theme,
    );
    final wide = !ScreenLayout.of(context).showSaleBarcodeShortcut && !dense;
    final titleColor = dark ? const Color(0xFFF1EDE6) : palette.navy;
    final capColor = dark
        ? const Color(0xFFCBD5E1)
        : palette.navy.withValues(alpha: 0.62);
    return Padding(
      padding: EdgeInsets.only(bottom: wide ? 12 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الشريط الذهبي العمودي مع توهج خفيف — العلامة المميزة لـ Brand DNA.
          Container(
            width: wide ? 4 : 3,
            height: wide ? 46 : 42,
            decoration: BoxDecoration(
              color: palette.gold,
              boxShadow: [
                BoxShadow(
                  color: palette.gold.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          SizedBox(width: wide ? 14 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: wide ? 17 : 16,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    letterSpacing: -0.2,
                    height: 1.25,
                  ),
                ),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    caption!,
                    style: TextStyle(
                      fontSize: wide ? 11.5 : 11,
                      height: 1.45,
                      color: capColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
