import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/global_barcode_route_bridge.dart';
import '../../providers/theme_provider.dart';
import '../../providers/inventory_products_provider.dart';
import '../../services/product_repository.dart';
import '../../utils/numeric_format.dart';
import '../../utils/screen_layout.dart';
import 'add_product_screen.dart';
import 'barcode_labels_screen.dart';
import 'inventory_settings_screen.dart';
import 'product_edit_screen.dart';

final class _AddProductShortcut extends Intent {
  const _AddProductShortcut();
}

final class _FocusSearchShortcut extends Intent {
  const _FocusSearchShortcut();
}

final class _DismissShortcut extends Intent {
  const _DismissShortcut();
}

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF10B981);
const _kGreenBg = Color(0xFFD1FAE5);
const _kOrange = Color(0xFFF97316);
const _kOrangeBg = Color(0xFFFFEDD5);
const _kBlue = Color(0xFF3B82F6);
const _kNavy = Color(0xFF1E3A5F);
const _kBg = Color(0xFFF1F5F9);
const _kCard = Colors.white;
const _kBorder = Color(0xFFE2E8F0);
const _kText1 = Color(0xFF0F172A);
const _kText2 = Color(0xFF64748B);
const _kText3 = Color(0xFF94A3B8);

// ═════════════════════════════════════════════════════════════════════════════
class InventoryProductsScreen extends StatefulWidget {
  const InventoryProductsScreen({super.key});
  @override
  State<InventoryProductsScreen> createState() =>
      _InventoryProductsScreenState();
}

