import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/global_barcode_route_bridge.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/product_repository.dart';
import '../../theme/design_tokens.dart';
import '../../utils/numeric_format.dart';
import '../../utils/screen_layout.dart';
import '../../utils/validate_price_logic.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/inputs/app_number_input.dart';
import '../../widgets/inputs/app_price_input.dart';

/// Intent for Ctrl+S
final class _SaveIntent extends Intent {
  const _SaveIntent();
}

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
  final _searchFn = FocusNode();
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
  bool _searchTooShort = false;

  int? _savingProductId;
  bool _leavingConfirmed = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bridge = context.read<GlobalBarcodeRouteBridge>();
      _barcodeBridge = bridge;
      bridge.setBarcodePriorityHandler(this, _onGlobalBarcode);
      _searchFn.requestFocus();
    });
    unawaited(_reload(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFn.dispose();
    _scrollCtrl.dispose();
    _disposeDrafts();
    _barcodeBridge?.clearBarcodePriorityHandler(this);
    super.dispose();
  }

  bool get _anyDirty =>
      _draftById.values.any((d) => d.isDirty) && !_leavingConfirmed;

  void _disposeDrafts() {
    for (final d in _draftById.values) {
      d.dispose();
    }
    _draftById.clear();
  }

  Future<bool> _ensureCanLeaveIfDirty() async {
    if (!_anyDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: const Text('التغييرات لم تُحفظ، هل تريد المغادرة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('البقاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('مغادرة'),
          ),
        ],
      ),
    );
    return ok == true;
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
    _searchTooShort = false;
    _syncDrafts();
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم اختيار: ${row['name']}')),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d = _draftById[id];
      d?.buyFn.requestFocus();
    });
    return true;
  }

  Future<void> _reload({required bool reset}) async {
    _debounce?.cancel();
    final qRaw = _searchCtrl.text.trim();
    if (qRaw.length == 1) {
      if (reset && mounted) {
        setState(() {
          _loading = false;
          _searchTooShort = true;
        });
      }
      return;
    }

    if (reset) {
      setState(() {
        _loading = true;
        _rows.clear();
        _offset = 0;
        _hasMore = true;
        _disposeDrafts();
      });
    }
    final q = qRaw;
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
        _searchTooShort = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('تعذّر التحميل: $e'),
        ),
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
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('تعذّر تحميل المزيد: $e'),
        ),
      );
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final t = _searchCtrl.text.trim();
      setState(() {
        _searchTooShort = t.length == 1;
      });
      if (t.length == 1) return;
      unawaited(_reload(reset: true));
    });
  }

  Future<void> _submitSearchFromKeyboard() async {
    _debounce?.cancel();
    final q = _searchCtrl.text.trim();
    if (q.length == 1) {
      setState(() => _searchTooShort = true);
      return;
    }
    await _reload(reset: true);
    if (!mounted || _rows.isEmpty) return;
    final id = _rows.first['id'] as int;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _draftById[id]?.nameFn.requestFocus();
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

  Future<void> _pickSuggestion(Map<String, dynamic> row) async {
    _searchCtrl.text = (row['name'] as String?) ?? '';
    setState(() {
      _loading = false;
      _hasMore = false;
      _offset = 1;
      _appliedSearch = _searchCtrl.text.trim();
      _rows
        ..clear()
        ..add(row);
      _disposeDrafts();
      _syncDrafts();
      _searchTooShort = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = row['id'] as int;
      final d = _draftById[id];
      d?.qtyFn.requestFocus();
    });
  }

  Future<void> _openConflictProduct(int productId) async {
    final row = await _repo.getProductQuickEditRow(productId);
    if (!mounted || row == null) return;
    await _pickSuggestion(row);
  }

  Future<void> _invokeSavePrimary() async {
    if (_rows.isEmpty) return;
    final id = _rows.first['id'] as int;
    await _saveRow(id);
  }

  double _moneyToDb(int iqdRounded) => iqdRounded.toDouble();

  Future<void> _saveRow(int productId) async {
    final d = _draftById[productId];
    if (d == null) return;
    final name = d.name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('اسم المنتج لا يمكن أن يكون فارغاً'),
        ),
      );
      return;
    }
    if (name.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('اسم المنتج طويل جداً'),
        ),
      );
      return;
    }
    final buy = NumericFormat.parseNumber(d.buy.text);
    final sell = NumericFormat.parseNumber(d.sell.text);
    final minSell = NumericFormat.parseNumber(d.minSell.text);
    final qty = NumericFormat.parseNumber(d.qty.text);
    final low = NumericFormat.parseNumber(d.low.text);
    final bcUpper = d.barcode.text.trim().toUpperCase();
    if (d.duplicateBarcodeProductId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('الباركود مستخدم مسبقاً'),
        ),
      );
      return;
    }
    if (minSell > sell) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('أقل سعر بيع يجب ألا يتجاوز سعر البيع'),
        ),
      );
      return;
    }
    try {
      setState(() => _savingProductId = productId);
      await _repo.updateProductBasic(
        productId: productId,
        name: name,
        barcode: bcUpper.isEmpty ? null : bcUpper,
        buyPrice: _moneyToDb(buy),
        sellPrice: _moneyToDb(sell),
        minSellPrice: _moneyToDb(minSell),
        qty: d.track ? qty.toDouble() : 0,
        lowStockThreshold: d.track ? low.toDouble() : 0,
        trackInventory: d.track,
      );
      if (!mounted) return;
      unawaited(context.read<ProductProvider>().loadProducts(seedIfEmpty: false));
      unawaited(context.read<NotificationProvider>().refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('تم تحديث المنتج بنجاح'),
        ),
      );
      d.rebaseline();
      setState(() {
        _savingProductId = null;
        _leavingConfirmed = true;
      });
      await _reload(reset: true);
      if (!mounted) return;
      setState(() => _leavingConfirmed = false);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _savingProductId = null);
      final m = e.message;
      if (m == 'duplicate_barcode') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: const Text('هذا الباركود مستخدم لمنتج آخر'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(m),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingProductId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('تعذّر الحفظ: $e'),
        ),
      );
    }
  }

  Widget _profitBox({
    required int buy,
    required int sell,
  }) {
    final profit = sell - buy;
    final marginPct =
        buy > 0 ? ((sell - buy) / buy * 100).clamp(-1e9, 1e9) : double.nan;
    final cs = Theme.of(context).colorScheme;
    late Color pctColor;
    String lossSuffix = '';
    if (buy <= 0) {
      pctColor = cs.onSurfaceVariant;
    } else if (profit < 0) {
      pctColor = Colors.red.shade700;
      lossSuffix = ' — خسارة';
    } else if (marginPct < 10) {
      pctColor = Colors.red.shade700;
    } else if (marginPct <= 20) {
      pctColor = const Color(0xFFF59E0B);
    } else {
      pctColor = Colors.green.shade700;
    }

    final pctLabel =
        buy > 0 ? '${marginPct.round()}%' : '—';
    final profitLabel = NumericFormat.formatNumber(profit.abs());
    final sign = profit < 0 ? '-' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.zero),
        border: Border.all(color: cs.outline.withValues(alpha: 0.45)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            children: [
              const TextSpan(text: 'هامش الربح: '),
              TextSpan(
                text: '$pctLabel ',
                style: TextStyle(color: pctColor),
              ),
              const TextSpan(text: 'ربح: '),
              TextSpan(
                text: '$sign$profitLabel د.ع$lossSuffix',
                style: TextStyle(
                  color: profit < 0 ? Colors.red.shade700 : pctColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final layout = context.screenLayout;
    final qTrim = _searchCtrl.text.trim();
    final showSuggest =
        qTrim.length >= 2 && !_loading && !_searchTooShort;

    final bodyCore = Scaffold(
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
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _SaveIntent(),
        },
        child: Actions(
          actions: {
            _SaveIntent: CallbackAction<_SaveIntent>(
              onInvoke: (_) {
                unawaited(_invokeSavePrimary());
                return null;
              },
            ),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: layout.pageHorizontalGap,
                  end: layout.pageHorizontalGap,
                  top: 12,
                  bottom: 8,
                ),
                child: AppInput(
                  label: 'بحث',
                  controller: _searchCtrl,
                  focusNode: _searchFn,
                  hint: 'اسم، باركود، رمز، أو رقم المنتج',
                  prefixIcon: const Icon(Icons.search_rounded),
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => _scheduleSearch(),
                  onFieldSubmitted: (_) =>
                      unawaited(_submitSearchFromKeyboard()),
                ),
              ),
              if (_searchTooShort)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: layout.pageHorizontalGap,
                    end: layout.pageHorizontalGap,
                    bottom: 4,
                  ),
                  child: Text(
                    'اكتب حرفين على الأقل للبحث الموحّد',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              if (showSuggest)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: layout.pageHorizontalGap,
                    end: layout.pageHorizontalGap,
                    bottom: 6,
                  ),
                  child: Material(
                    elevation: 3,
                    color: cs.surfaceContainerLowest,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                      side: BorderSide(color: Color(0x22000000)),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: _rows.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text('لا توجد نتائج'),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount:
                                  _rows.length > 12 ? 12 : _rows.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final r = _rows[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                      (r['name'] as String?) ?? ''),
                                  subtitle: Text(
                                    [
                                      if ((r['productCode'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                        r['productCode'].toString(),
                                      if ((r['barcode'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                        r['barcode'].toString(),
                                    ].where((x) => x.isNotEmpty).join(' • '),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant),
                                  ),
                                  onTap: () => unawaited(_pickSuggestion(r)),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: layout.pageHorizontalGap,
                  end: layout.pageHorizontalGap,
                  bottom: 8,
                ),
                child: Text(
                  'في هذه الصفحة: قارئ الباركود (HID) يبحث عن المنتج هنا ولا يُوجَّه للبيع. '
                  'مرّر للأسفل لتحميل المزيد.',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد نتائج لهذا النص بعد.',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : Scrollbar(
                            controller: _scrollCtrl,
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: EdgeInsetsDirectional.fromSTEB(
                                layout.pageHorizontalGap,
                                0,
                                layout.pageHorizontalGap,
                                24,
                              ),
                              itemCount:
                                  _rows.length + (_loadingMore ? 1 : 0),
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
                                  repo: _repo,
                                  row: _rows[i],
                                  draft: draft,
                                  profitBox: ({required buy, required sell}) =>
                                      _profitBox(buy: buy, sell: sell),
                                  onSave: () => _saveRow(id),
                                  saving: _savingProductId == id,
                                  validatePriceLogicFn: validatePriceLogic,
                                  onConflictProductTap: _openConflictProduct,
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope<bool>(
        canPop: !_anyDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final leave = await _ensureCanLeaveIfDirty();
          if (!mounted) return;
          if (leave && context.mounted) {
            _leavingConfirmed = true;
            Navigator.of(context).pop(result);
          }
        },
        child: bodyCore,
      ),
    );
  }
}

class _DraftBaseline {
  const _DraftBaseline({
    required this.name,
    required this.barcode,
    required this.buy,
    required this.sell,
    required this.minSell,
    required this.qty,
    required this.low,
  });

  final String name;
  final String barcode;
  final String buy;
  final String sell;
  final String minSell;
  final String qty;
  final String low;
}

String _formattedMoney(dynamic v) {
  final n = (v as num?)?.toDouble() ?? 0.0;
  return NumericFormat.formatNumber(n.round().clamp(0, 999999999));
}

String _formattedQty(dynamic v) {
  final n = (v as num?)?.toDouble() ?? 0.0;
  return NumericFormat.formatNumber(n.round().clamp(0, 999999999));
}

class _RowDraft {
  _RowDraft(Map<String, dynamic> m)
      : productId = m['id'] as int,
        track = ((m['trackInventory'] as num?)?.toInt() ?? 1) != 0,
        name = TextEditingController(text: (m['name'] as String?) ?? ''),
        barcode = TextEditingController(
            text: ((m['barcode'] as String?) ?? '').toUpperCase()),
        buy = TextEditingController(text: _formattedMoney(m['buy'])),
        sell = TextEditingController(text: _formattedMoney(m['sell'])),
        minSell = TextEditingController(text: _formattedMoney(m['minSell'])),
        qty = TextEditingController(text: _formattedQty(m['qty'])),
        low = TextEditingController(
            text: _formattedQty(m['lowStockThreshold'])),
        nameFn = FocusNode(),
        barcodeFn = FocusNode(),
        buyFn = FocusNode(),
        sellFn = FocusNode(),
        minSellFn = FocusNode(),
        qtyFn = FocusNode(),
        lowFn = FocusNode(),
        saveFn = FocusNode() {
    baseline = _DraftBaseline(
      name: name.text,
      barcode: barcode.text,
      buy: buy.text,
      sell: sell.text,
      minSell: minSell.text,
      qty: qty.text,
      low: low.text,
    );
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

  final FocusNode nameFn;
  final FocusNode barcodeFn;
  final FocusNode buyFn;
  final FocusNode sellFn;
  final FocusNode minSellFn;
  final FocusNode qtyFn;
  final FocusNode lowFn;
  final FocusNode saveFn;

  Timer? barcodeCheck;

  int? duplicateBarcodeProductId;

  late _DraftBaseline baseline;

  bool get isDirty {
    return baseline.name != name.text ||
        baseline.barcode != barcode.text ||
        baseline.buy != buy.text ||
        baseline.sell != sell.text ||
        baseline.minSell != minSell.text ||
        baseline.qty != qty.text ||
        baseline.low != low.text;
  }

  void rebaseline() {
    baseline = _DraftBaseline(
      name: name.text,
      barcode: barcode.text,
      buy: buy.text,
      sell: sell.text,
      minSell: minSell.text,
      qty: qty.text,
      low: low.text,
    );
  }

  void dispose() {
    name.dispose();
    barcode.dispose();
    buy.dispose();
    sell.dispose();
    minSell.dispose();
    qty.dispose();
    low.dispose();
    barcodeCheck?.cancel();
    nameFn.dispose();
    barcodeFn.dispose();
    buyFn.dispose();
    sellFn.dispose();
    minSellFn.dispose();
    qtyFn.dispose();
    lowFn.dispose();
    saveFn.dispose();
  }
}

class _QuickProductCard extends StatefulWidget {
  const _QuickProductCard({
    required this.row,
    required this.draft,
    required this.onSave,
    required this.repo,
    required this.profitBox,
    required this.saving,
    required this.validatePriceLogicFn,
    required this.onConflictProductTap,
  });

  final Map<String, dynamic> row;
  final _RowDraft draft;
  final VoidCallback onSave;
  final ProductRepository repo;
  final Widget Function({required int buy, required int sell}) profitBox;
  final bool saving;
  final PriceLogicWarnings Function({
    required int buyIqd,
    required int sellIqd,
    required int minSellIqdParsed,
  }) validatePriceLogicFn;
  final Future<void> Function(int productId) onConflictProductTap;

  @override
  State<_QuickProductCard> createState() => _QuickProductCardState();
}

class _BarcodeAlnumUpperFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final up = newValue.text.toUpperCase();
    final buf = StringBuffer();
    for (final c in up.runes) {
      final ch = String.fromCharCode(c);
      if (RegExp(r'[A-Z0-9]').hasMatch(ch)) {
        buf.write(ch);
      }
    }
    final s = buf.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}

class _QuickProductCardState extends State<_QuickProductCard> {
  @override
  void initState() {
    super.initState();
    widget.draft.name.addListener(_tick);
    widget.draft.barcode.addListener(_onBarcodeChanged);
    widget.draft.buy.addListener(_tick);
    widget.draft.sell.addListener(_tick);
    widget.draft.minSell.addListener(_tick);
    widget.draft.qty.addListener(_tick);
    widget.draft.low.addListener(_tick);
    widget.draft.nameFn.addListener(_nameFocusTrim);
  }

  void _nameFocusTrim() {
    if (!widget.draft.nameFn.hasFocus) {
      final t = widget.draft.name.text;
      final tr = t.trim();
      if (tr != t) {
        widget.draft.name.value = TextEditingValue(
          text: tr,
          selection: TextSelection.collapsed(offset: tr.length),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.draft.name.removeListener(_tick);
    widget.draft.barcode.removeListener(_onBarcodeChanged);
    widget.draft.buy.removeListener(_tick);
    widget.draft.sell.removeListener(_tick);
    widget.draft.minSell.removeListener(_tick);
    widget.draft.qty.removeListener(_tick);
    widget.draft.low.removeListener(_tick);
    widget.draft.nameFn.removeListener(_nameFocusTrim);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _onBarcodeChanged() {
    widget.draft.barcodeCheck?.cancel();
    widget.draft.barcodeCheck = null;
    final raw = widget.draft.barcode.text.trim().toUpperCase();
    if (raw.isEmpty) {
      setState(() => widget.draft.duplicateBarcodeProductId = null);
      return;
    }
    widget.draft.barcodeCheck =
        Timer(const Duration(milliseconds: 400), () async {
      final id = await widget.repo.findConflictingProductIdForBarcode(
        raw,
        excludeProductId: widget.draft.productId,
      );
      if (!mounted) return;
      setState(() {
        widget.draft.duplicateBarcodeProductId = id;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = widget.draft;
    final cat = (widget.row['categoryName'] as String?)?.trim() ?? '';
    final code = (widget.row['productCode'] as String?)?.trim() ?? '';
    final stockKind = (widget.row['stockBaseKind'] as num?)?.toInt() ?? 0;
    final unitSuffix = stockKind == 1 ? 'كجم' : 'قطعة';

    final buyI = NumericFormat.parseNumber(d.buy.text);
    final sellI = NumericFormat.parseNumber(d.sell.text);
    final minSI = NumericFormat.parseNumber(d.minSell.text);
    final qtyI = NumericFormat.parseNumber(d.qty.text);
    final lowI = NumericFormat.parseNumber(d.low.text);

    final priceWarn = widget.validatePriceLogicFn(
      buyIqd: buyI,
      sellIqd: sellI,
      minSellIqdParsed: minSI,
    );
    final sellWarn = [
      priceWarn.sellVsBuyWarning,
      priceWarn.sellVsMinSellWarning,
    ].whereType<String>().join(' • ').trim();

    String qtyWarn = '';
    if (d.track && qtyI <= 0) {
      qtyWarn = 'المنتج نفذ من المخزون';
    }
    final lowWarn = (d.track && lowI > 0 && qtyI <= lowI && qtyI >= 0)
        ? 'الكمية وصلت لحد التنبيه'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 520;

            Widget nameField() => AppInput(
                  label: 'اسم المنتج',
                  controller: d.name,
                  focusNode: d.nameFn,
                  isRequired: true,
                  maxLines: 1,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(100),
                  ],
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(d.barcodeFn),
                );

            Widget barcodeField() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppInput(
                      label: 'الباركود',
                      controller: d.barcode,
                      focusNode: d.barcodeFn,
                      isOptional: true,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [_BarcodeAlnumUpperFormatter()],
                      onChanged: (_) => setState(() {}),
                      warningText:
                          d.duplicateBarcodeProductId != null
                              ? 'الباركود مستخدم مسبقاً'
                              : null,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(d.buyFn),
                    ),
                    if (d.duplicateBarcodeProductId != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () =>
                              unawaited(widget.onConflictProductTap(
                                  d.duplicateBarcodeProductId!)),
                          child: const Text(
                            'عرض المنتج الذي يملك هذا الباركود',
                          ),
                        ),
                      ),
                  ],
                );

            Widget priceRowWide() => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppPriceInput(
                        label: 'سعر الشراء',
                        controller: d.buy,
                        focusNode: d.buyFn,
                        isRequired: true,
                        textInputAction: TextInputAction.next,
                        onParsedChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(d.sellFn),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppPriceInput(
                        label: 'سعر البيع',
                        controller: d.sell,
                        focusNode: d.sellFn,
                        isRequired: true,
                        warningText:
                            sellWarn.isEmpty ? null : sellWarn,
                        textInputAction: TextInputAction.next,
                        onParsedChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(d.minSellFn),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppPriceInput(
                        label: 'أقل سعر بيع',
                        controller: d.minSell,
                        focusNode: d.minSellFn,
                        isOptional: true,
                        textInputAction: TextInputAction.next,
                        onParsedChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(d.qtyFn),
                      ),
                    ),
                  ],
                );

            Widget priceColumn() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPriceInput(
                      label: 'سعر الشراء',
                      controller: d.buy,
                      focusNode: d.buyFn,
                      isRequired: true,
                      textInputAction: TextInputAction.next,
                      onParsedChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(d.sellFn),
                    ),
                    const SizedBox(height: 8),
                    AppPriceInput(
                      label: 'سعر البيع',
                      controller: d.sell,
                      focusNode: d.sellFn,
                      isRequired: true,
                      warningText:
                          sellWarn.isEmpty ? null : sellWarn,
                      textInputAction: TextInputAction.next,
                      onParsedChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(d.minSellFn),
                    ),
                    const SizedBox(height: 8),
                    AppPriceInput(
                      label: 'أقل سعر بيع',
                      controller: d.minSell,
                      focusNode: d.minSellFn,
                      isOptional: true,
                      textInputAction: TextInputAction.next,
                      onParsedChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(d.qtyFn),
                    ),
                  ],
                );

            final qtyRow = narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppNumberInput(
                        label: 'الكمية',
                        suffixText: unitSuffix,
                        controller: d.qty,
                        focusNode: d.qtyFn,
                        isRequired: true,
                        warningText:
                            qtyWarn.isEmpty ? null : qtyWarn,
                        textInputAction: TextInputAction.next,
                        enabled: d.track,
                        onParsedChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(d.lowFn),
                      ),
                      const SizedBox(height: 8),
                      AppNumberInput(
                        label: 'حد التنبيه',
                        controller: d.low,
                        focusNode: d.lowFn,
                        isOptional: true,
                        warningText:
                            lowWarn.isEmpty ? null : lowWarn,
                        textInputAction: TextInputAction.next,
                        enabled: d.track,
                        onParsedChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(d.saveFn),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppNumberInput(
                          label: 'الكمية',
                          suffixText: unitSuffix,
                          controller: d.qty,
                          focusNode: d.qtyFn,
                          isRequired: true,
                          warningText:
                              qtyWarn.isEmpty ? null : qtyWarn,
                          textInputAction: TextInputAction.next,
                          enabled: d.track,
                          onParsedChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(d.lowFn),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppNumberInput(
                          label: 'حد التنبيه',
                          controller: d.low,
                          focusNode: d.lowFn,
                          isOptional: true,
                          warningText:
                              lowWarn.isEmpty ? null : lowWarn,
                          textInputAction: TextInputAction.next,
                          enabled: d.track,
                          onParsedChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(d.saveFn),
                        ),
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'رقم ${widget.row['id']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    if (code.isNotEmpty)
                      Text(
                        code,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                nameField(),
                if (cat.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'التصنيف: $cat',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                barcodeField(),
                const SizedBox(height: 12),
                if (narrow) priceColumn() else priceRowWide(),
                const SizedBox(height: 10),
                widget.profitBox(buy: buyI, sell: sellI),
                const SizedBox(height: 12),
                qtyRow,
                if (!d.track)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'تتبع المخزون معطّل لهذا الصنف — الكمية من قاعدة البيانات تبقى كما هي عند الحفظ.',
                      style:
                          TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Focus(
                    focusNode: d.saveFn,
                    child: FilledButton.icon(
                      onPressed: widget.saving ? null : widget.onSave,
                      icon: widget.saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 20),
                      label: const Text('حفظ'),
                      style: FilledButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.none),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
