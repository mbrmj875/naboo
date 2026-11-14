import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/product_quick_pick_cache.dart';
import '../../../services/product_repository.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/inventory/product_quick_pick_grid_tile.dart';
import 'oil_change_form_theme.dart';
import 'oil_change_log_stitch.dart';

/// نافذة اختيار منتج من المخزون (شاشات عريضة) — شبكة مربعات كإدارة المنتجات.
class ProductPickerDialog extends StatefulWidget {
  const ProductPickerDialog({super.key, this.fullScreen = false});

  /// على الهاتف تُفتح صفحة كاملة بمربعات أكبر. على التابلت والكمبيوتر تبقى النافذة.
  final bool fullScreen;

  static const int _initialLimit = 240;
  static const int _searchLimit = 120;

  /// على الشاشات العريضة تُعرض النافذة دائماً.
  /// على الهاتف تُعرض فقط عند [allowHandset] حتى لا تتغير بطاقة الغيار.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    bool allowHandset = false,
  }) {
    final layout = ScreenLayout.of(context);
    final handset = layout.showSaleBarcodeShortcut;
    if (handset && !allowHandset) {
      return Future.value(null);
    }
    if (handset) {
      return Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ProductPickerDialog(fullScreen: true),
        ),
      );
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
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final cached = ProductQuickPickCache.instance.snapshot;
    if (cached != null) {
      _rows = cached;
      _loading = false;
    }
    _search.addListener(_onSearchChanged);
    if (!widget.fullScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
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
    _debounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_load());
    });
    setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    final q = _search.text.trim();
    if (_rows.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = q.isEmpty
          ? await ProductQuickPickCache.instance.refresh(
              limit: ProductPickerDialog._initialLimit,
            )
          : await _repo.searchSaleGridProducts(
              q,
              limit: ProductPickerDialog._searchLimit,
            );
      if (!mounted || request != _request) return;
      if (_sameGrid(_rows, rows)) {
        if (_loading || _error != null) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
        return;
      }
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = _rows.isEmpty ? 'تعذّر تحميل المنتجات' : _error;
        _loading = false;
      });
    }
  }

  bool _sameGrid(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (identical(a, b) || a.length != b.length) return identical(a, b);
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left['id'] != right['id'] ||
          left['qty'] != right['qty'] ||
          left['sell'] != right['sell'] ||
          left['name'] != right['name'] ||
          left['status'] != right['status']) {
        return false;
      }
    }
    return true;
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

    final pickerBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          focusNode: _searchFocus,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.start,
          style: TextStyle(
            color: OilChangeFormTheme.emphasisText(context),
            fontWeight: FontWeight.w600,
          ),
          cursorColor: OilChangeFormTheme.gold,
          textInputAction: TextInputAction.search,
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: '',
            hintText: 'ابحث بالاسم أو الباركود أو رمز المنتج',
            isDense: true,
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: OilChangeFormTheme.gold,
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
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
          ).copyWith(
            labelText: null,
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
        const SizedBox(height: 8),
        if (_search.text.trim().isEmpty && !widget.fullScreen)
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
    );

    if (widget.fullScreen) {
      final page = Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0F172A)
            : OilChangeLogStitchMetrics.background,
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'اختيار منتج',
          actions: const [],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
            child: pickerBody,
          ),
        ),
      );
      return Theme(
        data: OilChangeFormTheme.wrap(context, Theme.of(context)),
        child: page,
      );
    }

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Shortcuts(
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
          backgroundColor: isDark
              ? const Color(0xFF0F172A)
              : OilChangeLogStitchMetrics.background,
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
            child: pickerBody,
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
      return Align(
        alignment: AlignmentDirectional.topCenter,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 28),
          child: Text(
            _search.text.trim().isEmpty
                ? 'لا توجد منتجات نشطة.'
                : 'لا توجد نتائج مطابقة.',
            style: TextStyle(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = widget.fullScreen && width < 600
            ? 2
            : productQuickPickGridCrossAxisCount(width);
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