class _InventoryProductsScreenState extends State<InventoryProductsScreen>
    with SingleTickerProviderStateMixin {
  final _keyword = TextEditingController();
  final _barcode = TextEditingController();
  final _prodCode = TextEditingController();
  final _priceFrom = TextEditingController();
  final _priceTo = TextEditingController();
  final _keywordFn = FocusNode();

  Timer? _keywordDebounce;
  Timer? _barcodeDebounce;
  GlobalBarcodeRouteBridge? _barcodeBridge;

  // filter state
  String _category = 'جميع التصنيفات';
  String _brand = 'جميع الماركات';
  String _status = 'الكل';
  String _sortBy = 'الاسم';
  bool _sortAscending = true;
  bool _advanced = false;

  List<String> _categoryItems = const ['جميع التصنيفات'];
  List<String> _brandItems = const ['جميع الماركات'];

  final ProductRepository _productRepo = ProductRepository();

  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  Future<void> _loadCategoryBrandOptions() async {
    try {
      final cats = await _productRepo.listCategoriesForSettings();
      final brs = await _productRepo.listBrandsForSettings();
      if (!mounted) return;
      setState(() {
        _categoryItems = [
          'جميع التصنيفات',
          ...cats
              .map((r) => '${r['name'] ?? ''}'.trim())
              .where((e) => e.isNotEmpty),
        ];
        _brandItems = [
          'جميع الماركات',
          ...brs
              .map((r) => '${r['name'] ?? ''}'.trim())
              .where((e) => e.isNotEmpty),
        ];
        if (!_categoryItems.contains(_category)) {
          _category = 'جميع التصنيفات';
        }
        if (!_brandItems.contains(_brand)) {
          _brand = 'جميع الماركات';
        }
      });
    } catch (_) {
      /* keep defaults */
    }
  }

  void _pushFiltersToProvider() {
    if (!mounted) return;
    final prov = context.read<InventoryProductsProvider>();
    final pMin = _parsePriceIqdOptional(_priceFrom);
    final pMax = _parsePriceIqdOptional(_priceTo);
    unawaited(
      prov.setFilters(
        keyword: _keyword.text,
        barcode: _barcode.text,
        productCode: _prodCode.text,
        categoryName: _category,
        brandName: _brand,
        status: _status,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
        priceMinIqd: _advanced ? pMin : null,
        priceMaxIqd: _advanced ? pMax : null,
      ),
    );
  }

  int? _parsePriceIqdOptional(TextEditingController c) {
    final t = c.text.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0) return null;
    return v;
  }

  void _scheduleKeywordDebounced() {
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _pushFiltersToProvider();
    });
  }

  void _scheduleBarcodeDebounced() {
    _barcodeDebounce?.cancel();
    _barcodeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _pushFiltersToProvider();
    });
  }

  void _applyKeywordImmediateFromEnter() {
    _keywordDebounce?.cancel();
    _pushFiltersToProvider();
  }

  void _applyBarcodeImmediateFromScan() {
    _barcodeDebounce?.cancel();
    _pushFiltersToProvider();
  }

  int _activeFilterCount() {
    int n = 0;
    if (_keyword.text.trim().isNotEmpty) n++;
    if (_barcode.text.trim().isNotEmpty) n++;
    if (_advanced && _prodCode.text.trim().isNotEmpty) n++;
    if (_advanced &&
        (_parsePriceIqdOptional(_priceFrom) != null ||
            _parsePriceIqdOptional(_priceTo) != null)) {
      n++;
    }
    if (_category != 'جميع التصنيفات') n++;
    if (_brand != 'جميع الماركات') n++;
    if (_status != 'الكل') n++;
    return n;
  }

  bool get _hasAnyFilter => _activeFilterCount() > 0;

  Future<bool> _onGlobalBarcode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return false;
    if (!mounted) return true;
    _barcode.text = code;
    _applyBarcodeImmediateFromScan();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keywordFn.requestFocus();
      final bridge = context.read<GlobalBarcodeRouteBridge>();
      _barcodeBridge = bridge;
      bridge.setBarcodePriorityHandler(this, _onGlobalBarcode);
    });
    unawaited(_loadCategoryBrandOptions());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        context.read<InventoryProductsProvider>().refresh(seedIfEmpty: true),
      );
    });
    _barcode.addListener(_scheduleBarcodeDebounced);
    _prodCode.addListener(() {
      if (_advanced) _pushFiltersToProvider();
    });
    _priceFrom.addListener(() {
      if (_advanced) _pushFiltersToProvider();
    });
    _priceTo.addListener(() {
      if (_advanced) _pushFiltersToProvider();
    });
  }

  @override
  void dispose() {
    _keywordDebounce?.cancel();
    _barcodeDebounce?.cancel();
    _animCtrl.dispose();
    _keyword.dispose();
    _barcode.dispose();
    _prodCode.dispose();
    _priceFrom.dispose();
    _priceTo.dispose();
    _keywordFn.dispose();
    _barcodeBridge?.clearBarcodePriorityHandler(this);
    super.dispose();
  }

  void _toggleAdvanced() {
    setState(() => _advanced = !_advanced);
    _advanced ? _animCtrl.forward() : _animCtrl.reverse();
    if (_advanced) {
      _pushFiltersToProvider();
    }
  }

  void _clearFilters() {
    _keywordDebounce?.cancel();
    _barcodeDebounce?.cancel();
    setState(() {
      _keyword.clear();
      _barcode.clear();
      _prodCode.clear();
      _priceFrom.clear();
      _priceTo.clear();
      _category = 'جميع التصنيفات';
      _brand = 'جميع الماركات';
      _status = 'الكل';
    });
    _pushFiltersToProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keywordFn.requestFocus();
    });
  }

  bool get _isDark =>
      Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

  @override
  Widget build(BuildContext context) {
    final layout = context.screenLayout;
    final bg = _isDark ? const Color(0xFF0F172A) : _kBg;
    final surface = _isDark ? const Color(0xFF1E293B) : _kCard;
    final text1 = _isDark ? Colors.white : _kText1;
    final text2 = _isDark ? Colors.white60 : _kText2;
    final border = _isDark ? Colors.white12 : _kBorder;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: _kNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'إدارة المنتجات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 22),
              tooltip: 'الإعدادات',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventorySettingsScreen(),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (v) async {
                if (v == 'print_barcodes') {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BarcodeLabelsScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'print_barcodes',
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('طباعة ملصقات باركود'),
                    ],
                  ),
                ),
              ],
            ),
            if (!layout.isNarrowWidth) const SizedBox(width: 4),
            if (!layout.isNarrowWidth)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final products = context.read<InventoryProductsProvider>();
                    final messenger = ScaffoldMessenger.of(context);
                    final saved = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddProductScreen(),
                      ),
                    );
                    if (!mounted) return;
                    if (saved == true) {
                      await products.refresh();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('تم حفظ المنتج وتحديث القائمة'),
                          backgroundColor: _kGreen,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    '+ منتج جديد',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    elevation: 0,
                  ),
                ),
              ),
          ],
        ),
        body: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyN, control: true):
                _AddProductShortcut(),
            SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _FocusSearchShortcut(),
            SingleActivator(LogicalKeyboardKey.escape): _DismissShortcut(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _AddProductShortcut: CallbackAction<_AddProductShortcut>(
                onInvoke: (_) {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const AddProductScreen()),
                  );
                  return null;
                },
              ),
              _FocusSearchShortcut: CallbackAction<_FocusSearchShortcut>(
                onInvoke: (_) {
                  _keywordFn.requestFocus();
                  return null;
                },
              ),
              _DismissShortcut: CallbackAction<_DismissShortcut>(
                onInvoke: (_) {
                  if (_keyword.text.isNotEmpty) {
                    _keyword.clear();
                  } else {
                    _barcode.clear();
                  }
                  _keywordDebounce?.cancel();
                  _barcodeDebounce?.cancel();
                  _pushFiltersToProvider();
                  FocusManager.instance.primaryFocus?.unfocus();
                  return null;
                },
              ),
            },
            child: Consumer<InventoryProductsProvider>(
              builder: (context, provider, _) {
                final filtered = provider.items;
                final matched = provider.matchedTotal;
                final catalogTotal = provider.catalogTotal;
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (!provider.hasMore) return false;
                    if (provider.isLoadingMore) return false;
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 420) {
                      unawaited(provider.loadMore());
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _SearchCard(
                          keyword: _keyword,
                          keywordFn: _keywordFn,
                          barcode: _barcode,
                          prodCode: _prodCode,
                          priceFrom: _priceFrom,
                          priceTo: _priceTo,
                          category: _category,
                          brand: _brand,
                          categoryItems: _categoryItems,
                          brandItems: _brandItems,
                          status: _status,
                          advanced: _advanced,
                          expandAnim: _expandAnim,
                          surface: surface,
                          text1: text1,
                          text2: text2,
                          border: border,
                          isDark: _isDark,
                          keywordSearching: provider.isLoading,
                          showClearFiltersChip: _hasAnyFilter,
                          activeFiltersCount: _activeFilterCount(),
                          onKeywordChanged: () {
                            if (mounted) setState(() {});
                            _scheduleKeywordDebounced();
                          },
                          onKeywordSubmitImmediate:
                              _applyKeywordImmediateFromEnter,
                          onCategoryChanged: (v) {
                            setState(() => _category = v);
                            _pushFiltersToProvider();
                          },
                          onBrandChanged: (v) {
                            setState(() => _brand = v);
                            _pushFiltersToProvider();
                          },
                          onStatusChanged: (v) {
                            setState(() => _status = v);
                            _pushFiltersToProvider();
                          },
                          onSearch: _advanced ? _pushFiltersToProvider : () {},
                          onClear: _clearFilters,
                          onToggleAdvanced: _toggleAdvanced,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _ResultsHeader(
                          shownCount: filtered.length,
                          matchedTotal: matched,
                          catalogTotal: catalogTotal,
                          sortBy: _sortBy,
                          sortAscending: _sortAscending,
                          surface: surface,
                          text1: text1,
                          text2: text2,
                          border: border,
                          isDark: _isDark,
                          onSortChanged: (v) {
                            setState(() => _sortBy = v);
                            _pushFiltersToProvider();
                          },
                          onSortDirectionToggle: () {
                            setState(() => _sortAscending = !_sortAscending);
                            _pushFiltersToProvider();
                          },
                        ),
                      ),
                      if (filtered.isEmpty && provider.isLoading)
                        SliverPadding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            layout.pageHorizontalGap,
                            10,
                            layout.pageHorizontalGap,
                            24,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ProductSkeletonTile(
                                  surface: surface,
                                  border: border,
                                  text2: text2,
                                ),
                              ),
                              childCount: 6,
                            ),
                          ),
                        )
                      else if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _ProductsEmptyBlock(
                            isDark: _isDark,
                            catalogTotal: catalogTotal,
                            matchedTotal: matched,
                            onClearFilters: _clearFilters,
                            onAddFirst: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AddProductScreen(),
                                ),
                              );
                            },
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            layout.pageHorizontalGap,
                            10,
                            layout.pageHorizontalGap,
                            80,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                if (i >= filtered.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ProductRow(
                                    product: filtered[i],
                                    surface: surface,
                                    text1: text1,
                                    text2: text2,
                                    border: border,
                                    isDark: _isDark,
                                  ),
                                );
                              },
                              childCount:
                                  filtered.length +
                                  (provider.isLoadingMore ? 1 : 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH CARD
// ══════════════════════════════════════════════════════════════════════════════
class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.keyword,
    required this.keywordFn,
    required this.barcode,
    required this.prodCode,
    required this.priceFrom,
    required this.priceTo,
    required this.category,
    required this.brand,
    required this.categoryItems,
    required this.brandItems,
    required this.status,
    required this.advanced,
    required this.keywordSearching,
    required this.showClearFiltersChip,
    required this.activeFiltersCount,
    required this.expandAnim,
    required this.surface,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
    required this.onKeywordChanged,
    required this.onKeywordSubmitImmediate,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onStatusChanged,
    required this.onSearch,
    required this.onClear,
    required this.onToggleAdvanced,
  });

  final TextEditingController keyword;
  final FocusNode keywordFn;
  final TextEditingController barcode;
  final TextEditingController prodCode;
  final TextEditingController priceFrom;
  final TextEditingController priceTo;
  final List<String> categoryItems;
  final List<String> brandItems;
  final String category;
  final String brand;
  final String status;
  final bool advanced;
  final bool keywordSearching;
  final bool showClearFiltersChip;
  final int activeFiltersCount;
  final Animation<double> expandAnim;
  final Color surface;
  final Color text1;
  final Color text2;
  final Color border;
  final bool isDark;
  final VoidCallback onKeywordChanged;
  final VoidCallback onKeywordSubmitImmediate;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onBrandChanged;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onToggleAdvanced;

  static const List<String> _statusItems = [
    'الكل',
    'نشط',
    'مخزون منخفض',
    'نفذ من المخزون',
    'معطّل',
  ];

  @override
  Widget build(BuildContext context) {
    final layout = context.screenLayout;
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(
        layout.pageHorizontalGap,
        14,
        layout.pageHorizontalGap,
        14,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 14,
              end: 14,
              top: 12,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'بحث ومطابقة',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: text2,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.search_rounded, size: 16, color: text2),
              ],
            ),
          ),
          Divider(height: 16, color: border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (_, c) {
                final wide = c.maxWidth > 580;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _pickDropdownWide(
                          categoryItems,
                          category,
                          'التصنيف',
                          onCategoryChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _pickDropdownWide(
                          brandItems,
                          brand,
                          'الماركة',
                          onBrandChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _keyword()),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _keyword(),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _pickDropdownWide(
                            categoryItems,
                            category,
                            'التصنيف',
                            onCategoryChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickDropdownWide(
                            brandItems,
                            brand,
                            'الماركة',
                            onBrandChanged,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (_, c) {
                final wide = c.maxWidth > 580;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _barcodeField()),
                      const SizedBox(width: 12),
                      Expanded(child: _statusDropdown()),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusDropdown(),
                    const SizedBox(height: 10),
                    _barcodeField(),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          SizeTransition(
            sizeFactor: expandAnim,
            axisAlignment: -1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 20, color: border, indent: 14, endIndent: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final wide = c.maxWidth > 580;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _advancedPrice()),
                            const SizedBox(width: 12),
                            Expanded(child: _prod()),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _prod(),
                          const SizedBox(height: 10),
                          _advancedPrice(),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 14,
              end: 14,
              top: 4,
              bottom: 14,
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 560;
                final advancedBtn = OutlinedButton.icon(
                  onPressed: onToggleAdvanced,
                  icon: Icon(
                    advanced
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.tune_rounded,
                    size: 15,
                  ),
                  label: const Text(
                    'بحث متقدم',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBlue,
                    side: BorderSide(color: _kBlue.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (showClearFiltersChip)
                      OutlinedButton(
                        onPressed: onClear,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: text2,
                          side: BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          activeFiltersCount > 0
                              ? 'إلغاء الفلتر ($activeFiltersCount)'
                              : 'إلغاء الفلتر',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (advanced)
                      ElevatedButton.icon(
                        onPressed: onSearch,
                        icon: const Icon(
                          Icons.search_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'بحث',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kNavy,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: advancedBtn,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [advancedBtn, const Spacer(), actions],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyword() {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: keyword,
      builder: (context, val, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'البحث بكلمة مفتاحية',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: text2,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 40,
              child: TextField(
                controller: keyword,
                focusNode: keywordFn,
                keyboardType: TextInputType.text,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 13, color: text1),
                onChanged: (_) => onKeywordChanged(),
                onSubmitted: (_) => onKeywordSubmitImmediate(),
                decoration: InputDecoration(
                  hintText: 'ادخل الاسم أو الكود أو الباركود',
                  hintStyle: TextStyle(fontSize: 12, color: text2),
                  filled: true,
                  fillColor: fill,
                  isDense: true,
                  prefixIcon: keywordSearching
                      ? Padding(
                          padding: const EdgeInsets.all(11),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: text2.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      : Icon(Icons.search_rounded, size: 16, color: text2),
                  suffixIcon: val.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'مسح',
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            keyword.clear();
                            onKeywordChanged();
                          },
                          icon: const Icon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: 8,
                    end: 8,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: _kNavy, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pickDropdownWide(
    List<String> items,
    String value,
    String label,
    ValueChanged<String> onChanged,
  ) {
    if (items.where((e) => e.trim().isNotEmpty).length > 8) {
      return _AutocompletePick(
        label: label,
        value: value,
        options: items,
        text1: text1,
        text2: text2,
        border: border,
        isDark: isDark,
        onPick: onChanged,
      );
    }
    return _SearchDropdownCore(
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
      text1: text1,
      text2: text2,
      border: border,
      isDark: isDark,
    );
  }

  Widget _statusDropdown() {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    Color dot(String s) => switch (s) {
      'نشط' => _kGreen,
      'مخزون منخفض' => _kOrange,
      'نفذ من المخزون' => Colors.red.shade700,
      'معطّل' => _kText3,
      _ => Colors.transparent,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'الحالة',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: text2,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.zero,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusItems.contains(status) ? status : 'الكل',
              isExpanded: true,
              isDense: true,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: text2,
              ),
              style: TextStyle(fontSize: 12, color: text1),
              selectedItemBuilder: (ctx) => _statusItems
                  .map(
                    (s) => Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(s, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          if (dot(s) != Colors.transparent)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 2),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: dot(s),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              items: _statusItems
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(s),
                          const SizedBox(width: 10),
                          if (dot(s) != Colors.transparent)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: dot(s),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onStatusChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _barcodeField() {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'باركود',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: text2,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 40,
          child: TextField(
            controller: barcode,
            keyboardType: TextInputType.text,
            textAlign: TextAlign.right,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 13, color: text1),
            decoration: InputDecoration(
              hintText: 'مسح أو الكتابة',
              hintStyle: TextStyle(fontSize: 11, color: text2),
              filled: true,
              fillColor: fill,
              isDense: true,
              suffixIcon: Icon(
                Icons.qr_code_rounded,
                size: 18,
                color: text2.withValues(alpha: 0.8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: _kNavy, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _prod() => _SearchFieldCore(
    controller: prodCode,
    hint: '',
    label: 'كود المنتج',
    icon: Icons.tag_rounded,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _advancedPrice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'نطاق سعر البيع (دينار)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: text2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _SearchFieldCore(
                controller: priceTo,
                hint: 'إلى',
                label: '',
                icon: null,
                text1: text1,
                text2: text2,
                border: border,
                isDark: isDark,
                keyboard: TextInputType.number,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('-', style: TextStyle(color: text2)),
            ),
            Expanded(
              child: _SearchFieldCore(
                controller: priceFrom,
                hint: 'من',
                label: '',
                icon: null,
                text1: text1,
                text2: text2,
                border: border,
                isDark: isDark,
                keyboard: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SearchFieldCore extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final IconData? icon;
  final Color text1;
  final Color text2;
  final Color border;
  final bool isDark;
  final TextInputType keyboard;

  const _SearchFieldCore({
    required this.controller,
    required this.hint,
    required this.label,
    required this.icon,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: text2,
            ),
          ),
          const SizedBox(height: 5),
        ],
        SizedBox(
          height: 40,
          child: TextField(
            controller: controller,
            keyboardType: keyboard,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 13, color: text1),
            decoration: InputDecoration(
              hintText: hint.isEmpty ? null : hint,
              hintStyle: TextStyle(fontSize: 12, color: text2),
              prefixIcon: icon != null
                  ? Icon(icon, size: 16, color: text2)
                  : null,
              filled: true,
              fillColor: fill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: _kNavy, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchDropdownCore extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final Color text1;
  final Color text2;
  final Color border;
  final bool isDark;

  const _SearchDropdownCore({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    final v = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: text2,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.zero,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: v,
              isExpanded: true,
              isDense: true,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: text2,
              ),
              style: TextStyle(fontSize: 12, color: text1),
              items: items
                  .map(
                    (it) => DropdownMenuItem(
                      value: it,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(it),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (s) => s != null ? onChanged(s) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _AutocompletePick extends StatelessWidget {
  const _AutocompletePick({
    required this.label,
    required this.value,
    required this.options,
    required this.onPick,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;
  final Color text1;
  final Color text2;
  final Color border;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    final v = options.where((o) => o == value).isNotEmpty
        ? value
        : options.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: text2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.manage_search_rounded,
              size: 14,
              color: text2.withValues(alpha: 0.7),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.zero,
          ),
          alignment: AlignmentDirectional.centerEnd,
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(canvasColor: surfaceForMenu(context)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: v,
                isDense: true,
                isExpanded: true,
                menuMaxHeight: 280,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: text2,
                ),
                style: TextStyle(fontSize: 12, color: text1),
                items: options
                    .map(
                      (it) => DropdownMenuItem(
                        value: it,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(it),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) onPick(s);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color surfaceForMenu(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLowest;
}

// ══════════════════════════════════════════════════════════════════════════════
// RESULTS HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _ResultsHeader extends StatelessWidget {
  final int shownCount;
  final int matchedTotal;
  final int catalogTotal;
  final String sortBy;
  final bool sortAscending;
  final Color surface;
  final Color text1;
  final Color text2;
  final Color border;
  final bool isDark;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onSortDirectionToggle;

  const _ResultsHeader({
    required this.shownCount,
    required this.matchedTotal,
    required this.catalogTotal,
    required this.sortBy,
    required this.sortAscending,
    required this.surface,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
    required this.onSortChanged,
    required this.onSortDirectionToggle,
  });

  static const _sortChoices = ['الاسم', 'السعر', 'الكمية', 'تاريخ الإضافة'];

  @override
  Widget build(BuildContext context) {
    final layout = context.screenLayout;
    final extraCatalog = catalogTotal != matchedTotal && catalogTotal > 0
        ? ' · إجمالي النشط: $catalogTotal'
        : '';
    final sum = 'عرض $shownCount من أصل $matchedTotal منتج$extraCatalog';
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(
        layout.pageHorizontalGap,
        0,
        layout.pageHorizontalGap,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 640;
          final sortControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الفرز', style: TextStyle(fontSize: 11, color: text2)),
              const SizedBox(width: 8),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: border),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.zero,
                ),
                alignment: AlignmentDirectional.centerEnd,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortChoices.contains(sortBy) ? sortBy : 'الاسم',
                    isDense: true,
                    icon: Icon(Icons.sort_rounded, size: 16, color: text2),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: text1,
                    ),
                    items: _sortChoices
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(v),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onSortChanged(v);
                    },
                  ),
                ),
              ),
              IconButton(
                tooltip: sortAscending ? 'تصاعدي' : 'تنازلي',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  sortAscending
                      ? Icons.arrow_circle_up_rounded
                      : Icons.arrow_circle_down_rounded,
                  color: text1,
                  size: 22,
                ),
                onPressed: onSortDirectionToggle,
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sum,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: text1,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: sortControls,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  sum,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: text1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              sortControls,
            ],
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SKELETON / EMPTY (قائمة المنتجات)
// ══════════════════════════════════════════════════════════════════════════════
class _ProductSkeletonTile extends StatelessWidget {
  const _ProductSkeletonTile({
    required this.surface,
    required this.border,
    required this.text2,
  });

  final Color surface;
  final Color border;
  final Color text2;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: text2.withValues(alpha: 0.22),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 56,
                height: 16,
                decoration: BoxDecoration(color: text2.withValues(alpha: 0.18)),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 70,
                height: 10,
                decoration: BoxDecoration(color: text2.withValues(alpha: 0.15)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 90,
                height: 10,
                decoration: BoxDecoration(color: text2.withValues(alpha: 0.15)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductsEmptyBlock extends StatelessWidget {
  const _ProductsEmptyBlock({
    required this.isDark,
    required this.catalogTotal,
    required this.matchedTotal,
    required this.onClearFilters,
    required this.onAddFirst,
  });

  final bool isDark;
  final int catalogTotal;
  final int matchedTotal;
  final VoidCallback onClearFilters;
  final VoidCallback onAddFirst;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).colorScheme.onSurfaceVariant;
    final title = catalogTotal == 0
        ? 'لا توجد منتجات بعد'
        : 'لا توجد منتجات تطابق بحثك';
    final sub = catalogTotal == 0
        ? 'ابدأ بإضافة أول صنف إلى المخزون.'
        : 'جرّب تغيير كلمات البحث أو إلغاء الفلتر.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _kNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 36,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _kText1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              style: TextStyle(color: isDark ? Colors.white54 : txt),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            if (catalogTotal == 0)
              ElevatedButton.icon(
                onPressed: onAddFirst,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+ إضافة أول منتج'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              )
            else ...[
              if (catalogTotal > 0 && matchedTotal == 0)
                OutlinedButton(
                  onPressed: onClearFilters,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor(context)),
                  ),
                  child: const Text('إلغاء الفلتر'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color borderColor(BuildContext context) =>
      Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);
}

List<PopupMenuEntry<String>> _productPopupMenuEntries({
  required bool isPinned,
  required bool active,
  required bool hasTogglePin,
}) {
  return [
    if (hasTogglePin) ...[
      PopupMenuItem(
        value: isPinned ? 'unpin' : 'pin',
        child: Text(
          isPinned ? 'إلغاء التثبيت من الرئيسية' : 'تثبيت في الرئيسية',
        ),
      ),
      const PopupMenuDivider(),
    ],
    const PopupMenuItem(value: 'edit', child: Text('تعديل')),
    const PopupMenuItem(value: 'print_bc', child: Text('طباعة باركود')),
    PopupMenuItem(
      value: 'toggle_active',
      child: Text(active ? 'تعطيل' : 'تفعيل'),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: 'delete',
      child: Text('حذف', style: TextStyle(color: Colors.red)),
    ),
  ];
}

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCT ROW
// ══════════════════════════════════════════════════════════════════════════════
class _ProductRow extends StatefulWidget {
  final Map<String, dynamic> product;
  final Color surface, text1, text2, border;
  final bool isDark;
  const _ProductRow({
    required this.product,
    required this.surface,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
  });
  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  bool _hover = false;
  Offset? _lastPointer;
  final ProductRepository _repo = ProductRepository();

  Future<void> _applyProductMenuChoice(String? choice) async {
    final p = widget.product;
    final pid = (p['id'] as num?)?.toInt();
    if (choice == null || pid == null) return;
    final pinned = (p['isPinned'] as num?)?.toInt() == 1;
    final active = ((p['isActive'] as num?)?.toInt() ?? 1) != 0;

    if (choice == 'pin' || choice == 'unpin') {
      await _repo.setProductPinned(pid, !pinned);
      if (!mounted) return;
      await context.read<InventoryProductsProvider>().refresh();
    } else if (choice == 'edit') {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ProductEditScreen(productId: pid),
        ),
      );
      if (saved == true && mounted) {
        await context.read<InventoryProductsProvider>().refresh();
      }
    } else if (choice == 'print_bc') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BarcodeLabelsScreen(focusProductIds: [pid]),
        ),
      );
    } else if (choice == 'toggle_active') {
      if (active) {
        await _repo.deactivateProduct(pid);
      } else {
        await _repo.activateProduct(pid);
      }
      if (!mounted) return;
      await context.read<InventoryProductsProvider>().refresh();
    } else if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف المنتج'),
          content: const Text(
            'سيتم إخفاء المنتج من القوائم (حذف منطقي) بدون كسر الفواتير المرتبطة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        await _repo.deactivateProduct(pid);
        await context.read<InventoryProductsProvider>().refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final id = (p['id'] as num?)?.toInt();
    final active = ((p['isActive'] as num?)?.toInt() ?? 1) != 0;
    final qty = (p['qty'] as num?)?.toDouble() ?? 0;
    final lowTh = (p['lowStockThreshold'] as num?)?.toDouble() ?? 0;
    final st = '${p['status'] ?? ''}';

    late Color badgeBg;
    late Color badgeFg;
    late String badgeTxt;
    if (!active) {
      badgeTxt = 'معطّل';
      badgeBg = const Color(0xFFE5E7EB);
      badgeFg = _kText3;
    } else if (qty <= 0) {
      badgeTxt = 'نفذ';
      badgeBg = const Color(0xFFFFE4E6);
      badgeFg = Colors.red.shade800;
    } else if (st == 'low') {
      badgeTxt = 'مخزون منخفض';
      badgeBg = _kOrangeBg;
      badgeFg = _kOrange;
    } else {
      badgeTxt = 'نشط';
      badgeBg = _kGreenBg;
      badgeFg = _kGreen;
    }

    final sellN = (p['sell'] as num?)?.toDouble() ?? 0;
    final buyN = (p['buy'] as num?)?.toDouble() ?? 0;
    final sellF = NumericFormat.formatNumber(sellN.round().clamp(0, 999999999));
    final buyF = NumericFormat.formatNumber(buyN.round().clamp(0, 999999999));
    final pct = buyN > 0 ? (((sellN - buyN) / buyN * 100).round()) : 0;
    final marginColor = pct < 0
        ? Colors.red.shade800
        : pct < 10
        ? Colors.red.shade700
        : pct <= 20
        ? _kOrange
        : Colors.green.shade700;
    final lowWarn = active && qty > 0 && qty <= lowTh && lowTh > 0;
    String fmtQty(double q) {
      if (q == q.roundToDouble()) return q.round().toString();
      final t = q.toStringAsFixed(2);
      return t.endsWith('0') ? q.toStringAsFixed(1) : t;
    }

    final qtyTxt = fmtQty(qty);
    final pinned = (p['isPinned'] as num?)?.toInt() == 1;

    Future<void> openActionMenu(Offset global) async {
      if (id == null) return;
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final pos = RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 1, 1),
        Offset.zero & overlay.size,
      );
      final choice = await showMenu<String>(
        context: context,
        position: pos,
        items: _productPopupMenuEntries(
          isPinned: pinned,
          active: active,
          hasTogglePin: true,
        ),
      );
      if (!context.mounted) return;
      await _applyProductMenuChoice(choice);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: Listener(
          onPointerDown: (e) => _lastPointer = e.position,
          child: InkWell(
            onTap: () {
              if (id == null) return;
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProductEditScreen(productId: id),
                ),
              );
            },
            onSecondaryTap: id == null
                ? null
                : () {
                    final ox = _lastPointer;
                    if (ox == null) return;
                    openActionMenu(ox);
                  },
            onLongPress: id == null
                ? null
                : () {
                    Offset? g = _lastPointer;
                    final box = context.findRenderObject() as RenderBox?;
                    g ??= box?.localToGlobal(
                      Offset(box.size.width / 2, box.size.height / 2),
                    );
                    if (g == null) return;
                    openActionMenu(g);
                  },
            mouseCursor: SystemMouseCursors.click,
            hoverColor: widget.isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: .04),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _hover
                    ? (widget.isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF8FAFF))
                    : widget.surface,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: _hover
                      ? _kNavy.withValues(alpha: 0.25)
                      : widget.border,
                ),
                boxShadow: widget.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _hover ? 0.08 : 0.04,
                          ),
                          blurRadius: _hover ? 12 : 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;

                  Widget options() => _OptionsBtn(
                    isDark: widget.isDark,
                    border: widget.border,
                    isPinned: pinned,
                    isActive: active,
                    hasTogglePin: id != null,
                    onMenuChoice: (v) => unawaited(_applyProductMenuChoice(v)),
                  );

                  Widget statusBadge() => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(
                      badgeTxt,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeFg,
                      ),
                    ),
                  );

                  final name = '${p['name'] ?? ''}';
                  final barcode =
                      (p['barcode'] == null || '${p['barcode']}'.isEmpty)
                      ? '—'
                      : '${p['barcode']}';

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            options(),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: widget.text1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.end,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      statusBadge(),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        barcode,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: widget.text2,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        textDirection: TextDirection.ltr,
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.barcode_reader,
                                        size: 16,
                                        color: _kText3,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _mini(
                                icon: Icons.shopping_cart_outlined,
                                label: 'هامش: $pct%',
                                value: '$sellF د.ع',
                                color: widget.text1,
                                subColor: marginColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: _mini(
                                      icon: Icons.people_outline_rounded,
                                      label: 'المتاح',
                                      value: qtyTxt,
                                      color: (active && qty <= 0)
                                          ? Colors.red.shade800
                                          : widget.text1,
                                      subColor: widget.text2,
                                    ),
                                  ),
                                  if (lowWarn)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 4,
                                      ),
                                      child: Icon(
                                        Icons.warning_amber_rounded,
                                        color: _kOrange,
                                        size: 22,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  // wide layout (desktop/tablet)
                  return Row(
                    children: [
                      options(),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.text1,
                                    fontFamily: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.fontFamily,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$sellF د.ع ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '| ',
                                      style: TextStyle(color: widget.text2),
                                    ),
                                    TextSpan(
                                      text: 'هامش: $pct%',
                                      style: TextStyle(
                                        color: marginColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.shopping_cart_outlined,
                                size: 13,
                                color: _kText3,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'شراء: $buyF د.ع',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.text2,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.local_shipping_outlined,
                                size: 13,
                                color: _kText3,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          statusBadge(),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 13,
                                color: _kText3,
                              ),
                              const SizedBox(width: 3),
                              if (active && qty <= 0)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 6,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE4E6),
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      'نفذ',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.red.shade800,
                                      ),
                                    ),
                                  ),
                                ),
                              if (lowWarn)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 4,
                                  ),
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: _kOrange,
                                  ),
                                ),
                              Text(
                                'المتاح: $qtyTxt',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (active && qty <= 0)
                                      ? Colors.red.shade700
                                      : widget.text2,
                                  fontWeight: (active && qty <= 0)
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ' #${p['id']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.text2,
                                ),
                              ),
                              const SizedBox(width: 2),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: widget.text1,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                barcode,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.text2,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.barcode_reader,
                                size: 16,
                                color: _kText3,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_left_rounded,
                        color: widget.text2,
                        size: 20,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mini({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color subColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        border: Border.all(color: widget.border),
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: subColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionsBtn extends StatelessWidget {
  final bool isDark;
  final Color border;
  final bool isPinned;
  final bool isActive;
  final bool hasTogglePin;
  final void Function(String value) onMenuChoice;

  const _OptionsBtn({
    required this.isDark,
    required this.border,
    required this.isPinned,
    required this.isActive,
    required this.hasTogglePin,
    required this.onMenuChoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.zero,
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8FAFC),
      ),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'خيارات المنتج',
        icon: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: isDark ? Colors.white54 : _kText2,
        ),
        onSelected: (v) => onMenuChoice(v),
        itemBuilder: (_) => _productPopupMenuEntries(
          isPinned: isPinned,
          active: isActive,
          hasTogglePin: hasTogglePin,
        ),
      ),
    );
  }
}
