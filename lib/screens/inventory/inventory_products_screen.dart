import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/inventory_products_provider.dart';
import 'add_product_screen.dart';
import 'inventory_settings_screen.dart';
import 'product_detail_screen.dart';
import 'product_edit_screen.dart';
import '../../services/product_repository.dart';
import 'barcode_labels_screen.dart';

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
  // controllers
  final _keyword = TextEditingController();
  final _barcode = TextEditingController();
  final _prodCode = TextEditingController();
  final _priceFrom = TextEditingController();
  final _priceTo = TextEditingController();

  // filter state
  String _category = 'جميع التصنيفات';
  String _brand = 'جميع الماركات';
  String _status = 'الكل';
  String _sortBy = 'الاسم';
  bool _advanced = false;

  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  void _syncFiltersToProvider({bool seedIfEmpty = false}) {
    if (!mounted) return;
    final prov = context.read<InventoryProductsProvider>();
    unawaited(
      prov.setFilters(
        keyword: _keyword.text,
        barcode: _barcode.text,
        productCode: _prodCode.text,
        status: _status,
        sortBy: _sortBy,
      ),
    );
    if (seedIfEmpty) {
      unawaited(prov.refresh(seedIfEmpty: true));
    }
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
      _syncFiltersToProvider(seedIfEmpty: true);
    });
    _keyword.addListener(_syncFiltersToProvider);
    _barcode.addListener(_syncFiltersToProvider);
    _prodCode.addListener(_syncFiltersToProvider);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _keyword.dispose();
    _barcode.dispose();
    _prodCode.dispose();
    _priceFrom.dispose();
    _priceTo.dispose();
    super.dispose();
  }

  void _toggleAdvanced() {
    setState(() => _advanced = !_advanced);
    _advanced ? _animCtrl.forward() : _animCtrl.reverse();
  }

  void _clearFilters() {
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
    _syncFiltersToProvider();
  }

  bool get _isDark =>
      Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final products = context.read<InventoryProductsProvider>();
                  final messenger = ScaffoldMessenger.of(context);
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const AddProductScreen()),
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
        body: Consumer<InventoryProductsProvider>(
          builder: (context, provider, _) {
            final filtered = provider.items;
            // اجعل شريط البحث/النتائج جزء من التمرير: عند السحب للأعلى
            // يرتفع ويختفي، وتبقى القائمة تملأ الشاشة.
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
                      barcode: _barcode,
                      prodCode: _prodCode,
                      priceFrom: _priceFrom,
                      priceTo: _priceTo,
                      category: _category,
                      brand: _brand,
                      status: _status,
                      advanced: _advanced,
                      expandAnim: _expandAnim,
                      surface: surface,
                      text1: text1,
                      text2: text2,
                      border: border,
                      isDark: _isDark,
                      onCategoryChanged: (v) => setState(() => _category = v),
                      onBrandChanged: (v) => setState(() => _brand = v),
                      onStatusChanged: (v) {
                        setState(() => _status = v);
                        _syncFiltersToProvider();
                      },
                      onSearch: _syncFiltersToProvider,
                      onClear: _clearFilters,
                      onToggleAdvanced: _toggleAdvanced,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ResultsHeader(
                      count: filtered.length,
                      sortBy: _sortBy,
                      surface: surface,
                      text1: text1,
                      text2: text2,
                      border: border,
                      isDark: _isDark,
                      onSortChanged: (v) {
                        setState(() => _sortBy = v);
                        _syncFiltersToProvider();
                      },
                    ),
                  ),
                  if (filtered.isEmpty && provider.isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(isDark: _isDark),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            if (i >= filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator()),
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
                              filtered.length + (provider.isLoadingMore ? 1 : 0),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH CARD
// ══════════════════════════════════════════════════════════════════════════════
class _SearchCard extends StatelessWidget {
  final TextEditingController keyword, barcode, prodCode, priceFrom, priceTo;
  final String category, brand, status;
  final bool advanced, isDark;
  final Animation<double> expandAnim;
  final Color surface, text1, text2, border;
  final ValueChanged<String> onCategoryChanged, onBrandChanged, onStatusChanged;
  final VoidCallback onSearch, onClear, onToggleAdvanced;

  const _SearchCard({
    required this.keyword,
    required this.barcode,
    required this.prodCode,
    required this.priceFrom,
    required this.priceTo,
    required this.category,
    required this.brand,
    required this.status,
    required this.advanced,
    required this.isDark,
    required this.expandAnim,
    required this.surface,
    required this.text1,
    required this.text2,
    required this.border,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onStatusChanged,
    required this.onSearch,
    required this.onClear,
    required this.onToggleAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
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
          // ── Section title ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'بحث',
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
          // ── Row 1: keyword | category | brand ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (_, c) {
                final wide = c.maxWidth > 580;
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: _buildBrandDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildCategoryDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKeywordField()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildKeywordField(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildCategoryDropdown()),
                        const SizedBox(width: 10),
                        Expanded(child: _buildBrandDropdown()),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // ── Row 2: status | barcode ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (_, c) {
                final wide = c.maxWidth > 580;
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: _buildBarcodeField()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatusDropdown()),
                      const Expanded(child: SizedBox()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildStatusDropdown(),
                    const SizedBox(height: 10),
                    _buildBarcodeField(),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          // ── Advanced search (animated) ─────────────────────────────────────
          SizeTransition(
            sizeFactor: expandAnim,
            axisAlignment: -1,
            child: Column(
              children: [
                Divider(height: 20, color: border, indent: 14, endIndent: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final wide = c.maxWidth > 580;
                      if (wide) {
                        return Row(
                          children: [
                            Expanded(child: _buildPriceRange()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildProdCodeField()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildProdCodeField(),
                          const SizedBox(height: 10),
                          _buildPriceRange(),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // ── Action buttons ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                // Advanced search toggle
                OutlinedButton.icon(
                  onPressed: onToggleAdvanced,
                  icon: Icon(
                    advanced
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.tune_rounded,
                    size: 15,
                  ),
                  label: Text(
                    'بحث متقدم',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBlue,
                    side: BorderSide(color: _kBlue.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                // Clear
                OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: text2,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'إلغاء الفلتر',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                // Search
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Field builders ──────────────────────────────────────────────────────────
  Widget _buildKeywordField() => _SearchField(
    controller: keyword,
    hint: 'ادخل الإسم أو الكود',
    label: 'البحث بكلمة مفتاحية',
    icon: Icons.search_rounded,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildBarcodeField() => _SearchField(
    controller: barcode,
    hint: '',
    label: 'باركود',
    icon: Icons.qr_code_rounded,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildProdCodeField() => _SearchField(
    controller: prodCode,
    hint: '',
    label: 'كود المنتج',
    icon: Icons.tag_rounded,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildCategoryDropdown() => _SearchDropdown(
    label: 'التصنيف',
    value: category,
    items: const ['جميع التصنيفات', 'مشروبات', 'مواد غذائية', 'أخرى'],
    onChanged: onCategoryChanged,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildBrandDropdown() => _SearchDropdown(
    label: 'الماركة',
    value: brand,
    items: const ['جميع الماركات', 'Pepsi', 'Coca-Cola', 'Pringles'],
    onChanged: onBrandChanged,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildStatusDropdown() => _SearchDropdown(
    label: 'الحالة',
    value: status,
    items: const ['الكل', 'في المخزون', 'منخفض'],
    onChanged: onStatusChanged,
    text1: text1,
    text2: text2,
    border: border,
    isDark: isDark,
  );

  Widget _buildPriceRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'أسعار',
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
              child: _SearchField(
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
              child: _SearchField(
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
            const SizedBox(width: 8),
            // تخصيص dropdown
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.zero,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF8FAFC),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: 'تخصيص',
                  isDense: true,
                  style: TextStyle(fontSize: 12, color: text1),
                  items: ['تخصيص', 'سعر البيع', 'سعر الشراء']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (_) {},
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RESULTS HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _ResultsHeader extends StatelessWidget {
  final int count;
  final String sortBy;
  final Color surface, text1, text2, border;
  final bool isDark;
  final ValueChanged<String> onSortChanged;

  const _ResultsHeader({
    required this.count,
    required this.sortBy,
    required this.surface,
    required this.text1,
    required this.text2,
    required this.border,
    required this.isDark,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.zero,
              border: Border.all(color: _kNavy.withValues(alpha: 0.15)),
            ),
            child: Text(
              '($count) المنتجات',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kNavy,
              ),
            ),
          ),
          const Spacer(),
          // Sort dropdown
          Text('الترتيب حسب', style: TextStyle(fontSize: 12, color: text2)),
          const SizedBox(width: 6),
          Icon(Icons.swap_vert_rounded, size: 14, color: text2),
          const SizedBox(width: 8),
          Text(
            'النتائج',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: text1,
            ),
          ),
        ],
      ),
    );
  }
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
  final ProductRepository _repo = ProductRepository();

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final id = (p['id'] as num?)?.toInt();
    final isLow = p['status'] == 'low';
    final badgeBg = isLow ? _kOrangeBg : _kGreenBg;
    final badgeFg = isLow ? _kOrange : _kGreen;
    final badgeTxt = isLow ? 'مخزون منخفض' : 'في المخزون';
    final sell = _fmtPrice(p['sell'] as double);
    final buy = _fmtPrice(p['buy'] as double);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (id == null) return;
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ProductDetailScreen(productId: id),
              ),
            );
          },
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
                color: _hover ? _kNavy.withValues(alpha: 0.25) : widget.border,
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

                final pinned = (p['isPinned'] as num?)?.toInt() == 1;

                Widget options() => _OptionsBtn(
                      isDark: widget.isDark,
                      border: widget.border,
                      isPinned: pinned,
                      onTogglePin: id == null
                          ? null
                          : () async {
                              await _repo.setProductPinned(id, !pinned);
                              if (!context.mounted) return;
                              await context
                                  .read<InventoryProductsProvider>()
                                  .refresh();
                            },
                      onEdit: id == null
                          ? null
                          : () async {
                              final saved = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute<bool>(
                                  builder: (_) => ProductEditScreen(productId: id),
                                ),
                              );
                              if (saved == true && context.mounted) {
                                await context
                                    .read<InventoryProductsProvider>()
                                    .refresh();
                              }
                            },
                      onDelete: id == null
                          ? null
                          : () async {
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
                              if (ok != true) return;
                              await _repo.deactivateProduct(id);
                              if (!context.mounted) return;
                              await context.read<InventoryProductsProvider>().refresh();
                            },
                    );

                Widget statusBadge() => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                final barcode = (p['barcode'] == null || '${p['barcode']}'.isEmpty)
                    ? '—'
                    : '${p['barcode']}';
                final qtyTxt = '${p['qty']}';

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
                                      style: TextStyle(fontSize: 10.5, color: widget.text2),
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.ltr,
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.barcode_reader, size: 16, color: _kText3),
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
                              label: 'بيع',
                              value: '$sell د.ع',
                              color: widget.text1,
                              subColor: widget.text2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _mini(
                              icon: Icons.people_outline_rounded,
                              label: 'المتاح',
                              value: qtyTxt,
                              color: widget.text1,
                              subColor: widget.text2,
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
                            Text(
                              '$sell د.ع',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.text1,
                              ),
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
                              '$buy د.ع',
                              style: TextStyle(fontSize: 11, color: widget.text2),
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
                          children: [
                            Text(
                              '$qtyTxt المتاح',
                              style: TextStyle(fontSize: 11, color: widget.text2),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.people_outline_rounded,
                              size: 13,
                              color: _kText3,
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
                              style: TextStyle(fontSize: 11, color: widget.text2),
                            ),
                            const SizedBox(width: 2),
                            Flexible(
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
                            const Icon(Icons.barcode_reader, size: 16, color: _kText3),
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
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)},${(v % 1000).toStringAsFixed(0).padLeft(3, '0')}';
    }
    return v.toStringAsFixed(0);
  }
}

class _OptionsBtn extends StatelessWidget {
  final bool isDark;
  final Color border;
  final bool isPinned;
  final VoidCallback? onTogglePin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _OptionsBtn({
    required this.isDark,
    required this.border,
    required this.isPinned,
    required this.onTogglePin,
    required this.onEdit,
    required this.onDelete,
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
        onSelected: (v) {
          if (v == 'pin') onTogglePin?.call();
          if (v == 'unpin') onTogglePin?.call();
          if (v == 'edit') onEdit?.call();
          if (v == 'delete') onDelete?.call();
        },
        itemBuilder: (_) => [
          if (onTogglePin != null)
            PopupMenuItem(
              value: isPinned ? 'unpin' : 'pin',
              child: Text(
                isPinned ? 'إلغاء التثبيت من الرئيسية' : 'تثبيت في الرئيسية',
              ),
            ),
          if (onTogglePin != null) const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'edit',
            child: Text('تعديل المنتج'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 38,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد نتائج',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : _kText1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جرّب تغيير معايير البحث',
            style: TextStyle(color: isDark ? Colors.white54 : _kText2),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED MICRO-WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint, label;
  final IconData? icon;
  final Color text1, text2, border;
  final bool isDark;
  final TextInputType keyboard;

  const _SearchField({
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
              hintText: hint,
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: const BorderSide(color: _kNavy, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchDropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final Color text1, text2, border;
  final bool isDark;

  const _SearchDropdown({
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
              value: value,
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
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
