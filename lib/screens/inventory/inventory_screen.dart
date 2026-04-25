import 'package:flutter/material.dart';
import '../../widgets/app_notifications_sheet.dart';
import 'inventory_products_screen.dart';
import 'stock_voucher_screen.dart';
import 'warehouses_screen.dart';
import 'price_lists_screen.dart';
import 'stocktaking_screen.dart';
import 'inventory_management_screen.dart';
import 'inventory_settings_screen.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _navy   = Color(0xFF1E3A5F);
const _teal   = Color(0xFF0D9488);
const _bg     = Color(0xFFF1F5F9);
const _card   = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1     = Color(0xFF0F172A);
const _t2     = Color(0xFF64748B);
const _green  = Color(0xFF10B981);
const _orange = Color(0xFFF97316);
const _blue   = Color(0xFF3B82F6);
const _purple = Color(0xFF8B5CF6);

// ══════════════════════════════════════════════════════════════════════════════
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('إدارة المخزون',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, size: 22),
              tooltip: 'التنبيهات',
              onPressed: () => showAppNotificationsSheet(context),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 22),
              tooltip: 'إعدادات المخزون',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InventorySettingsScreen())),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatsBar(),
              const SizedBox(height: 16),
              _QuickActionsCard(context: context),
              const SizedBox(height: 20),
              _sectionTitle('الأقسام الرئيسية'),
              const SizedBox(height: 12),
              _ModulesGrid(context: context),
              const SizedBox(height: 20),
              _sectionTitle('آخر الحركات المخزونية'),
              const SizedBox(height: 12),
              const _RecentMovements(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: _t1));
}

// ══════════════════════════════════════════════════════════════════════════════
// STATS BAR — 4 بطاقات إحصاء
// ══════════════════════════════════════════════════════════════════════════════
class _StatsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        _StatCard(
          icon: Icons.inventory_2_rounded,
          color: _blue,
          bg: Color(0xFFEFF6FF),
          title: 'إجمالي المنتجات',
          value: '248',
          unit: 'صنف',
        ),
        _StatCard(
          icon: Icons.monetization_on_rounded,
          color: _green,
          bg: Color(0xFFD1FAE5),
          title: 'قيمة المخزون',
          value: '4.25M',
          unit: 'د.ع',
        ),
        _StatCard(
          icon: Icons.warning_amber_rounded,
          color: _orange,
          bg: Color(0xFFFFEDD5),
          title: 'مخزون منخفض',
          value: '12',
          unit: 'صنف',
        ),
        _StatCard(
          icon: Icons.warehouse_rounded,
          color: _purple,
          bg: Color(0xFFF5F3FF),
          title: 'المستودعات',
          value: '3',
          unit: 'مستودع',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String value;
  final String unit;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.zero),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 11, color: _t2),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(width: 4),
                    Text(unit,
                        style: const TextStyle(fontSize: 11, color: _t2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUICK ACTIONS
// ══════════════════════════════════════════════════════════════════════════════
class _QuickActionsCard extends StatelessWidget {
  final BuildContext context;
  const _QuickActionsCard({required this.context});

  @override
  Widget build(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('إجراءات سريعة',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: _t2)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _QuickBtn(
                icon: Icons.add_box_rounded,
                label: 'إضافة منتج',
                color: _blue,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const InventoryProductsScreen())),
              ),
              _QuickBtn(
                icon: Icons.swap_vert_rounded,
                label: 'سند مخزوني',
                color: _purple,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StockVoucherScreen())),
              ),
              _QuickBtn(
                icon: Icons.fact_check_rounded,
                label: 'جرد دوري',
                color: _orange,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StocktakingScreen())),
              ),
              _QuickBtn(
                icon: Icons.analytics_rounded,
                label: 'الحركات',
                color: _teal,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const InventoryManagementScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _t2)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MODULES GRID — 6 بطاقات أقسام
// ══════════════════════════════════════════════════════════════════════════════
class _ModulesGrid extends StatelessWidget {
  final BuildContext context;
  const _ModulesGrid({required this.context});

