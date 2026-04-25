import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'product_settings_screen.dart';
import 'barcode_settings_screen.dart';
import 'categories_settings_screen.dart';
import 'brands_settings_screen.dart';
import 'unit_templates_settings_screen.dart';

// ── ألوان الواجهة ─────────────────────────────────────────────────────────────
const _kAccent = Color(0xFF1E3A5F);

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
        final isDark = tp.isDarkMode;
        final bg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F5F9);
        final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
        final textMuted = isDark ? Colors.grey.shade500 : Colors.grey.shade500;
        final divColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              backgroundColor: _kAccent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'إعدادات المخزون',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _SectionHeader(
                  icon: Icons.tune_outlined,
                  title: 'الإعدادات الفرعية',
                  subtitle: 'إعدادات تفصيلية لكل جانب من جوانب المخزون',
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                const SizedBox(height: 10),
                _SubSettingsGrid(
                  surface: surface,
                  divColor: divColor,
                  items: [
                    _SubSettingItem(
                      icon: Icons.add_box_outlined,
                      title: 'إعدادات إضافة منتج',
                      desc: 'الحقول الافتراضية، المخزن الافتراضي، حقول إلزامية',
                      color: _kAccent,
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
                      color: _kAccent,
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
                      color: _kAccent,
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
                      color: _kAccent,
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
                      color: _kAccent,
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
            color: _kAccent.withOpacity(0.08),
            borderRadius: BorderRadius.zero,
          ),
          child: Icon(icon, color: _kAccent, size: 20),
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
                ? widget.item.color.withOpacity(0.06)
                : widget.surface,
            border: Border.all(
              color: _hovered
                  ? widget.item.color.withOpacity(0.5)
                  : widget.divColor,
              width: _hovered ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.zero,
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
