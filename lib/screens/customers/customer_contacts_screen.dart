import 'dart:async' show Timer, unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/customer_record.dart';
import '../../providers/customers_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../utils/customer_phone_launch.dart';
import '../../utils/customer_validation.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../debts/customer_debt_detail_screen.dart';
import 'customer_financial_detail_screen.dart';
import 'customer_form_screen.dart';
import 'customers_screen.dart';

enum _ContactSort {
  nameAsc,
  balanceDesc,
}

/// تصفية جهات الاتصال: الكل أو من عليهم دين/آجل.
enum _ContactFilter {
  all,
  debtOrCreditSale,
}

/// قائمة جهات اتصال العملاء — عرض مضغوط متوافق مع باقي التطبيق.
class CustomerContactsScreen extends StatefulWidget {
  const CustomerContactsScreen({super.key});

  @override
  State<CustomerContactsScreen> createState() => _CustomerContactsScreenState();
}

class _CustomerContactsScreenState extends State<CustomerContactsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;

  _ContactFilter _filter = _ContactFilter.all;
  _ContactSort _sort = _ContactSort.nameAsc;

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;
  Color get _filterBg =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomersProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (!mounted) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _syncSearch();
    });
  }

  void _syncSearch() {
    unawaited(
      context.read<CustomersProvider>().setFilters(
            query: _searchCtrl.text,
            idQuery: '',
            statusArabic: 'الكل',
            sortKey:
                _sort == _ContactSort.balanceDesc ? 'balance_desc' : 'name_asc',
          ),
    );
  }

  List<CustomerRecord> _visible(
    List<CustomerRecord> input,
    Set<int> openDebtIds,
    Map<
            int,
            ({
              int creditInvoices,
              int installmentPlans,
              int openRemainingFils,
            })>
        financeById,
  ) {
    final debtMode = _filter == _ContactFilter.debtOrCreditSale;
    final q = debtMode ? _searchCtrl.text.trim().toLowerCase() : '';
    var list = input.where((c) {
      if (debtMode) {
        // آجل مفتوح فقط — لا رصيد بطاقة موجب وحده.
        final fin = financeById[c.id];
        final hasOpen =
            openDebtIds.contains(c.id) ||
            (fin != null && fin.openRemainingFils > 0);
        if (!hasOpen) return false;
        if (q.isEmpty) return true;
        final name = c.name.toLowerCase();
        final phone = (c.phone ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();

    if (_sort == _ContactSort.balanceDesc) {
      list.sort((a, b) {
        final fa = financeById[a.id]?.openRemainingFils ?? 0;
        final fb = financeById[b.id]?.openRemainingFils ?? 0;
        final da = fa > 0 ? fa / 1000.0 : a.balance.abs();
        final db = fb > 0 ? fb / 1000.0 : b.balance.abs();
        return db.compareTo(da);
      });
    } else if (debtMode) {
      list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return list;
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _syncSearch();
  }

  void _setSort(_ContactSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _syncSearch();
  }

  void _setFilter(_ContactFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    if (filter == _ContactFilter.debtOrCreditSale) {
      unawaited(
        context.read<CustomersProvider>().ensureDebtorsLoaded(),
      );
    }
  }

  Future<void> _openEditor({CustomerRecord? customer}) async {
    final saved = await Navigator.of(context).push<CustomerRecord?>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(existing: customer),
      ),
    );
    if (saved != null && mounted) {
      context.read<CustomersProvider>().onCustomerChanged();
    }
  }

  void _openFinancialDetail(CustomerRecord c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerFinancialDetailScreen(customer: c),
      ),
    );
  }

  void _openAdvancedCustomers() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CustomersScreen(),
      ),
    );
  }

  Future<void> _confirmDelete(CustomerRecord c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف جهة الاتصال'),
        content: Text('حذف «${c.name}» من النظام؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppSemanticColors.danger),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DatabaseHelper().deleteCustomer(c.id);
      CloudSyncService.instance.scheduleSyncSoon();
      context.read<CustomersProvider>().onCustomerChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحذف: $e')),
        );
      }
    }
  }

  Future<void> _dialCustomer(String? raw) async {
    final d = CustomerValidation.normalizePhoneDigits(raw);
    if (d == null || d.length < 7) return;
    final uri = Uri(scheme: 'tel', path: d);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String? raw) async {
    final phone = (raw ?? '').trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رقم هاتف لهذا العميل')),
      );
      return;
    }
    await launchCustomerWhatsApp(context, [phone]);
  }

  void _openDebtPayPage(CustomerRecord c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
          registeredCustomerId: c.id,
        ),
      ),
    );
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

  AppBar _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surfaceContainerHighest,
      foregroundColor: cs.onSurface,
      elevation: 0,
      centerTitle: false,
      title: Text(
        'جهات اتصال العملاء',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: cs.onSurface,
        ),
      ),
      // مجموعة واحدة: إضافة عميل | إدارة العملاء | تحديث
      actions: [
        IconButton(
          tooltip: 'عميل جديد',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          onPressed: () => unawaited(_openEditor()),
        ),
        IconButton(
          tooltip: 'إدارة العملاء الكاملة',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.manage_accounts_outlined),
          onPressed: _openAdvancedCustomers,
        ),
        IconButton(
          tooltip: 'تحديث الشاشة',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => context.read<CustomersProvider>().refresh(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSearchDock() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 600;
        final useGlassBlur = !ScreenLayout.of(context).isHandsetForLayout;
        final ac = context.appCorners;
        const royalGold = AppColors.accentGold;

        Widget dockBody = Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 4,
            vertical: 2,
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([_searchCtrl, _searchFocus]),
            builder: (context, _) {
              final focused = _searchFocus.hasFocus;
              final hasText = _searchCtrl.text.trim().isNotEmpty;
              return TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: isNarrow ? 14 : 15,
                  color: _textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف…',
                  hintStyle: TextStyle(
                    color: _textSecondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: focused ? royalGold : _textSecondary,
                  ),
                  suffixIcon: IconButton(
                    tooltip: hasText ? 'مسح البحث' : null,
                    onPressed: hasText ? _clearSearch : null,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: hasText ? _textSecondary : Colors.transparent,
                    ),
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 12 : 14,
                    vertical: isNarrow ? 12 : 14,
                  ),
                ),
              );
            },
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

        return ListenableBuilder(
          listenable: _searchFocus,
          builder: (context, child) {
            final focused = _searchFocus.hasFocus;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: useGlassBlur
                    ? AppGlass.surfaceTintStrong
                    : _filterBg.withValues(alpha: 0.92),
                border: Border.all(
                  color:
                      focused ? royalGold : royalGold.withValues(alpha: 0.5),
                  width: focused ? 2.0 : 1.0,
                ),
              ),
              child: child,
            );
          },
          child: dockBody,
        );
      },
    );
  }

  Widget _buildFilterStrip(int shown, int debtCount) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                    filter: _ContactFilter.all,
                    label: 'الكل',
                    icon: Icons.people_outline_rounded,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    filter: _ContactFilter.debtOrCreditSale,
                    label: debtCount > 0
                        ? 'عليهم دين ($debtCount)'
                        : 'عليهم دين',
                    icon: Icons.account_balance_wallet_outlined,
                    tooltip: 'فواتير بيع آجل غير مسدّدة فقط.',
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<_ContactSort>(
            tooltip: 'ترتيب',
            initialValue: _sort,
            onSelected: _setSort,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ContactSort.nameAsc,
                child: Text('الاسم (أ-ي)'),
              ),
              PopupMenuItem(
                value: _ContactSort.balanceDesc,
                child: Text('حجم الرصيد'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 20, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '$shown',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required _ContactFilter filter,
    required String label,
    required IconData icon,
    String? tooltip,
  }) {
    final selected = _filter == filter;
    final chip = FilterChip(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppColors.primary : _textSecondary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: selected ? AppColors.primary : _textPrimary,
        ),
      ),
      selected: selected,
      onSelected: (_) => _setFilter(filter),
      selectedColor: AppColors.accentGold.withValues(alpha: 0.22),
      showCheckmark: false,
      side: BorderSide(
        color: selected
            ? AppColors.accentGold
            : _outline.withValues(alpha: 0.45),
        width: selected ? 1.5 : 1,
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
  }

  Widget _buildEmptyState() {
    final noData = context.read<CustomersProvider>().items.isEmpty &&
        _searchCtrl.text.trim().isEmpty;
    final debtEmpty =
        _filter == _ContactFilter.debtOrCreditSale && !noData;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Icon(
            debtEmpty
                ? Icons.account_balance_wallet_outlined
                : Icons.contact_phone_outlined,
            size: 48,
            color: _textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            noData
                ? 'لا توجد جهات اتصال بعد'
                : debtEmpty
                    ? 'لا يوجد عملاء عليهم دين حالياً'
                    : 'لا توجد نتائج مطابقة. غيّر البحث أو أضف عميلاً.',
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

  Widget _contactCard(
    CustomerRecord c, {
    required bool showDebtAmount,
    required int openRemainingFils,
  }) {
    final initial = c.name.isNotEmpty ? c.name.substring(0, 1) : '?';
    final phone = (c.phone?.trim().isNotEmpty == true) ? c.phone!.trim() : null;
    final av = _avatarColor(c.id);
    final debtIqd = openRemainingFils > 0
        ? openRemainingFils / 1000.0
        : (c.balance > 0.01 ? c.balance : 0.0);
    final debtLabel = IraqiCurrencyFormat.formatIqd(debtIqd);

    return Material(
      color: _surface,
      elevation: 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () => _openFinancialDetail(c),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: av.withValues(alpha: 0.18),
                foregroundColor: av,
                child: Text(
                  initial,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    if (phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showDebtAmount)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 2),
                  child: TextButton(
                    onPressed: () => _openDebtPayPage(c),
                    style: TextButton.styleFrom(
                      foregroundColor: AppSemanticColors.warning,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      debtLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'واتساب',
                visualDensity: VisualDensity.compact,
                onPressed: phone == null
                    ? null
                    : () => unawaited(_openWhatsApp(phone)),
                icon: Icon(
                  Icons.chat_rounded,
                  size: 22,
                  color: phone == null
                      ? _textSecondary.withValues(alpha: 0.35)
                      : const Color(0xFF25D366),
                ),
              ),
              IconButton(
                tooltip: 'اتصال',
                visualDensity: VisualDensity.compact,
                onPressed: phone == null
                    ? null
                    : () => unawaited(_dialCustomer(phone)),
                icon: Icon(
                  Icons.phone_outlined,
                  size: 20,
                  color: phone == null
                      ? _textSecondary.withValues(alpha: 0.35)
                      : AppColors.accentBlue,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'إجراءات',
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'edit') _openEditor(customer: c);
                  if (v == 'detail') _openFinancialDetail(c);
                  if (v == 'pay') _openDebtPayPage(c);
                  if (v == 'delete') _confirmDelete(c);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: Text('التفاصيل المالية'),
                  ),
                  if (showDebtAmount)
                    const PopupMenuItem(
                      value: 'pay',
                      child: Text('تسديد الدين'),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('تعديل البيانات'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'حذف',
                      style: TextStyle(color: AppSemanticColors.danger),
                    ),
                  ),
                ],
                icon: Icon(Icons.more_vert, color: _textSecondary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomersProvider>(
      child: _buildSearchDock(),
      builder: (context, prov, searchDock) {
        final debtMode = _filter == _ContactFilter.debtOrCreditSale;
        final loading = debtMode
            ? (prov.isLoadingDebtors && prov.debtorItems.isEmpty)
            : (prov.isLoading &&
                prov.items.isEmpty &&
                _searchCtrl.text.isEmpty);
        final financeById = prov.financeById;
        final openDebtIds = prov.openDebtIds;
        final source = debtMode ? prov.debtorItems : prov.items;
        final visible = _visible(source, openDebtIds, financeById);
        final gap = ScreenLayout.of(context).pageHorizontalGap;
        final debtBadgeCount = openDebtIds.length;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: _pageBg,
            appBar: _buildAppBar(),
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(gap, 10, gap, 0),
                        child: searchDock,
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gap),
                        child: _buildFilterStrip(
                          visible.length,
                          debtBadgeCount,
                        ),
                      ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (!debtMode && n.metrics.extentAfter < 360) {
                              unawaited(prov.loadMore());
                            }
                            return false;
                          },
                          child: CustomScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            slivers: [
                              if (visible.isEmpty)
                                SliverToBoxAdapter(child: _buildEmptyState())
                              else
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    gap,
                                    4,
                                    gap,
                                    24,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) {
                                        final c = visible[i];
                                        final fin = financeById[c.id];
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom:
                                                i == visible.length - 1 ? 0 : 8,
                                          ),
                                          child: _contactCard(
                                            c,
                                            showDebtAmount: _filter ==
                                                _ContactFilter.debtOrCreditSale,
                                            openRemainingFils:
                                                fin?.openRemainingFils ?? 0,
                                          ),
                                        );
                                      },
                                      childCount: visible.length,
                                    ),
                                  ),
                                ),
                              if (prov.isLoadingMore)
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
