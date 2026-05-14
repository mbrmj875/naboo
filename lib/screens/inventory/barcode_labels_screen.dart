import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/global_barcode_route_bridge.dart';
import '../../services/app_settings_repository.dart';
import '../../services/product_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/barcode_labels_pdf.dart';
import '../../utils/numeric_format.dart';

final class _PrintLabelsIntent extends Intent {
  const _PrintLabelsIntent();
}

final class _FocusBarcodeSearchIntent extends Intent {
  const _FocusBarcodeSearchIntent();
}

final class _MakeAllOneIntent extends Intent {
  const _MakeAllOneIntent();
}

final class _DismissSearchIntent extends Intent {
  const _DismissSearchIntent();
}

class BarcodeLabelsScreen extends StatefulWidget {
  const BarcodeLabelsScreen({
    super.key,
    this.focusProductIds,
  });

  /// إذا كانت غير فارغة: تُعرض هذه المنتجات فقط (ويُولَّد لها باركود داخلي إن كان مفقوداً) —
  /// تُستخدم بعد حفظ منتج بلا باركود لفتح شاشة طباعة جاهزة.
  final List<int>? focusProductIds;

  @override
  State<BarcodeLabelsScreen> createState() => _BarcodeLabelsScreenState();
}

class _BarcodeLabelsScreenState extends State<BarcodeLabelsScreen> {
  final ProductRepository _repo = ProductRepository();

  static const _kPrefSize = 'inv.barcode_label.size';
  static const _kPrefShowName = 'inv.barcode_label.show_name';
  static const _kPrefShowPrice = 'inv.barcode_label.show_price';

  GlobalBarcodeRouteBridge? _bridge;

  bool _loading = true;
  bool _refreshing = false;
  String? _err;
  DateTime _lastSynced = DateTime.now();

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFn = FocusNode();
  Timer? _searchDeb;
  List<Map<String, dynamic>> _searchHits = const [];
  bool _searchBusy = false;

  final List<int> _queueIds = [];
  final Map<int, Map<String, dynamic>> _rowsById = {};
  final Map<int, int> _copies = {};
  final Map<int, TextEditingController> _qtyCtrl = {};
  final Map<int, FocusNode> _qtyFn = {};

  int? _flashDupId;

  BarcodeLabelSize _size = BarcodeLabelSize.mm50x30;
  bool _showName = true;
  bool _showPrice = true;
  bool _printBusy = false;

  int get _tenantId => TenantContextService.instance.activeTenantId;

  Future<void> _loadPrefs() async {
    final p = AppSettingsRepository.instance;
    final sv = await p.getForTenant(_kPrefSize, tenantId: _tenantId);
    final nm = await p.getForTenant(_kPrefShowName, tenantId: _tenantId);
    final pr = await p.getForTenant(_kPrefShowPrice, tenantId: _tenantId);
    if (!mounted) return;
    if (sv != null) {
      for (final e in BarcodeLabelSize.values) {
        if (e.name == sv) {
          _size = e;
          break;
        }
      }
    }
    if (nm != null) _showName = nm == '1';
    if (pr != null) _showPrice = pr == '1';
  }

  Future<void> _persistSize() async {
    await AppSettingsRepository.instance
        .setForTenant(_kPrefSize, _size.name, tenantId: _tenantId);
  }

  Future<void> _persistShowName() async {
    await AppSettingsRepository.instance
        .setForTenant(_kPrefShowName, _showName ? '1' : '0', tenantId: _tenantId);
  }

