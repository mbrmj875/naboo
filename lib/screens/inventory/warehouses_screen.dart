import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/inventory_repository.dart';
import '../../services/permission_service.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/permission_guard.dart';

const _navy = Color(0xFF1E3A5F);
const _teal = Color(0xFF0D9488);
const _green = Color(0xFF16A34A);
const _purple = Color(0xFFA855F7);
const _blue = Color(0xFF3B82F6);
const _greenStat = Color(0xFF22C55E);
const _amber = Color(0xFFF59E0B);
const _bg = Color(0xFFF1F5F9);
const _card = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1 = Color(0xFF0F172A);
const _t2 = Color(0xFF64748B);
const _red = Color(0xFFEF4444);

/// فلتر/ترتيب عند النقر على بطاقة إحصائية.
enum _StatTapMode { none, byTotalValue, byTotalItems }

/// نتيجة حفظ من نموذج المستودع.
class _WarehouseSaveOutcome {
  const _WarehouseSaveOutcome({
    required this.success,
    this.newWarehouseId,
    this.generatedCodeDisplay,
    this.firstWarehouseInfo,
    this.errorMessage,
    this.wasCreate = true,
  });

  final bool success;
  final int? newWarehouseId;
  final String? generatedCodeDisplay;
  final String? firstWarehouseInfo;
  final String? errorMessage;
  final bool wasCreate;
}

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _warehouses = const [];
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;

  Timer? _searchDebounce;
  String _debouncedQuery = '';

  _StatTapMode _statMode = _StatTapMode.none;

  int? _highlightWarehouseId;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    _load();
  }

  void _onSearchTextChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _debouncedQuery = _search.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _repo.listWarehousesWithStats();
      final branches = await _repo.listBranchesActive();
      if (!mounted) return;
      setState(() {
        _warehouses = rows;
        _branches = branches;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر تحميل المستودعات: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _debouncedQuery;
    if (q.isEmpty) return _warehouses;
    return _warehouses
        .where(
          (w) =>
              (w['name']?.toString() ?? '').toLowerCase().contains(q) ||
              (w['code']?.toString() ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  List<Map<String, dynamic>> get _visibleList {
    final list = List<Map<String, dynamic>>.from(_filtered);
    switch (_statMode) {
      case _StatTapMode.byTotalValue:
        list.sort(
          (a, b) => ((b['value'] as num?)?.toDouble() ?? 0).compareTo(
            (a['value'] as num?)?.toDouble() ?? 0,
          ),
        );
        break;
      case _StatTapMode.byTotalItems:
        list.sort(
          (a, b) => ((b['items'] as num?)?.toInt() ?? 0).compareTo(
            (a['items'] as num?)?.toInt() ?? 0,
          ),
        );
        break;
      case _StatTapMode.none:
        break;
    }
    return list;
  }

  int get _totalItems =>
      _warehouses.fold(0, (s, w) => s + ((w['items'] as num?)?.toInt() ?? 0));

  double get _totalValue => _warehouses.fold(
    0.0,
    (s, w) => s + ((w['value'] as num?)?.toDouble() ?? 0),
  );

  void _onStatCardTap(_StatTapMode mode) {
    setState(() {
      if (_statMode == mode) {
        _statMode = _StatTapMode.none;
      } else {
        _statMode = mode;
      }
    });
  }

  void _clearStatSort() {
    setState(() => _statMode = _StatTapMode.none);
  }

  Future<void> _openSheet(Map<String, dynamic>? existing) async {
    final outcome = await showModalBottomSheet<_WarehouseSaveOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WarehouseSheet(
        existing: existing,
        branches: _branches,
        warehouses: _warehouses,
        repo: _repo,
        isFirstWarehouseCreation: existing == null && _warehouses.isEmpty,
      ),
    );
    if (outcome == null || !outcome.success) {
      if (outcome?.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(outcome!.errorMessage!),
            backgroundColor: _red,
          ),
        );
      }
      return;
    }
    await _load();
    if (!mounted) return;
    if (outcome.newWarehouseId != null) {
      setState(() => _highlightWarehouseId = outcome.newWarehouseId);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightWarehouseId = null);
      });
    }

    String successMessage() {
      if (!outcome.wasCreate) return 'تم حفظ التعديلات بنجاح';
      final buf = StringBuffer('تم إنشاء المستودع بنجاح');
      final first = outcome.firstWarehouseInfo;
      if (first != null && first.isNotEmpty) {
        buf.writeln();
        buf.write(first);
      }
      final code = outcome.generatedCodeDisplay;
      if (code != null && code.isNotEmpty) {
        buf.writeln();
        buf.write('الكود: $code');
      }
      return buf.toString();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage()), backgroundColor: _green),
    );
  }

  Future<void> _delete(Map<String, dynamic> w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المستودع'),
        content: Text('هل أنت متأكد من حذف المستودع «${w['name']}»؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteWarehouse((w['id'] as num).toInt());
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف المستودع (قد يكون مرتبطا بحركات): $e'),
          backgroundColor: _red,
        ),
      );
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> w) async {
    final id = (w['id'] as num).toInt();
    final isActive = (w['isActive'] as num? ?? 1) == 1;
    if (isActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تعطيل المستودع'),
          content: const Text(
            'لن يُستخدم هذا المستودع في عمليات البيع والشراء حتى يُفعَّل من جديد.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تعطيل'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _repo.setWarehouseActive(id, !isActive);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الحالة: $e'), backgroundColor: _red),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.removeListener(_onSearchTextChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permissionKey: PermissionKeys.inventoryView,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            title: const Text('المستودعات'),
            backgroundColor: _navy,
            foregroundColor: Colors.white,
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _teal,
            onPressed: () => _openSheet(null),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text(
              'مستودع جديد',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Column(
            children: [
              Container(
                color: _navy,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    _StatSummaryCard(
                      accent: _blue,
                      label: 'القيمة الإجمالية',
                      selected: _statMode == _StatTapMode.byTotalValue,
                      onTap: () => _onStatCardTap(_StatTapMode.byTotalValue),
                      child: _loading
                          ? const Text('—', style: _statValueStyle)
                          : TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              tween: Tween(begin: 0, end: _totalValue),
                              builder: (_, v, __) => Text(
                                IraqiCurrencyFormat.formatCompactWarehouseValue(
                                  v,
                                ),
                                style: _statValueStyle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    _StatSummaryCard(
                      accent: _greenStat,
                      label: 'إجمالي الأصناف',
                      selected: _statMode == _StatTapMode.byTotalItems,
                      onTap: () => _onStatCardTap(_StatTapMode.byTotalItems),
                      child: _loading
                          ? const Text('—', style: _statValueStyle)
                          : TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              tween: Tween(
                                begin: 0,
                                end: _totalItems.toDouble(),
                              ),
                              builder: (_, v, __) => Text(
                                IraqiCurrencyFormat.formatInt(v.round()),
                                style: _statValueStyle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    _StatSummaryCard(
                      accent: _purple,
                      label: 'المستودعات',
                      selected: _statMode == _StatTapMode.none,
                      onTap: _clearStatSort,
                      child: _loading
                          ? const Text('—', style: _statValueStyle)
                          : TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              tween: Tween(
                                begin: 0,
                                end: _warehouses.length.toDouble(),
                              ),
                              builder: (_, v, __) => Text(
                                IraqiCurrencyFormat.formatInt(v.round()),
                                style: _statValueStyle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _search,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      textAlign: TextAlign.start,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو الكود...',
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'مسح',
                                onPressed: () {
                                  _search.clear();
                                  setState(() {
                                    _debouncedQuery = '';
                                  });
                                  _searchFocus.requestFocus();
                                },
                                icon: const Icon(Icons.clear_rounded, size: 20),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: _navy,
                            width: 1.4,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                    ? _EmptyWarehouseState(onCreate: () => _openSheet(null))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                        itemCount: _visibleList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _WarehouseCard(
                          highlight:
                              (_visibleList[i]['id'] as num?)?.toInt() ==
                              _highlightWarehouseId,
                          data: _visibleList[i],
                          onEdit: () => _openSheet(_visibleList[i]),
                          onDelete: () => _delete(_visibleList[i]),
                          onToggleActive: () => _toggleActive(_visibleList[i]),
                          onViewStock: () =>
                              _showStockDetails(context, _visibleList[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStockDetails(BuildContext ctx, Map<String, dynamic> w) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StockDetailSheet(warehouse: w),
    );
  }
}

const TextStyle _statValueStyle = TextStyle(
  color: Colors.white,
  fontSize: 14,
  fontWeight: FontWeight.bold,
);

class _StatSummaryCard extends StatelessWidget {
  const _StatSummaryCard({
    required this.label,
    required this.child,
    required this.accent,
    required this.onTap,
    required this.selected,
  });

  final String label;
  final Widget child;
  final Color accent;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.95)
                    : Colors.white24,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle(
                        style: _statValueStyle,
                        textAlign: TextAlign.center,
                        child: child,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyWarehouseState extends StatelessWidget {
  const _EmptyWarehouseState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warehouse_outlined,
              size: 72,
              color: _t2.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد مستودعات بعد',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _t1.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إنشاء أول مستودع'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onViewStock,
    required this.onToggleActive,
    required this.highlight,
  });

  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewStock;
  final VoidCallback onToggleActive;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDefault = (data['isDefault'] as num? ?? 0) == 1;
    final isActive = (data['isActive'] as num? ?? 1) == 1;
    final whValue = (data['value'] as num?)?.toDouble() ?? 0;
    final items = (data['items'] as num?)?.toInt() ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight
              ? _green.withValues(alpha: 0.85)
              : (isDefault ? _teal.withValues(alpha: 0.5) : _border),
          width: highlight ? 2.2 : (isDefault ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.warehouse_rounded,
                    color: _teal,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _t1,
                              ),
                            ),
                          ),
                          if (isDefault) _chip('افتراضي', _green),
                          const SizedBox(width: 6),
                          _chip(
                            isActive ? 'نشط' : 'معطّل',
                            isActive ? _green : _t2,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data['code']?.toString().isNotEmpty == true
                            ? data['code'].toString()
                            : '—',
                        style: const TextStyle(fontSize: 12, color: _t2),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: _t2,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              data['location']?.toString().isNotEmpty == true
                                  ? data['location'].toString()
                                  : '—',
                              style: const TextStyle(fontSize: 12, color: _t2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _InfoCell(
                  icon: Icons.inventory_2_outlined,
                  label: 'عدد الأصناف',
                  value: '$items',
                ),
                const SizedBox(width: 20),
                _InfoCell(
                  icon: Icons.payments_outlined,
                  label: 'القيمة الإجمالية',
                  value: IraqiCurrencyFormat.formatCompactWarehouseValue(
                    whValue,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onEdit, child: const Text('تعديل')),
                TextButton(
                  onPressed: onToggleActive,
                  child: Text(isActive ? 'تعطيل' : 'تفعيل'),
                ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: _red),
                  child: const Text('حذف'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: onViewStock,
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text(
                  'عرض المخزون',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
    ),
  );
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _t2),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: _t2)),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _t1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Add / Edit Warehouse Sheet
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseSheet extends StatefulWidget {
  const _WarehouseSheet({
    required this.branches,
    required this.warehouses,
    required this.repo,
    this.existing,
    required this.isFirstWarehouseCreation,
  });

  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> warehouses;
  final InventoryRepository repo;
  final bool isFirstWarehouseCreation;

  @override
  State<_WarehouseSheet> createState() => _WarehouseSheetState();
}

class _WarehouseSheetState extends State<_WarehouseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _location;

  final _nameFn = FocusNode();
  final _codeFn = FocusNode();
  final _locationFn = FocusNode();
  final _branchFn = FocusNode();

  bool _active = true;
  bool _isDefault = false;

  int? _branchId;

  String? _nameDuplicateError;
  String? _codeDuplicateError;
  String? _branchSelectError;

  bool _submitting = false;

  /// حقل الفرع يتطلب اختياراً صريحاً عند وجود أكثر من فرع.
  bool get _branchRequired => widget.branches.length > 1;

  int? get _editingId =>
      widget.existing == null ? null : (widget.existing!['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _code = TextEditingController(text: e?['code'] ?? '');
    _location = TextEditingController(text: e?['location'] ?? '');
    _active = ((e?['isActive'] as num?) ?? 1) == 1;
    _isDefault = ((e?['isDefault'] as num?) ?? 0) == 1;

    if (widget.isFirstWarehouseCreation) {
      _isDefault = true;
    }

    _branchId =
        (e?['branchId'] as num?)?.toInt() ??
        (widget.branches.isNotEmpty
            ? (widget.branches.first['id'] as num).toInt()
            : null);

    _name.addListener(_markDirty);
    _code.addListener(_markDirty);
    _location.addListener(_markDirty);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFn.requestFocus();
    });
  }

  void _markDirty() {
    setState(() {});
  }

  bool get _hasUnsavedInput {
    final e = widget.existing;
    if (e == null) {
      return _name.text.trim().isNotEmpty ||
          _code.text.trim().isNotEmpty ||
          _location.text.trim().isNotEmpty ||
          !_active ||
          _isDefault != widget.isFirstWarehouseCreation;
    }
    return _name.text.trim() != (e['name']?.toString() ?? '') ||
        _code.text.trim() != (e['code']?.toString() ?? '') ||
        _location.text.trim() != (e['location']?.toString() ?? '') ||
        _active != (((e['isActive'] as num?) ?? 1) == 1) ||
        _isDefault != (((e['isDefault'] as num?) ?? 0) == 1) ||
        _branchId != (e['branchId'] as num?)?.toInt();
  }

  Future<void> _checkNameOnBlur() async {
    var t = _name.text;
    final trimmed = t.trim();
    if (trimmed != t) {
      _name.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
      t = trimmed;
    }
    if (trimmed.isEmpty) {
      setState(() => _nameDuplicateError = null);
      return;
    }
    final exists = await widget.repo.warehouseNameExists(
      t,
      excludingWarehouseId: _editingId,
    );
    if (!mounted) return;
    setState(() {
      _nameDuplicateError = exists ? 'يوجد مستودع بهذا الاسم مسبقاً' : null;
    });
    _formKey.currentState?.validate();
  }

  Future<void> _checkCodeOnBlur() async {
    final t = _code.text.trim().toUpperCase();
    if (t.isEmpty) {
      setState(() => _codeDuplicateError = null);
      return;
    }
    final exists = await widget.repo.warehouseCodeExists(
      t,
      excludingWarehouseId: _editingId,
    );
    if (!mounted) return;
    setState(() {
      _codeDuplicateError = exists ? 'الكود مستخدم مسبقاً' : null;
    });
    _formKey.currentState?.validate();
  }

  Future<void> _onDefaultToggleRequest(bool next) async {
    if (!next) {
      setState(() => _isDefault = false);
      return;
    }
    final myId = _editingId;
    Map<String, dynamic>? otherDefault;
    for (final w in widget.warehouses) {
      if ((w['isDefault'] as num? ?? 0) != 1) continue;
      final wid = (w['id'] as num).toInt();
      if (myId != null && wid == myId) continue;
      otherDefault = w;
      break;
    }

    if (otherDefault != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تعيين افتراضي'),
          content: const Text(
            'سيتم إزالة الافتراضي من المستودع الحالي وتحديد هذا المستودع كافتراضي.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        setState(() => _isDefault = true);
      }
    } else {
      setState(() => _isDefault = true);
    }
  }

  Future<bool> _confirmClose() async {
    if (!_hasUnsavedInput) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق النموذج'),
        content: const Text('هل تريد إغلاق النموذج؟ البيانات لن تُحفظ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _tryClose() async {
    if (await _confirmClose() && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_branchRequired && _branchId == null && widget.branches.length > 5) {
      setState(() => _branchSelectError = 'اختر فرعاً');
      return;
    }
    setState(() => _branchSelectError = null);

    if (!_formKey.currentState!.validate()) return;
    if (_nameDuplicateError != null || _codeDuplicateError != null) {
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final loc = _location.text.trim();
      var codeOut = _code.text.trim().toUpperCase();
      if (widget.existing != null && codeOut.isEmpty) {
        codeOut = widget.existing!['code']?.toString() ?? '';
      }

      final makeDefault = _isDefault;

      if (widget.existing == null) {
        final result = await widget.repo.createWarehouse(
          name: name,
          code: codeOut,
          location: loc,
          branchId: _branchId,
          isActive: _active,
          isDefault: makeDefault,
        );
        if (!mounted) return;
        Navigator.of(context).pop(
          _WarehouseSaveOutcome(
            success: true,
            wasCreate: true,
            newWarehouseId: result.id,
            generatedCodeDisplay: result.resolvedCode,
            firstWarehouseInfo: widget.isFirstWarehouseCreation
                ? 'تم تعيينه افتراضياً تلقائياً لأنه المستودع الأول'
                : null,
          ),
        );
      } else {
        await widget.repo.updateWarehouse(
          id: _editingId!,
          name: name,
          code: codeOut,
          location: loc,
          branchId: _branchId,
          isActive: _active,
          isDefault: makeDefault,
        );
        if (!mounted) return;
        Navigator.of(
          context,
        ).pop(const _WarehouseSaveOutcome(success: true, wasCreate: false));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(
        _WarehouseSaveOutcome(
          success: false,
          errorMessage: 'تعذر حفظ المستودع: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validateNameField(String? v) {
    if (v == null || v.trim().isEmpty) return 'مطلوب';
    if (_nameDuplicateError != null) return _nameDuplicateError;
    return null;
  }

  String? _validateCodeField(String? v) {
    if (_codeDuplicateError != null) return _codeDuplicateError;
    return null;
  }

  String? _validateBranch(int? v) {
    if (_branchRequired && v == null) return 'اختر فرعاً';
    return null;
  }

  Future<void> _openBranchPicker() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BranchSearchSheet(branches: widget.branches),
    );
    if (chosen != null && mounted) {
      setState(() {
        _branchId = chosen;
        _branchSelectError = null;
      });
    }
  }

  Future<void> _scanCode() async {
    final raw = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح كود المستودع',
    );
    if (raw == null || !mounted) return;
    final sanitized = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '')
        .toUpperCase();
    if (sanitized.isEmpty) return;
    setState(() {
      _code.text = sanitized.length > 20
          ? sanitized.substring(0, 20)
          : sanitized;
    });
  }

  @override
  void dispose() {
    _name.removeListener(_markDirty);
    _code.removeListener(_markDirty);
    _location.removeListener(_markDirty);
    _name.dispose();
    _code.dispose();
    _location.dispose();
    _nameFn.dispose();
    _codeFn.dispose();
    _locationFn.dispose();
    _branchFn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final codeLen = _code.text.length;
    final showCodeCounter = codeLen > 15;

    final branchWide = widget.branches.length > 5;

    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? 'تعديل المستودع' : 'مستودع جديد',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _t1,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => unawaited(_tryClose()),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (widget.isFirstWarehouseCreation)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'تم تعيينه افتراضياً تلقائياً لأنه المستودع الأول',
                    style: TextStyle(fontSize: 12, color: _blue),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
          Focus(
            onFocusChange: (has) {
              if (!has) unawaited(_checkNameOnBlur());
            },
            child: AppInput(
              label: 'اسم المستودع',
              isRequired: true,
              controller: _name,
              focusNode: _nameFn,
              hint: 'مثال: مستودع الرئيسي، مستودع الفرع الشمالي',
              prefixIcon: const Icon(Icons.warehouse_outlined, size: 20),
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              validator: _validateNameField,
              onFieldSubmitted: (_) => _codeFn.requestFocus(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (has) {
                    if (!has) unawaited(_checkCodeOnBlur());
                  },
                  child: AppInput(
                    label: 'كود المستودع',
                    isOptional: true,
                    controller: _code,
                    focusNode: _codeFn,
                    hint: 'مثال: WH-001',
                    prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\-]'),
                      ),
                      LengthLimitingTextInputFormatter(20),
                      _UpperCaseWarehouseCodeFormatter(),
                    ],
                    validator: _validateCodeField,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _locationFn.requestFocus(),
                    suffixText: showCodeCounter ? '$codeLen/20' : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: IconButton.filledTonal(
                  onPressed: () => unawaited(_scanCode()),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                  tooltip: 'مسح',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppInput(
            label: 'الموقع',
            isOptional: true,
            controller: _location,
            focusNode: _locationFn,
            hint: 'العنوان أو وصف الموقع',
            prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(100)],
            onFieldSubmitted: (_) {
              unawaited(_submit());
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  'الفرع',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_branchRequired) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (branchWide)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => unawaited(_openBranchPicker()),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _branchSelectError != null
                                ? Theme.of(context).colorScheme.error
                                : Colors.grey.shade400,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, color: _t2),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _branchLabel(),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_branchSelectError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _branchSelectError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else
            DropdownButtonFormField<int>(
              focusNode: _branchFn,
              value: _branchId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: widget.branches
                  .map(
                    (b) => DropdownMenuItem<int>(
                      value: (b['id'] as num).toInt(),
                      child: Text(_branchLine(b)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _branchId = v),
              validator: _validateBranch,
            ),
          const SizedBox(height: 14),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Switch(
                value: _active,
                activeThumbColor: _teal,
                onChanged: (v) {
                  setState(() {
                    _active = v;
                    if (!v) _isDefault = false;
                  });
                },
              ),
              const Expanded(
                child: Text(
                  'مستودع نشط',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 14, color: _t1),
                ),
              ),
            ],
          ),
          if (!_active) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'المستودع المعطّل لن يظهر في عمليات البيع والشراء',
                style: TextStyle(fontSize: 12, color: _amber),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Switch(
                value: _isDefault && _active,
                activeThumbColor: _teal,
                onChanged: !_active
                    ? null
                    : (v) => unawaited(_onDefaultToggleRequest(v)),
              ),
              const Expanded(
                child: Text(
                  'افتراضي',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 14, color: _t1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_submitting || _name.text.trim().isEmpty)
                  ? null
                  : () => unawaited(_submit()),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _submitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(isEdit ? 'جاري الحفظ...' : 'جارٍ الإنشاء...'),
                      ],
                    )
                  : Text(
                      isEdit ? 'حفظ التعديلات' : 'إنشاء المستودع',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmClose() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(_tryClose()),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                unawaited(_submit()),
          },
          child: Focus(
            autofocus: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(child: form),
            ),
          ),
        ),
      ),
    );
  }

  String _branchLine(Map<String, dynamic> b) {
    final name = b['name']?.toString() ?? '';
    final code = b['code']?.toString() ?? '';
    if (code.isEmpty) return name;
    return '$name ($code)';
  }

  String _branchLabel() {
    for (final b in widget.branches) {
      if ((b['id'] as num).toInt() == _branchId) {
        return _branchLine(b);
      }
    }
    return 'اختر الفرع';
  }
}

class _UpperCaseWarehouseCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _BranchSearchSheet extends StatefulWidget {
  const _BranchSearchSheet({required this.branches});

  final List<Map<String, dynamic>> branches;

  @override
  State<_BranchSearchSheet> createState() => _BranchSearchSheetState();
}

class _BranchSearchSheetState extends State<_BranchSearchSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _q.text.trim().toLowerCase();
    final list = query.isEmpty
        ? widget.branches
        : widget.branches
              .where(
                (b) =>
                    (b['name']?.toString() ?? '').toLowerCase().contains(
                      query,
                    ) ||
                    (b['code']?.toString() ?? '').toLowerCase().contains(query),
              )
              .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'بحث بالاسم أو رمز الفرع...',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final b = list[i];
                    return ListTile(
                      title: Text(b['name']?.toString() ?? ''),
                      subtitle: Text(b['code']?.toString() ?? ''),
                      onTap: () =>
                          Navigator.pop(context, (b['id'] as num).toInt()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockDetailSheet extends StatelessWidget {
  const _StockDetailSheet({required this.warehouse});

  final Map<String, dynamic> warehouse;

  @override
  Widget build(BuildContext context) {
    final repo = InventoryRepository();
    final warehouseId = (warehouse['id'] as num?)?.toInt() ?? -1;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warehouse_rounded, color: _teal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'مخزون ${warehouse['name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _t1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            SizedBox(
              height: 300,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: repo.listWarehouseStockPreview(warehouseId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snap.data!;
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('لا توجد كميات في هذا المستودع'),
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _border),
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final qty = (row['qty'] as num?)?.toDouble() ?? 0.0;
                      final statusColor = qty <= 0
                          ? _red
                          : qty < 5
                          ? Colors.orange
                          : Colors.green;
                      return ListTile(
                        leading: Icon(
                          Icons.inventory_2_outlined,
                          color: statusColor,
                        ),
                        title: Text(row['name']?.toString() ?? ''),
                        subtitle: Text(
                          qty <= 0 ? 'نفد' : (qty < 5 ? 'منخفض' : 'في المخزون'),
                          style: TextStyle(color: statusColor),
                        ),
                        trailing: Text(
                          qty.toStringAsFixed(2),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
