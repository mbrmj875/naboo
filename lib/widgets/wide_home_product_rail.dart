import 'dart:async' show Timer, unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/product_repository.dart';
import '../services/product_variants_repository.dart';
import '../utils/iraqi_currency_format.dart';

const _kSalePinnedGridHeightPref = 'sale_wide_pinned_grid_height_v1';
const _kPinnedQuickGroupsPref = 'dashboard_pinned_quick_groups_v1';
const _kSalePinsPrefKey = 'sale_wide_rail_pins_v1';

class _PinnedQuickGroup {
  const _PinnedQuickGroup({
    required this.isCategory,
    required this.id,
    required this.label,
  });

  final bool isCategory;
  final int id;
  final String label;

  String get key => isCategory ? 'c_$id' : 'b_$id';

  Map<String, dynamic> toMap() => {
        'c': isCategory ? 1 : 0,
        'i': id,
        'l': label,
      };

  static _PinnedQuickGroup? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final isCat = (m['c'] as num?)?.toInt() == 1;
    final id = (m['i'] as num?)?.toInt();
    final l = (m['l'] as String?)?.trim();
    if (id == null || l == null || l.isEmpty) return null;
    return _PinnedQuickGroup(isCategory: isCat, id: id, label: l);
  }
}

/// عمود منتجات على يمين/يسار الشاشة العريضة (ليس الهاتف):
/// أعلى: نفس «منتجات مثبّتة» الشاشة الرئيسية (قاعدة البيانات).
/// أسفل: «كل المنتجات» مع تثبيت محلي للترتيب داخل القائمة فقط.
class WideHomeProductRail extends StatefulWidget {
  const WideHomeProductRail({
    super.key,
    required this.searchQuery,
    required this.isDark,
    required this.onProductPick,
  });

  /// نص البحث العلوي (صغير) لمزامنة تصفية القائمة.
  final String searchQuery;
  final bool isDark;

  /// إضافة أو دمج سطر: [addQuantity] كمية لإضافتها (&gt; 0) — عادة 1 من النقر؛ من حوار الضغط المطوّل أوامر أخرى.
  final void Function(
    Map<String, dynamic> product, {
    required double addQuantity,
  }) onProductPick;

  @override
  State<WideHomeProductRail> createState() => _WideHomeProductRailState();
}

class _WideHomeProductRailState extends State<WideHomeProductRail> {
  final _repo = ProductRepository();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _pinnedRows = [];
  List<int> _pinnedIds = [];
  bool _loading = true;
  final Map<int, int> _variantStockSumByProductId = {};
  final Set<int> _variantStockLoading = {};
  Timer? _debounce;
  double _pinnedGridHeight = 240;
  int _group = 0; // 0 الكل | 1 بالقطعة | 2 بالوزن
  List<_PinnedQuickGroup> _quickGroups = const [];
  String? _activeQuickKey;
  VoidCallback? _pinnedListener;
  int? _flashProductId;

  @override
  void initState() {
    super.initState();
    _pinnedListener = () => _scheduleLoad();
    ProductRepository.pinnedVersion.addListener(_pinnedListener!);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _restorePinnedGridHeight();
    await _restoreQuickGroups();
    await _restoreSalePins();
    if (mounted) await _load();
  }

  @override
  void didUpdateWidget(covariant WideHomeProductRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final l = _pinnedListener;
    if (l != null) {
      ProductRepository.pinnedVersion.removeListener(l);
    }
    super.dispose();
  }

