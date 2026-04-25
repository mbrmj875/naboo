import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/database_helper.dart';
import '../../services/inventory_repository.dart';
import '../../services/permission_service.dart';
import '../../services/tenant_context_service.dart';
import '../../widgets/permission_guard.dart';

const _navy = Color(0xFF1E3A5F);
const _teal = Color(0xFF0D9488);
const _bg = Color(0xFFF1F5F9);
const _card = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1 = Color(0xFF0F172A);
const _t2 = Color(0xFF64748B);
const _green = Color(0xFF10B981);
const _orange = Color(0xFFF97316);
const _red = Color(0xFFEF4444);

// ══════════════════════════════════════════════════════════════════════════════
class StocktakingScreen extends StatefulWidget {
  const StocktakingScreen({super.key});

  @override
  State<StocktakingScreen> createState() => _StocktakingScreenState();
}

class _StocktakingScreenState extends State<StocktakingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _openSessions = const [];
  List<Map<String, dynamic>> _closedSessions = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final openRows = await _repo.listStocktakingSessions(status: 'open');
      final closedRows = await _repo.listStocktakingSessions(status: 'closed');
      if (!mounted) return;
      setState(() {
        _openSessions = openRows;
        _closedSessions = closedRows;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _newSession() async {
    final result =
        await showModalBottomSheet<({String title, int warehouseId})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _NewSessionSheet(),
        );
    if (result == null) return;
    await _repo.createStocktakingSession(
      title: result.title,
      warehouseId: result.warehouseId,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permissionKey: PermissionKeys.inventoryStocktakingManage,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text(
            'الجرد الدوري',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tab,
            indicatorColor: _teal,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'جلسات مفتوحة (${_openSessions.length})'),
              Tab(text: 'مكتملة (${_closedSessions.length})'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _orange,
          onPressed: _newSession,
          icon: const Icon(Icons.fact_check_rounded, color: Colors.white),
          label: const Text(
            'بدء جرد جديد',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tab,
                children: [
                  _SessionList(
                    sessions: _openSessions,
                    onTap: (s) => _openCounting(context, s),
                    onClose: (s) => _closeSession(s),
                  ),
                  _SessionList(
                    sessions: _closedSessions,
                    onTap: (s) => _openReport(context, s),
                  ),
                ],
              ),
      ),
    );
  }

  void _closeSession(Map<String, dynamic> s) async {
    var postDiffs = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('إقفال الجرد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('هل تريد إقفال جلسة «${s['title']}»؟'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: postDiffs,
                onChanged: (v) => setLocal(() => postDiffs = v ?? true),
                title: const Text('ترحيل الفروقات تلقائيا'),
                subtitle: const Text('ينشئ سند تسوية مخزني واحد للجلسة'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إقفال', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (postDiffs) {
        await _repo.postStocktakingAdjustments((s['id'] as num).toInt());
      }
      await _repo.closeStocktakingSession((s['id'] as num).toInt());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إقفال الجلسة بنجاح'),
            backgroundColor: _green,
          ),
        );
      }
    }
  }

  void _openCounting(BuildContext ctx, Map<String, dynamic> s) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => _CountingScreen(session: s)),
    );
  }

  void _openReport(BuildContext ctx, Map<String, dynamic> s) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SessionReportSheet(session: s),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Session List
