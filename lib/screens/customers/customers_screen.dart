import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/customer_validation.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:async' show Timer, unawaited;

import '../../models/customer_record.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_notifications_sheet.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../providers/customers_provider.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/inputs/app_input.dart';
import 'package:provider/provider.dart';
import '../debts/customer_debt_detail_screen.dart';
import '../installments/installments_screen.dart';
import 'customer_financial_detail_screen.dart';
import 'customer_form_screen.dart';

enum _CustomerSort {
  nameAsc,
  nameDesc,
  totalPurchasesDesc,
  balanceDesc,
  dateDesc,
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

  String _filterStatus = 'الكل';
  _CustomerSort _sort = _CustomerSort.nameAsc;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomersProvider>().refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchFocus.canRequestFocus) {
          _searchFocus.requestFocus();
        }
      });
    });
    _searchCtrl.addListener(() {
      if (!mounted) return;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _syncFilters();
      });
      setState(() {});
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final hw = HardwareKeyboard.instance;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.keyN &&
        hw.isControlPressed &&
        !hw.isAltPressed &&
        !hw.isMetaPressed) {
      unawaited(_openEditor());
      return true;
    }
    if (k == LogicalKeyboardKey.keyF && hw.isControlPressed) {
      if (_searchFocus.canRequestFocus) _searchFocus.requestFocus();
      return true;
    }
    if (k == LogicalKeyboardKey.f5) {
      unawaited(_refreshFromServer());
      return true;
    }
    return false;
  }

  String _formatMoney(double v) {
    final fmt = NumberFormat('#,##0.##', 'en');
    return fmt.format(v);
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر الحذف: $e')));
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر الحذف: $e')));
      }
    }
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'مديون':
        return const Color(0xFFFF9800);
      case 'دائن':
        return const Color(0xFF7E57C2);
      default:
        return const Color(0xFF00897B);
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

  void _openCustomerFinancialDetail(CustomerRecord c) {
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
          child: Scaffold(
            backgroundColor: _pageBg,
            appBar: _buildAppBar(prov),
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
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
                        // شريط التحديد + العدد + إضافة — يطوى مع التمرير (مثل رأس الفواتير)
                        SliverToBoxAdapter(child: _buildToolbar(prov)),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _StickyStatusChipsDelegate(
                            background: _surface,
                            outline: _outline,
                            tabCounts: prov.tabCounts,
                            selectedStatus: _filterStatus,
                            onSelected: (s) {
                              setState(() => _filterStatus = s);
                              _syncFilters();
                            },
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(gap, 0, gap, 12),
                          sliver: SliverToBoxAdapter(
                            child: _buildFiltersCard(),
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
                                      Divider(
                                        height: 1,
                                        color: _outline.withValues(alpha: 0.35),
                                      ),
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
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'العملاء',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      actions: [
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

  Widget _buildToolbar(CustomersProvider prov) {
    final total = prov.items.length;
    final sel = _selectedIds.length;
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 600;
        return Material(
          color: _surface,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 8 : 12,
              vertical: 10,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _headerCheckboxValue,
                  tristate: true,
                  activeColor: _primary,
                  onChanged: _toggleSelectAllVisible,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    sel == 0
                        ? (isNarrow
                              ? 'إجمالي: ${prov.totalCustomersInDb} · معروض: ${prov.matchingCount}'
                              : 'إجمالي العملاء: ${prov.totalCustomersInDb} | معروض: ${prov.matchingCount}')
                        : (isNarrow
                              ? 'محدد: $sel / $total'
                              : 'محدد: $sel — المعروض في الصفحة: $total'),
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sel > 0) ...[
                  if (isNarrow)
                    IconButton(
                      tooltip: 'حذف المحدد',
                      onPressed: _confirmDeleteSelected,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    )
                  else
                    TextButton.icon(
                      onPressed: _confirmDeleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('حذف المحدد'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  const SizedBox(width: 4),
                ],
                if (isNarrow)
                  FilledButton(
                    onPressed: () => _openEditor(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppShape.none,
                      ),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 20,
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppShape.none,
                      ),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                    label: const Text(
                      'إضافة عميل',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ملاحظة: شرائح الحالة تُبنى داخل SliverPersistentHeaderDelegate لتجنب
  // إعادة استخدام عناصر (Elements) بشكل غير متوقع بعد hot restart.

  Widget _buildFiltersCard() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 600;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'بحث وتصفية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ابحث بالاسم أو الهاتف أو البريد. مبيعات الدين والتقسيط تُربط بالعميل من شاشة البيع.',
              style: TextStyle(fontSize: 12.5, color: _textSecondary),
            ),
          ],
        );

        final sortBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ترتيب العرض',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: AppShape.none,
                border: Border.all(color: _outline.withValues(alpha: 0.55)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_CustomerSort>(
                  isExpanded: true,
                  value: _sort,
                  items: const [
                    DropdownMenuItem(
                      value: _CustomerSort.nameAsc,
                      child: Text('الاسم (أ-ي)'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerSort.nameDesc,
                      child: Text('الاسم (ي-أ)'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerSort.totalPurchasesDesc,
                      child: Text('الأكثر شراءً'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerSort.balanceDesc,
                      child: Text('الديون الأكبر'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerSort.dateDesc,
                      child: Text('الأحدث تسجيلاً'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _sort = v);
                    _syncFilters();
                  },
                ),
              ),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.all(isNarrow ? 12 : 16),
          decoration: BoxDecoration(
            color: _filterBg,
            borderRadius: AppShape.none,
            border: Border.all(color: _outline.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isNarrow) ...[
                header,
                const SizedBox(height: 12),
                sortBlock,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    SizedBox(width: 220, child: sortBlock),
                  ],
                ),
              const SizedBox(height: 14),
              AppInput(
                label: 'البحث',
                subtitle:
                    'الإدخال يُطبَّق تلقائياً خلال جزء ثانٍ — Enter أو زر التطبيق لتحسين الوضوح. اختصار: Ctrl+F',
                hint: 'ابحث بالاسم أو رقم الهاتف أو البريد…',
                controller: _searchCtrl,
                focusNode: _searchFocus,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        onPressed: () {
                          _searchCtrl.clear();
                          _syncFilters();
                        },
                        icon: const Icon(Icons.close),
                      ),
                onFieldSubmitted: (_) => _syncFilters(),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      _syncFilters();
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('تطبيق البحث'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textPrimary,
                      side: BorderSide(color: _outline),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppShape.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _searchCtrl.clear();
                        _filterStatus = 'الكل';
                        _sort = _CustomerSort.nameAsc;
                      });
                      _syncFilters();
                    },
                    child: Text(
                      'مسح التصفية',
                      style: TextStyle(color: _primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
                : 'لا يوجد عملاء يطابقون البحث أو التصفية',
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
      decoration: BoxDecoration(color: _filterBg),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Checkbox(
              value: _headerCheckboxValue,
              tristate: true,
              activeColor: _primary,
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

        final avatar = Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: av, borderRadius: AppShape.none),
          child: Text(
            initial,
            style: TextStyle(
              color: ThemeData.estimateBrightnessForColor(av) == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        );

        final financeChips = [
          if (fin.creditInvoices > 0)
            ActionChip(
              label: Text(
                'بيع آجل ×${fin.creditInvoices}',
                style: const TextStyle(fontSize: 11),
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onPressed: () => _openDebtDetail(c),
            ),
          if (fin.installmentPlans > 0)
            ActionChip(
              label: Text(
                'تقسيط ×${fin.installmentPlans}',
                style: const TextStyle(fontSize: 11),
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
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
                      fontSize: 14,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isNarrow) ...[
                  const SizedBox(width: 6),
                  statusBadge(fontSize: 10.5),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$idStr · ولاء ${c.loyaltyPoints} · ${_shortDate(c.createdAt)}',
              style: TextStyle(fontSize: 11.5, color: _textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
            if (isNarrow) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone_rounded, size: 13, color: _textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      phone,
                      style: TextStyle(fontSize: 12, color: _textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 13,
                    color: _textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatMoney(c.balance),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ],
            if (financeChips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: financeChips),
            ],
          ],
        );

        final popup = SizedBox(
          width: 40,
          height: 36,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, color: _textSecondary, size: 22),
            onSelected: (v) {
              if (v == 'view') _openCustomerFinancialDetail(c);
              if (v == 'edit') _openEditor(customer: c);
              if (v == 'call') unawaited(_dialCustomer(c.phone));
              if (v == 'delete') _confirmDelete(c);
              if (v == 'debt') _openDebtDetail(c);
              if (v == 'inst') _openInstallmentsForCustomer(c);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view', child: Text('عرض')),
              const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
              const PopupMenuItem(value: 'call', child: Text('اتصال')),
              const PopupMenuItem(
                value: 'debt',
                child: Text('ديون الآجل المرتبطة'),
              ),
              const PopupMenuItem(value: 'inst', child: Text('خطط التقسيط')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text('حذف', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        final checkbox = SizedBox(
          width: 42,
          child: Checkbox(
            value: selected,
            activeColor: _primary,
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

        return Material(
          color: selected ? _primary.withValues(alpha: 0.08) : _surface,
          child: InkWell(
            onTap: () => _openCustomerFinancialDetail(c),
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
                                  ? const Color(0xFF2E7D32)
                                  : (c.balance > 0.01
                                        ? Colors.red.shade800
                                        : const Color(0xFF7E57C2)),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 88, child: Center(child: statusBadge())),
                    popup,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── شريحة الحالة Sticky أعلى القائمة ─────────────────────────────────────────
class _StickyStatusChipsDelegate extends SliverPersistentHeaderDelegate {
  _StickyStatusChipsDelegate({
    required this.background,
    required this.outline,
    required this.tabCounts,
    required this.selectedStatus,
    required this.onSelected,
  });

  final Color background;
  final Color outline;
  final ({int all, int indebted, int creditor, int distinguished}) tabCounts;
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  @override
  double get minExtent => 49;

  @override
  double get maxExtent => 49;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return SizedBox.expand(
      child: Material(
        color: background,
        elevation: overlapsContent ? 2 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        child: _StatusChipsStrip(
          background: background,
          outline: outline,
          tabCounts: tabCounts,
          selectedStatus: selectedStatus,
          onSelected: onSelected,
          primary: primary,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyStatusChipsDelegate oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.outline != outline ||
        oldDelegate.tabCounts.all != tabCounts.all ||
        oldDelegate.tabCounts.indebted != tabCounts.indebted ||
        oldDelegate.tabCounts.creditor != tabCounts.creditor ||
        oldDelegate.tabCounts.distinguished != tabCounts.distinguished ||
        oldDelegate.selectedStatus != selectedStatus ||
        oldDelegate.onSelected != onSelected;
  }
}

class _StatusChipsStrip extends StatelessWidget {
  const _StatusChipsStrip({
    required this.background,
    required this.outline,
    required this.tabCounts,
    required this.selectedStatus,
    required this.onSelected,
    this.primary,
  });

  final Color background;
  final Color outline;
  final ({int all, int indebted, int creditor, int distinguished}) tabCounts;
  final String selectedStatus;
  final ValueChanged<String> onSelected;
  final Color? primary;

  int _badgeForLabel(String label) => switch (label) {
    'الكل' => tabCounts.all,
    'مديون' => tabCounts.indebted,
    'دائن' => tabCounts.creditor,
    _ => tabCounts.distinguished,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectivePrimary = primary ?? cs.primary;
    const statusOptions = ['الكل', 'مديون', 'دائن', 'مميز'];

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ix = statusOptions.indexOf(selectedStatus);
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (ix <= 0) return KeyEventResult.ignored;
          onSelected(statusOptions[ix - 1]);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (ix < 0 || ix >= statusOptions.length - 1) {
            return KeyEventResult.ignored;
          }
          onSelected(statusOptions[ix + 1]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          border: Border(
            bottom: BorderSide(color: outline.withValues(alpha: 0.35)),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in statusOptions) ...[
                FilterChip(
                  padding: EdgeInsets.zero,
                  label: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s),
                        const SizedBox(width: 6),
                        _TabCountBadge(
                          count: _badgeForLabel(s),
                          urgentRed: s == 'مديون',
                          goldAccent: s == 'مميز',
                          fallback: effectivePrimary,
                        ),
                      ],
                    ),
                  ),
                  selected: selectedStatus == s,
                  onSelected: (_) => onSelected(s),
                  selectedColor: effectivePrimary.withValues(alpha: 0.18),
                  checkmarkColor: effectivePrimary,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppShape.none,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TabCountBadge extends StatelessWidget {
  const _TabCountBadge({
    required this.count,
    required this.fallback,
    this.urgentRed = false,
    this.goldAccent = false,
  });

  final int count;
  final Color fallback;
  final bool urgentRed;
  final bool goldAccent;

  @override
  Widget build(BuildContext context) {
    var bg = fallback.withValues(alpha: 0.82);
    if (urgentRed) bg = const Color(0xFFB91C1C);
    if (goldAccent && !urgentRed) bg = const Color(0xFFC6A032);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
