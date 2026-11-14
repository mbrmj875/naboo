import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../utils/screen_layout.dart';
import 'product_settings_screen.dart';
import 'barcode_settings_screen.dart';
import 'categories_settings_screen.dart';
import 'brands_settings_screen.dart';
import 'unit_templates_settings_screen.dart';

import '../../theme/design_tokens.dart';

class InventorySettingsScreen extends StatefulWidget {
  const InventorySettingsScreen({super.key});

  @override
  State<InventorySettingsScreen> createState() =>
      _InventorySettingsScreenState();
}

class _InventorySettingsScreenState extends State<InventorySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, tp, _) {
        final cs = Theme.of(context).colorScheme;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurface,
              iconTheme: IconThemeData(color: cs.onSurface),
              elevation: 0,
              title: Text(
                'إعدادات المخزون',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            body: ListView(
              padding: EdgeInsetsDirectional.only(
                start: ScreenLayout.of(context).pageHorizontalGap,
                end: ScreenLayout.of(context).pageHorizontalGap,
                top: 16,
                bottom: 32,
              ),
              children: [
                _SectionHeader(
                  icon: Icons.tune_outlined,
                  title: 'الإعدادات الفرعية',
                  subtitle: 'إعدادات تفصيلية لكل جانب من جوانب المخزون',
                  textPrimary: cs.onSurface,
                  textMuted: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                _SubSettingsGrid(
                  surface: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  divColor: cs.outlineVariant.withValues(alpha: 0.5),
                  items: [
                    _SubSettingItem(
                      icon: Icons.add_box_outlined,
                      title: 'إعدادات إضافة منتج',
                      desc: 'الحقول الافتراضية، المخزن الافتراضي، حقول إلزامية',
                      color: AppColors.accentGold,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ProductSettingsScreen(),
                        ),
                      ),
                    ),
                    _SubSettingItem(
                      icon: Icons.qr_code_outlined,
                      title: 'إعدادات الباركود',
                      desc: 'معيار الباركود، الحقول المدمجة في الباركود',
                      color: AppColors.accentGold,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BarcodeSettingsScreen(),
                        ),
                      ),
                    ),
                    _SubSettingItem(
                      icon: Icons.category_outlined,
                      title: 'الفئات والتصنيفات',
                      desc: 'إضافة وتعديل وحذف فئات المنتجات',
                      color: AppColors.accentGold,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const CategoriesSettingsScreen(),
                        ),
                      ),
                    ),
                    _SubSettingItem(
                      icon: Icons.branding_watermark_outlined,
                      title: 'الماركات والعلامات التجارية',
                      desc: 'إضافة وتعديل وحذف الماركات',
                      color: AppColors.accentGold,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BrandsSettingsScreen(),
                        ),
                      ),
                    ),
                    _SubSettingItem(
                      icon: Icons.straighten_outlined,
                      title: 'قوالب وحدات القياس',
                      desc: 'تعريف وحدات البيع والشراء وعوامل التحويل',
                      color: AppColors.accentGold,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const UnitTemplatesSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// مكونات الواجهة المساعدة
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textPrimary,
    required this.textMuted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color textPrimary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.accentGold, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── شبكة الإعدادات الفرعية ────────────────────────────────────────────────────

class _SubSettingItem {
  const _SubSettingItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final VoidCallback onTap;
}

class _SubSettingsGrid extends StatelessWidget {
  const _SubSettingsGrid({
    required this.items,
    required this.surface,
    required this.divColor,
  });

  final List<_SubSettingItem> items;
  final Color surface;
  final Color divColor;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 90,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _SubSettingCard(item: items[i], surface: surface, divColor: divColor),
    );
  }
}

class _SubSettingCard extends StatefulWidget {
  const _SubSettingCard({
    required this.item,
    required this.surface,
    required this.divColor,
  });

  final _SubSettingItem item;
  final Color surface;
  final Color divColor;

  @override
  State<_SubSettingCard> createState() => _SubSettingCardState();
}

class _SubSettingCardState extends State<_SubSettingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.item.color.withValues(alpha: 0.1)
                : widget.surface,
            border: Border.all(
              color: _hovered
                  ? widget.item.color.withValues(alpha: 0.5)
                  : widget.divColor,
              width: _hovered ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                color: _hovered ? widget.item.color : Colors.grey.shade400,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _hovered ? widget.item.color : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.item.desc,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade500,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: _hovered ? widget.item.color : Colors.grey.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