// ══════════════════════════════════════════════════════════════════════════════
class _SessionList extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onClose;
  const _SessionList({
    required this.sessions,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text('لا توجد جلسات', style: TextStyle(color: _t2)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _SessionCard(data: sessions[i], onTap: onTap, onClose: onClose),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onClose;
  const _SessionCard({required this.data, required this.onTap, this.onClose});

  @override
  Widget build(BuildContext context) {
    final isOpen = data['status'] == 'open';
    final total = (data['totalItems'] as num?)?.toInt() ?? 0;
    final counted = (data['countedItems'] as num?)?.toInt() ?? 0;
    final progress = total > 0 ? counted / total : 0.0;

    return InkWell(
      onTap: () => onTap(data),
      borderRadius: BorderRadius.zero,
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: isOpen ? _orange.withValues(alpha: 0.5) : _border,
            width: isOpen ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isOpen
                        ? _orange.withValues(alpha: 0.1)
                        : _green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(
                    isOpen
                        ? Icons.pending_actions_rounded
                        : Icons.check_circle_rounded,
                    color: isOpen ? _orange : _green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['title']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _t1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.warehouse_outlined,
                            size: 13,
                            color: _t2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data['warehouseName']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 12, color: _t2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? _orange.withValues(alpha: 0.1)
                        : _green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    isOpen ? 'مفتوح' : 'مكتمل',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOpen ? _orange : _green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress bar
            Row(
              children: [
                Text(
                  '$counted / $total صنف',
                  style: const TextStyle(fontSize: 12, color: _t2),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isOpen ? _orange : _green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _border,
                color: isOpen ? _orange : _green,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: _t2),
                const SizedBox(width: 4),
                Text(
                  isOpen
                      ? 'بدأ: ${_fmtDate(data['startedAt']?.toString())}'
                      : 'أُقفل: ${_fmtDate(data['closedAt']?.toString())}',
                  style: const TextStyle(fontSize: 12, color: _t2),
                ),
                const Spacer(),
                if (isOpen && onClose != null)
                  TextButton.icon(
                    onPressed: () => onClose!(data),
                    icon: const Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: _orange,
                    ),
                    label: const Text(
                      'إقفال الجرد',
                      style: TextStyle(fontSize: 12, color: _orange),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => onTap(data),
                    icon: const Icon(
                      Icons.bar_chart_rounded,
                      size: 14,
                      color: _teal,
                    ),
                    label: const Text(
                      'التقرير',
                      style: TextStyle(fontSize: 12, color: _teal),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('yyyy-MM-dd').format(dt.toLocal());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// New Session Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet();

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _warehouses = const [];
  int? _warehouseId;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    final rows = await _db.listWarehousesActive(
      tenantId: TenantContextService.instance.activeTenantId,
    );
    if (!mounted) return;
    setState(() {
      _warehouses = rows;
      _warehouseId ??= rows.isNotEmpty
          ? (rows.first['id'] as num).toInt()
          : null;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            const Text(
              'بدء جلسة جرد جديدة',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _t1,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'عنوان الجلسة *',
                hintText: 'مثال: جرد شهر يوليو 2025',
                prefixIcon: const Icon(
                  Icons.title_rounded,
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
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _warehouseId,
              decoration: InputDecoration(
                labelText: 'المستودع',
                prefixIcon: const Icon(
                  Icons.warehouse_outlined,
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
              items: _warehouses
                  .map(
                    (w) => DropdownMenuItem<int>(
                      value: (w['id'] as num).toInt(),
                      child: Text(w['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _warehouseId = v),
              validator: (v) => v == null ? 'اختر مستودعاً' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context, (
                  title: _titleCtrl.text.trim(),
                  warehouseId: _warehouseId!,
                ));
              },
              icon: const Icon(Icons.fact_check_rounded, color: Colors.white),
              label: const Text(
                'بدء الجرد',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Counting Screen
// ══════════════════════════════════════════════════════════════════════════════
class _CountingScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  const _CountingScreen({required this.session});

  @override
  State<_CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends State<_CountingScreen> {
  final _searchCtrl = TextEditingController();
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.listStocktakingItems(
      (widget.session['id'] as num).toInt(),
      search: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where(
          (i) =>
              i['name'].toString().toLowerCase().contains(q) ||
              i['barcode'].toString().contains(q),
        )
        .toList();
  }

  int get _countedItems => _items.where((i) => i['countedQty'] != null).length;

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
        title: Text(
          widget.session['title']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '$_countedItems/${_items.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: _orange,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: _items.isEmpty ? 0 : _countedItems / _items.length,
                backgroundColor: Colors.white30,
                color: Colors.white,
                minHeight: 6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الباركود...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: _card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _orange, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = _filtered[i];
                      return _CountItem(
                        item: item,
                        onCount: (v) async {
                          await _repo.saveStocktakingCount(
                            itemId: (item['id'] as num).toInt(),
                            countedQty: v,
                          );
                          await _load();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final void Function(double) onCount;
  const _CountItem({required this.item, required this.onCount});

  @override
  State<_CountItem> createState() => _CountItemState();
}

class _CountItemState extends State<_CountItem> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final countedQty = widget.item['countedQty'];
    _ctrl = TextEditingController(
      text: countedQty != null
          ? (countedQty as num).toDouble().toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _diff {
    final c = double.tryParse(_ctrl.text);
    if (c == null) return null;
    return c - ((widget.item['systemQty'] as num?)?.toDouble() ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final isCounted = widget.item['countedQty'] != null;
    final diff = _diff;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isCounted
              ? (diff == 0 ? _green : _orange).withValues(alpha: 0.5)
              : _border,
        ),
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
          // Status icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCounted
                  ? (diff == 0 ? _green : _orange).withValues(alpha: 0.1)
                  : _border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(
              isCounted
                  ? (diff == 0
                        ? Icons.check_circle_rounded
                        : Icons.warning_rounded)
                  : Icons.pending_rounded,
              color: isCounted ? (diff == 0 ? _green : _orange) : _t2,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),

          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _t1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'النظام: ${((widget.item['systemQty'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: _t2),
                    ),
                    if (diff != null && diff != 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        'فرق: ${diff > 0 ? '+' : ''}${diff.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: diff > 0 ? _green : _red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Count input
          SizedBox(
            width: 80,
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _t1,
              ),
              decoration: InputDecoration(
                hintText: 'أدخل',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(color: _orange, width: 1.5),
                ),
              ),
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null) {
                  widget.onCount(d);
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Session Report Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _SessionReportSheet extends StatelessWidget {
  final Map<String, dynamic> session;
  const _SessionReportSheet({required this.session});

  @override
  Widget build(BuildContext context) {
    final total = (session['totalItems'] as num?)?.toInt() ?? 0;
    final counted = (session['countedItems'] as num?)?.toInt() ?? 0;
    final diff = total - counted;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
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
                const Icon(Icons.bar_chart_rounded, color: _teal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تقرير: ${session['title']}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _t1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Summary
                  Row(
                    children: [
                      _ReportBadge(
                        label: 'إجمالي الأصناف',
                        value: '$total',
                        color: _teal,
                      ),
                      const SizedBox(width: 10),
                      _ReportBadge(
                        label: 'تم عده',
                        value: '$counted',
                        color: _green,
                      ),
                      const SizedBox(width: 10),
                      _ReportBadge(
                        label: 'غير معدود',
                        value: '$diff',
                        color: _orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sample differences
                  const Text(
                    'ملخص الجلسة:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _t2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _diffRow('الحالة', total, counted, counted - total),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffRow(String name, int sys, int cnt, int diff) {
    final color = diff > 0 ? _green : _red;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _t1,
              ),
            ),
          ),
          Text(
            'النظام: $sys',
            style: const TextStyle(fontSize: 12, color: _t2),
          ),
          const SizedBox(width: 12),
          Text(
            'الفعلي: $cnt',
            style: const TextStyle(fontSize: 12, color: _t2),
          ),
          const SizedBox(width: 12),
          Text(
            '${diff > 0 ? '+' : ''}$diff',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ReportBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: _t2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
