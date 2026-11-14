import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../navigation/content_navigation.dart';
import '../../services/global_search/global_search_controller.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../theme/sale_brand.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../inputs/arabic_speech_mic_button.dart';
import '../search_virtual_keyboard.dart';
import '../virtual_keyboard_controller.dart';

typedef GlobalSearchOpen =
    void Function(String routeId, String title, WidgetBuilder builder);

/// صفحة البحث الشامل كاملة — تُفتح من زر البحث في الشريط العلوي.
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({
    super.key,
    required this.search,
    required this.onOpen,
    required this.onProductPick,
    required this.onScanBarcode,
    required this.customersDestination,
    required this.usersDestination,
    this.searchConfig,
  });

  final GlobalSearchController search;
  final GlobalSearchOpen onOpen;
  final ValueChanged<Map<String, dynamic>> onProductPick;
  final VoidCallback onScanBarcode;
  final WidgetBuilder customersDestination;
  final WidgetBuilder usersDestination;
  final HomeSearchConfig? searchConfig;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  GlobalSearchController get _search => widget.search;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary => _isDark
      ? Theme.of(context).colorScheme.onSurface
      : AppColors.primaryDark;
  Color get _textSecondary => _isDark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : AppColors.primaryDark.withValues(alpha: 0.75);

  @override
  void initState() {
    super.initState();
    _search.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search.focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.removeListener(_rebuild);
    _search.focus.unfocus();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String _hint(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final short = sl.isHandsetForLayout && MediaQuery.sizeOf(context).width < 400;
    final config = widget.searchConfig;
    if (config != null) {
      return short ? config.shortPlaceholder : config.placeholder;
    }
    return short
        ? 'بحث سريع: وحدات، منتجات، عملاء…'
        : 'بحث: وحدات، منتجات، عملاء، موظفون، باركود…';
  }

  /// يغلق الصفحة ثم ينتقل، حتى تُفتح النتيجة داخل الغلاف.
  void _onResultTap({required String query, required VoidCallback navigate}) {
    if (query.trim().isNotEmpty) unawaited(_search.remember(query));
    _search.focus.unfocus();
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _search.clear();
      navigate();
    });
  }

  Widget _buildResults() {
    if (_search.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_search.hasQuery) return _buildRecentSearchSuggestions();
    return _buildSearchOverlayScrollable();
  }

  @override
  Widget build(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final cs = Theme.of(context).colorScheme;
    final hideVk = sl.hideInAppSearchKeyboard;
    final vkVisible = _search.showVirtualKeyboard && !hideVk;
    final vkReserve = vkVisible ? MediaQuery.sizeOf(context).height * 0.40 : 0.0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: _textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.arrow_forward, color: _textPrimary),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('بحث', style: TextStyle(color: _textPrimary)),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: vkReserve),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: sl.isWideVariant ? 920 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          sl.pageHorizontalGap,
                          8,
                          sl.pageHorizontalGap,
                          8,
                        ),
                        child: _buildSearchBar(),
                      ),
                      Expanded(
                        child: Material(
                          color: cs.surface,
                          child: _buildResults(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (vkVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SearchVirtualKeyboard(
                  controller: _search.text,
                  isDark: _isDark,
                  onClose: _search.hideVirtualKeyboard,
                  onSubmit: () {
                    _search.schedule();
                    _search.hideVirtualKeyboard();
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// أيقونات حقل البحث (باركود، لوحة مفاتيح، مسح) — نفس منطق الزوايا عند «مستدير».
  ButtonStyle? _searchBarSuffixIconStyle(Color iconColor) {
    final ac = context.appCorners;
    if (!ac.isRounded) return null;
    return IconButton.styleFrom(
      foregroundColor: iconColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      shape: RoundedRectangleBorder(
        borderRadius: ac.sm,
        side: BorderSide(color: iconColor.withValues(alpha: 0.45), width: 1),
      ),
    );
  }

  Widget _buildSearchBarSuffixRow(Color iconInField, bool hideVk) {
    final sl = ScreenLayout.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final collapse = sl.isHandsetForLayout && w < 400 && !hideVk;

    final micBtn = ArabicSpeechMicButton(
      controller: _search.text,
      tooltip: 'إملاء البحث بالصوت',
      onTextUpdated: () => _search.schedule(),
    );

    final barcodeBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip:
          'قراءة باركود (كاميرا على الجهاز المحمول، أو نافذة القارئ على الحاسوب)',
      icon: Icon(Icons.qr_code_scanner_rounded, color: iconInField, size: 21),
      onPressed: widget.onScanBarcode,
    );

    final keyboardBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip: _search.showVirtualKeyboard
          ? 'إخفاء لوحة المفاتيح'
          : 'لوحة مفاتيح عربي / English — اسحب من المقبض أو ثبّتها بالدبوس',
      icon: Icon(
        _search.showVirtualKeyboard
            ? Icons.keyboard_hide_rounded
            : Icons.keyboard_rounded,
        color: iconInField,
        size: 21,
      ),
      onPressed: _search.toggleVirtualKeyboard,
    );

    final clearBtn = _search.hasQuery
        ? IconButton(
            style: _searchBarSuffixIconStyle(iconInField),
            tooltip: 'مسح البحث',
            icon: Icon(Icons.clear_rounded, color: iconInField, size: 20),
            onPressed: _search.clear,
          )
        : null;

    if (!collapse) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [micBtn, barcodeBtn, if (!hideVk) keyboardBtn, ?clearBtn],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        micBtn,
        barcodeBtn,
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'أدوات البحث',
          color: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          icon: Icon(Icons.tune_rounded, color: iconInField, size: 20),
          onSelected: (value) {
            if (value == 'kb') _search.toggleVirtualKeyboard();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'kb',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _search.showVirtualKeyboard
                      ? Icons.keyboard_hide_rounded
                      : Icons.keyboard_rounded,
                ),
                title: Text(
                  _search.showVirtualKeyboard
                      ? 'إخفاء لوحة المفاتيح'
                      : 'إظهار لوحة المفاتيح (عربي / English)',
                ),
              ),
            ),
          ],
        ),
        ?clearBtn,
      ],
    );
  }

  Widget _buildSearchBar() {
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final hideVk = sl.hideInAppSearchKeyboard;
    final iconInField = _textSecondary;
    final w = MediaQuery.sizeOf(context).width;
    final shortHint = sl.isHandsetForLayout && w < 400;
    final oilSearch = widget.searchConfig;
    final royalGold = SaleBrandColors.gold;
    final useRoyal = oilSearch?.routeToOilHub == true;

    Widget field = TextField(
      controller: _search.text,
      focusNode: _search.focus,
      readOnly:
          _search.showVirtualKeyboard &&
          !hideVk &&
          VirtualKeyboardController.instance.isPinned,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search.schedule(immediate: true),
      style: TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.search_rounded,
          color: useRoyal ? royalGold : iconInField,
          size: 22,
        ),
        suffixIcon: _buildSearchBarSuffixRow(iconInField, hideVk),
        suffixIconConstraints: const BoxConstraints(
          minHeight: 48,
          maxHeight: 52,
        ),
        hintText: oilSearch != null
            ? (shortHint
                  ? oilSearch.shortPlaceholder
                  : oilSearch.placeholder)
            : (shortHint
                  ? 'بحث سريع: وحدات، منتجات، عملاء…'
                  : 'بحث: وحدات، منتجات، عملاء، موظفون، باركود…'),
        hintStyle: TextStyle(
          color: _textSecondary,
          fontSize: sl.isNarrowWidth ? 12 : 13,
        ),
        isDense: true,
        filled: true,
        fillColor: _isDark
            ? const Color(0xFF1E293B)
            : (useRoyal
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22)
                  : Colors.white),
        border: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.35)
                : AppColors.accentGold.withValues(
                    alpha: _isDark ? 0.4 : 0.28,
                  ),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.28)
                : AppColors.accentGold.withValues(
                    alpha: _isDark ? 0.4 : 0.28,
                  ),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ac.lg,
          borderSide: BorderSide(
            color: useRoyal
                ? royalGold.withValues(alpha: 0.85)
                : AppColors.accentGold,
            width: 1.4,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: sl.isCompactHeight ? 8 : 10,
          horizontal: sl.isNarrowWidth ? 4 : 8,
        ),
      ),
    );

    if (!useRoyal) {
      return Directionality(textDirection: TextDirection.rtl, child: field);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: _royalGoldBorderDecoration(context, radius: ac.rLg),
        child: field,
      ),
    );
  }

  Widget _buildSearchOverlayScrollable() {
    final sl = ScreenLayout.of(context);
    final query = _search.text.text.trim();
    final hasAny =
        _search.tools.isNotEmpty ||
        _search.modules.isNotEmpty ||
        _search.products.isNotEmpty ||
        _search.customers.isNotEmpty ||
        _search.users.isNotEmpty;
    if (!hasAny) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: sl.pageHorizontalGap,
          vertical: 20,
        ),
        child: Text(
          'لا توجد نتائج لـ «$query»',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.4),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.only(
        start: sl.pageHorizontalGap,
        end: sl.pageHorizontalGap,
        top: 12,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_search.tools.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'أدوات وصفحات',
              count: _search.tools.length,
              height: 96,
              itemCount: _search.tools.length,
              itemBuilder: (i) {
                final t = _search.tools[i];
                return _searchHChip(
                  onTap: () => _onResultTap(
                    query: query,
                    navigate: () => widget.onOpen(
                      t.routeId,
                      t.breadcrumbTitle,
                      t.destination,
                    ),
                  ),
                  icon: t.icon,
                  iconColor: t.iconColor,
                  title: t.title,
                  subtitle: t.subtitle ?? 'فتح',
                );
              },
            ),
          if (_search.customers.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'العملاء',
              count: _search.customers.length,
              height: 96,
              itemCount: _search.customers.length,
              itemBuilder: (i) {
                final c = _search.customers[i];
                final sub = [
                  if ((c['phone'] ?? '').toString().isNotEmpty)
                    c['phone'].toString(),
                  if ((c['email'] ?? '').toString().isNotEmpty)
                    c['email'].toString(),
                ].where((s) => s.isNotEmpty).take(2).join(' · ');
                return _searchHChip(
                  onTap: () => _onResultTap(
                    query: query,
                    navigate: () => widget.onOpen(
                      AppContentRoutes.customers,
                      'العملاء',
                      widget.customersDestination,
                    ),
                  ),
                  icon: Icons.person_outline,
                  iconColor: const Color(0xFF0D9488),
                  title: '${c['name'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض العملاء' : sub,
                );
              },
            ),
          if (_search.products.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'المنتجات',
              count: _search.products.length,
              height: 128,
              itemCount: _search.products.length,
              itemBuilder: (i) {
                final p = _search.products[i];
                final sellRaw = p['sell'] as num?;
                final sell = sellRaw != null
                    ? IraqiCurrencyFormat.formatInt(sellRaw)
                    : '—';
                final stockLine = _productSearchStockLine(p);
                return _searchHChip(
                  onTap: () => _onResultTap(
                    query: query,
                    navigate: () => widget.onProductPick(p),
                  ),
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF0D9488),
                  title: '${p['name'] ?? ''}',
                  subtitle: 'بيع $sell د.ع',
                  belowSubtitle: stockLine,
                );
              },
            ),
          if (_search.users.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'الموظفون',
              count: _search.users.length,
              height: 96,
              itemCount: _search.users.length,
              itemBuilder: (i) {
                final u = _search.users[i];
                final sub = [
                  if ((u['role'] ?? '').toString().isNotEmpty)
                    u['role'].toString(),
                  if ((u['email'] ?? '').toString().isNotEmpty)
                    u['email'].toString(),
                ].where((s) => s.isNotEmpty).join(' · ');
                return _searchHChip(
                  onTap: () => _onResultTap(
                    query: query,
                    navigate: () => widget.onOpen(
                      AppContentRoutes.users,
                      'المستخدمين',
                      widget.usersDestination,
                    ),
                  ),
                  icon: Icons.badge_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: '${u['username'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض الموظفين' : sub,
                );
              },
            ),
          if (_search.modules.isNotEmpty && _search.tools.isEmpty)
            _buildHorizontalSearchSection(
              title: 'الوحدات',
              count: _search.modules.length,
              height: 92,
              itemCount: _search.modules.length,
              itemBuilder: (i) {
                final m = _search.modules[i];
                return _searchHChip(
                  onTap: () => _onResultTap(
                    query: query,
                    navigate: () => widget.onOpen(
                      m.routeId,
                      m.breadcrumbTitle,
                      m.destination,
                    ),
                  ),
                  icon: m.icon,
                  iconColor: m.iconColor,
                  title: m.title,
                  subtitle: 'فتح الوحدة',
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSearchSection({
    required String title,
    required int count,
    required double height,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchSectionTitle(title, count),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => itemBuilder(i),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر المخزون تحت السعر في نتائج بحث المنتجات.
  String _productSearchStockLine(Map<String, dynamic> p) {
    if (((p['isService'] as num?)?.toInt() ?? 0) == 1) {
      return 'خدمة فنية';
    }
    final track = (p['trackInventory'] as int?) != 0;
    if (!track) return 'غير متتبّع للمخزون';
    final q = p['qty'];
    if (q == null) return 'المتوفر: —';
    final n = (q as num).toDouble();
    if (n < -1e-9) {
      final qStr = (n % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n)
          : IraqiCurrencyFormat.formatDecimal2(n);
      final soldOver = (n.abs() % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n.abs())
          : IraqiCurrencyFormat.formatDecimal2(n.abs());
      return 'رصيد سالب $qStr — بيع زائد قدره $soldOver عن آخر رصيد';
    }
    if (n.abs() < 1e-9) {
      return 'المتوفر: 0';
    }
    final s = (n % 1).abs() < 1e-6
        ? IraqiCurrencyFormat.formatInt(n)
        : IraqiCurrencyFormat.formatDecimal2(n);
    return 'المتوفر: $s';
  }

  Widget _searchHChip({
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? belowSubtitle,
  }) {
    final ac = context.appCorners;
    return Material(
      color: _isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: ac.md),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.accentGold.withValues(
                alpha: _isDark ? 0.4 : 0.28,
              ),
            ),
            borderRadius: ac.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary,
                        height: 1.2,
                      ),
                    ),
                    if (belowSubtitle != null && belowSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        belowSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSecondary.withValues(alpha: 0.92),
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchSectionTitle(String title, int count) {
    final ac = context.appCorners;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: ac.sm,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearchSuggestions() {
    final sl = ScreenLayout.of(context);
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        sl.pageHorizontalGap,
        12,
        sl.pageHorizontalGap,
        24,
      ),
      children: [
        Text(
          _hint(context),
          textAlign: TextAlign.start,
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
        ),
        if (_search.recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'آخر عمليات البحث',
            textAlign: TextAlign.start,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ..._search.recent.map(
            (q) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, color: _textSecondary),
              title: Text(q, textAlign: TextAlign.start),
              trailing: const Icon(Icons.north_west_rounded, size: 18),
              onTap: () => _search.applyRecent(q),
            ),
          ),
        ],
      ],
    );
  }

  BoxDecoration _royalGoldBorderDecoration(
    BuildContext context, {
    required double radius,
  }) {
    final gold = SaleBrandColors.gold;
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: gold.withValues(alpha: 0.72),
        width: 1.75,
      ),
      boxShadow: const [
        BoxShadow(
          color: AppGlass.goldGlow,
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
      ],
    );
  }
}
