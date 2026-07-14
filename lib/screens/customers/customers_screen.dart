import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/customer_validation.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:async' show Timer, unawaited;

import '../../models/customer_record.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_notifications_sheet.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../providers/customers_provider.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/adaptive/master_detail_layout.dart';
import 'package:provider/provider.dart';
import '../debts/customer_debt_detail_screen.dart';
import '../installments/installments_screen.dart';
import 'customer_financial_detail_panel.dart';
import 'customer_financial_detail_screen.dart';
import 'customer_form_screen.dart';

enum _CustomerSort {
  nameAsc,
  nameDesc,
  totalPurchasesDesc,
  balanceDesc,
  dateDesc,
}

// Intents لاختصارات لوحة المفاتيح — يحاكي نمط `invoices_screen.dart` (Golden).
class _NewCustomerIntent extends Intent {
  const _NewCustomerIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _CloseDetailIntent extends Intent {
  const _CloseDetailIntent();
}

class _RefreshCustomersIntent extends Intent {
  const _RefreshCustomersIntent();
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg => Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;

  final Set<int> _selectedIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  int? _hoveredCustomerId;

  static const String _filterStatus = 'الكل';
  static const _CustomerSort _sort = _CustomerSort.nameAsc;

  /// العميل المختار حالياً للعرض في لوحة التفاصيل (MasterDetail).
  /// تنشط فقط على `isWideVariant`؛ على الموبايل يبقى `null` ويتم النفور
  /// إلى صفحة كاملة عبر `Navigator.push`.
  CustomerRecord? _selectedCustomer;
  int? get _selectedCustomerId => _selectedCustomer?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomersProvider>().refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchFocus.canRequestFocus) {
          _searchFocus.requestFocus();
        }
      });
    });
    _searchCtrl.addListener(_onSearchTextChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  void _onSearchTextChanged() {
    if (!mounted) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _syncFilters();
    });
    setState(() {});
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _shortDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('yyyy/MM/dd', 'en').format(d);
  }

  String get _sortKey => switch (_sort) {
    _CustomerSort.nameDesc => 'name_desc',
    _CustomerSort.totalPurchasesDesc => 'total_purchases_desc',
    _CustomerSort.balanceDesc => 'balance_desc',
    _CustomerSort.dateDesc => 'date_desc',
    _ => 'name_asc',
  };

  void _syncFilters() {
    unawaited(
      context.read<CustomersProvider>().setFilters(
        query: _searchCtrl.text,
        idQuery: '',
        statusArabic: _filterStatus,
        sortKey: _sortKey,
      ),
    );
  }

  bool? get _headerCheckboxValue {
    final v = context.read<CustomersProvider>().items;
    if (v.isEmpty) return false;
    var n = 0;
    for (final c in v) {
      if (_selectedIds.contains(c.id)) n++;
    }
    if (n == 0) return false;
    if (n == v.length) return true;
    return null;
  }

  void _toggleSelectAllVisible(bool? checked) {
    setState(() {
      final ids = context
          .read<CustomersProvider>()
          .items
          .map((e) => e.id)
          .toSet();
      if (checked == true) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeWhere((id) => ids.contains(id));
      }
    });
  }

  Future<void> _openEditor({CustomerRecord? customer}) async {
    final saved = await Navigator.of(context).push<CustomerRecord?>(
      MaterialPageRoute(builder: (_) => CustomerFormScreen(existing: customer)),
    );
    if (saved != null && mounted) {
      context.read<CustomersProvider>().onCustomerChanged();
    }
  }

  Future<void> _confirmDelete(CustomerRecord c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف عميل'),
        content: Text('هل تريد حذف «${c.name}»؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppSemanticColors.danger,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DatabaseHelper().deleteCustomer(c.id);
      CloudSyncService.instance.scheduleSyncSoon();
      setState(() => _selectedIds.remove(c.id));
      context.read<CustomersProvider>().onCustomerChanged();
    } catch (e) {
      if (mounted) {
        AppMessenger.error(context, message: 'تعذر الحذف: $e');
      }
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العملاء المحددين'),
        content: Text('سيتم حذف ${_selectedIds.length} عميل. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppSemanticColors.danger,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DatabaseHelper().deleteCustomers(_selectedIds);
      _selectedIds.clear();
      context.read<CustomersProvider>().onCustomerChanged();
    } catch (e) {
      if (mounted) {
        AppMessenger.error(context, message: 'تعذر الحذف: $e');
      }
    }
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'مديون':
        return AppSemanticColors.warning;
      case 'دائن':
        return AppSemanticColors.info;
      default:
        return AppSemanticColors.success;
    }
  }

  Color _avatarColor(int id) {
    final cs = Theme.of(context).colorScheme;
    final colors = <Color>[
      cs.primary,
      cs.secondary,
      cs.tertiary,
      Color.lerp(cs.primary, cs.secondary, 0.45)!,
    ];
    return colors[id % colors.length];
  }

  void _openDebtDetail(CustomerRecord c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            CustomerDebtDetailScreen.fromCustomerId(registeredCustomerId: c.id),
      ),
    );
  }

  void _openInstallmentsForCustomer(CustomerRecord c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InstallmentsScreen(initialSearchQuery: c.name.trim()),
      ),
    );
  }

  /// يفتح تفاصيل العميل: على wide variants يظهر داخل لوحة MasterDetail
  /// (تحديث state)، على الموبايل push كامل.
  void _openCustomerFinancialDetail(CustomerRecord c) {
    final isWide = context.screenLayout.isWideVariant;
    if (isWide) {
      setState(() => _selectedCustomer = c);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerFinancialDetailScreen(customer: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomersProvider>(
      builder: (context, prov, _) {
        final visible = prov.items;
        final total = visible.length;
        final loading = prov.isLoading && visible.isEmpty;

        final gap = ScreenLayout.of(context).pageHorizontalGap;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  const _NewCustomerIntent(),
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                  const _NewCustomerIntent(),
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  const _FocusSearchIntent(),
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  const _FocusSearchIntent(),
              const SingleActivator(LogicalKeyboardKey.escape):
                  const _CloseDetailIntent(),
              const SingleActivator(LogicalKeyboardKey.f5):
                  const _RefreshCustomersIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _NewCustomerIntent: CallbackAction<_NewCustomerIntent>(
                  onInvoke: (_) {
                    unawaited(_openEditor());
                    return null;
                  },
                ),
                _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
                  onInvoke: (_) {
                    if (_searchFocus.canRequestFocus) {
                      _searchFocus.requestFocus();
                    }
                    return null;
                  },
                ),
                _CloseDetailIntent: CallbackAction<_CloseDetailIntent>(
                  onInvoke: (_) {
                    if (_selectedCustomer != null) {
                      setState(() => _selectedCustomer = null);
                    }
                    return null;
                  },
                ),
                _RefreshCustomersIntent:
                    CallbackAction<_RefreshCustomersIntent>(
                  onInvoke: (_) {
                    unawaited(_refreshFromServer());
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: AppInlineToastHost(
                  child: Scaffold(
                  backgroundColor: _pageBg,
                  appBar: _buildAppBar(prov),
                  // الـ Inline Toast يَلتصق فوق أي محتوى عبر `bottomNavigationBar`
                  // (Scaffold يَحجز مساحته دون إغلاقها). يَختفي تلقائياً عند
                  // غياب الـ toast لأن الـ widget يُرجع SizedBox.shrink.
                  bottomNavigationBar: const SafeArea(
                    top: false,
                    child: AppInlineToastBar(),
                  ),
                  body: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(builder: (innerCtx) {
                  final isWide = innerCtx.screenLayout.isWideVariant;
                  final listBody = NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (!prov.hasMore) return false;
                      if (prov.isLoadingMore) return false;
                      if (n.metrics.extentAfter < 420) {
                        unawaited(prov.loadMore());
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      slivers: [
                        // شريط KPIs العام (Golden Pattern §9.2) — يلخّص حالة العملاء
                        // الكلية بصرف النظر عن الفلتر الحالي.
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(gap, 12, gap, 12),
                          sliver: SliverToBoxAdapter(
                            child: _buildUnifiedSearchDock(),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(gap, 12, gap, 24),
                          sliver: total == 0
                              ? SliverToBoxAdapter(child: _buildEmptyState())
                              : SliverToBoxAdapter(
                                  child: LayoutBuilder(
                                    builder: (context, c) {
                                      if (c.maxWidth < 600) {
                                        return const SizedBox.shrink();
                                      }
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: _surface,
                                          borderRadius: AppShape.none,
                                          border: Border.all(
                                            color: _outline.withValues(
                                              alpha: 0.35,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.04,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: _tableHeader(),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        if (total > 0)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(gap, 0, gap, 24),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                i,
                              ) {
                                if (i >= visible.length) return null;
                                return Column(
                                  children: [
                                    if (i > 0)
                                      const SizedBox(height: 10),
                                    _tableRow(
                                      visible[i],
                                      finance: prov.financeById,
                                    ),
                                  ],
                                );
                              }, childCount: visible.length),
                            ),
                          ),
                        if (prov.isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
                  );
                  if (isWide) {
                    return MasterDetailLayout<int>(
                      masterWidth: 480,
                      selectedItemId: _selectedCustomerId ?? -1,
                      masterBuilder: (_, __) => listBody,
                      detailBuilder: (_) => Container(
                        color: Theme.of(innerCtx).scaffoldBackgroundColor,
                        child: CustomerFinancialDetailPanel(
                          customer: _selectedCustomer,
                          onClose: () =>
                              setState(() => _selectedCustomer = null),
                          onEdit: _selectedCustomer == null
                              ? null
                              : () =>
                                  _openEditor(customer: _selectedCustomer),
                        ),
                      ),
                    );
                  }
                  return listBody;
                }),
                ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshFromServer() async {
    await CloudSyncService.instance.syncNow(
      forcePull: true,
      forcePush: true,
      forceImportOnPull: true,
    );
    if (!mounted) return;
    await context.read<CustomersProvider>().refresh();
  }

  AppBar _buildAppBar(CustomersProvider prov) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surfaceContainerHighest,
      foregroundColor: cs.onSurface,
      elevation: 0,
      centerTitle: false,
      title: Text(
        'العملاء',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface),
      ),
      actions: [
        if (_selectedIds.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف المحدد',
            onPressed: _confirmDeleteSelected,
          ),
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: 'إضافة عميل',
          onPressed: () => unawaited(_openEditor()),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: _refreshHint(prov.lastRefreshedAt),
          onPressed: _refreshFromServer,
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'التنبيهات: متأخرات، فواتير آجل، مخزون وأقساط',
          onPressed: () => showAppNotificationsSheet(context),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _refreshHint(DateTime? t) {
    if (t == null) return 'تحديث القائمة من السحابة والمزامنة — F5';
    final secs = DateTime.now().difference(t).inSeconds;
    if (secs < 40) return 'آخر تحديث: الآن تقريباً — F5';
    if (secs < 3600) return 'آخر تحديث: منذ ${secs ~/ 60} دقيقة — F5';
    final h = secs ~/ 3600;
    return 'آخر تحديث: منذ $h ساعة تقريباً — F5';
  }

  Future<void> _dialCustomer(String? raw) async {
    final d = CustomerValidation.normalizePhoneDigits(raw);
    if (d == null || d.length < 7) return;
    final uri = Uri(scheme: 'tel', path: d);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _buildUnifiedSearchDock() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 600;
        final useGlassBlur = !ScreenLayout.of(context).isHandsetForLayout;
        final ac = context.appCorners;
        final focused = _searchFocus.hasFocus;
        const royalGold = AppColors.accentGold;

        Widget dockBody = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              fontSize: isNarrow ? 14 : 15,
              color: _textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم، الهاتف، أو البريد…',
              hintStyle: TextStyle(
                color: _textSecondary.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: focused ? royalGold : _textSecondary,
              ),
              suffixIcon: _searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        _searchCtrl.clear();
                        _syncFilters();
                      },
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 12 : 14,
                vertical: isNarrow ? 14 : 16,
              ),
            ),
          ),
        );

        if (useGlassBlur) {
          dockBody = ClipRRect(
            borderRadius: ac.md,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppGlass.blurSigma * 0.75,
                sigmaY: AppGlass.blurSigma * 0.75,
              ),
              child: dockBody,
            ),
          );
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: useGlassBlur
                ? AppGlass.surfaceTintStrong
                : _filterBg.withValues(alpha: 0.92),
            border: Border.all(
              color: focused ? royalGold : royalGold.withValues(alpha: 0.5),
              width: focused ? 2.0 : 1.0,
            ),
          ),
          child: dockBody,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final noData = context.read<CustomersProvider>().items.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(Icons.groups_2_outlined, size: 56, color: _textSecondary),
          const SizedBox(height: 12),
          Text(
            noData
                ? 'لا يوجد عملاء بعد'
                : 'لا يوجد عملاء يطابقون البحث',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 15),
          ),
          if (noData) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة أول عميل'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: _filterBg.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: _outline.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Checkbox(
              value: _headerCheckboxValue,
              tristate: true,
              activeColor: AppColors.accentGold,
              onChanged: _toggleSelectAllVisible,
            ),
          ),
          const Expanded(
            flex: 3,
            child: Text(
              'العميل',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'الهاتف',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'إجمالي المشتريات',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'الرصيد المستحق',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          const SizedBox(
            width: 88,
            child: Text(
              'الحالة',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _tableRow(
    CustomerRecord c, {
    required Map<int, ({int creditInvoices, int installmentPlans})> finance,
  }) {
    final initial = c.name.isNotEmpty ? c.name.substring(0, 1) : '?';
    final idStr = '#${c.id.toString().padLeft(5, '0')}';
    final phone = (c.phone?.trim().isNotEmpty == true) ? c.phone! : '—';
    final selected = _selectedIds.contains(c.id);
    final av = _avatarColor(c.id);
    final st = c.statusLabel;
    final fin = finance[c.id] ?? (creditInvoices: 0, installmentPlans: 0);

    Widget statusBadge({double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _statusColor(st),
        borderRadius: AppShape.none,
      ),
      child: Text(
        st,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, cnst) {
        final isNarrow = cnst.maxWidth < 600;
        final ac = context.appCorners;

        final avatar = Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.25, -0.35),
              radius: 1.1,
              colors: [
                Color.lerp(av, Colors.white, 0.42)!,
                av,
                Color.lerp(av, Colors.black, 0.28)!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: av.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            initial,
            style: const TextStyle(
              fontFamily: 'Tajawal',
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        );

        // اختصارات الديون/التقسيط — للعرض الواسع فقط؛ القائمة الضيقة تبقى نظيفة.
        final financePills = <Widget>[
          if (!isNarrow && fin.creditInvoices > 0)
            _CustomerActionPill(
              icon: Icons.account_balance_wallet_rounded,
              label: 'ديون ×${fin.creditInvoices}',
              color: AppSemanticColors.warning,
              tooltip: 'فتح ديون الآجل المرتبطة',
              onPressed: () => _openDebtDetail(c),
            ),
          if (!isNarrow && fin.installmentPlans > 0)
            _CustomerActionPill(
              icon: Icons.event_repeat_rounded,
              label: 'تقسيط ×${fin.installmentPlans}',
              color: AppSemanticColors.info,
              tooltip: 'فتح خطط التقسيط',
              onPressed: () => _openInstallmentsForCustomer(c),
            ),
        ];

        final nameBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isNarrow && st != 'مميز') ...[
                  const SizedBox(width: 6),
                  statusBadge(fontSize: 10.5),
                ],
              ],
            ),
            const SizedBox(height: 4),
            if (isNarrow) ...[
              Row(
                children: [
                  if (c.phone?.trim().isNotEmpty == true) ...[
                    Icon(Icons.phone_rounded, size: 12.5, color: _textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        phone,
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    Text(
                      'لا يوجد هاتف',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary.withValues(alpha: 0.75),
                      ),
                    ),
                  if (c.balance.abs() > 0.01) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 12.5,
                      color: _statusColor(st),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      st == 'مديون'
                          ? 'دين: ${IraqiCurrencyFormat.formatIqd(c.balance)}'
                          : 'دائن: ${IraqiCurrencyFormat.formatIqd(c.balance.abs())}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(st),
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              Text(
                '$idStr · ولاء ${c.loyaltyPoints} · ${_shortDate(c.createdAt)}',
                style: TextStyle(fontSize: 11.5, color: _textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
              if (financePills.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: financePills),
              ],
            ],
          ],
        );

        // قائمة overflow — تحوي فقط الإجراءات النادرة بعد ترقية المتكرّرة
        // إلى Card Action Pills (اتصال/ديون/تقسيط ⇐ Pills في البطاقة).
        final popup = SizedBox(
          width: 40,
          height: 36,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, color: _textSecondary, size: 22),
            tooltip: 'المزيد',
            onSelected: (v) {
              if (v == 'view') _openCustomerFinancialDetail(c);
              if (v == 'edit') _openEditor(customer: c);
              if (v == 'delete') _confirmDelete(c);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view', child: Text('عرض التفاصيل')),
              const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'حذف',
                  style: TextStyle(color: AppSemanticColors.danger),
                ),
              ),
            ],
          ),
        );

        final checkbox = SizedBox(
          width: 42,
          child: Checkbox(
            value: selected,
            activeColor: AppColors.accentGold,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedIds.add(c.id);
                } else {
                  _selectedIds.remove(c.id);
                }
              });
            },
          ),
        );

        // إبراز البطاقة المختارة في وضع MasterDetail (الديسكتوب) — يميّز البطاقة
        // النشطة في اللوحة اليسرى عن البطاقات الأخرى. يبقى تأثير bulk-select
        // (selected) منفصلاً، فإذا اجتمع الاثنان نُعطي الأولوية للـ MasterDetail.
        final hovered = _hoveredCustomerId == c.id;
        final isOpenedInPanel =
            _selectedCustomerId != null && _selectedCustomerId == c.id;
        return Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isOpenedInPanel
                  ? AppColors.accentGold.withValues(alpha: 0.12)
                  : (hovered
                      ? AppColors.accentGold.withValues(alpha: 0.05)
                      : (selected
                          ? AppColors.accentGold.withValues(alpha: 0.06)
                          : _surface)),
              border: Border.all(
                color: isOpenedInPanel
                    ? AppColors.accentGold
                    : (hovered
                        ? AppColors.accentGold.withValues(alpha: 0.85)
                        : AppColors.accentGold.withValues(alpha: 0.35)),
                width: isOpenedInPanel ? 2.0 : (hovered ? 1.5 : 1.0),
              ),
              boxShadow: isOpenedInPanel
                  ? [
                      BoxShadow(
                        color: AppColors.accentGold.withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : (hovered
                      ? [
                          BoxShadow(
                            color: AppColors.accentGold.withValues(alpha: 0.22),
                            blurRadius: 10,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _openCustomerFinancialDetail(c),
                onHover: (isHovering) {
                  setState(() {
                    _hoveredCustomerId = isHovering ? c.id : null;
                  });
                },
                hoverColor: Colors.transparent, // الخلفية مدارة بـ AnimatedContainer
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 6 : 8,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      checkbox,
                      if (isNarrow) ...[
                        avatar,
                        const SizedBox(width: 10),
                        Expanded(child: nameBlock),
                        popup,
                      ] else ...[
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              avatar,
                              const SizedBox(width: 10),
                              Expanded(child: nameBlock),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Tooltip(
                            message: 'اتصال',
                            child: InkWell(
                              onTap: () => _dialCustomer(c.phone),
                              borderRadius: AppShape.none,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.call_outlined,
                                      size: 16,
                                      color: _primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        phone,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            IraqiCurrencyFormat.formatIqd(c.purchaseTotalApprox),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c.balance.abs() < 0.01
                                    ? 'لا ديون'
                                    : (c.balance > 0.01
                                          ? 'دين: ${IraqiCurrencyFormat.formatIqd(c.balance)}'
                                          : 'دائن: ${IraqiCurrencyFormat.formatIqd(-c.balance)}'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.balance.abs() < 0.01
                                      ? AppSemanticColors.success
                                      : (c.balance > 0.01
                                            ? AppSemanticColors.danger
                                            : AppSemanticColors.info),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 88,
                          child: Center(
                            child: st != 'مميز'
                                ? statusBadge()
                                : const SizedBox.shrink(),
                          ),
                        ),
                        popup,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Card Action Pill ──────────────────────────────────────────────────────────
/// زر فعل صغير (Pill) يظهر داخل بطاقة العميل بدلاً من سهم التنقل العام.
///
/// يلتزم نمط `_ReturnActionPill` في `invoices_screen.dart` (Golden §9.2.1):
/// - lozenge مدور (أيقونة + نص قصير).
/// - لون دلالي (`AppSemanticColors.*` أو `cs.primary`).
/// - يوقف انتشار الحدث حتى لا يُفعّل onTap الأصلي للبطاقة.
class _CustomerActionPill extends StatelessWidget {
  const _CustomerActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        hoverColor: AppColors.accentGold.withValues(alpha: 0.12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

// ── شريط الإحصاءات (KPIs) ─────────────────────────────────────────────────────
/// شريط إحصاءات قابل للتجاوب مع `DeviceVariant` — يعرض 4 KPIs للعملاء.
///
/// يتبع نمط `_StatsBar` في `invoices_screen.dart` (Golden):
/// - على `phoneVariant` أو `maxWidth < 600`: شبكة 2×2.
/// - على tabletLG+: صف أفقي بـ 4 chips.