  Future<void> _persistShowPrice() async {
    await AppSettingsRepository.instance
        .setForTenant(_kPrefShowPrice, _showPrice ? '1' : '0', tenantId: _tenantId);
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bridge = context.read<GlobalBarcodeRouteBridge>();
      _bridge = bridge;
      bridge.setBarcodePriorityHandler(this, _onGlobalBarcodeScan);
      await _load();
    });
  }

  Future<bool> _onGlobalBarcodeScan(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return false;
    final resolved = await _repo.resolveProductByAnyBarcode(code);
    if (!mounted) return true;
    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد منتج بهذا الباركود')),
      );
      return true;
    }
    final prod = resolved['product'] as Map<String, dynamic>? ?? {};
    final id = (prod['id'] as num?)?.toInt();
    if (id == null || id <= 0) return true;
    final rows = await _repo.getProductsForBarcodeLabelsByIds(
      tenantId: _tenantId,
      productIds: [id],
    );
    if (!mounted) return true;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحميل بيانات المنتج')),
      );
      return true;
    }
    _tryEnqueue(rows.first);
    return true;
  }

  Future<void> _reloadQueueFresh() async {
    if (_queueIds.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      final rows = await _repo.getProductsForBarcodeLabelsByIds(
        tenantId: _tenantId,
        productIds: _queueIds.toList(growable: false),
      );
      final byId = {for (final r in rows) (r['id'] as num).toInt(): r};
      if (!mounted) return;
      setState(() {
        for (final id in _queueIds) {
          final r = byId[id];
          if (r != null) _rowsById[id] = r;
        }
        _lastSynced = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _bridge?.clearBarcodePriorityHandler(this);
    _searchDeb?.cancel();
    _search.dispose();
    _searchFn.dispose();
    for (final e in _qtyCtrl.entries) {
      e.value.dispose();
    }
    for (final e in _qtyFn.entries) {
      e.value.dispose();
    }

    super.dispose();
  }

  void _onSearchChanged() {
    _searchDeb?.cancel();
    setState(() {});
    _searchDeb = Timer(const Duration(milliseconds: 300), _runBackendSearch);
  }

  Future<void> _runBackendSearch() async {
    final q = _search.text.trim();
    if (!mounted) return;
    if (q.length < 2) {
      setState(() {
        _searchHits = [];
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    try {
      final rows = await _repo.queryProductsForBarcodeLabels(
        tenantId: _tenantId,
        query: q,
        hasBarcodeFilter: 0,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _searchHits = rows;
        _searchBusy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchBusy = false);
    }
  }

  void _clearSearchDropdown() {
    setState(() {
      _searchHits = [];
      _searchBusy = false;
    });
  }

  void _clearSearchRefocusSearch() {
    _search.clear();
    _clearSearchDropdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFn.requestFocus();
    });
  }


  int _smartCopiesForRow(Map<String, dynamic> r) {
    final track = ((r['trackInventory'] as num?)?.toInt() ?? 1) == 1;
    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
    final stockBaseKind = (r['stockBaseKind'] as num?)?.toInt() ?? 0;
    if (!track) return 1;
    if (stockBaseKind == 1) {
      return 1;
    }
    final c = qty.isFinite ? qty.ceil() : 1;
    return c.clamp(1, 999);
  }

  void _ensureQtyField(int id) {
    final n = (_copies[id] ?? 1).clamp(1, 999);
    _copies[id] = n;
    final c = _qtyCtrl.putIfAbsent(id, TextEditingController.new);
    if (c.text != '$n') c.text = '$n';
    _qtyFn.putIfAbsent(id, FocusNode.new);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      await _loadPrefs();
      final tid = _tenantId;
      final focus = widget.focusProductIds?.where((e) => e > 0).toSet().toList();
      if (focus != null && focus.isNotEmpty) {
        await _repo.assignInternalBarcodesForIds(
          tenantId: tid,
          productIds: focus,
        );
        final rows = await _repo.getProductsForBarcodeLabelsByIds(
          tenantId: tid,
          productIds: focus,
        );
        for (final c in _qtyCtrl.values) {
          c.dispose();
        }
        _qtyCtrl.clear();
        for (final f in _qtyFn.values) {
          f.dispose();
        }
        _qtyFn.clear();
        _queueIds.clear();
        _rowsById.clear();
        _copies.clear();
        for (final r in rows) {
          final id = (r['id'] as num?)?.toInt();
          if (id == null) continue;
          _queueIds.add(id);
          _rowsById[id] = r;
          _copies[id] = _smartCopiesForRow(r);
          _ensureQtyField(id);
        }
        _lastSynced = DateTime.now();
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      for (final c in _qtyCtrl.values) {
        c.dispose();
      }
      _qtyCtrl.clear();
      for (final f in _qtyFn.values) {
        f.dispose();
      }
      _qtyFn.clear();
      _queueIds.clear();
      _rowsById.clear();
      _copies.clear();
      _lastSynced = DateTime.now();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  void _tryEnqueue(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt();
    if (id == null || id <= 0) return;
    if (_queueIds.contains(id)) {
      setState(() => _flashDupId = id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المنتج موجود بالفعل')),
      );
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() {
          if (_flashDupId == id) _flashDupId = null;
        });
      });
      return;
    }
    setState(() {
      _queueIds.add(id);
      _rowsById[id] = row;
      _copies[id] = 1;
      _ensureQtyField(id);
    });
    _clearSearchRefocusSearch();
  }

  Future<void> _removeQueued(int productId, {bool confirmHeavy = false}) async {
    final n = (_copies[productId] ?? 1).clamp(1, 999);
    if (confirmHeavy && n > 5) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('إزالة من القائمة'),
              content: const Text(
                'كمية الطباعة أكبر من 5؛ هل تريد الإزالة؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('إزالة'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    setState(() {
      _queueIds.remove(productId);
      _rowsById.remove(productId);
      _copies.remove(productId);
      final dc = _qtyCtrl.remove(productId);
      dc?.dispose();
      final df = _qtyFn.remove(productId);
      df?.dispose();
    });
  }

  void _adjustCopies(int id, int delta) {
    final cur = (_copies[id] ?? 1).clamp(1, 999);
    _setCopies(id, cur + delta);
  }

  void _setCopies(int id, int raw) {
    final n = raw.clamp(1, 999);
    setState(() {
      _copies[id] = n;
      final c = _qtyCtrl[id];
      if (c != null && c.text != '$n') c.text = '$n';
    });
  }

  Future<void> _applySmartQuantities() async {
    var skipped = 0;
    for (final id in _queueIds) {
      final r = _rowsById[id];
      if (r == null) continue;
      final q = _smartQtyFromStock(r);
      if (q == null) {
        skipped++;
        continue;
      }
      _copies[id] = q;
      final c = _qtyCtrl[id];
      if (c != null && c.text != '$q') c.text = '$q';
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث الكميات')),
    );
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تخطي المنتجات ذات الكمية صفر ($skipped)')),
      );
    }
  }

  /// كمية طباعة من المخزون؛ `null` = تخطّي التحديث (كمية مخزون صفر).
  int? _smartQtyFromStock(Map<String, dynamic> r) {
    final track = ((r['trackInventory'] as num?)?.toInt() ?? 1) == 1;
    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
    final stockBaseKind = (r['stockBaseKind'] as num?)?.toInt() ?? 0;
    if (!track || stockBaseKind == 1) return 1;
    if (!qty.isFinite || qty <= 0) return null;
    final c = qty.ceil();
    return c.clamp(1, 999);
  }

  Future<void> _makeAllCopiesOne() async {
    if (_queueIds.isEmpty) return;
    final customized = _queueIds.any((id) => (_copies[id] ?? 1) != 1);
    if (customized) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('إعادة التعيين'),
              content: const Text(
                'سيتم إعادة تعيين جميع الكميات إلى 1، هل تريد المتابعة؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('متابعة'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    setState(() {
      for (final id in _queueIds) {
        _copies[id] = 1;
        final c = _qtyCtrl[id];
        if (c != null) c.text = '1';
      }
    });
  }

  Future<void> _confirmAndPrintPipeline() async {
    if (_totalLabels <= 0) return;
    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final first = _queueIds.isEmpty ? null : _rowsById[_queueIds.first];
            return AlertDialog(
              title: const Text('معاينة الطباعة'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'إجمالي الملصقات: $_totalLabels',
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'الطباعة عبر الطابعة الافتراضية للنظام أو من شاشة المعاينة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (first != null)
                      SizedBox(
                        height: 240,
                        child: _CardLabelPreview(
                          row: first,
                          showName: _showName,
                          showPrice: _showPrice,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
              ],
            );
          },
        ) ??
        false;
    if (ok != true) return;
    await _executePrintPdf();
  }

  Future<void> _executePrintPdf() async {
    if (_totalLabels <= 0) return;
    setState(() => _printBusy = true);
    try {
      final tid = _tenantId;
      final ids = List<int>.from(_queueIds);
      final toAssign = <int>[];
      for (final id in ids) {
        final r = _rowsById[id];
        if (r == null) continue;
        final bc = '${r['barcode']}'.trim();
        final c = (_copies[id] ?? 0).clamp(0, 999);
        if (c > 0 && bc.isEmpty) toAssign.add(id);
      }
      if (toAssign.isNotEmpty) {
        await _repo.assignInternalBarcodesForIds(
          tenantId: tid,
          productIds: toAssign,
        );
      }
      final fresh = await _repo.getProductsForBarcodeLabelsByIds(
        tenantId: tid,
        productIds: ids,
      );
      final byId = {for (final r in fresh) (r['id'] as num).toInt(): r};
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          final rr = byId[id];
          if (rr != null) _rowsById[id] = rr;
          _ensureQtyField(id);
        }
      });
      final products = _toProductsOrdered();
      if (products.isEmpty) return;
      await BarcodeLabelsPdf.present(
        context,
        title: 'ملصقات باركود المنتجات',
        products: products,
        copiesByProductId: _copies,
        size: _size,
        showName: _showName,
        showPrice: _showPrice,
      );
      if (!mounted) return;
      await _showPrintDoneChoices();
    } finally {
      if (mounted) setState(() => _printBusy = false);
    }
  }

  Future<void> _showPrintDoneChoices() async {
    final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تمت الطباعة'),
            content: const Text('تم تنفيذ المعاينة أو الطباعة من نافذة النظام.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('مسح القائمة'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('طباعة مرة أخرى'),
              ),
            ],
          ),
        );
    if (!mounted) return;
    if (go == true) {
      await _executePrintPdf();
      return;
    }
    _clearWholeQueueUi();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح قائمة الطباعة')),
    );
  }

  void _clearWholeQueueUi() {
    for (final c in _qtyCtrl.values) {
      c.dispose();
    }
    _qtyCtrl.clear();
    for (final f in _qtyFn.values) {
      f.dispose();
    }
    _qtyFn.clear();
    setState(() {
      _queueIds.clear();
      _rowsById.clear();
      _copies.clear();
    });
  }

  List<BarcodeLabelProduct> _toProductsOrdered() {
    final out = <BarcodeLabelProduct>[];
    for (final id in _queueIds) {
      final r = _rowsById[id];
      if (r == null) continue;
      final pid = (r['id'] as num?)?.toInt();
      if (pid == null || pid <= 0) continue;
      final barcode = (r['barcode'] as String?)?.trim() ?? '';
      if (barcode.isEmpty) continue;
      final name = (r['name'] as String?) ?? 'صنف';
      final sell = (r['sellPrice'] as num?)?.toDouble() ?? 0;
      final stockBaseKind = (r['stockBaseKind'] as num?)?.toInt() ?? 0;
      out.add(
        BarcodeLabelProduct(
          id: pid,
          name: name,
          barcode: barcode,
          sellPrice: sell,
          stockBaseKind: stockBaseKind,
        ),
      );
    }
    return out;
  }

  int get _totalProducts => _queueIds.length;

  int get _totalLabels {
    var s = 0;
    for (final id in _queueIds) {
      s += (_copies[id] ?? 0).clamp(0, 999);
    }
    return s;
  }

  String _qtyLine(Map<String, dynamic> r) {
    final isWeight = ((r['stockBaseKind'] as num?)?.toInt() ?? 0) == 1;
    final q = (r['qty'] as num?)?.toDouble() ?? 0;
    if (isWeight) return '${q.toStringAsFixed(2)} كغم';
    final w = q == q.roundToDouble();
    return w ? '${q.round()}' : q.toStringAsFixed(2);
  }

  String _agoAr(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 55) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
    return 'منذ يوم أو أكثر';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyP, control: true): _PrintLabelsIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _FocusBarcodeSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: true): _MakeAllOneIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissSearchIntent(),
      },
      child: Actions(
        actions: {
          _PrintLabelsIntent: CallbackAction<_PrintLabelsIntent>(
            onInvoke: (_) {
              if (_totalLabels > 0 && !_printBusy) unawaited(_confirmAndPrintPipeline());
              return null;
            },
          ),
          _FocusBarcodeSearchIntent: CallbackAction<_FocusBarcodeSearchIntent>(
            onInvoke: (_) {
              _searchFn.requestFocus();
              return null;
            },
          ),
          _MakeAllOneIntent: CallbackAction<_MakeAllOneIntent>(
            onInvoke: (_) {
              if (_queueIds.isNotEmpty) unawaited(_makeAllCopiesOne());
              return null;
            },
          ),
          _DismissSearchIntent: CallbackAction<_DismissSearchIntent>(
            onInvoke: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              _clearSearchDropdown();
              return null;
            },
          ),
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('طباعة ملصقات باركود'),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              actions: [
                IconButton(
                      tooltip:
                          'آخر تحديث: ${_agoAr(_lastSynced)} — إعادة جلب الأسعار والمخزون',
                      onPressed:
                          _loading ? null : () => unawaited(_reloadQueueFresh()),
                      icon: _refreshing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary.withValues(alpha: 0.9),
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                TextButton.icon(
                  onPressed: _loading ||
                          _totalLabels <= 0 ||
                          _printBusy
                      ? null
                      : () => unawaited(_confirmAndPrintPipeline()),
                  icon: _printBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_rounded),
                  label: Text('طباعة $_totalLabels ملصق'),
                  style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _err != null
                    ? Center(child: Text('تعذّر التحميل: $_err'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _cardSearch(cs),
                          const SizedBox(height: 12),
                          _cardSettings(cs),
                          const SizedBox(height: 10),
                          _summaryBar(cs),
                          const SizedBox(height: 12),
                          if (_queueIds.isEmpty) _emptyState(cs),
                          ..._queueIds.asMap().entries.map(
                                (en) =>
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _queueCard(en.key, en.value, cs),
                                    ),
                              ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _cardSearch(ColorScheme cs) {
    final q = _search.text.trim();
    final showDd = !_searchBusy && q.length >= 2;
    final emptyHits = !_searchBusy && showDd && _searchHits.isEmpty;
    return Card(
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              focusNode: _searchFn,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'بحث عن منتج',
                hintText: 'حرفان أو أكثر (اسم / باركود / رمز صنف)',
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(borderRadius: AppShape.none),
                isDense: true,
                suffixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchBusy)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(start: 6),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (q.isNotEmpty)
                        IconButton(
                          tooltip: 'مسح',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearchRefocusSearch,
                        ),
                    ],
                  ),
                ),
              ),
              onSubmitted: (_) {
                final first = showDd && _searchHits.isNotEmpty ? _searchHits.first : null;
                if (first != null) _tryEnqueue(Map<String, dynamic>.from(first));
              },
            ),
            const SizedBox(height: 6),
            Text(
              'منتجات الوزن: يُطبع المعرف على الملصق؛ الوزن يُوزَّن عند البيع.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (showDd || emptyHits || _searchBusy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 210),
                    child: emptyHits
                        ? const Center(child: Text('لا توجد نتائج'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: showDd ? _searchHits.length : 0,
                            itemBuilder: (context, i) {
                              final r = _searchHits[i];
                              final nm = (r['name'] ?? '').toString();
                              final bc = '${r['barcode'] ?? ''}'.trim();
                              final sk = '${r['productCode'] ?? ''}'.trim();
                              final qStock = _qtyLine(r);
                              return ListTile(
                                dense: true,
                                trailing: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.qr_code_2_rounded,
                                    color: cs.primary.withValues(alpha: .7),
                                    size: 24,
                                  ),
                                ),
                                title: Text(nm, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '${bc.isNotEmpty ? 'باركود: $bc' : 'بدون باركود'}'
                                  ' — مخزون: $qStock'
                                  '${sk.isNotEmpty ? '\nرمز صنف: $sk' : ''}',
                                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                ),
                                onTap: () {
                                  final map = Map<String, dynamic>.from(r);
                                  _tryEnqueue(map);
                                },
                              );
                            },
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardSettings(ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'اختَر المقاس ومظهر المعاينة (تطبَّق على البطاقات والطباعة).',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BarcodeLabelSize>(
              value: _size,
              decoration: const InputDecoration(
                labelText: 'مقاس الملصق',
                border: OutlineInputBorder(borderRadius: AppShape.none),
                isDense: true,
              ),
              items: kBarcodeLabelSizesCommonFirst
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Row(
                        children: [
                          _labelSizeThumbChip(e),
                          const SizedBox(width: 12),
                          Text(e.labelAr),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _size = v);
                unawaited(_persistSize());
              },
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: AnimatedOpacity(
                key: ValueKey<bool>(_showName && _showPrice),
                opacity: 1,
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _TogglePreviewRibbon(
                    size: _size,
                    showName: _showName,
                    showPrice: _showPrice,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار اسم المنتج'),
              value: _showName,
              onChanged: (v) async {
                setState(() => _showName = v);
                await _persistShowName();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار السعر'),
              value: _showPrice,
              onChanged: (v) async {
                setState(() => _showPrice = v);
                await _persistShowPrice();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'يضبط كمية الطباعة تلقائياً حسب كمية المخزون',
                    child: OutlinedButton(
                      onPressed: _queueIds.isEmpty
                          ? null
                          : () => unawaited(_applySmartQuantities()),
                      child: const Text('اعتماد الكمية الذكية'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _queueIds.isEmpty
                        ? null
                        : () => unawaited(_makeAllCopiesOne()),
                    child: Text(_totalProducts <= 1
                        ? 'اجعل الكل (1)'
                        : 'اجعل الكل (1) ($_totalProducts)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelSizeThumbChip(BarcodeLabelSize z) {
    final s = z.thumbnailLogicalSize;
    const maxSide = 32.0;
    final scale = maxSide / math.max(s.width, s.height);
    return SizedBox(
      width: s.width * scale,
      height: s.height * scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.black26),
        ),
      ),
    );
  }

  Widget _summaryBar(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'المنتجات: $_totalProducts',
                style: const TextStyle(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
            Text('|', style: TextStyle(color: cs.outline)),
            Expanded(
              child: Text(
                'إجمالي الملصقات: $_totalLabels',
                style: const TextStyle(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          Icon(Icons.qr_code_2_rounded, size: 72, color: cs.outlineVariant),
          const SizedBox(height: 12),
          const Text(
            'ابحث عن منتج لإضافته للطباعة',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(
            'يمكنك إضافة منتجات متعددة وطباعتها دفعة واحدة',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _queueCard(int ix, int id, ColorScheme cs) {
    final r = _rowsById[id];
    if (r == null) return const SizedBox.shrink();
    final name = '${r['name'] ?? ''}';
    final printQ = (_copies[id] ?? 1).clamp(1, 999);
    final stk = _qtyStockNum(r);
    final overStock = stk != null && printQ > stk;
    final ctl = _qtyCtrl[id]!;
    final fn = _qtyFn.putIfAbsent(id, FocusNode.new);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: _flashDupId == id
              ? Colors.amber.shade600
              : cs.outlineVariant,
          width: _flashDupId == id ? 3 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إزالة',
                    onPressed: () => _removeQueued(id, confirmHeavy: true),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'مخزون: ${_qtyLine(r)} | طباعة: $printQ',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (overStock)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'كمية الطباعة أكبر من المخزون',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: math.max(_size.thumbnailLogicalSize.height * .55, 118),
                child: _CardLabelPreview(row: r, showName: _showName, showPrice: _showPrice),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'نقص',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () =>
                        (_copies[id] ?? 1) > 1 ? _adjustCopies(id, -1) : null,
                  ),
                  SizedBox(
                    width: 92,
                    child: Focus(
                      onKeyEvent: (_, ev) {
                        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
                        if (ev.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _adjustCopies(id, 1);
                          return KeyEventResult.handled;
                        }
                        if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _adjustCopies(id, -1);
                          return KeyEventResult.handled;
                        }
                        if (ev.logicalKey == LogicalKeyboardKey.delete) {
                          unawaited(_removeQueued(id, confirmHeavy: false));
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: ctl,
                        focusNode: fn,
                        textAlign: TextAlign.center,
                        keyboardType:
                            const TextInputType.numberWithOptions(signed: false),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                        onTap: () {
                          ctl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: ctl.text.length,
                          );
                        },
                        onSubmitted: (_) {
                          final p = int.tryParse(ctl.text.trim()) ??
                              (_copies[id] ?? 1);
                          _setCopies(id, p);
                          final nx = ix + 1;
                          if (nx < _queueIds.length && _qtyFn[_queueIds[nx]] != null) {
                            FocusScope.of(context).requestFocus(_qtyFn[_queueIds[nx]]);
                          } else {
                            _searchFn.requestFocus();
                          }
                        },
                        onChanged: (s) {
                          final digits = int.tryParse(s.trim());
                          if (digits != null) _setCopies(id, digits);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'زيادة',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _adjustCopies(id, 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _qtyStockNum(Map<String, dynamic> r) {
    if (((r['stockBaseKind'] as num?)?.toInt() ?? 0) == 1) return null;
    final q = (r['qty'] as num?)?.toDouble();
    return q?.isFinite == true ? q! : null;
  }
}

class _TogglePreviewRibbon extends StatelessWidget {
  const _TogglePreviewRibbon({
    required this.size,
    required this.showName,
    required this.showPrice,
  });

  final BarcodeLabelSize size;
  final bool showName;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Text(
      'معاينة: ${showName ? 'اسم' : 'بدون اسم'} — ${showPrice ? 'سعر' : 'بدون سعر'} — ${size.labelAr}',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class NumberFormatHelper {
  static String line(Map<String, dynamic> r) {
    final sell = (r['sellPrice'] as num?)?.toDouble() ?? 0;
    return '${NumericFormat.formatNumber(sell.round().clamp(0, 999999999))} د.ع';
  }
}

class _BarcodeStripe extends StatelessWidget {
  const _BarcodeStripe({
    required this.row,
    this.compact = true,
  });

  final Map<String, dynamic> row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bc = '${row['barcode'] ?? ''}'.trim();
    final id = ((row['id'] as num?)?.toInt() ?? 0);
    final data = bc.isNotEmpty ? bc : 'P${id.abs()}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bc.isEmpty)
          Text(
            'سيتم توليد باركود تلقائياً',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: compact ? 8 : 10, color: Colors.orange.shade900),
          ),
        Expanded(
          child: Center(
            child: SizedBox(
              height: compact ? 38 : 54,
              width: 200,
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: data,
                drawText: false,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ),
        Text(
          bc.isNotEmpty ? bc : data,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: compact ? 8 : 9, color: Colors.black54),
        ),
      ],
    );
  }
}

class _CardLabelPreview extends StatelessWidget {
  const _CardLabelPreview({
    required this.row,
    required this.showName,
    required this.showPrice,
  });

  final Map<String, dynamic> row;
  final bool showName;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final isWeight = ((row['stockBaseKind'] as num?)?.toInt() ?? 0) == 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showName)
              Text(
                '${row['name'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            Expanded(
              child: _BarcodeStripe(row: row, compact: true),
            ),
            if (showPrice)
              Text(
                isWeight
                    ? '${NumberFormatHelper.line(row)} /كغم'
                    : NumberFormatHelper.line(row),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade900),
              ),
          ],
        ),
      ),
    );
  }
}

