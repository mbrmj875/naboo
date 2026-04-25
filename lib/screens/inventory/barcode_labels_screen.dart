import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../../services/product_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/barcode_labels_pdf.dart';

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

  bool _loading = true;
  String? _err;

  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;

  BarcodeLabelSize _size = BarcodeLabelSize.mm50x30;
  bool _showName = true;
  bool _showPrice = true;

  List<Map<String, dynamic>> _allRows = const [];
  List<Map<String, dynamic>> _rows = const [];
  final Map<int, int> _copies = {};

  Future<void> _searchFromDbIfNeeded(String q) async {
    final t = q.trim();
    if (t.isEmpty) return;
    try {
      final tid = TenantContextService.instance.activeTenantId;
      final rows = await _repo.queryProductsForBarcodeLabels(
        tenantId: tid,
        query: t,
        hasBarcodeFilter: 0,
        limit: 500,
      );
      if (!mounted) return;
      if (rows.isEmpty) return;
      // لا نلمس _allRows حتى لا نغيّر “القائمة الأساسية”.
      setState(() => _rows = rows);
    } catch (_) {
      // تجاهل أخطاء البحث الخلفي حتى لا نزعج المستخدم أثناء الكتابة.
    }
  }

  void _applySearchFilter() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _rows = _allRows);
      return;
    }
    final tokens = q.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    bool match(Map<String, dynamic> r) {
      final name = (r['name'] as String?)?.trim().toLowerCase() ?? '';
      final code = (r['productCode'] as String?)?.trim().toLowerCase() ?? '';
      final bc = (r['barcode'] as String?)?.trim().toLowerCase() ?? '';
      final words = name.split(RegExp(r'[\s\-_]+')).where((e) => e.isNotEmpty);
      for (final t in tokens) {
        final nameStarts = words.any((w) => w.startsWith(t));
        final fallbackContains = name.contains(t);
        if (!(nameStarts || fallbackContains || code.contains(t) || bc.contains(t))) {
          return false;
        }
      }
      return true;
    }

    final filtered = _allRows.where(match).toList(growable: false);
    setState(() => _rows = filtered);
    if (filtered.isEmpty) {
      // قد لا تكون النتيجة ضمن أول دفعة محمّلة؛ ابحث في القاعدة بدون “ريست”.
      unawaited(_searchFromDbIfNeeded(q));
    }
  }

  int _smartCopiesForRow(Map<String, dynamic> r) {
    final track = ((r['trackInventory'] as num?)?.toInt() ?? 1) == 1;
    final qty = (r['qty'] as num?)?.toDouble() ?? 0;
    final stockBaseKind = (r['stockBaseKind'] as num?)?.toInt() ?? 0;
    if (!track) return 1;
    if (stockBaseKind == 1) {
      // وزن: الملصق يعرّف المنتج فقط؛ الكمية تتغير. نختار 1 افتراضياً.
      return 1;
    }
    final c = qty.isFinite ? qty.ceil() : 1;
    return c.clamp(1, 200);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final tid = TenantContextService.instance.activeTenantId;
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
        final copies = <int, int>{};
        for (final r in rows) {
          final id = (r['id'] as num?)?.toInt();
          if (id == null) continue;
          copies[id] = _smartCopiesForRow(r);
        }
        if (!mounted) return;
        setState(() {
          _allRows = rows;
          _rows = rows;
          _copies
            ..clear()
            ..addAll(copies);
          _loading = false;
        });
        return;
      }

      // تحميل قاعدة بيانات واحدة؛ البحث يُطبَّق محلياً بدون إعادة تحميل على كل حرف.
      final rows = await _repo.queryProductsForBarcodeLabels(
        tenantId: tid,
        query: '',
        hasBarcodeFilter: 0,
        limit: 5000,
      );

      final copies = <int, int>{};
      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt();
        if (id == null) continue;
        copies[id] = _smartCopiesForRow(r);
      }

      if (!mounted) return;
      setState(() {
        _allRows = rows;
        _rows = rows;
        _copies
          ..clear()
          ..addAll(copies);
        _loading = false;
      });
      // طبّق بحث إن كان هناك نص مكتوب بالفعل (بدون "ريست").
      _applySearchFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (!mounted) return;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        _applySearchFilter();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<BarcodeLabelProduct> _toProducts() {
    final out = <BarcodeLabelProduct>[];
    for (final r in _rows) {
      final id = (r['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      final name = (r['name'] as String?) ?? 'صنف';
      final barcode = (r['barcode'] as String?)?.trim() ?? '';
      if (barcode.isEmpty) continue;
      final sell = (r['sellPrice'] as num?)?.toDouble() ?? 0;
      final stockBaseKind = (r['stockBaseKind'] as num?)?.toInt() ?? 0;
      out.add(
        BarcodeLabelProduct(
          id: id,
          name: name,
          barcode: barcode,
          sellPrice: sell,
          stockBaseKind: stockBaseKind,
        ),
      );
    }
    return out;
  }

  int get _totalLabels {
    final visible = <int>{};
    for (final r in _rows) {
      final id = (r['id'] as num?)?.toInt();
      if (id != null && id > 0) visible.add(id);
    }
    var s = 0;
    for (final e in _copies.entries) {
      if (!visible.contains(e.key)) continue;
      s += e.value.clamp(0, 500);
    }
    return s;
  }

  void _excludeProduct(int productId) {
    setState(() {
      _copies[productId] = 0;
    });
  }

  Future<void> _print() async {
    if (_totalLabels <= 0) return;
    final tid = TenantContextService.instance.activeTenantId;
    final toAssign = <int>[];
    final ids = <int>[];
    for (final r in _rows) {
      final id = (r['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      ids.add(id);
      final bc = (r['barcode'] as String?)?.trim() ?? '';
      final c = (_copies[id] ?? 0).clamp(0, 500);
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
    setState(() => _rows = fresh);
    final products = _toProducts();
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طباعة ملصقات باركود'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            TextButton.icon(
              onPressed: _loading || _totalLabels <= 0 ? null : _print,
              icon: const Icon(Icons.print_rounded),
              label: Text('طباعة ($_totalLabels)'),
              style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(child: Text('تعذر التحميل: $_err'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppShape.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _search,
                                textAlign: TextAlign.right,
                                decoration: InputDecoration(
                                  labelText: 'بحث عن منتج',
                                  hintText: 'اكتب اسم المنتج أو الكود أو الباركود…',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  border: const OutlineInputBorder(
                                    borderRadius: AppShape.none,
                                  ),
                                  isDense: true,
                                  suffixIcon: _search.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'مسح',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () {
                                            _search.clear();
                                            _applySearchFilter();
                                          },
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'نتائج: ${_rows.length} منتج. عند الطباعة: أي منتج بدون باركود سيتم توليد باركود داخلي له تلقائياً.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppShape.none,
                        ),
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
                                      'اختَر المقاس وعدد النسخ لكل منتج.\n'
                                      'منتجات الوزن: نطبع ملصق يعرّف المنتج فقط (الوزن يُدخل عند البيع).',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<BarcodeLabelSize>(
                                value: _size,
                                decoration: const InputDecoration(
                                  labelText: 'مقاس الملصق',
                                  border: OutlineInputBorder(
                                    borderRadius: AppShape.none,
                                  ),
                                  isDense: true,
                                ),
                                items: BarcodeLabelSize.values
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e.labelAr),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _size = v ?? _size),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('إظهار اسم المنتج'),
                                value: _showName,
                                onChanged: (v) => setState(() => _showName = v),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('إظهار السعر'),
                                value: _showPrice,
                                onChanged: (v) =>
                                    setState(() => _showPrice = v),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          for (final r in _rows) {
                                            final id =
                                                (r['id'] as num?)?.toInt();
                                            if (id == null) continue;
                                            _copies[id] = _smartCopiesForRow(r);
                                          }
                                        });
                                      },
                                      child: const Text('اعتماد الكمية الذكية'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          for (final r in _rows) {
                                            final id =
                                                (r['id'] as num?)?.toInt();
                                            if (id == null) continue;
                                            _copies[id] = 1;
                                          }
                                        });
                                      },
                                      child: const Text('اجعل الكل (1)'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'لا توجد منتجات في القائمة الحالية.\n'
                            'ارجع لقائمة المنتجات ثم افتح هذه الشاشة مرة أخرى.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      else
                        ..._rows.map((r) {
                          final id = (r['id'] as num?)?.toInt() ?? 0;
                          final name = (r['name'] as String?)?.trim() ?? 'صنف';
                          final bc = (r['barcode'] as String?)?.trim() ?? '';
                          final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                          final stockBaseKind =
                              (r['stockBaseKind'] as num?)?.toInt() ?? 0;
                          final isWeight = stockBaseKind == 1;
                          final sell = (r['sellPrice'] as num?)?.toDouble() ?? 0;
                          final c = _copies[id] ?? 0;
                          final excluded = c <= 0;
                          final hasBc = bc.isNotEmpty;
                          return Card(
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppShape.none,
                            ),
                            child: ListTile(
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: excluded
                                    ? TextStyle(color: cs.onSurfaceVariant)
                                    : null,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 6),
                                  Text(
                                    'الكمية: ${qty.toStringAsFixed(isWeight ? 2 : 0)}'
                                    '${isWeight ? ' كغم' : ''} — السعر: ${sell.toStringAsFixed(0)} د.ع',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (hasBc) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.35),
                                          border: Border.all(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              SizedBox(
                                                width: 170,
                                                height: 34,
                                                child: BarcodeWidget(
                                                  barcode: Barcode.code128(),
                                                  data: bc,
                                                  drawText: false,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                bc,
                                                textDirection: TextDirection.ltr,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'بدون باركود — سيُولَّد باركود داخلي عند الطباعة (إذا اخترت نسخاً > 0).',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: false,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!excluded)
                                    IconButton(
                                      tooltip: 'استثناء من الطباعة',
                                      onPressed: () => _excludeProduct(id),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                      ),
                                    )
                                  else
                                    IconButton(
                                      tooltip: 'إرجاع للطباعة',
                                      onPressed: () => setState(() {
                                        _copies[id] = 1;
                                      }),
                                      icon: const Icon(Icons.undo_rounded),
                                    ),
                                  IconButton(
                                    tooltip: 'نقص',
                                    onPressed: excluded
                                        ? null
                                        : () => setState(() {
                                      _copies[id] = math.max(0, c - 1);
                                    }),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '$c',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'زيادة',
                                    onPressed: excluded
                                        ? null
                                        : () => setState(() {
                                      _copies[id] = math.min(500, c + 1);
                                    }),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
      ),
    );
  }
}

