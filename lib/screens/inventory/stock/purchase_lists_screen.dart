import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/product_variant_kind.dart';
import '../../../models/supplier_ap_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/database_helper.dart';
import '../../../services/oil_product_grades_repository.dart';
import '../../../services/stock/purchase_list_repository.dart';
import '../../../services/stock/purchase_product_draft.dart';
import '../add_product_screen.dart';
import '../../../services/stock/stock_engine.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/stock_qty_format.dart';
import '../../../verticals/oil_change/widgets/oil_change_form_theme.dart';

String _actorOf(BuildContext context) {
  try {
    return context.read<AuthProvider>().displayName;
  } catch (_) {
    return '';
  }
}

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

double _num(String raw) => StockQtyFormat.parse(raw) ?? 0;

double _money(String raw) =>
    IraqiCurrencyFormat.parseIqdInt(raw.replaceAll('د.ع', '')).toDouble();

String _moneyText(num v) => v <= 0 ? '' : IraqiCurrencyFormat.formatInt(v);

/// إعداد ق-22: تاريخ القائمة تلقائي بيوم الفتح أو يدوي.
abstract final class PurchaseListSettings {
  static const _manualDateKey = 'purchase_list_manual_date';

  static Future<bool> manualDate() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_manualDateKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setManualDate(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_manualDateKey, v);
    } catch (_) {}
  }
}

/// غلاف الشاشات: ثيم بطاقة الغيار + ألوان «إعدادات شاشة البيع».
class _Themed extends StatelessWidget {
  const _Themed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: OilChangeFormTheme.wrap(context, Theme.of(context)),
    child: child,
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.list);
  final PurchaseList list;

  @override
  Widget build(BuildContext context) {
    final (text, color) = list.isDraft
        ? ('مسودة', OilChangeFormTheme.goldOf(context))
        : list.needsFinish
        ? ('ينقصها فاتورة المورد', AppSemanticColors.warning)
        : ('مستلمة', AppSemanticColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: OilChangeFormTheme.radiusOf(context),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// «قوائم المشتريات»
// ═══════════════════════════════════════════════════════════════════════════

class PurchaseListsScreen extends StatefulWidget {
  const PurchaseListsScreen({super.key, this.supplierId});

  /// من صفحة المورد: قوائمه فقط.
  final int? supplierId;

  @override
  State<PurchaseListsScreen> createState() => _PurchaseListsScreenState();
}

class _PurchaseListsScreenState extends State<PurchaseListsScreen> {
  final _repo = PurchaseListRepository.instance;
  List<PurchaseList>? _lists;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await _repo.listAll(supplierId: widget.supplierId);
    if (mounted) setState(() => _lists = l);
  }

  Future<void> _newList() async {
    final created = await showModalBottomSheet<PurchaseList>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _Themed(child: _NewListSheet(supplierId: widget.supplierId)),
    );
    if (created == null || !mounted) return;
    await _open(created);
  }

  Future<void> _open(PurchaseList l) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PurchaseListScreen(listGlobalId: l.globalId),
      ),
    );
    await _load();
  }

  Future<void> _toggleDateSetting() async {
    final manual = await PurchaseListSettings.manualDate();
    await PurchaseListSettings.setManualDate(!manual);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !manual
              ? 'تاريخ القائمة يُكتب يدوياً'
              : 'تاريخ القائمة تلقائي بيوم فتحها',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return _Themed(
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'قوائم المشتريات',
          actions: [
            PopupMenuButton<String>(
              onSelected: (_) => _toggleDateSetting(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'date',
                  child: Text('تاريخ القائمة: تلقائي / يدوي'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newList,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('قائمة جديدة'),
        ),
        body: lists == null
            ? const Center(child: CircularProgressIndicator())
            : lists.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'لا قوائم بعد. كل مرة تشتري افتح «قائمة جديدة»، '
                    'اكتب المورد ثم أضف الأصناف.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    96,
                  ),
                  itemCount: lists.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) =>
                      _ListCard(list: lists[i], onTap: () => _open(lists[i])),
                ),
              ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list, required this.onTap});
  final PurchaseList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    return Material(
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: OilChangeFormTheme.radiusOf(context),
        side: BorderSide(color: gold.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: OilChangeFormTheme.radiusOf(context),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: gold),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.supplierName.isEmpty
                          ? 'بلا مورد'
                          : list.supplierName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: OilChangeFormTheme.emphasisText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_date(list.listDate)} · ${list.lineCount} صنف · '
                      '${list.place.label}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: OilChangeFormTheme.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    IraqiCurrencyFormat.formatIqd(list.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OilChangeFormTheme.emphasisText(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _StatusChip(list),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── قائمة جديدة ────────────────────────────────────────────────────────────

class _NewListSheet extends StatefulWidget {
  const _NewListSheet({this.supplierId});
  final int? supplierId;

  @override
  State<_NewListSheet> createState() => _NewListSheetState();
}

