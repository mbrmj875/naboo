import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';
import 'add_purchase_order_screen.dart';

// ── ألوان وثوابت ──────────────────────────────────────────────────────────────
const Color _kAccent = Color(0xFF1E3A5F);

class _PoStatus {
  static const draft    = 'draft';
  static const sent     = 'sent';
  static const partial  = 'partial';
  static const received = 'received';
  static const cancelled = 'cancelled';

  static String label(String s) => switch (s) {
    draft    => 'مسودة',
    sent     => 'مرسل',
    partial  => 'مستلم جزئياً',
    received => 'مكتمل',
    cancelled => 'ملغى',
    _ => s,
  };

  static Color color(String s) => switch (s) {
    draft    => Colors.grey,
    sent     => Colors.blue,
    partial  => Colors.orange,
    received => Colors.green,
    cancelled => Colors.red,
    _ => Colors.grey,
  };
}

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  final _db      = DatabaseHelper();
  final _tenant  = TenantContextService.instance;
  final _search  = TextEditingController();
  final _fmt     = NumberFormat('#,##0.000', 'ar');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  String _statusFilter = 'all';
  bool   _loading      = true;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT po.*,
             s.name AS supplierDisplayName,
             (SELECT COUNT(*) FROM purchase_order_items i WHERE i.poId = po.id) AS itemCount
      FROM purchase_orders po
      LEFT JOIN suppliers s ON s.id = po.supplierId
      WHERE po.tenantId = ?
      ORDER BY po.id DESC
    ''', [_tenant.activeTenantId]);
    if (!mounted) return;
    setState(() {
      _all     = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((po) {
        final matchStatus = _statusFilter == 'all' || po['status'] == _statusFilter;
        if (!matchStatus) return false;
        if (q.isEmpty) return true;
        final no   = (po['poNumber'] as String? ?? '').toLowerCase();
        final sup  = (po['supplierDisplayName'] as String? ?? '').toLowerCase();
        final note = (po['notes'] as String? ?? '').toLowerCase();
        return no.contains(q) || sup.contains(q) || note.contains(q);
      }).toList();
    });
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return _dateFmt.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(builder: (context, tp, _) {
      final isDark  = tp.isDarkMode;
      final bg      = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F5F9);
      final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
      final textSec = isDark ? Colors.grey.shade500 : Colors.grey.shade500;

      // ── إحصاءات مختصرة ────────────────────────────────────────────────────
      final total     = _all.length;
      final pending   = _all.where((p) => p['status'] == _PoStatus.sent).length;
      final partial   = _all.where((p) => p['status'] == _PoStatus.partial).length;
      final completed = _all.where((p) => p['status'] == _PoStatus.received).length;

      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: _kAccent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'أوامر الشراء',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_outlined, color: Colors.white),
                onPressed: _load,
                tooltip: 'تحديث',
              ),
              const SizedBox(width: 4),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _kAccent,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('أمر شراء جديد'),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const AddPurchaseOrderScreen()),
              );
              if (result == true) _load();
            },
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // ── شريط الإحصاءات ──────────────────────────────────────
                    Container(
                      color: _kAccent,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          _StatChip(label: 'الإجمالي', value: '$total', color: Colors.white),
                          const SizedBox(width: 8),
                          _StatChip(label: 'مرسلة', value: '$pending', color: Colors.blue.shade200),
                          const SizedBox(width: 8),
                          _StatChip(label: 'جزئي', value: '$partial', color: Colors.orange.shade200),
                          const SizedBox(width: 8),
                          _StatChip(label: 'مكتمل', value: '$completed', color: Colors.green.shade200),
                        ],
                      ),
                    ),

                    // ── شريط البحث والفلتر ───────────────────────────────────
                    Container(
                      color: surface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(
                                hintText: 'بحث باسم المورد أو رقم الأمر…',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FA),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusFilterDropdown(
                            value: _statusFilter,
                            onChanged: (v) {
                              setState(() => _statusFilter = v ?? 'all');
                              _applyFilter();
                            },
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    // ── القائمة ──────────────────────────────────────────────
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long_outlined,
                                      size: 64, color: textSec),
                                  const SizedBox(height: 12),
                                  Text(
                                    _all.isEmpty
                                        ? 'لا توجد أوامر شراء بعد\nاضغط + لإنشاء أول أمر'
                                        : 'لا توجد نتائج تطابق البحث',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textSec, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final po = _filtered[i];
                                return _PoCard(
                                  po: po,
                                  surface: surface,
                                  fmtMoney: _fmt,
                                  fmtDate: _formatDate,
                                  onTap: () async {
                                    final result = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddPurchaseOrderScreen(
                                          poId: po['id'] as int?,
                                        ),
                                      ),
                                    );
                                    if (result == true) _load();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      );
    });
  }
}

// ── مكونات الواجهة ─────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
      ],
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  const _StatusFilterDropdown({required this.value, required this.onChanged, required this.isDark});
  final String               value;
  final ValueChanged<String?> onChanged;
  final bool                 isDark;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 'all',                  child: Text('الكل',       style: TextStyle(fontSize: 12))),
        DropdownMenuItem(value: _PoStatus.draft,        child: Text('مسودة',      style: TextStyle(fontSize: 12))),
        DropdownMenuItem(value: _PoStatus.sent,         child: Text('مرسل',       style: TextStyle(fontSize: 12))),
        DropdownMenuItem(value: _PoStatus.partial,      child: Text('جزئي',       style: TextStyle(fontSize: 12))),
        DropdownMenuItem(value: _PoStatus.received,     child: Text('مكتمل',      style: TextStyle(fontSize: 12))),
        DropdownMenuItem(value: _PoStatus.cancelled,    child: Text('ملغى',       style: TextStyle(fontSize: 12))),
      ],
      onChanged: onChanged,
    );
  }
}

class _PoCard extends StatelessWidget {
  const _PoCard({
    required this.po,
    required this.surface,
    required this.fmtMoney,
    required this.fmtDate,
    required this.onTap,
  });

  final Map<String, dynamic>       po;
  final Color                      surface;
  final NumberFormat               fmtMoney;
  final String Function(String?)   fmtDate;
  final VoidCallback               onTap;

  @override
  Widget build(BuildContext context) {
    final status   = (po['status'] as String?) ?? 'draft';
    final total    = (po['totalAmount'] as num?)?.toDouble() ?? 0;
    final received = (po['receivedAmount'] as num?)?.toDouble() ?? 0;
    final pct      = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
    final supplier = (po['supplierDisplayName'] as String?)?.trim().isNotEmpty == true
        ? po['supplierDisplayName'] as String
        : (po['supplierName'] as String? ?? 'مورد غير محدد');

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.zero,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (po['poNumber'] as String? ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _PoStatus.color(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _PoStatus.label(status),
                    style: TextStyle(
                      color: _PoStatus.color(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(supplier,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(fmtDate(po['orderDate'] as String?),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade200,
                        color: _PoStatus.color(status),
                        minHeight: 4,
                        borderRadius: BorderRadius.zero,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مستلم ${fmtMoney.format(received)} من ${fmtMoney.format(total)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmtMoney.format(total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${po['itemCount'] ?? 0} صنف',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
