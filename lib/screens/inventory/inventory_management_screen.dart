import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/inventory_repository.dart';
import '../../utils/screen_layout.dart';
import 'stock_voucher_screen.dart';

const _navy = Color(0xFF1E3A5F);
const _teal = Color(0xFF0D9488);
const _bg = Color(0xFFF1F5F9);
const _card = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1 = Color(0xFF0F172A);
const _t2 = Color(0xFF64748B);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'حركات المخزون',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StockVoucherScreen()),
        ),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'سند جديد',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // ── Summary bar ─────────────────────────────────────────────────
          Container(
            color: _navy,
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
            color: _card,
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
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      filled: true,
                      fillColor: _bg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: _border),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: _border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: _navy, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  height: 44,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      icon: const Icon(Icons.sort_rounded, size: 18),
                      style: const TextStyle(color: _t1, fontSize: 13),
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
            color: _card,
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
                    _ => _teal,
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
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected ? color : _t2,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: selected
                            ? color.withValues(alpha: 0.5)
                            : _border,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const Divider(height: 1, color: _border),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? const Center(
                    child: Text('لا توجد حركات', style: TextStyle(color: _t2)),
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
    final type = data['voucherType']?.toString() ?? '';
    final (icon, color, label) = switch (type) {
      'in' => (Icons.arrow_downward_rounded, _green, 'إيداع'),
      'out' => (Icons.arrow_upward_rounded, _red, 'صرف'),
      'transfer' => (Icons.swap_horiz_rounded, _blue, 'تحويل'),
      _ => (Icons.circle, _t2, ''),
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
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _border),
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
              borderRadius: BorderRadius.zero,
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
                        borderRadius: BorderRadius.zero,
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
                      style: const TextStyle(fontSize: 12, color: _t2),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  firstProduct,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _t1,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.warehouse_outlined, size: 13, color: _t2),
                    const SizedBox(width: 4),
                    Text(loc, style: const TextStyle(fontSize: 12, color: _t2)),
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
              Text(dateLabel, style: const TextStyle(fontSize: 11, color: _t2)),
              const SizedBox(height: 4),
              const Icon(Icons.chevron_left_rounded, size: 18, color: _t2),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