  @override
  Widget build(BuildContext ctx) {
    final mods = [
      _ModDef(
        icon: Icons.category_outlined,
        color: _blue,
        bg: const Color(0xFFEFF6FF),
        title: 'المنتجات',
        sub: 'عرض وإدارة جميع الأصناف',
        badge: '248',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InventoryProductsScreen())),
      ),
      _ModDef(
        icon: Icons.warehouse_outlined,
        color: _teal,
        bg: const Color(0xFFCCFBF1),
        title: 'المستودعات',
        sub: 'مراقبة الأرصدة والأماكن',
        badge: '3',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WarehousesScreen())),
      ),
      _ModDef(
        icon: Icons.swap_horiz_rounded,
        color: _purple,
        bg: const Color(0xFFF5F3FF),
        title: 'السندات المخزونية',
        sub: 'إيداع وصرف ونقل',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const StockVoucherScreen())),
      ),
      _ModDef(
        icon: Icons.price_change_outlined,
        color: _green,
        bg: const Color(0xFFD1FAE5),
        title: 'فوائم الأسعار',
        sub: 'تجزئة وجملة وخاصة',
        badge: '2',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PriceListsScreen())),
      ),
      _ModDef(
        icon: Icons.fact_check_outlined,
        color: _orange,
        bg: const Color(0xFFFFEDD5),
        title: 'الجرد الدوري',
        sub: 'تسوية الفروقات الفعلية',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const StocktakingScreen())),
      ),
      _ModDef(
        icon: Icons.settings_outlined,
        color: const Color(0xFF37474F),
        bg: const Color(0xFFECEFF1),
        title: 'إعدادات المخزون',
        sub: 'وحدات، تصنيفات، طباعة',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InventorySettingsScreen())),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: mods.map((m) => _ModuleCard(mod: m)).toList(),
    );
  }
}

class _ModDef {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String sub;
  final String? badge;
  final VoidCallback onTap;
  const _ModDef({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.sub,
    required this.onTap,
    this.badge,
  });
}

class _ModuleCard extends StatefulWidget {
  final _ModDef mod;
  const _ModuleCard({required this.mod});

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.mod;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        m.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: _pressed ? m.color.withValues(alpha: 0.4) : _border,
              width: _pressed ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.08 : 0.04),
                blurRadius: _pressed ? 12 : 8,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: m.bg, borderRadius: BorderRadius.zero),
                  child: Icon(m.icon, color: m.color, size: 22),
                ),
                if (m.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(m.badge!,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: m.color)),
                  ),
              ],
            ),
            const Spacer(),
            Text(m.title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _t1)),
            const SizedBox(height: 3),
            Text(m.sub,
                style: const TextStyle(fontSize: 11, color: _t2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECENT MOVEMENTS
// ══════════════════════════════════════════════════════════════════════════════
class _RecentMovements extends StatelessWidget {
  const _RecentMovements();

  static const _movements = [
    ('in',       'Pringles-1250',          '+50 قطعة',  'المستودع الرئيسي', 'اليوم، 10:30'),
    ('out',      'Coca-Cola 330ml',         '-20 علبة',  'مستودع المبيعات',  'أمس، 14:15'),
    ('transfer', 'رز الحياني 5 كيلو',      '×30 كيس',   'تحويل داخلي',      'أمس، 09:00'),
    ('in',       'Pepsi 500ml',            '+100 زجاجة', 'المستودع الرئيسي', 'الإثنين'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('آخر الحركات',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _t2)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const InventoryManagementScreen())),
                  child: const Text('عرض الكل',
                      style: TextStyle(fontSize: 12, color: _teal)),
                ),
              ],
            ),
          ),
          for (final m in _movements)
            _MoveTile(type: m.$1, name: m.$2, qty: m.$3, loc: m.$4, date: m.$5),
        ],
      ),
    );
  }
}

class _MoveTile extends StatelessWidget {
  final String type;
  final String name;
  final String qty;
  final String loc;
  final String date;
  const _MoveTile(
      {required this.type,
      required this.name,
      required this.qty,
      required this.loc,
      required this.date});

  @override
  Widget build(BuildContext context) {
    final (ico, col, lbl) = switch (type) {
      'in'       => (Icons.arrow_downward_rounded, _green, 'إيداع'),
      'out'      => (Icons.arrow_upward_rounded, Colors.red.shade500, 'صرف'),
      'transfer' => (Icons.swap_horiz_rounded, _blue, 'تحويل'),
      _          => (Icons.circle, _t2, ''),
    };

    return Column(
      children: [
        const Divider(height: 1, color: _border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.zero,
                ),
                child: Icon(ico, color: col, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _t1)),
                    const SizedBox(height: 2),
                    Text('$lbl • $loc',
                        style: const TextStyle(fontSize: 11, color: _t2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(qty,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: col)),
                  const SizedBox(height: 2),
                  Text(date,
                      style: const TextStyle(fontSize: 10, color: _t2)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