  Future<void> _restorePinnedGridHeight() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_kSalePinnedGridHeightPref);
    if (v == null || !v.isFinite) return;
    _pinnedGridHeight = v.clamp(160, 520);
  }

  Future<void> _persistPinnedGridHeight() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kSalePinnedGridHeightPref, _pinnedGridHeight);
  }

  Future<void> _restoreSalePins() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSalePinsPrefKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _pinnedIds = list.map((e) => (e as num).toInt()).toList();
    } catch (_) {}
  }

  Future<void> _persistSalePins() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSalePinsPrefKey, jsonEncode(_pinnedIds));
  }

  Future<void> _restoreQuickGroups() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPinnedQuickGroupsPref);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final out = <_PinnedQuickGroup>[];
      for (final e in decoded) {
        final g = _PinnedQuickGroup.fromMap(e);
        if (g != null) out.add(g);
      }
      _quickGroups = out;
    } catch (_) {}
  }

  Future<void> _openCreateQuickGroup() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('مجموعة حسب التصنيف'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAndActivateCategoryGroup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: const Text('مجموعة حسب الماركة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAndActivateBrandGroup();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndActivateCategoryGroup() async {
    final rows = await _repo.listCategoriesForSettings();
    if (!mounted) return;
    if (rows.isEmpty) return;
    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('اختر تصنيفاً'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final name = (r['name'] as String?)?.trim() ?? 'تصنيف';
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );
    if (!mounted || picked == null) return;
    final id = (picked['id'] as num?)?.toInt();
    final name = (picked['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return;
    final g = _PinnedQuickGroup(isCategory: true, id: id, label: name);
    if (_quickGroups.every((e) => e.key != g.key)) {
      setState(() => _quickGroups = [..._quickGroups, g]);
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kPinnedQuickGroupsPref,
        jsonEncode(_quickGroups.map((e) => e.toMap()).toList()),
      );
    }
    setState(() => _activeQuickKey = g.key);
  }

  Future<void> _pickAndActivateBrandGroup() async {
    final rows = await _repo.listBrandsForSettings();
    if (!mounted) return;
    if (rows.isEmpty) return;
    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('اختر ماركة'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final name = (r['name'] as String?)?.trim() ?? 'ماركة';
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );
    if (!mounted || picked == null) return;
    final id = (picked['id'] as num?)?.toInt();
    final name = (picked['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return;
    final g = _PinnedQuickGroup(isCategory: false, id: id, label: name);
    if (_quickGroups.every((e) => e.key != g.key)) {
      setState(() => _quickGroups = [..._quickGroups, g]);
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kPinnedQuickGroupsPref,
        jsonEncode(_quickGroups.map((e) => e.toMap()).toList()),
      );
    }
    setState(() => _activeQuickKey = g.key);
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _load);
  }

  void _triggerProductFlash(int productId) {
    setState(() => _flashProductId = productId);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        if (_flashProductId == productId) _flashProductId = null;
      });
    });
  }

  Future<void> _promptAddQuantity(
    Map<String, dynamic> p,
    void Function(double q) onChosen,
  ) async {
    final isWeight = ((p['stockBaseKind'] as num?)?.toInt() ?? 0) == 1;
    final ctrl = TextEditingController(text: '1');
    bool? ok;
    try {
      ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('الكمية'),
              content: TextField(
                controller: ctrl,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: isWeight,
                  signed: false,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isWeight ? 'كمية (كغ)' : 'كمية',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('إضافة'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      ctrl.dispose();
    }
    if (ok != true || !mounted) return;
    final raw = ctrl.text.trim().replaceAll(',', '');
    final v =
        isWeight ? (double.tryParse(raw) ?? 0) : (int.tryParse(raw) ?? 0).toDouble();
    if (v <= 0) return;
    onChosen(v);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final q = widget.searchQuery.trim();
      final pins = await _repo.listPinnedProductsForQuickPick(limit: 200);

      List<Map<String, dynamic>> raw;
      if (q.isEmpty) {
        raw = await _repo.listActiveProductsForQuickPick(limit: 500);
      } else {
        raw = await _repo.searchProducts(q, limit: 120);
      }
      if (!mounted) return;
      final sorted = _sortRows(raw, q);
      setState(() {
        _rows = sorted;
        _pinnedRows = pins;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// داخل «كل المنتجات» فقط: العناصر المعلّمة محلياً أولاً، ثم الأقرب للنص.
  List<Map<String, dynamic>> _sortRows(List<Map<String, dynamic>> raw, String q) {
    final ql = q.trim().toLowerCase();

    int relevance(Map<String, dynamic> m) {
      if (ql.isEmpty) return 99;
      final name = (m['name'] ?? '').toString().toLowerCase();
      final code = (m['productCode'] ?? '').toString().toLowerCase();
      if (name.startsWith(ql)) return 0;
      if (code.startsWith(ql)) return 1;
      if (name.contains(ql)) return 2;
      return 3;
    }

    final byId = <int, Map<String, dynamic>>{
      for (final m in raw) (m['id'] as int): m,
    };

    final pinned = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final id in _pinnedIds) {
      final row = byId[id];
      if (row != null) {
        pinned.add(row);
        seen.add(id);
      }
    }

    final rest = <Map<String, dynamic>>[];
    for (final m in raw) {
      final id = m['id'] as int;
      if (seen.contains(id)) continue;
      rest.add(m);
    }

    rest.sort((a, b) {
      final ra = relevance(a);
      final rb = relevance(b);
      if (ra != rb) return ra.compareTo(rb);
      final na = (a['name'] ?? '').toString();
      final nb = (b['name'] ?? '').toString();
      return na.toLowerCase().compareTo(nb.toLowerCase());
    });

    return [...pinned, ...rest];
  }

  void _togglePinnedLocal(int id) {
    setState(() {
      if (_pinnedIds.contains(id)) {
        _pinnedIds.remove(id);
      } else {
        _pinnedIds.insert(0, id);
      }
    });
    unawaited(_persistSalePins());
    unawaited(_load());
  }

  void _ensureVariantStockSum(int productId) {
    if (productId <= 0) return;
    if (_variantStockSumByProductId.containsKey(productId)) return;
    if (_variantStockLoading.contains(productId)) return;
    _variantStockLoading.add(productId);
    unawaited(() async {
      try {
        final vars =
            await ProductVariantsRepository.instance.getVariantsForProduct(productId);
        final sum = vars.fold<int>(
          0,
          (s, r) => s + ((r['quantity'] as num?)?.toInt() ?? 0),
        );
        if (!mounted) return;
        setState(() => _variantStockSumByProductId[productId] = sum);
      } catch (_) {
        if (!mounted) return;
        setState(() => _variantStockSumByProductId[productId] = 0);
      } finally {
        _variantStockLoading.remove(productId);
      }
    }());
  }

  static String _stockLine(Map<String, dynamic> p) {
    final track = (p['trackInventory'] as int?) != 0;
    if (!track) return 'غير متتبّع';
    final q = p['qty'];
    if (q == null) return '—';
    final n = (q as num).toDouble();
    if (n < 0) return '—';
    if (n.abs() < 1e-9) return '0';
    final s = (n % 1).abs() < 1e-6
        ? IraqiCurrencyFormat.formatInt(n)
        : IraqiCurrencyFormat.formatDecimal2(n);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final border = widget.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final text1 = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final text2 = widget.isDark ? Colors.white60 : const Color(0xFF64748B);

    _PinnedQuickGroup? activeQuick;
    if (_activeQuickKey != null) {
      for (final q in _quickGroups) {
        if (q.key == _activeQuickKey) {
          activeQuick = q;
          break;
        }
      }
    }

    final pinnedFiltered = _pinnedRows.where((p) {
      final k = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
      if (_group == 1 && k != 0) return false;
      if (_group == 2 && k != 1) return false;
      final g = activeQuick;
      if (g != null) {
        if (g.isCategory) {
          final cid = (p['categoryId'] as num?)?.toInt();
          if (cid != g.id) return false;
        } else {
          final bid = (p['brandId'] as num?)?.toInt();
          if (bid != g.id) return false;
        }
      }
      return true;
    }).toList(growable: false);

    Widget pinnedCard(Map<String, dynamic> p) {
      final name = (p['name'] as String?)?.trim() ?? 'منتج';
      final sellRaw = p['sell'] as num?;
      final sell = sellRaw != null ? sellRaw.toDouble() : 0.0;
      final pid = (p['id'] as num?)?.toInt();
      final flashing = pid != null && _flashProductId == pid;
      final isService = ((p['isService'] as num?)?.toInt() ?? 0) == 1;
      final track = (p['trackInventory'] as int?) != 0;
      final rawQty = ((p['qty'] as num?)?.toDouble() ?? 0);
      // الملابس لا تستخدم products.qty؛ إذا كانت 0/سالبة نعرض مجموع مخزون الـ variants.
      final needsVariantFix = track && pid != null && rawQty <= 0;
      if (needsVariantFix) _ensureVariantStockSum(pid);
      final variantSum = (pid == null) ? null : _variantStockSumByProductId[pid];
      final effectiveQty = needsVariantFix && variantSum != null
          ? variantSum.toDouble()
          : rawQty;
      final stock = needsVariantFix && variantSum != null
          ? IraqiCurrencyFormat.formatInt(effectiveQty)
          : _stockLine(p);
      final outOfStock = track && effectiveQty <= 0;
      final border2 = widget.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);
      final textMuted = widget.isDark ? Colors.white60 : const Color(0xFF64748B);
      final stockColor = (p['trackInventory'] as int?) == 0
          ? textMuted
          : effectiveQty <= 0
              ? const Color(0xFFEF4444)
              : (effectiveQty < 5
                  ? const Color(0xFFF59E0B)
                  : textMuted);

      void pickOne() {
        if (pid != null) _triggerProductFlash(pid);
        widget.onProductPick(p, addQuantity: 1);
      }

      Widget card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: pickOne,
          onLongPress: () async {
            await _promptAddQuantity(p, (q) {
              if (pid != null) _triggerProductFlash(pid);
              widget.onProductPick(p, addQuantity: q);
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                width: flashing ? 2 : 1,
                color: flashing
                    ? const Color(0xFF22C55E)
                    : border2,
              ),
              color: widget.isDark
                  ? Colors.white.withValues(alpha: outOfStock ? 0.02 : 0.04)
                  : (outOfStock
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF1F5F9),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(12)),
                          border: Border.all(color: border2),
                        ),
                        child: const Center(
                          child: Icon(Icons.inventory_2_outlined, size: 34),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: text1,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              IraqiCurrencyFormat.formatIqd(sell),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: widget.isDark
                                    ? Colors.white70
                                    : const Color(0xFF0D9488),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: isService
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: widget.isDark
                                              ? const Color(0xFF0F172A)
                                                  .withValues(alpha: 0.55)
                                              : const Color(0xFF2563EB)
                                                  .withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: widget.isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : const Color(0xFF2563EB)
                                                    .withValues(alpha: 0.22),
                                          ),
                                        ),
                                        child: Text(
                                          'خدمة فنية',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: widget.isDark
                                                ? Colors.white70
                                                : const Color(0xFF1D4ED8),
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'الكمية المتاحة: $stock',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: stockColor,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (outOfStock)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'نفذ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (outOfStock) {
        card = Opacity(opacity: 0.62, child: card);
      }
      return card;
    }

    return Material(
      color: bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(color: border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: text2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'منتجات مثبّتة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: text1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(start: 10, end: 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _group == 0,
                    onSelected: (_) => setState(() => _group = 0),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('بالقطعة'),
                    selected: _group == 1,
                    onSelected: (_) => setState(() => _group = 1),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('بالوزن'),
                    selected: _group == 2,
                    onSelected: (_) => setState(() => _group = 2),
                  ),
                  for (final g in _quickGroups) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(g.label),
                      selected: _activeQuickKey == g.key,
                      onSelected: (_) => setState(() {
                        _activeQuickKey =
                            (_activeQuickKey == g.key) ? null : g.key;
                      }),
                    ),
                  ],
                  IconButton(
                    tooltip: 'إضافة مجموعة',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      size: 22,
                      color: text2,
                    ),
                    onPressed: _openCreateQuickGroup,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SizedBox(
                height: _pinnedGridHeight,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final crossAxisCount = c.maxWidth >= 260 ? 2 : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: pinnedFiltered.length,
                      itemBuilder: (_, i) => pinnedCard(pinnedFiltered[i]),
                    );
                  },
                ),
              ),
            ),
            Tooltip(
              message: 'اسحب لتغيير حجم المثبّتات',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _pinnedGridHeight =
                          (_pinnedGridHeight + d.delta.dy).clamp(160, 520);
                    });
                  },
                  onPanEnd: (_) => unawaited(_persistPinnedGridHeight()),
                  child: SizedBox(
                    height: 12,
                    child: Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: border.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  Icon(Icons.list_alt_rounded, size: 18, color: text2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'كل المنتجات',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: text1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.searchQuery.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Text(
                  'تصفية: «${widget.searchQuery.trim()}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: text2),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              widget.searchQuery.trim().isEmpty
                                  ? 'لا توجد أصناف'
                                  : 'لا نتائج مطابقة',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: text2, fontSize: 12),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                          itemCount: _rows.length,
                          itemBuilder: (context, i) {
                            final p = _rows[i];
                            final pid = p['id'] as int;
                            final pinned = _pinnedIds.contains(pid);
                            final isService =
                                ((p['isService'] as num?)?.toInt() ?? 0) == 1;
                            final sellRaw = p['sell'] as num?;
                            final sellDisp = sellRaw != null
                                ? IraqiCurrencyFormat.formatIqd(sellRaw)
                                : '—';
                            final flashing = _flashProductId == pid;
                            final track = (p['trackInventory'] as int?) != 0;
                            final rawQty = ((p['qty'] as num?)?.toDouble() ?? 0);
                            final needsVariantFix = track && rawQty <= 0;
                            if (needsVariantFix) _ensureVariantStockSum(pid);
                            final variantSum = _variantStockSumByProductId[pid];
                            final effectiveQty = needsVariantFix && variantSum != null
                                ? variantSum.toDouble()
                                : rawQty;
                            final outOfStock = track && effectiveQty <= 0;
                            final stock = needsVariantFix && variantSum != null
                                ? IraqiCurrencyFormat.formatInt(effectiveQty)
                                : _stockLine(p);
                            final cardBg = widget.isDark
                                ? const Color(0xFF334155)
                                    .withValues(alpha: 0.35)
                                : Colors.white;
                            final cardBorder = flashing
                                ? const Color(0xFF22C55E)
                                : (widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.08));

                            void pickOne() {
                              _triggerProductFlash(pid);
                              widget.onProductPick(p, addQuantity: 1);
                            }

                            Widget row = Material(
                              color: outOfStock
                                  ? cardBg.withValues(alpha: 0.72)
                                  : cardBg,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: cardBorder,
                                  width: flashing ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: pickOne,
                                onLongPress: () async {
                                  await _promptAddQuantity(p, (q) {
                                    _triggerProductFlash(pid);
                                    widget.onProductPick(p, addQuantity: q);
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8,
                                    end: 4,
                                    top: 8,
                                    bottom: 8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${p['name'] ?? ''}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.start,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: text1,
                                                height: 1.15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              sellDisp,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: text1,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            if (isService)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: widget.isDark
                                                      ? const Color(0xFF0F172A)
                                                          .withValues(
                                                            alpha: 0.52,
                                                          )
                                                      : const Color(0xFF2563EB)
                                                          .withValues(
                                                            alpha: 0.10,
                                                          ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    999,
                                                  ),
                                                  border: Border.all(
                                                    color: widget.isDark
                                                        ? Colors.white
                                                            .withValues(
                                                              alpha: 0.12,
                                                            )
                                                        : const Color(
                                                            0xFF2563EB,
                                                          ).withValues(
                                                            alpha: 0.22,
                                                          ),
                                                  ),
                                                ),
                                                child: Text(
                                                  'خدمة فنية',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: widget.isDark
                                                        ? Colors.white70
                                                        : const Color(
                                                            0xFF1D4ED8,
                                                          ),
                                                  ),
                                                ),
                                              )
                                            else
                                              Text(
                                                'الكمية المتاحة: $stock',
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: text2,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 36,
                                        child: IconButton(
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          tooltip: pinned
                                              ? 'إلغاء التثبيت من أعلى «كل المنتجات» فقط'
                                              : 'تثبيت أعلى «كل المنتجات» فقط (لا يغيّر تثبيت الشاشة الرئيسية)',
                                          onPressed: () => _togglePinnedLocal(
                                            pid,
                                          ),
                                          icon: Icon(
                                            pinned
                                                ? Icons.push_pin_rounded
                                                : Icons.push_pin_outlined,
                                            size: 22,
                                            color: pinned
                                                ? const Color(0xFF0D9488)
                                                : text2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            row = Stack(
                              clipBehavior: Clip.none,
                              children: [
                                row,
                                if (outOfStock)
                                  PositionedDirectional(
                                    top: 4,
                                    end: 40,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'نفذ',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: row,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