class _NewListSheetState extends State<_NewListSheet> {
  List<Supplier> _suppliers = const [];
  Supplier? _supplier;
  bool _newSupplier = false;
  final _newSupplierName = TextEditingController();
  final _theirRef = TextEditingController();
  DateTime _date = DateTime.now();
  bool _manualDate = false;
  StockPlace _place = StockPlace.store;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manual = await PurchaseListSettings.manualDate();
    List<Supplier> sups = const [];
    try {
      final s = await DatabaseHelper().getSupplierApSummaries();
      sups = s.map((e) => e.supplier).where((s) => s.isActive).toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _manualDate = manual;
      _suppliers = sups;
      _newSupplier = sups.isEmpty;
      if (widget.supplierId != null) {
        final m = sups.where((s) => s.id == widget.supplierId);
        if (m.isNotEmpty) _supplier = m.first;
      }
    });
  }

  @override
  void dispose() {
    _newSupplierName.dispose();
    _theirRef.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _open() async {
    if (_busy) return;
    int? sid;
    String sname;
    if (_newSupplier) {
      sname = _newSupplierName.text.trim();
      if (sname.isEmpty) {
        _snack('اكتب اسم المورد');
        return;
      }
    } else {
      if (_supplier == null) {
        _snack('اختر المورد');
        return;
      }
      sid = _supplier!.id;
      sname = _supplier!.name;
    }
    setState(() => _busy = true);
    try {
      if (_newSupplier) {
        sid = await DatabaseHelper().insertSupplier(name: sname);
      }
      final l = await PurchaseListRepository.instance.createDraft(
        supplierId: sid,
        supplierName: sname,
        listDate: _date,
        place: _place,
        theirRef: _theirRef.text,
        createdBy: _actorOf(context),
      );
      if (mounted) Navigator.of(context).pop(l);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('تعذّر فتح القائمة: $e');
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'قائمة مشتريات جديدة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: OilChangeFormTheme.isDark(context)
                    ? gold
                    : OilChangeFormTheme.navyOf(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(height: 1, color: gold.withValues(alpha: 0.35)),
            const SizedBox(height: AppSpacing.md),
            if (!_newSupplier)
              DropdownButtonFormField<Supplier>(
                initialValue: _supplier,
                isExpanded: true,
                decoration: OilChangeFormTheme.field(
                  context: context,
                  labelText: 'المورد',
                ),
                items: [
                  for (final s in _suppliers)
                    DropdownMenuItem(value: s, child: Text(s.name)),
                ],
                onChanged: (s) => setState(() => _supplier = s),
              )
            else
              TextField(
                controller: _newSupplierName,
                autofocus: true,
                decoration: OilChangeFormTheme.field(
                  context: context,
                  labelText: 'اسم المورد الجديد',
                ),
              ),
            if (_suppliers.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _newSupplier = !_newSupplier),
                  icon: Icon(
                    _newSupplier ? Icons.list_rounded : Icons.person_add_alt_1,
                    size: 18,
                  ),
                  label: Text(_newSupplier ? 'من الموردين' : 'مورد جديد'),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _manualDate ? _pickDate : null,
              child: InputDecorator(
                decoration: OilChangeFormTheme.field(
                  context: context,
                  labelText: 'التاريخ',
                  helperText: _manualDate ? null : 'تلقائي بيوم فتح القائمة',
                  suffixIcon: _manualDate
                      ? const Icon(Icons.calendar_month_rounded)
                      : null,
                ),
                child: Text(_date.toString().substring(0, 10)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _theirRef,
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'رقم فاتورة المورد (اختياري)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InputDecorator(
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'تدخل البضاعة إلى',
              ),
              child: SegmentedButton<StockPlace>(
                segments: const [
                  ButtonSegment(value: StockPlace.store, label: Text('المخزن')),
                  ButtonSegment(value: StockPlace.shop, label: Text('المحل')),
                ],
                selected: {_place},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _place = s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _open,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('فتح القائمة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// القائمة
// ═══════════════════════════════════════════════════════════════════════════

class PurchaseListScreen extends StatefulWidget {
  const PurchaseListScreen({super.key, required this.listGlobalId});
  final String listGlobalId;

  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  final _repo = PurchaseListRepository.instance;
  PurchaseList? _list;
  List<PurchaseLine> _lines = const [];
  final _paid = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await _repo.getList(widget.listGlobalId);
    final lines = await _repo.lines(widget.listGlobalId);
    if (!mounted) return;
    setState(() {
      _list = l;
      _lines = lines;
      if (l != null && _paid.text.isEmpty)
        _paid.text = _moneyText(l.paidAmount);
    });
  }

  Future<void> _addItem({PurchaseLine? edit}) async {
    final l = _list;
    if (l == null || !l.isDraft) return;
    final d = edit?.productDraft;
    if (edit != null && d != null) {
      // سطر صنف جديد كُتب في «إضافة منتج»: يُعاد فتحها بما فيه.
      final replace = d.isFluid
          ? [
              for (final x in _lines)
                if (x.productId == null &&
                    x.isFluid &&
                    x.familyKey == edit.familyKey)
                  x.globalId,
            ]
          : [edit.globalId];
      final another = await openPurchaseProductScreen(
        context,
        list: l,
        existing: _lines,
        draft: d,
        replace: replace,
      );
      await _load();
      if (another == true && mounted) await _addItem();
      return;
    }
    // «حفظ وإضافة صنف آخر» يرجع true: نحدّث الجدول ونفتح صفحة فارغة،
    // فيرى صاحب المحل كل سطر حفظه حين يرجع للقائمة.
    var another = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PurchaseLineEditorScreen(
          list: l,
          existing: _lines,
          editFamilyKey: edit != null && edit.isFluid ? edit.familyKey : null,
          editLine: edit != null && !edit.isFluid ? edit : null,
        ),
      ),
    );
    await _load();
    while (another == true && mounted) {
      another = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PurchaseLineEditorScreen(list: l, existing: _lines),
        ),
      );
      await _load();
    }
  }

  Future<void> _lineMenu(PurchaseLine line) async {
    if (!(_list?.isDraft ?? false)) return;
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('تعديل'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppSemanticColors.danger,
              ),
              title: const Text('حذف من القائمة'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (a == 'edit') {
      await _addItem(edit: line);
    } else if (a == 'delete') {
      await _repo.deleteLines(widget.listGlobalId, [line.globalId]);
      await _load();
    }
  }

  Future<void> _setPay(PurchasePayMode m) async {
    await _repo.updateHeader(widget.listGlobalId, payMode: m);
    await _load();
  }

  Future<void> _receive() async {
    final l = _list;
    if (l == null || _busy) return;
    if (l.isDraft && l.payMode == PurchasePayMode.part) {
      await _repo.updateHeader(
        widget.listGlobalId,
        paidAmount: _money(_paid.text),
      );
    }
    final newCount = _lines.where((x) => x.productId == null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isDraft ? 'حفظ واستلام' : 'إكمال فاتورة المورد'),
        content: Text(
          l.isDraft
              ? 'تدخل ${_lines.length} صنف إلى «${l.place.label}» بمجموع '
                    '${IraqiCurrencyFormat.formatIqd(l.total)}'
                    '${newCount > 0 ? '، ويُنشأ $newCount صنف جديد' : ''}. '
                    'الدفع: ${l.payMode.label}. بعد الحفظ لا تُعدّل القائمة.'
              : 'تُكتب فاتورة المورد والدفع الناقصان.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await _repo.receive(
      widget.listGlobalId,
      actor: _actorOf(context),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? 'استُلمت القائمة' : res.message)),
    );
    await _load();
  }

  Future<void> _deleteDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المسودة'),
        content: const Text('تُحذف القائمة وسطورها. لا رصيد ولا صنف يتغير.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteDraft(widget.listGlobalId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return _Themed(
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: l == null
              ? 'قائمة مشتريات'
              : (l.supplierName.trim().isEmpty ? 'قائمة مشتريات' : l.supplierName),
          actions: [
            if (l != null) Center(child: _StatusChip(l)),
            if (l?.isDraft ?? false)
              IconButton(
                tooltip: 'حذف المسودة',
                onPressed: _deleteDraft,
                icon: const Icon(Icons.delete_outline),
              ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: l == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_lines.isNotEmpty)
                    _LinesTable(
                      lines: _lines,
                      onTap: l.isDraft ? _lineMenu : null,
                    ),
                  if (l.isDraft) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => _addItem(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة صنف'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _TotalsBox(list: l, lines: _lines),
                  const SizedBox(height: AppSpacing.md),
                  if (l.isDraft) ...[
                    InputDecorator(
                      decoration: OilChangeFormTheme.field(
                        context: context,
                        labelText: 'الدفع',
                      ),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final m in PurchasePayMode.values)
                            ChoiceChip(
                              label: Text(m.label),
                              selected: l.payMode == m,
                              onSelected: (_) => _setPay(m),
                            ),
                        ],
                      ),
                    ),
                    if (l.payMode == PurchasePayMode.part) ...[
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _paid,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          IraqiCurrencyFormat.moneyInputFormatter(),
                        ],
                        decoration: OilChangeFormTheme.field(
                          context: context,
                          labelText: 'المدفوع نقداً الآن',
                          helperText: 'الباقي دين على حساب المورد',
                        ),
                      ),
                    ],
                    if (l.supplierId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          'قائمة بلا مورد: تدخل البضاعة بلا فاتورة مورد.',
                          style: TextStyle(color: AppSemanticColors.warning),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _busy || _lines.isEmpty ? null : _receive,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.inventory_rounded),
                      label: const Text('حفظ واستلام'),
                    ),
                  ] else if (l.needsFinish)
                    FilledButton.icon(
                      onPressed: _busy ? null : _receive,
                      icon: const Icon(Icons.receipt_rounded),
                      label: const Text('إكمال فاتورة المورد'),
                    )
                  else
                    Text(
                      'استُلمت إلى «${l.place.label}». للتصحيح: إذن صادر '
                      '(إرجاع للمورد) لا تعديل القائمة.',
                      style: TextStyle(
                        color: OilChangeFormTheme.secondaryText(context),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// جدول السطور: الزيت مجمّع تحت اسم عائلته (ق-27، البند 5).
class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines, this.onTap});
  final List<PurchaseLine> lines;
  final ValueChanged<PurchaseLine>? onTap;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    final head = TextStyle(
      color: gold,
      fontWeight: FontWeight.w800,
      fontSize: 12.5,
    );
    final rows = <Widget>[];
    final seenFamilies = <String>{};

    Widget row({
      required Widget name,
      required String qty,
      required String price,
      required String total,
      VoidCallback? tap,
      bool bold = false,
      double indent = 0,
    }) {
      final st = TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: OilChangeFormTheme.emphasisText(context),
        fontSize: 13,
      );
      return InkWell(
        onTap: tap,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: AppSpacing.md + indent,
            end: AppSpacing.md,
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(flex: 5, child: name),
              Expanded(flex: 3, child: Text(qty, style: st)),
              Expanded(flex: 3, child: Text(price, style: st)),
              Expanded(
                flex: 3,
                child: Text(total, style: st, textAlign: TextAlign.end),
              ),
            ],
          ),
        ),
      );
    }

    Widget nameCell(PurchaseLine l, {bool bold = false, String? text}) => Row(
      children: [
        Flexible(
          child: Text(
            text ?? l.name,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: OilChangeFormTheme.emphasisText(context),
              fontSize: 13,
            ),
          ),
        ),
        if (l.productId == null) ...[
          const SizedBox(width: AppSpacing.xs),
          _NewBadge(catalog: l.catalogId != null),
        ],
      ],
    );

    void divider() =>
        rows.add(Divider(height: 1, color: gold.withValues(alpha: 0.15)));

    for (final l in lines) {
      if (l.isFluid) {
        if (!seenFamilies.add(l.familyKey)) continue;
        final fam = lines.where((x) => x.isFluid && x.familyKey == l.familyKey);
        final sum = fam.fold<double>(0, (a, x) => a + x.lineTotal);
        final liters = fam.fold<double>(0, (a, x) => a + x.qty);
        if (rows.isNotEmpty) divider();
        rows.add(
          row(
            name: nameCell(l, bold: true, text: l.familyName ?? l.name),
            qty: '${StockQtyFormat.format(liters)} لتر',
            price: '',
            total: IraqiCurrencyFormat.formatInt(sum),
            bold: true,
            tap: onTap == null ? null : () => onTap!(l),
          ),
        );
        for (final g in fam) {
          rows.add(
            row(
              name: nameCell(g, text: g.viscosity ?? g.name),
              qty: StockQtyFormat.format(g.qty),
              price: IraqiCurrencyFormat.formatInt(g.unitCost),
              total: IraqiCurrencyFormat.formatInt(g.lineTotal),
              indent: AppSpacing.lg,
              tap: onTap == null ? null : () => onTap!(g),
            ),
          );
        }
        continue;
      }
      if (rows.isNotEmpty) divider();
      rows.add(
        row(
          name: nameCell(l),
          qty: '${StockQtyFormat.format(l.qty)} ${l.unitLabel}',
          price: IraqiCurrencyFormat.formatInt(l.unitCost),
          total: IraqiCurrencyFormat.formatInt(l.lineTotal),
          tap: onTap == null ? null : () => onTap!(l),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
        borderRadius: OilChangeFormTheme.radiusOf(context),
        border: Border.all(color: gold.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(flex: 5, child: Text('الصنف', style: head)),
                Expanded(flex: 3, child: Text('الكمية', style: head)),
                Expanded(flex: 3, child: Text('سعر الشراء', style: head)),
                Expanded(
                  flex: 3,
                  child: Text('المجموع', style: head, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
          Container(height: 1, color: gold.withValues(alpha: 0.5)),
          ...rows,
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({this.catalog = false});
  final bool catalog;

  @override
  Widget build(BuildContext context) {
    final c = AppSemanticColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: OilChangeFormTheme.radiusOf(context),
      ),
      child: Text(
        catalog ? 'من الكتالوج' : 'جديد',
        style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TotalsBox extends StatelessWidget {
  const _TotalsBox({required this.list, required this.lines});
  final PurchaseList list;
  final List<PurchaseLine> lines;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: OilChangeFormTheme.fieldContainerDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_date(list.listDate)} · ${lines.length} سطر',
              style: TextStyle(
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
          ),
          Text(
            'الإجمالي  ',
            style: TextStyle(color: gold, fontWeight: FontWeight.w700),
          ),
          Text(
            IraqiCurrencyFormat.formatIqd(list.total),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: OilChangeFormTheme.emphasisText(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// «إضافة صنف» إلى القائمة
// ═══════════════════════════════════════════════════════════════════════════

/// صف لزوجة/درجة في شجرة العائلة.
class _GradeRow {
  _GradeRow({
    this.productId,
    String viscosity = '',
    double qty = 0,
    double cost = 0,
    double sell = 0,
    this.balance,
    this.avgCost,
    this.lineGid,
    this.catalogId,
  }) : viscosity = TextEditingController(text: viscosity),
       qty = TextEditingController(
         text: qty > 0 ? StockQtyFormat.format(qty) : '',
       ),
       cost = TextEditingController(text: _moneyText(cost)),
       sell = TextEditingController(text: _moneyText(sell));

  final int? productId;
  final TextEditingController viscosity;
  final TextEditingController qty;
  final TextEditingController cost;
  final TextEditingController sell;
  final double? balance;
  final double? avgCost;
  final String? lineGid;
  final int? catalogId;

  void dispose() {
    viscosity.dispose();
    qty.dispose();
    cost.dispose();
    sell.dispose();
  }
}

/// يفتح شاشة «إضافة منتج» الكاملة لصنف جديد في القائمة. الشاشة لا تنشئ
/// المنتج: ترجع مسودة تُحفظ أسطراً بشارة «جديد»، ويُنشأ المنتج عند الاستلام.
/// [replace] أسطر المسودة نفسها عند تعديلها. يعيد null إن أُلغيت الشاشة، وإلا
/// true إن طلب صاحب المحل «حفظ وإضافة صنف آخر».
Future<bool?> openPurchaseProductScreen(
  BuildContext context, {
  required PurchaseList list,
  required List<PurchaseLine> existing,
  int stockType = 0,
  String? name,
  PurchaseProductDraft? draft,
  List<String> replace = const [],
}) async {
  final res = await Navigator.of(context)
      .push<({PurchaseProductDraft draft, bool another})>(
    MaterialPageRoute(
      builder: (_) => AddProductScreen(
        forPurchase: true,
        purchaseDraft: draft,
        purchaseStockType: stockType,
        purchaseName: name,
      ),
    ),
  );
  if (res == null || !context.mounted) return null;
  final lines = res.draft.toLines();
  if (lines.isEmpty) return null;
  var toRemove = [...replace];
  // عائلة جديدة بالاسم نفسه سبق أن كُتبت في القائمة: يُسأل قبل استبدالها.
  final others = existing.where(
    (l) =>
        l.productId == null &&
        !replace.contains(l.globalId) &&
        (res.draft.isFluid
            ? l.isFluid && l.familyKey == lines.first.familyKey
            : !l.isFluid &&
                  l.name.trim().toLowerCase() ==
                      lines.first.name.trim().toLowerCase()),
  );
  if (others.isNotEmpty) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('موجود في القائمة'),
        content: Text(
          '«${res.draft.isFluid ? res.draft.familyName : lines.first.name}» '
          'جديد في القائمة من قبل. تستبدل سطره القديم بما كتبته الآن؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استبدال'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    toRemove = [...toRemove, ...others.map((l) => l.globalId)];
  }
  final repo = PurchaseListRepository.instance;
  if (toRemove.isNotEmpty) await repo.deleteLines(list.globalId, toRemove);
  await repo.saveLines(list.globalId, lines);
  return res.another;
}

class PurchaseLineEditorScreen extends StatefulWidget {
  const PurchaseLineEditorScreen({
    super.key,
    required this.list,
    required this.existing,
    this.editLine,
    this.editFamilyKey,
  });

  final PurchaseList list;
  final List<PurchaseLine> existing;
  final PurchaseLine? editLine;
  final String? editFamilyKey;

  @override
  State<PurchaseLineEditorScreen> createState() =>
      _PurchaseLineEditorScreenState();
}

enum _Mode { search, product, family }

class _PurchaseLineEditorScreenState extends State<PurchaseLineEditorScreen> {
  final _repo = PurchaseListRepository.instance;
  final _search = TextEditingController();
  Timer? _debounce;
  List<PurchasePickHit> _hits = const [];
  _Mode _mode = _Mode.search;

  // صنف عادي
  int? _productId;
  String? _lineGid;
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _sell = TextEditingController();
  int _baseKind = 0;
  ({double shop, double store, double avgCost, bool track})? _bal;

  // عائلة زيت/هيدروليك
  int? _familyParentId;
  int _familyKind = ProductVariantKind.oilFamily;
  final _familyName = TextEditingController();
  final List<_GradeRow> _grades = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editLine;
    if (e != null) {
      _fillProduct(
        productId: e.productId,
        name: e.name,
        barcode: e.barcode,
        cost: e.unitCost,
        sell: e.sellPrice ?? 0,
        qty: e.qty,
        baseKind: e.stockBaseKind,
        lineGid: e.globalId,
      );
    } else if (widget.editFamilyKey != null) {
      final fam = widget.existing
          .where((x) => x.isFluid && x.familyKey == widget.editFamilyKey)
          .toList();
      if (fam.isNotEmpty) {
        unawaited(
          _openFamily(
            parentId: fam.first.familyParentId,
            name: fam.first.familyName ?? fam.first.name,
            kind: fam.first.familyKind,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _search,
      _name,
      _barcode,
      _qty,
      _cost,
      _sell,
      _familyName,
    ]) {
      c.dispose();
    }
    for (final g in _grades) {
      g.dispose();
    }
    super.dispose();
  }

  bool get _isOilMode => _familyKind == ProductVariantKind.oilFamily;

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final h = await _repo.search(q);
      if (mounted) setState(() => _hits = h);
    });
  }

  void _fillProduct({
    int? productId,
    required String name,
    String? barcode,
    double cost = 0,
    double sell = 0,
    double qty = 0,
    int baseKind = 0,
    String? lineGid,
  }) {
    _productId = productId;
    _lineGid = lineGid;
    _name.text = name;
    _barcode.text = barcode ?? '';
    _cost.text = _moneyText(cost);
    _sell.text = _moneyText(sell);
    _qty.text = qty > 0 ? StockQtyFormat.format(qty) : '';
    _baseKind = baseKind;
    _bal = null;
    _mode = _Mode.product;
    if (productId != null) {
      DatabaseHelper().database
          .then((db) => StockEngine.balances(db, productId))
          .then((b) {
            if (mounted) setState(() => _bal = b);
          })
          .catchError((_) {});
    }
    setState(() {});
  }

  Future<void> _pick(PurchasePickHit h) async {
    if (h.isCatalog) {
      final parent = await _repo.findFamilyByName(h.title, h.familyKind);
      await _openFamily(
        parentId: parent,
        name: h.title,
        kind: h.familyKind,
        catalog: h,
      );
      return;
    }
    if (h.isFamily) {
      await _openFamily(
        parentId: h.familyParentId,
        name: h.title,
        kind: h.familyKind,
      );
      return;
    }
    final dup = widget.existing.where(
      (l) => l.productId != null && l.productId == h.productId,
    );
    if (dup.isNotEmpty && widget.editLine == null) {
      final merge = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('الصنف موجود في القائمة'),
          content: Text(
            '«${h.title}» في القائمة. تدمج الكمية أم سطراً ثانياً بسعر آخر؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('سطر ثانٍ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('دمج الكمية'),
            ),
          ],
        ),
      );
      if (merge == null) return;
      if (merge) {
        final d = dup.first;
        _fillProduct(
          productId: d.productId,
          name: d.name,
          barcode: d.barcode,
          cost: d.unitCost,
          sell: d.sellPrice ?? h.sellPrice,
          qty: d.qty,
          baseKind: d.stockBaseKind,
          lineGid: d.globalId,
        );
        return;
      }
    }
    _fillProduct(
      productId: h.productId,
      name: h.title,
      barcode: h.barcode,
      cost: h.buyPrice,
      sell: h.sellPrice,
      baseKind: h.stockBaseKind,
    );
  }

  Future<void> _openFamily({
    int? parentId,
    required String name,
    required int kind,
    PurchasePickHit? catalog,
  }) async {
    for (final g in _grades) {
      g.dispose();
    }
    _grades.clear();
    _familyParentId = parentId;
    _familyKind = kind;
    _familyName.text = name;
    final inList = widget.existing.where(
      (x) =>
          x.isFluid &&
          (parentId != null
              ? x.familyParentId == parentId
              : (x.familyName ?? '').trim().toLowerCase() ==
                    name.trim().toLowerCase()),
    );
    if (parentId != null) {
      final snaps = await OilProductGradesRepository.instance
          .loadGradeSnapshotsForParent(parentId);
      final db = await DatabaseHelper().database;
      for (final s in snaps) {
        final b = await StockEngine.balances(db, s.linkedProductId);
        final l = inList.where((x) => x.productId == s.linkedProductId);
        _grades.add(
          _GradeRow(
            productId: s.linkedProductId,
            viscosity: s.input.viscosity,
            qty: l.isEmpty ? 0 : l.first.qty,
            cost: l.isEmpty ? 0 : l.first.unitCost,
            sell: l.isEmpty
                ? s.input.sellPrice
                : (l.first.sellPrice ?? s.input.sellPrice),
            balance: b.shop + b.store,
            avgCost: b.avgCost,
            lineGid: l.isEmpty ? null : l.first.globalId,
          ),
        );
      }
    }
    // لزوجات جديدة سبق أن أُضيفت لهذه العائلة في القائمة.
    for (final l in inList.where((x) => x.productId == null)) {
      _grades.add(
        _GradeRow(
          viscosity: l.viscosity ?? '',
          qty: l.qty,
          cost: l.unitCost,
          sell: l.sellPrice ?? 0,
          lineGid: l.globalId,
          catalogId: l.catalogId,
        ),
      );
    }
    if (catalog != null) {
      final v = (catalog.catalogViscosity ?? '').trim().toLowerCase();
      final has = _grades.any(
        (g) => g.viscosity.text.trim().toLowerCase() == v,
      );
      if (!has) {
        _grades.add(
          _GradeRow(
            viscosity: catalog.catalogViscosity ?? '',
            sell: catalog.catalogSellPerLiter ?? 0,
            catalogId: catalog.catalogId,
          ),
        );
      }
    }
    if (_grades.isEmpty) _grades.add(_GradeRow());
    if (mounted) setState(() => _mode = _Mode.family);
  }

  // صنف جديد أو عائلة جديدة: شاشة «إضافة منتج» الكاملة (طلب صاحب المحل).
  Future<void> _newProduct() => _openFull(0);

  Future<void> _newFamily(int kind) =>
      _openFull(kind == ProductVariantKind.oilFamily ? 5 : 4);

  Future<void> _openFull(int stockType) async {
    final another = await openPurchaseProductScreen(
      context,
      list: widget.list,
      existing: widget.existing,
      stockType: stockType,
      name: _search.text.trim(),
    );
    if (another == null || !mounted) return;
    Navigator.of(context).pop(another);
  }

  Future<bool> _save() async {
    if (_saving) return false;
    final items = <PurchaseLine>[];
    final removed = <String>[];
    if (_mode == _Mode.product) {
      final name = _name.text.trim();
      final qty = _num(_qty.text);
      if (name.isEmpty) return _err('اكتب اسم الصنف');
      if (qty <= 0) return _err('اكتب الكمية المشتراة');
      if (_productId == null) {
        final same = widget.existing.where(
          (l) =>
              l.productId == null &&
              l.globalId != _lineGid &&
              l.name.trim().toLowerCase() == name.toLowerCase(),
        );
        if (same.isNotEmpty)
          return _err('صنف جديد بالاسم نفسه موجود في القائمة');
      }
      items.add(
        PurchaseLine(
          globalId: _lineGid,
          productId: _productId,
          name: name,
          qty: qty,
          unitCost: _money(_cost.text),
          sellPrice: _money(_sell.text) > 0 ? _money(_sell.text) : null,
          barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
          isNew: _productId == null,
          stockBaseKind: _baseKind,
        ),
      );
    } else if (_mode == _Mode.family) {
      final fam = _familyName.text.trim();
      if (fam.isEmpty)
        return _err('اكتب اسم ${_isOilMode ? 'الزيت' : 'الهيدروليك'}');
      final seen = <String>{};
      for (final g in _grades) {
        final vis = g.viscosity.text.trim();
        final qty = _num(g.qty.text);
        if (qty <= 0) {
          if (g.lineGid != null) removed.add(g.lineGid!);
          continue;
        }
        if (vis.isEmpty)
          return _err('اكتب ${_isOilMode ? 'اللزوجة' : 'الدرجة'}');
        if (!seen.add(vis.toLowerCase())) return _err('«$vis» مكررة');
        items.add(
          PurchaseLine(
            globalId: g.lineGid,
            productId: g.productId,
            name: '$fam — $vis',
            qty: qty,
            unitCost: _money(g.cost.text),
            sellPrice: _money(g.sell.text) > 0 ? _money(g.sell.text) : null,
            isNew: g.productId == null,
            familyParentId: _familyParentId,
            familyName: fam,
            viscosity: vis,
            familyKind: _familyKind,
            catalogId: g.catalogId,
            stockBaseKind: 3,
          ),
        );
      }
      if (items.isEmpty && removed.isEmpty) {
        return _err('اكتب كمية لزوجة واحدة على الأقل');
      }
    } else {
      return false;
    }
    setState(() => _saving = true);
    try {
      if (removed.isNotEmpty) {
        await _repo.deleteLines(widget.list.globalId, removed);
      }
      await _repo.saveLines(widget.list.globalId, items);
      return true;
    } catch (e) {
      return _err('تعذّر الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    return false;
  }

  Future<void> _saveAndBack() async {
    if (await _save() && mounted) Navigator.of(context).pop();
  }

  Future<void> _saveAndAnother() async {
    if (await _save() && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return _Themed(
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'إضافة صنف',
          actions: const [],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_mode == _Mode.search) ..._searchBody(),
            if (_mode == _Mode.product) ..._productBody(),
            if (_mode == _Mode.family) ..._familyBody(),
          ],
        ),
        bottomNavigationBar: _mode == _Mode.search
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _saveAndAnother,
                          child: const Text('حفظ وإضافة صنف آخر'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _saveAndBack,
                          child: const Text('حفظ والرجوع للقائمة'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _searchBody() => [
    TextField(
      controller: _search,
      autofocus: true,
      onChanged: _onSearch,
      decoration: OilChangeFormTheme.field(
        context: context,
        labelText: 'ابحث بالاسم أو الباركود',
        prefixIcon: const Icon(Icons.search_rounded),
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    for (final h in _hits)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          h.isFamily || h.isCatalog
              ? Icons.oil_barrel_rounded
              : Icons.inventory_2_outlined,
          color: OilChangeFormTheme.goldOf(context),
        ),
        title: Text(
          h.isCatalog ? '${h.title} · ${h.catalogViscosity}' : h.title,
        ),
        subtitle: Text(
          h.isCatalog
              ? 'من الكتالوج: أول شراء يحوّله زيت مخزون'
              : h.isFamily
              ? (h.familyKind == ProductVariantKind.oilFamily
                    ? 'زيت — عائلة'
                    : 'هيدروليك — عائلة')
              : 'آخر سعر شراء ${IraqiCurrencyFormat.formatIqd(h.buyPrice)}',
        ),
        trailing: h.isCatalog ? const _NewBadge(catalog: true) : null,
        onTap: () => _pick(h),
      ),
    const SizedBox(height: AppSpacing.md),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: _newProduct,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('صنف جديد'),
        ),
        OutlinedButton.icon(
          onPressed: () => _newFamily(ProductVariantKind.oilFamily),
          icon: const Icon(Icons.oil_barrel_outlined),
          label: const Text('زيت — عائلة جديدة'),
        ),
        OutlinedButton.icon(
          onPressed: () => _newFamily(ProductVariantKind.hydraulicFamily),
          icon: const Icon(Icons.water_drop_outlined),
          label: const Text('هيدروليك — عائلة جديدة'),
        ),
      ],
    ),
  ];

  Widget _balances(double? shop, double? store, double? avg, String unit) {
    Widget cell(String label, String v) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: OilChangeFormTheme.fieldContainerDecoration(context),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: OilChangeFormTheme.goldOf(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell('المحل', '${StockQtyFormat.format(shop ?? 0)} $unit'),
        const SizedBox(width: AppSpacing.sm),
        cell('المخزن', '${StockQtyFormat.format(store ?? 0)} $unit'),
        const SizedBox(width: AppSpacing.sm),
        cell('متوسط الكلفة', IraqiCurrencyFormat.formatIqd(avg ?? 0)),
      ],
    );
  }

  List<Widget> _productBody() {
    final isNew = _productId == null;
    final unit = _baseKind == 3 ? 'لتر' : (_baseKind == 1 ? 'كغم' : 'قطعة');
    return [
      if (isNew)
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: _NewBadge(),
        ),
      if (!isNew && _bal != null) ...[
        _balances(_bal!.shop, _bal!.store, _bal!.avgCost, unit),
        const SizedBox(height: AppSpacing.md),
      ],
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _name,
        enabled: isNew,
        decoration: OilChangeFormTheme.field(
          context: context,
          labelText: 'اسم الصنف',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (isNew) ...[
        TextField(
          controller: _barcode,
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: 'الباركود (اختياري)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InputDecorator(
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: 'الوحدة',
          ),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('قطعة')),
              ButtonSegment(value: 1, label: Text('كغم')),
              ButtonSegment(value: 3, label: Text('لتر')),
            ],
            selected: {_baseKind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _baseKind = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      TextField(
        controller: _qty,
        autofocus: !isNew,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: OilChangeFormTheme.field(
          context: context,
          labelText: 'الكمية المشتراة ($unit)',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'الشراء / $unit',
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _sell,
              keyboardType: TextInputType.number,
              inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'البيع / $unit',
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _familyBody() {
    final gold = OilChangeFormTheme.goldOf(context);
    final noun = _isOilMode ? 'لزوجة' : 'درجة';
    return [
      TextField(
        controller: _familyName,
        enabled: _familyParentId == null,
        decoration: OilChangeFormTheme.field(
          context: context,
          labelText: _isOilMode ? 'اسم الزيت (الماركة)' : 'اسم الهيدروليك',
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '$noun بلا كمية لا تدخل القائمة. الكمية باللتر وسعر الشراء للتر.',
        style: TextStyle(
          color: OilChangeFormTheme.secondaryText(context),
          fontSize: 12.5,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      for (final g in _grades)
        Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: OilChangeFormTheme.fieldContainerDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: g.productId != null
                        ? Text(
                            g.viscosity.text,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: OilChangeFormTheme.emphasisText(context),
                            ),
                          )
                        : TextField(
                            controller: g.viscosity,
                            decoration: OilChangeFormTheme.field(
                              context: context,
                              labelText: _isOilMode ? 'اللزوجة' : 'الدرجة',
                              hintText: _isOilMode
                                  ? 'مثال: 5W30'
                                  : 'مثال: ISO VG 46',
                              isDense: true,
                            ),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (g.productId == null)
                    const _NewBadge()
                  else
                    Text(
                      'الرصيد ${StockQtyFormat.format(g.balance ?? 0)} لتر',
                      style: TextStyle(color: gold, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: g.qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: OilChangeFormTheme.field(
                        context: context,
                        labelText: 'لترات',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: g.cost,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        IraqiCurrencyFormat.moneyInputFormatter(),
                      ],
                      decoration: OilChangeFormTheme.field(
                        context: context,
                        labelText: 'شراء/لتر',
                        helperText: g.avgCost == null || g.avgCost! <= 0
                            ? null
                            : 'المتوسط ${IraqiCurrencyFormat.formatInt(g.avgCost!)}',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: g.sell,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        IraqiCurrencyFormat.moneyInputFormatter(),
                      ],
                      decoration: OilChangeFormTheme.field(
                        context: context,
                        labelText: 'بيع/لتر',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.tonalIcon(
          onPressed: () => setState(() => _grades.add(_GradeRow())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(noun),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'عبوات البيع (4 لترات…) للزوجة الجديدة تُضاف من شاشة الصنف بعد الاستلام.',
        style: TextStyle(
          color: OilChangeFormTheme.secondaryText(context),
          fontSize: 12,
        ),
      ),
    ];
  }
}
