import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import 'add_purchase_order_screen.dart';

// ── ألوان وثوابت ──────────────────────────────────────────────────────────────
const Color _kAccent = Color(0xFF1E3A5F);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kOrange = Color(0xFFF97316);
const Color _kGreen = Color(0xFF16A34A);
const Color _kRed = Color(0xFFEF4444);

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
    draft     => Colors.grey,
    sent      => _kAmber,
    partial   => _kOrange,
    received  => _kGreen,
    cancelled => _kRed,
    _         => Colors.grey,
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
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _searchFocus = FocusNode();

  Timer? _debounce;
  String _debouncedQuery = '';

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  String _statusFilter = 'all';
  String _statFilter = 'all';
  bool   _loading      = true;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _debouncedQuery = _search.text.trim().toLowerCase();
      });
      _applyFilter();
    });
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
    final q = _debouncedQuery;
    final shouldSearch = q.length >= 2;
    setState(() {
      _filtered = _all.where((po) {
        final effectiveStatus =
            _statFilter != 'all' ? _statFilter : _statusFilter;
        final matchStatus =
            effectiveStatus == 'all' || po['status'] == effectiveStatus;
        if (!matchStatus) return false;
        if (!shouldSearch) return q.isEmpty;
        final no   = (po['poNumber'] as String? ?? '').toLowerCase();
        final sup  = (po['supplierDisplayName'] as String? ?? '').toLowerCase();
        final note = (po['notes'] as String? ?? '').toLowerCase();
        final od = _formatDate(po['orderDate'] as String?).toLowerCase();
        final ex = _formatDate(po['expectedDate'] as String?).toLowerCase();
        return no.contains(q) ||
            sup.contains(q) ||
            note.contains(q) ||
            od.contains(q) ||
            ex.contains(q);
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
      final layout = context.screenLayout;
      final bg      = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F5F9);
      final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
      final textSec = isDark ? Colors.grey.shade500 : Colors.grey.shade500;

      // ── إحصاءات مختصرة ────────────────────────────────────────────────────
      final total     = _all.length;
      final pending   = _all.where((p) => p['status'] == _PoStatus.sent).length;
      final partial   = _all.where((p) => p['status'] == _PoStatus.partial).length;
      final completed = _all.where((p) => p['status'] == _PoStatus.received).length;

      final totalValue = _all.fold<num>(
        0,
        (s, p) => s + ((p['totalAmount'] as num?) ?? 0),
      );

      Future<void> openNew() async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const AddPurchaseOrderScreen()),
        );
        if (result == true) _load();
      }

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
                  'أوامر الشراء',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
                onPressed: () => unawaited(openNew()),
              ),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                  children: [
                    // ── شريط الإحصاءات ──────────────────────────────────────
                    Container(
                      color: _kAccent,
                      padding: EdgeInsetsDirectional.fromSTEB(
                        layout.pageHorizontalGap,
                        0,
                        layout.pageHorizontalGap,
                        12,
                      ),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final narrow = c.maxWidth < 760;
                          final counters = <Widget>[
                            _StatCounter(
                              label: 'الإجمالي',
                              value: total,
                              color: _kBlue,
                              active: _statFilter == 'all',
                              onTap: () {
                                setState(() => _statFilter = 'all');
                                _applyFilter();
                              },
                            ),
                            _StatCounter(
                              label: 'مرسلة',
                              value: pending,
                              color: _kAmber,
                              active: _statFilter == _PoStatus.sent,
                              onTap: () {
                                setState(() => _statFilter = _PoStatus.sent);
                                _applyFilter();
                              },
                            ),
                            _StatCounter(
                              label: 'جزئي',
                              value: partial,
                              color: _kOrange,
                              active: _statFilter == _PoStatus.partial,
                              onTap: () {
                                setState(() => _statFilter = _PoStatus.partial);
                                _applyFilter();
                              },
                            ),
                            _StatCounter(
                              label: 'مكتمل',
                              value: completed,
                              color: _kGreen,
                              active: _statFilter == _PoStatus.received,
                              onTap: () {
                                setState(() => _statFilter = _PoStatus.received);
                                _applyFilter();
                              },
                            ),
                          ];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (narrow)
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: counters
                                      .map(
                                        (w) => SizedBox(
                                          width: (c.maxWidth - 10) / 2,
                                          child: w,
                                        ),
                                      )
                                      .toList(),
                                )
                              else
                                Row(
                                  children: [
                                    for (var i = 0; i < counters.length; i++) ...[
                                      Expanded(child: counters[i]),
                                      if (i != counters.length - 1) const SizedBox(width: 10),
                                    ],
                                  ],
                                ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  'القيمة الكلية: ${IraqiCurrencyFormat.formatIqd(totalValue)}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // ── شريط البحث والفلتر ───────────────────────────────────
                    Container(
                      color: surface,
                      padding: EdgeInsets.symmetric(horizontal: layout.pageHorizontalGap, vertical: 8),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final narrow = c.maxWidth < 680;
                          final searchField = TextField(
                              controller: _search,
                              focusNode: _searchFocus,
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(
                                hintText: 'بحث باسم المورد أو رقم الأمر أو التاريخ…',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _search.text.trim().isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'مسح',
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _search.clear();
                                          setState(() => _debouncedQuery = '');
                                          _applyFilter();
                                          _searchFocus.requestFocus();
                                        },
                                      ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FA),
                              ),
                            );
                          final statusDropdown = _StatusFilterDropdown(
                            value: _statusFilter,
                            onChanged: (v) {
                              setState(() => _statusFilter = v ?? 'all');
                              _applyFilter();
                            },
                            isDark: isDark,
                          );
                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField,
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: statusDropdown,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: searchField),
                              const SizedBox(width: 8),
                              statusDropdown,
                            ],
                          );
                        },
                      ),
                    ),

                    // ── القائمة ──────────────────────────────────────────────
                    Expanded(
                      child: _filtered.isEmpty
                          ? _PoEmptyState(
                              hasAny: _all.isNotEmpty,
                              textSec: textSec,
                              onCreate: () => unawaited(openNew()),
                            )
                          : ListView.separated(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                layout.pageHorizontalGap,
                                8,
                                layout.pageHorizontalGap,
                                100,
                              ),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final po = _filtered[i];
                                return _PoCard(
                                  po: po,
                                  surface: surface,
                                  fmtDate: _formatDate,
                                  onView: () async {
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
                                  onEdit: () async {
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
                                  onCopy: () async {
                                    final result = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddPurchaseOrderScreen(
                                          copyFromPoId: po['id'] as int?,
                                        ),
                                      ),
                                    );
                                    if (result == true) _load();
                                  },
                                  onCancel: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('إلغاء أمر الشراء'),
                                        content: const Text('هل تريد إلغاء هذا الأمر؟'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('رجوع'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: TextButton.styleFrom(
                                              foregroundColor: _kRed,
                                            ),
                                            child: const Text('إلغاء'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    final db = await _db.database;
                                    await db.update(
                                      'purchase_orders',
                                      {
                                        'status': _PoStatus.cancelled,
                                        'updatedAt': DateTime.now().toIso8601String(),
                                      },
                                      where: 'id = ? AND tenantId = ?',
                                      whereArgs: [po['id'], _tenant.activeTenantId],
                                    );
                                    _load();
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

class _StatCounter extends StatelessWidget {
  const _StatCounter({
    required this.label,
    required this.value,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(active ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                IraqiCurrencyFormat.formatInt(value),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: active ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FA),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: cs.surface,
        items: [
          _statusItem('all', 'الكل', _kBlue),
          _statusItem(_PoStatus.draft, 'مسودة', Colors.grey),
          _statusItem(_PoStatus.sent, 'مرسلة', _kAmber),
          _statusItem(_PoStatus.partial, 'جزئي', _kOrange),
          _statusItem(_PoStatus.received, 'مكتمل', _kGreen),
          _statusItem(_PoStatus.cancelled, 'ملغي', _kRed),
        ],
        onChanged: onChanged,
      ),
    );
  }

  DropdownMenuItem<String> _statusItem(String v, String label, Color dot) {
    return DropdownMenuItem(
      value: v,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PoCard extends StatelessWidget {
  const _PoCard({
    required this.po,
    required this.surface,
    required this.fmtDate,
    required this.onView,
    required this.onEdit,
    required this.onCopy,
    required this.onCancel,
  });

  final Map<String, dynamic>       po;
  final Color                      surface;
  final String Function(String?)   fmtDate;
  final VoidCallback               onView;
  final VoidCallback               onEdit;
  final VoidCallback               onCopy;
  final VoidCallback               onCancel;

  @override
  Widget build(BuildContext context) {
    final status   = (po['status'] as String?) ?? 'draft';
    final total    = (po['totalAmount'] as num?)?.toDouble() ?? 0;
    final received = (po['receivedAmount'] as num?)?.toDouble() ?? 0;
    final pct      = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
    final supplier = (po['supplierDisplayName'] as String?)?.trim().isNotEmpty == true
        ? po['supplierDisplayName'] as String
        : (po['supplierName'] as String? ?? 'مورد غير محدد');

    return Container(
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
                        'مستلم ${IraqiCurrencyFormat.formatIqd(received)} من ${IraqiCurrencyFormat.formatIqd(total)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(IraqiCurrencyFormat.formatIqd(total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${po['itemCount'] ?? 0} صنف',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onView, child: const Text('عرض')),
                TextButton(onPressed: onEdit, child: const Text('تعديل')),
                TextButton(onPressed: onCopy, child: const Text('نسخ')),
                TextButton(
                  onPressed: status == _PoStatus.cancelled ? null : onCancel,
                  style: TextButton.styleFrom(foregroundColor: _kRed),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ],
        ),
    );
  }
}

class _PoEmptyState extends StatelessWidget {
  const _PoEmptyState({
    required this.hasAny,
    required this.textSec,
    required this.onCreate,
  });

  final bool hasAny;
  final Color textSec;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: textSec),
            const SizedBox(height: 12),
            Text(
              hasAny ? 'لا توجد نتائج تطابق البحث' : 'لا توجد أوامر شراء بعد',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSec, fontSize: 14),
            ),
            if (!hasAny) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.add),
                label: const Text('+ إنشاء أول أمر شراء'),
              ),
              const SizedBox(height: 10),
              Text(
                'أو اضغط Ctrl+N',
                style: TextStyle(color: textSec, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
