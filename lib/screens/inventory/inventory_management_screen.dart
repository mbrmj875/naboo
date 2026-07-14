import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/inventory_repository.dart';
import '../../utils/screen_layout.dart';
import 'stock_voucher_screen.dart';

import '../../theme/design_tokens.dart';

const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);
const _blue = Color(0xFF3B82F6);

// ══════════════════════════════════════════════════════════════════════════════
class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({super.key});

  @override
  State<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  String _filter = 'الكل';
  String _sortBy = 'الأحدث';
  final _searchCtrl = TextEditingController();
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  static const _filterOptions = ['الكل', 'إيداع', 'صرف', 'تحويل'];
  static const _sortOptions = ['الأحدث', 'الأقدم'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mappedType = switch (_filter) {
        'إيداع' => 'in',
        'صرف' => 'out',
        'تحويل' => 'transfer',
        _ => null,
      };
      final rows = await _repo.listStockMovements(
        type: mappedType,
        search: _searchCtrl.text,
        oldestFirst: _sortBy == 'الأقدم',
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر تحميل الحركات: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalIn =>
      _rows.where((m) => (m['voucherType']?.toString() ?? '') == 'in').length;
  int get _totalOut =>
      _rows.where((m) => (m['voucherType']?.toString() ?? '') == 'out').length;
  int get _totalTransfer => _rows
      .where((m) => (m['voucherType']?.toString() ?? '') == 'transfer')
      .length;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _isDark ? AppColors.primaryDark : const Color(0xFFF1F5F9);
    final borderColor = _isDark ? AppColors.accentGold.withValues(alpha: 0.35) : AppColors.accentGold.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'حركات المخزون',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: cs.onSurface),
        ),
        backgroundColor: bg,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentGold,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StockVoucherScreen()),
        ),
        icon: Icon(Icons.add_rounded, color: _isDark ? AppColors.primaryDark : Colors.white),
        label: Text(
          'سند جديد',
          style: TextStyle(color: _isDark ? AppColors.primaryDark : Colors.white, fontWeight: FontWeight.bold),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      body: Column(
        children: [
          // ── Summary bar ─────────────────────────────────────────────────
          Container(
            color: bg,
            padding: EdgeInsetsDirectional.only(
              start: ScreenLayout.of(context).pageHorizontalGap,
              end: ScreenLayout.of(context).pageHorizontalGap,
              top: 0,
              bottom: 16,
            ),
            child: Row(
              children: [
                _SummaryChip(
                  label: 'إيداعات',
                  value: _totalIn.toString(),
                  icon: Icons.arrow_downward_rounded,
                  color: _green,
                ),
                const SizedBox(width: 10),
                _SummaryChip(
                  label: 'مصروفات',
                  value: _totalOut.toString(),
                  icon: Icons.arrow_upward_rounded,
                  color: _red,
                ),
                const SizedBox(width: 10),
                _SummaryChip(
                  label: 'تحويلات',
                  value: _totalTransfer.toString(),
                  icon: Icons.swap_horiz_rounded,
                  color: _blue,
                ),
              ],
            ),
          ),

          // ── Search + Sort ────────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'بحث بالمنتج أو رقم السند...',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(Icons.search_rounded, size: 19, color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      icon: Icon(Icons.sort_rounded, size: 18, color: cs.onSurfaceVariant),
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                      dropdownColor: cs.surface,
                      items: _sortOptions
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _sortBy = v!;
                        _load();
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filterOptions.map((f) {
                  final selected = _filter == f;
                  final color = switch (f) {
                    'إيداع' => _green,
                    'صرف' => _red,
                    'تحويل' => _blue,
                    _ => AppColors.accentGold,
                  };
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: FilterChip(
                      label: Text(f),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _filter = f;
                        _load();
                      }),
                      selectedColor: color.withValues(alpha: 0.15),
                      checkmarkColor: color,
                      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected ? color : cs.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(
                        color: selected
                            ? color.withValues(alpha: 0.5)
                            : cs.outlineVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? Center(
                    child: Text('لا توجد حركات', style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _MovementCard(data: _rows[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Movement Card
// ══════════════════════════════════════════════════════════════════════════════
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MovementCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = data['voucherType']?.toString() ?? '';
    final (icon, color, label) = switch (type) {
      'in' => (Icons.arrow_downward_rounded, _green, 'إيداع'),
      'out' => (Icons.arrow_upward_rounded, _red, 'صرف'),
      'transfer' => (Icons.swap_horiz_rounded, _blue, 'تحويل'),
      _ => (Icons.circle, cs.onSurfaceVariant, ''),
    };
    final from = data['fromWarehouseName']?.toString() ?? '—';
    final to = data['toWarehouseName']?.toString() ?? '—';
    final loc = switch (type) {
      'in' => to,
      'out' => from,
      'transfer' => '$from → $to',
      _ => '—',
    };
    final firstProduct = data['firstProductName']?.toString() ?? 'بدون بنود';
    final totalQty = (data['totalQty'] as num?)?.toDouble() ?? 0;
    final qtyLabel = totalQty.toStringAsFixed(2);
    final createdAt = data['createdAt']?.toString();
    final dateLabel = createdAt == null
        ? '—'
        : DateFormat(
            'yyyy-MM-dd HH:mm',
          ).format(DateTime.parse(createdAt).toLocal());
    final voucherNo = data['voucherNo']?.toString() ?? '#${data['id']}';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      voucherNo,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  firstProduct,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.warehouse_outlined, size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(loc, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),

          // Qty + date
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                qtyLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(dateLabel, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Icon(Icons.chevron_left_rounded, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
