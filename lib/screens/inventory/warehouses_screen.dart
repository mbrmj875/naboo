import 'package:flutter/material.dart';

import '../../services/permission_service.dart';
import '../../services/inventory_repository.dart';
import '../../widgets/permission_guard.dart';

const _navy = Color(0xFF1E3A5F);
const _teal = Color(0xFF0D9488);
const _bg = Color(0xFFF1F5F9);
const _card = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1 = Color(0xFF0F172A);
const _t2 = Color(0xFF64748B);
const _orange = Color(0xFFF97316);
const _red = Color(0xFFEF4444);

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  final _search = TextEditingController();
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _warehouses = const [];
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _warehouses;
    return _warehouses
        .where(
          (w) =>
              (w['name']?.toString() ?? '').toLowerCase().contains(q) ||
              (w['code']?.toString() ?? '').toLowerCase().contains(q) ||
              (w['location']?.toString() ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  int get _totalItems =>
      _warehouses.fold(0, (s, w) => s + ((w['items'] as num?)?.toInt() ?? 0));
  double get _totalValue => _warehouses.fold(
    0.0,
    (s, w) => s + ((w['value'] as num?)?.toDouble() ?? 0),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openSheet([Map<String, dynamic>? existing]) async {
    final result = await showModalBottomSheet<_WarehouseInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WarehouseSheet(existing: existing, branches: _branches),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await _repo.createWarehouse(
          name: result.name,
          code: result.code,
          location: result.location,
          branchId: result.branchId,
          isActive: result.isActive,
          isDefault: result.isDefault,
        );
      } else {
        await _repo.updateWarehouse(
          id: (existing['id'] as num).toInt(),
          name: result.name,
          code: result.code,
          location: result.location,
          branchId: result.branchId,
          isActive: result.isActive,
          isDefault: result.isDefault,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ المستودع: $e')));
    }
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

  Future<void> _setDefault(int id) async {
    await _repo.setDefaultWarehouse(id);
    await _load();
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
            onPressed: _openSheet,
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
                    _SumBadge(
                      label: 'المستودعات',
                      value: '${_warehouses.length}',
                    ),
                    const SizedBox(width: 12),
                    _SumBadge(label: 'إجمالي الأصناف', value: '$_totalItems'),
                    const SizedBox(width: 12),
                    _SumBadge(
                      label: 'القيمة الإجمالية',
                      value: '${(_totalValue / 1000000).toStringAsFixed(2)}M',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'بحث بالاسم أو الكود أو الموقع...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: _navy, width: 1.4),
                    ),
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                    ? const Center(child: Text('لا توجد مستودعات'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _WarehouseCard(
                          data: _filtered[i],
                          onEdit: () => _openSheet(_filtered[i]),
                          onDelete: () => _delete(_filtered[i]),
                          onSetDefault: () =>
                              _setDefault((_filtered[i]['id'] as num).toInt()),
                          onViewStock: () =>
                              _showStockDetails(context, _filtered[i]),
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

// ══════════════════════════════════════════════════════════════════════════════
// Summary badge
// ══════════════════════════════════════════════════════════════════════════════
class _SumBadge extends StatelessWidget {
  final String label;
  final String value;
  const _SumBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Warehouse Card
// ══════════════════════════════════════════════════════════════════════════════
class _WarehouseCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  final VoidCallback onViewStock;
  const _WarehouseCard({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    required this.onViewStock,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = (data['isDefault'] as num? ?? 0) == 1;
    final isActive = (data['isActive'] as num? ?? 1) == 1;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isDefault ? _teal.withValues(alpha: 0.5) : _border,
          width: isDefault ? 1.5 : 1,
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
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
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
                          if (isDefault) _chip('افتراضي', _teal),
                          if (!isActive) _chip('غير نشط', _orange),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.qr_code_rounded,
                            size: 13,
                            color: _t2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data['code']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12, color: _t2),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: _t2,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              data['location']?.toString() ?? '',
                              style: const TextStyle(fontSize: 12, color: _t2),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.account_tree_outlined,
                            size: 13,
                            color: _t2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data['branchName']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 12, color: _t2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                    if (v == 'default') onSetDefault();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('تعديل'),
                        ],
                      ),
                    ),
                    if (!isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Row(
                          children: [
                            Icon(Icons.star_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('تعيين كافتراضي'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: _red,
                          ),
                          SizedBox(width: 8),
                          Text('حذف', style: TextStyle(color: _red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: _border),

          // ── Stats row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _InfoCell(
                  icon: Icons.inventory_2_outlined,
                  label: 'الأصناف',
                  value: '${(data['items'] as num?)?.toInt() ?? 0}',
                ),
                const SizedBox(width: 16),
                _InfoCell(
                  icon: Icons.monetization_on_outlined,
                  label: 'قيمة المخزون',
                  value:
                      '${(((data['value'] as num?)?.toDouble() ?? 0) / 1000).toStringAsFixed(1)} ألف',
                ),
                const Spacer(),
                OutlinedButton.icon(
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
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.zero,
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
    ),
  );
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

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
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> branches;
  const _WarehouseSheet({this.existing, required this.branches});

  @override
  State<_WarehouseSheet> createState() => _WarehouseSheetState();
}

class _WarehouseSheetState extends State<_WarehouseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _location;
  bool _active = true;
  bool _isDefault = false;
  int? _branchId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _code = TextEditingController(text: e?['code'] ?? '');
    _location = TextEditingController(text: e?['location'] ?? '');
    _active = ((e?['isActive'] as num?) ?? 1) == 1;
    _isDefault = ((e?['isDefault'] as num?) ?? 0) == 1;
    _branchId =
        (e?['branchId'] as num?)?.toInt() ??
        (widget.branches.isNotEmpty
            ? (widget.branches.first['id'] as num).toInt()
            : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
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
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isEdit ? 'تعديل المستودع' : 'مستودع جديد',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _t1,
                ),
              ),
              const SizedBox(height: 20),
              _field(
                _name,
                'اسم المستودع *',
                Icons.warehouse_outlined,
                required: true,
              ),
              const SizedBox(height: 12),
              _field(_code, 'كود المستودع', Icons.qr_code_rounded),
              const SizedBox(height: 12),
              _field(_location, 'الموقع', Icons.location_on_outlined),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _branchId,
                decoration: InputDecoration(
                  labelText: 'الفرع',
                  prefixIcon: const Icon(
                    Icons.account_tree_outlined,
                    size: 20,
                    color: _t2,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _navy, width: 1.5),
                  ),
                ),
                items: widget.branches
                    .map(
                      (b) => DropdownMenuItem<int>(
                        value: (b['id'] as num).toInt(),
                        child: Text(b['name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _branchId = v),
                validator: (v) => v == null ? 'اختر فرعا' : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text(
                  'مستودع نشط',
                  style: TextStyle(fontSize: 14, color: _t1),
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeColor: _teal,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('افتراضي'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                activeColor: _teal,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    _WarehouseInput(
                      name: _name.text.trim(),
                      code: _code.text.trim().isEmpty
                          ? 'WH-${DateTime.now().millisecondsSinceEpoch}'
                          : _code.text.trim(),
                      location: _location.text.trim(),
                      branchId: _branchId,
                      isActive: _active,
                      isDefault: _isDefault,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  isEdit ? 'حفظ التعديلات' : 'إنشاء المستودع',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: _t2),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: _navy, width: 1.5),
        ),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null
          : null,
    );
  }
}

class _WarehouseInput {
  const _WarehouseInput({
    required this.name,
    required this.code,
    required this.location,
    required this.branchId,
    required this.isActive,
    required this.isDefault,
  });

  final String name;
  final String code;
  final String location;
  final int? branchId;
  final bool isActive;
  final bool isDefault;
}

// ══════════════════════════════════════════════════════════════════════════════
// Stock Detail Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _StockDetailSheet extends StatelessWidget {
  final Map<String, dynamic> warehouse;
  const _StockDetailSheet({required this.warehouse});

  @override
  Widget build(BuildContext context) {
    final repo = InventoryRepository();
    final warehouseId = (warehouse['id'] as num?)?.toInt() ?? -1;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
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
                  borderRadius: BorderRadius.zero,
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
