import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/product_repository.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/inventory/product_quick_pick_grid_tile.dart';

/// نافذة اختيار منتج من المخزون (شاشات عريضة) — شبكة مربعات كإدارة المنتجات.
class ProductPickerDialog extends StatefulWidget {
  const ProductPickerDialog({super.key});

  static const int _initialLimit = 80;
  static const int _searchLimit = 120;

  /// يُعرض على الشاشات العريضة فقط ([ScreenLayout.showSaleBarcodeShortcut] == false).
  static Future<Map<String, dynamic>?> show(BuildContext context) {
    final layout = ScreenLayout.of(context);
    if (layout.showSaleBarcodeShortcut) {
      return Future.value(null);
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ProductPickerDialog(),
    );
  }

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final ProductRepository _repo = ProductRepository();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_load());
    });
    setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final rows = q.isEmpty
          ? await _repo.listActiveProductsForQuickPick(
              limit: ProductPickerDialog._initialLimit,
            )
          : await _repo.searchProducts(
              q,
              limit: ProductPickerDialog._searchLimit,
            );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المنتجات';
        _loading = false;
      });
    }
  }

  void _pick(Map<String, dynamic> row) {
    Navigator.of(context).pop(row);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = ProductQuickPickColors.of(context);
    final layout = ScreenLayout.of(context);
    final dialogW = layout.isDesktopVariant
        ? 860.0
        : (layout.isTabletVariant ? 700.0 : 560.0);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : null,
          title: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: AppColors.accentGold,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'إضافة منتج من المخزون',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق (Esc)',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              ),
            ],
          ),
          content: SizedBox(
            width: dialogW,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  style: TextStyle(color: colors.textPrimary),
                  cursorColor: AppColors.accentGold,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الباركود أو رمز المنتج…',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: colors.textSecondary,
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح',
                            onPressed: () {
                              _search.clear();
                              unawaited(_load());
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.textSecondary,
                            ),
                          ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.accentGold,
                        width: 2,
                      ),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                if (_search.text.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 6),
                    child: Text(
                      'يعرض أول ${ProductPickerDialog._initialLimit} منتجاً — ابحث للوصول إلى صنف بعينه. '
                      'يمكنك مسح الباركود بالقارئ دون النقر هنا.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                Expanded(child: _buildBody(colors)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(color: isDark ? colors.textSecondary : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ProductQuickPickColors colors) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => unawaited(_load()),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty
              ? 'لا توجد منتجات نشطة.'
              : 'لا توجد نتائج مطابقة.',
          style: TextStyle(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            productQuickPickGridCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: _rows.length,
          itemBuilder: (context, i) {
            final row = _rows[i];
            return ProductQuickPickGridTile(
              product: row,
              onTap: () => _pick(row),
            );
          },
        );
      },
    );
  }
}
