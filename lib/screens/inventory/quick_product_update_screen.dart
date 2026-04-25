import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/global_barcode_route_bridge.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/product_repository.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/barcode_input_launcher.dart';

/// تعديل سريع لمنتجات موجودة: بحث + صفحات، ومسح باركود يُستهلك هنا (لا يُوجَّه للبيع).
class QuickProductUpdateScreen extends StatefulWidget {
  const QuickProductUpdateScreen({super.key});

  @override
  State<QuickProductUpdateScreen> createState() => _QuickProductUpdateScreenState();
}

class _QuickProductUpdateScreenState extends State<QuickProductUpdateScreen> {
  static const _pageSize = 40;

  final ProductRepository _repo = ProductRepository();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  GlobalBarcodeRouteBridge? _barcodeBridge;

  final List<Map<String, dynamic>> _rows = [];
  final Map<int, _RowDraft> _draftById = {};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bridge = context.read<GlobalBarcodeRouteBridge>();
      _barcodeBridge = bridge;
      bridge.setBarcodePriorityHandler(this, _onGlobalBarcode);
    });
    _reload(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    for (final d in _draftById.values) {
      d.dispose();
    }
    _draftById.clear();
    _barcodeBridge?.clearBarcodePriorityHandler(this);
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  Future<bool> _onGlobalBarcode(String raw) async {
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
    final prod = resolved['product'] as Map<String, dynamic>;
    final id = prod['id'] as int;
    final row = await _repo.getProductQuickEditRow(id);
    if (!mounted) return true;
    if (row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحميل بيانات المنتج')),
      );
      return true;
    }
    _disposeDrafts();
    _rows
      ..clear()
      ..add(row);
    _hasMore = false;
    _offset = 0;
    _appliedSearch = '';
    _searchCtrl.text = code;
    _syncDrafts();
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم اختيار: ${row['name']}')),
    );
    return true;
  }

  void _disposeDrafts() {
    for (final d in _draftById.values) {
      d.dispose();
    }
    _draftById.clear();
  }

  void _syncDrafts() {
    final ids = _rows.map((e) => e['id'] as int).toSet();
    for (final id in _draftById.keys.toList()) {
      if (!ids.contains(id)) {
        _draftById.remove(id)?.dispose();
      }
    }
    for (final r in _rows) {
      final id = r['id'] as int;
      _draftById.putIfAbsent(id, () => _RowDraft(r));
    }
  }

  Future<void> _reload({required bool reset}) async {
    _debounce?.cancel();
    if (reset) {
      setState(() {
        _loading = true;
        _rows.clear();
        _offset = 0;
        _hasMore = true;
        _disposeDrafts();
      });
    }
    final q = _searchCtrl.text.trim();
    _appliedSearch = q;
    try {
      final batch = await _repo.queryProductsQuickEditPage(
        search: q,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      if (_appliedSearch != q) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(batch);
        _offset = batch.length;
        _hasMore = batch.length >= _pageSize;
        _syncDrafts();
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التحميل: $e')),
      );
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    final q = _appliedSearch;
    try {
      final batch = await _repo.queryProductsQuickEditPage(
        search: q,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      if (_appliedSearch != q) return;
      setState(() {
        _rows.addAll(batch);
        _offset += batch.length;
        _hasMore = batch.length >= _pageSize;
        _syncDrafts();
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحميل المزيد: $e')),
      );
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_reload(reset: true));
    });
  }

  Future<void> _openCameraScan() async {
    final code = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح باركود المنتج',
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _onGlobalBarcode(code.trim());
  }

  double _parseMoney(String raw) {
    final t = raw.replaceAll(',', '').trim();
    return double.tryParse(t) ?? 0;
  }

  Future<void> _saveRow(int productId) async {
    final d = _draftById[productId];
    if (d == null) return;
    final name = d.name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم المنتج لا يمكن أن يكون فارغاً')),
      );
      return;
    }
    final buy = _parseMoney(d.buy.text);
    final sell = _parseMoney(d.sell.text);
    final minSell = _parseMoney(d.minSell.text);
    final qty = _parseMoney(d.qty.text);
    final low = _parseMoney(d.low.text);
    if (sell < 0 || buy < 0 || minSell < 0 || qty < 0 || low < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قيم غير صالحة')),
      );
      return;
    }
    if (minSell > sell + 1e-9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أقل سعر بيع لا يتجاوز سعر البيع')),
      );
      return;
    }
    final bc = d.barcode.text.trim();
    try {
      await _repo.updateProductBasic(
        productId: productId,
        name: name,
        barcode: bc.isEmpty ? null : bc,
        buyPrice: buy,
        sellPrice: sell,
        minSellPrice: minSell,
        qty: d.track ? qty : 0,
        lowStockThreshold: d.track ? low : 0,
        trackInventory: d.track,
      );
      if (!mounted) return;
      unawaited(context.read<ProductProvider>().loadProducts(seedIfEmpty: false));
      unawaited(context.read<NotificationProvider>().refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المنتج')),
      );
      await _reload(reset: true);
    } on StateError catch (e) {
      if (!mounted) return;
      final m = e.message;
      if (m == 'duplicate_barcode') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الباركود مستخدم لمنتج آخر')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(m)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحديث منتج موجود'),
          actions: [
            IconButton(
              tooltip: 'مسح باركود (كاميرا)',
              onPressed: _loading ? null : _openCameraScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'بحث',
                  hintText: 'اسم، باركود، رمز، أو رقم المنتج — اتركه فارغاً لعرض أول الصفحة',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: AppShape.none),
                  isDense: true,
                ),
                onChanged: (_) => _scheduleSearch(),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_reload(reset: true)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'في هذه الصفحة: قارئ الباركود (HID) يبحث عن المنتج هنا ولا يُوجَّه للبيع. '
                'مرّر للأسفل لتحميل المزيد.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'لا نتائج. جرّب بحثاً آخر أو امسح باركوداً.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollCtrl,
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: _rows.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i >= _rows.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final id = _rows[i]['id'] as int;
                              final draft = _draftById[id];
                              if (draft == null) {
                                return const SizedBox.shrink();
                              }
                              return _QuickProductCard(
                                row: _rows[i],
                                draft: draft,
                                onSave: () => _saveRow(id),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowDraft {
  _RowDraft(Map<String, dynamic> m)
      : productId = m['id'] as int,
        track = ((m['trackInventory'] as int?) ?? 1) != 0,
        name = TextEditingController(text: (m['name'] as String?) ?? ''),
        barcode = TextEditingController(text: (m['barcode'] as String?) ?? ''),
        buy = TextEditingController(text: _num(m['buy'])),
        sell = TextEditingController(text: _num(m['sell'])),
        minSell = TextEditingController(text: _num(m['minSell'])),
        qty = TextEditingController(text: _num(m['qty'])),
        low = TextEditingController(text: _num(m['lowStockThreshold']));

  static String _num(dynamic v) {
    final d = (v as num?)?.toDouble() ?? 0;
    if ((d - d.roundToDouble()).abs() < 1e-9) {
      return d.toInt().toString();
    }
    return d.toStringAsFixed(2);
  }

  final int productId;
  final bool track;
  final TextEditingController name;
  final TextEditingController barcode;
  final TextEditingController buy;
  final TextEditingController sell;
  final TextEditingController minSell;
  final TextEditingController qty;
  final TextEditingController low;

  void dispose() {
    name.dispose();
    barcode.dispose();
    buy.dispose();
    sell.dispose();
    minSell.dispose();
    qty.dispose();
    low.dispose();
  }
}

class _QuickProductCard extends StatelessWidget {
  const _QuickProductCard({
    required this.row,
    required this.draft,
    required this.onSave,
  });

  final Map<String, dynamic> row;
  final _RowDraft draft;
  final VoidCallback onSave;

  Widget _numField(
    BuildContext context, {
    required TextEditingController ctrl,
    required String label,
    bool readOnly = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: AppShape.none),
        filled: readOnly,
        fillColor: readOnly ? cs.surfaceContainerHighest : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = (row['categoryName'] as String?)?.trim() ?? '';
    final code = (row['productCode'] as String?)?.trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'رقم ${row['id']}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                if (code.isNotEmpty)
                  Text(
                    code,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.name,
              decoration: const InputDecoration(
                labelText: 'اسم المنتج',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppShape.none),
              ),
            ),
            if (cat.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('التصنيف: $cat', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: draft.barcode,
              decoration: const InputDecoration(
                labelText: 'الباركود',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppShape.none),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (ctx, c) {
                final narrow = c.maxWidth < 520;

                final buyW = Expanded(
                  child: _numField(ctx, ctrl: draft.buy, label: 'سعر الشراء'),
                );
                final sellW = Expanded(
                  child: _numField(ctx, ctrl: draft.sell, label: 'سعر البيع'),
                );
                final minW = Expanded(
                  child: _numField(ctx, ctrl: draft.minSell, label: 'أقل سعر بيع'),
                );
                final qtyW = Expanded(
                  child: _numField(
                    ctx,
                    ctrl: draft.qty,
                    label: 'الكمية',
                    readOnly: !draft.track,
                  ),
                );
                final lowW = Expanded(
                  child: _numField(
                    ctx,
                    ctrl: draft.low,
                    label: 'حد التنبيه',
                    readOnly: !draft.track,
                  ),
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _numField(ctx, ctrl: draft.buy, label: 'سعر الشراء'),
                      const SizedBox(height: 8),
                      _numField(ctx, ctrl: draft.sell, label: 'سعر البيع'),
                      const SizedBox(height: 8),
                      _numField(ctx, ctrl: draft.minSell, label: 'أقل سعر بيع'),
                      const SizedBox(height: 8),
                      _numField(
                        ctx,
                        ctrl: draft.qty,
                        label: 'الكمية',
                        readOnly: !draft.track,
                      ),
                      const SizedBox(height: 8),
                      _numField(
                        ctx,
                        ctrl: draft.low,
                        label: 'حد التنبيه',
                        readOnly: !draft.track,
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [buyW, const SizedBox(width: 8), sellW, const SizedBox(width: 8), minW],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [qtyW, const SizedBox(width: 8), lowW],
                    ),
                  ],
                );
              },
            ),
            if (!draft.track)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'تتبع المخزون معطّل لهذا الصنف — الكمية من قاعدة البيانات تبقى كما هي عند الحفظ.',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded, size: 20),
                label: const Text('حفظ'),
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
