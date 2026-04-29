import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/installment.dart';
import '../../models/invoice.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';
import 'installment_details_screen.dart';

final _numFmt = NumberFormat('#,##0', 'en');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

enum _PlanFilter { all, active, overdue, settled }

_PlanFilter _planFilterFromTabIndex(int i) {
  switch (i.clamp(0, 3)) {
    case 1:
      return _PlanFilter.active;
    case 2:
      return _PlanFilter.overdue;
    case 3:
      return _PlanFilter.settled;
    default:
      return _PlanFilter.all;
  }
}

/// ملخص أصناف الفاتورة لعرضه على بطاقة الخطة.
String _formatInvoiceItemsBrief(Invoice? inv) {
  if (inv == null || inv.items.isEmpty) {
    return 'لا توجد أصناف مسجّلة في الفاتورة';
  }
  final items = inv.items;
  String trimName(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return 'صنف';
    return n.length > 40 ? '${n.substring(0, 39)}…' : n;
  }

  if (items.length == 1) {
    final it = items.first;
    final q = it.quantity;
    final nm = trimName(it.productName);
    return q == 1 ? nm : '$nm × ${_numFmt.format(q)}';
  }
  final a = trimName(items[0].productName);
  final b = trimName(items[1].productName);
  if (items.length == 2) return '$a، $b';
  return '$a، $b + ${_numFmt.format(items.length - 2)} صنف';
}

/// قائمة خطط التقسيط مع تصفية وبحث وملخص أعلى الصفحة.
class InstallmentsScreen extends StatefulWidget {
  const InstallmentsScreen({super.key, this.initialSearchQuery});

  /// يملأ حقل البحث (مثلاً عند الانتقال من بطاقة عميل).
  final String? initialSearchQuery;

  @override
  State<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends State<InstallmentsScreen>
    with SingleTickerProviderStateMixin {
  static const _tabLabels = ['الكل', 'نشطة', 'متأخرة', 'مكتملة'];

  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _search = TextEditingController();

  List<InstallmentPlan> _plans = [];

  /// ملخص منتجات الفاتورة لكل خطة (مفتاح: id الخطة).
  Map<int, String> _productLineByPlanId = {};
  bool _loading = true;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {});
      }
    });
    final preset = widget.initialSearchQuery?.trim();
    if (preset != null && preset.isNotEmpty) {
      _search.text = preset;
    }
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _db.syncMissingInstallmentPlansFromInvoices();
    final plans = await _db.getAllInstallmentPlans();
    final lines = <int, String>{};
    await Future.wait(
      plans.map((p) async {
        final pid = p.id;
        if (pid == null || p.invoiceId <= 0) return;
        final inv = await _db.getInvoiceById(p.invoiceId);
        lines[pid] = _formatInvoiceItemsBrief(inv);
      }),
    );
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _productLineByPlanId = lines;
      _loading = false;
    });
  }

  Future<void> _refreshFromServer() async {
    await CloudSyncService.instance.syncNow(
      forcePull: true,
      forcePush: true,
      forceImportOnPull: true,
    );
    if (!mounted) return;
    await _load();
  }

  static bool _isOverdue(InstallmentPlan p) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    for (final i in p.installments) {
      if (!i.paid) {
        final d = DateTime(i.dueDate.year, i.dueDate.month, i.dueDate.day);
        if (d.isBefore(start)) return true;
      }
    }
    return false;
  }

  static double _remaining(InstallmentPlan p) =>
      (p.totalAmount - p.paidAmount).clamp(0.0, double.infinity);

  static bool _isSettled(InstallmentPlan p) => _remaining(p) < 0.5;

  List<InstallmentPlan> _filteredListFor(
    _PlanFilter filter, {
    String? searchOverride,
  }) {
    var list = List<InstallmentPlan>.from(_plans);
    final q = (searchOverride ?? _search.text).trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final pid = p.id;
        final prod = pid != null
            ? (_productLineByPlanId[pid] ?? '').toLowerCase()
            : '';
        return p.customerName.toLowerCase().contains(q) ||
            (p.id?.toString().contains(q) ?? false) ||
            p.invoiceId.toString().contains(q) ||
            prod.contains(q);
      }).toList();
    }
    switch (filter) {
      case _PlanFilter.all:
        break;
      case _PlanFilter.active:
        list = list.where((p) => !_isSettled(p)).toList();
        break;
      case _PlanFilter.overdue:
        list = list.where((p) => _isOverdue(p) && !_isSettled(p)).toList();
        break;
      case _PlanFilter.settled:
        list = list.where(_isSettled).toList();
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gap = ScreenLayout.of(context).pageHorizontalGap;

    if (_loading) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text(
              'خطط التقسيط',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: null,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final tabFilter = _planFilterFromTabIndex(_tabs.index);
    final filtered = _filteredListFor(tabFilter);
    final tabOnly = _filteredListFor(tabFilter, searchOverride: '');
    final listScope = filtered.length != tabOnly.length;

    final totalDebt = _plans.fold<double>(0, (s, p) => s + _remaining(p));
    final overdueCount = _plans
        .where((p) => _isOverdue(p) && !_isSettled(p))
        .length;
    final activeCount = _plans.where((p) => !_isSettled(p)).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'خطط التقسيط',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refreshFromServer,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(gap, 12, gap, 8),
                    child: _InfoBanner(colorScheme: cs),
                  ),
                  _InstallmentStatsBar(
                    totalDebt: totalDebt,
                    activePlans: activeCount,
                    overduePlans: overdueCount,
                    settledPlans: _plans.where(_isSettled).length,
                    colorScheme: cs,
                    tabController: _tabs,
                  ),
                  _InstallmentSearchBar(controller: _search, colorScheme: cs),
                  if (listScope)
                    Padding(
                      padding: EdgeInsets.fromLTRB(gap, 6, gap, 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'القائمة: ${filtered.length} من ${tabOnly.length} خطة في «${_tabLabels[_tabs.index]}» (بحث)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyInstallmentsTabBarDelegate(
                tabBar: _buildInstallmentTabBar(cs),
                backgroundColor: cs.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(
              _tabLabels.length,
              (tabIdx) => _InstallmentPlansListTabBody(
                plans: _filteredListFor(_planFilterFromTabIndex(tabIdx)),
                productLines: _productLineByPlanId,
                colorScheme: cs,
                isDark: isDark,
                onRefresh: _load,
                onOpenPlan: (plan) async {
                  final id = plan.id;
                  if (id == null) return;
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InstallmentDetailsScreen(planId: id),
                    ),
                  );
                  await _load();
                },
                emptyHasPlans: _plans.isNotEmpty,
                filterKind: _planFilterFromTabIndex(tabIdx),
                hasSearchText: _search.text.trim().isNotEmpty,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallmentTabBar(ColorScheme cs) {
    final narrow = ScreenLayout.of(context).isNarrowWidth;
    return Container(
      color: cs.surface,
      child: TabBar(
        controller: _tabs,
        onTap: (_) => setState(() {}),
        isScrollable: true,
        labelColor: cs.secondary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.secondary,
        indicatorWeight: 3,
        labelStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: narrow ? 12 : 13,
        ),
        unselectedLabelStyle: TextStyle(fontSize: narrow ? 12 : 13),
        tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
      ),
    );
  }
}

class _StickyInstallmentsTabBarDelegate extends SliverPersistentHeaderDelegate {
  _StickyInstallmentsTabBarDelegate({
    required this.tabBar,
    required this.backgroundColor,
  });

  final Widget tabBar;
  final Color backgroundColor;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: backgroundColor,
      elevation: overlapsContent ? 2 : 0,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyInstallmentsTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// شريط إحصاءات بنفس أسلوب قائمة الفواتير — الضغط ينتقل للتبويب المطابق.
class _InstallmentStatsBar extends StatelessWidget {
  const _InstallmentStatsBar({
    required this.totalDebt,
    required this.activePlans,
    required this.overduePlans,
    required this.settledPlans,
    required this.colorScheme,
    required this.tabController,
  });

  final double totalDebt;
  final int activePlans;
  final int overduePlans;
  final int settledPlans;
  final ColorScheme colorScheme;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(gap, 4, gap, 12),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 380) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InstStatChip(
                        label: 'متبقي الكل',
                        value: '${_numFmt.format(totalDebt)} د.ع',
                        color: cs.primary,
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: () => tabController.animateTo(0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InstStatChip(
                        label: 'خطط نشطة',
                        value: '$activePlans',
                        color: const Color(0xFF0E7490),
                        icon: Icons.schedule_rounded,
                        onTap: () => tabController.animateTo(1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InstStatChip(
                        label: 'متأخرة',
                        value: '$overduePlans',
                        color: overduePlans > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFF59E0B),
                        icon: Icons.warning_amber_rounded,
                        onTap: () => tabController.animateTo(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InstStatChip(
                        label: 'مكتملة',
                        value: '$settledPlans',
                        color: const Color(0xFF15803D),
                        icon: Icons.check_circle_outline_rounded,
                        onTap: () => tabController.animateTo(3),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              _InstStatChip(
                label: 'متبقي الكل',
                value: '${_numFmt.format(totalDebt)} د.ع',
                color: cs.primary,
                icon: Icons.account_balance_wallet_outlined,
                onTap: () => tabController.animateTo(0),
              ),
              const SizedBox(width: 8),
              _InstStatChip(
                label: 'خطط نشطة',
                value: '$activePlans',
                color: const Color(0xFF0E7490),
                icon: Icons.schedule_rounded,
                onTap: () => tabController.animateTo(1),
              ),
              const SizedBox(width: 8),
              _InstStatChip(
                label: 'متأخرة',
                value: '$overduePlans',
                color: overduePlans > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFF59E0B),
                icon: Icons.warning_amber_rounded,
                onTap: () => tabController.animateTo(2),
              ),
              const SizedBox(width: 8),
              _InstStatChip(
                label: 'مكتملة',
                value: '$settledPlans',
                color: const Color(0xFF15803D),
                icon: Icons.check_circle_outline_rounded,
                onTap: () => tabController.animateTo(3),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InstStatChip extends StatelessWidget {
  const _InstStatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShape.none,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: AppShape.none,
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallmentSearchBar extends StatelessWidget {
  const _InstallmentSearchBar({
    required this.controller,
    required this.colorScheme,
  });

  final TextEditingController controller;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            textDirection: TextDirection.rtl,
            style: TextStyle(color: cs.onSurface),
            cursorColor: cs.primary,
            decoration: InputDecoration(
              hintText: 'بحث: عميل، منتج، رقم خطة، رقم فاتورة…',
              hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.65),
              border: OutlineInputBorder(
                borderRadius: AppShape.none,
                borderSide: BorderSide.none,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'مسح البحث',
                      onPressed: controller.clear,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _InstallmentPlansListTabBody extends StatelessWidget {
  const _InstallmentPlansListTabBody({
    required this.plans,
    required this.productLines,
    required this.colorScheme,
    required this.isDark,
    required this.onRefresh,
    required this.onOpenPlan,
    required this.emptyHasPlans,
    required this.filterKind,
    required this.hasSearchText,
  });

  final List<InstallmentPlan> plans;
  final Map<int, String> productLines;
  final ColorScheme colorScheme;
  final bool isDark;
  final Future<void> Function() onRefresh;
  final Future<void> Function(InstallmentPlan plan) onOpenPlan;
  final bool emptyHasPlans;
  final _PlanFilter filterKind;
  final bool hasSearchText;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    if (plans.isEmpty) {
      return RefreshIndicator(
        color: cs.primary,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.42,
              child: _EmptyState(
                hasPlans: emptyHasPlans,
                colorScheme: cs,
                filterActive: filterKind != _PlanFilter.all || hasSearchText,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: cs.primary,
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        itemCount: plans.length,
        itemBuilder: (_, i) {
          final plan = plans[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanListTile(
              plan: plan,
              productSummary: plan.id != null ? productLines[plan.id!] : null,
              colorScheme: cs,
              isDark: isDark,
              onTap: () => onOpenPlan(plan),
            ),
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final ColorScheme colorScheme;
  const _InfoBanner({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: ScreenLayout.of(context).pageHorizontalGap,
          end: ScreenLayout.of(context).pageHorizontalGap,
          top: 14,
          bottom: 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تُنشأ خطة لكل فاتورة نوعها «تقسيط» (حتى لو المقدّم = الإجمالي). التسديد من تفاصيل الخطة يظهر في الصندوق. المقدّم والجدولة: الأقساط ← إعدادات تقسيط.',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanListTile extends StatelessWidget {
  final InstallmentPlan plan;
  final String? productSummary;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  const _PlanListTile({
    required this.plan,
    required this.productSummary,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  /// خط صريح (Tajawal) — دمج [bodyMedium] على الويب أحياناً يُفقد الرسم مع RTL/طبقات Ink.
  static TextStyle _planTextStyle(
    BuildContext context, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double height = 1.25,
  }) {
    return TextStyle(
      fontFamily: 'Tajawal',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleC = isDark ? const Color(0xFFF8FAFC) : colorScheme.onSurface;
    final mutedC = isDark
        ? const Color(0xFF94A3B8)
        : colorScheme.onSurfaceVariant;
    final badgeC = isDark ? const Color(0xFF38BDF8) : colorScheme.tertiary;
    final chevronC = isDark ? const Color(0xFF64748B) : colorScheme.outline;
    final accentRem = isDark ? const Color(0xFF38BDF8) : AppColors.accent;
    final rem = _InstallmentsScreenState._remaining(plan);
    final settled = _InstallmentsScreenState._isSettled(plan);
    final overdue = _InstallmentsScreenState._isOverdue(plan) && !settled;

    Installment? nextDue;
    for (final i in plan.installments) {
      if (!i.paid) {
        nextDue = i;
        break;
      }
    }

    final statusColor = overdue
        ? const Color(0xFFDC2626)
        : (settled ? const Color(0xFF15803D) : const Color(0xFF3B82F6));
    final statusLabel = settled ? 'مكتملة' : (overdue ? 'متأخرة' : 'نشطة');

    final fill = isDark ? AppColors.cardDark : colorScheme.surface;
    final r = BorderRadius.circular(12);
    final ratioRaw = plan.totalAmount > 1e-6
        ? (plan.paidAmount / plan.totalAmount).clamp(0.0, 1.0)
        : 0.0;
    final ratio = ratioRaw.isFinite ? ratioRaw : 0.0;

    final prod = (productSummary ?? 'جاري تحميل أصناف الفاتورة…').trim();

    /// Material بلون سطحي + InkWell بلا موجة — يتفادى طبقة مواد شفافة فوق الديكور (مشاكل عرض على الويب).
    return Material(
      elevation: isDark ? 3 : 1,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: colorScheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            statusLabel,
                            style: _planTextStyle(
                              context,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_left_rounded,
                        color: chevronC,
                        size: 26,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    plan.customerName.isEmpty ? 'عميل' : plan.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _planTextStyle(
                      context,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: titleC,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 16, color: mutedC),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          prod,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _planTextStyle(
                            context,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: mutedC,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: isDark
                          ? const Color(0xFF0F172A)
                          : colorScheme.surfaceContainerHighest,
                      color: settled
                          ? const Color(0xFF22C55E)
                          : colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تقدّم السداد: ${_numFmt.format(plan.paidAmount)} / ${_numFmt.format(plan.totalAmount)} د.ع',
                    style: _planTextStyle(
                      context,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: mutedC,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المتبقي',
                              style: _planTextStyle(
                                context,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: mutedC,
                              ),
                            ),
                            Text(
                              '${_numFmt.format(rem)} د.ع',
                              style: _planTextStyle(
                                context,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: overdue
                                    ? const Color(0xFFFCA5A5)
                                    : accentRem,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _AmountChip(
                          label: 'المدفوع',
                          amount: '${_numFmt.format(plan.paidAmount)} د.ع',
                          labelColor: mutedC,
                          valueColor: titleC,
                        ),
                      ),
                      Expanded(
                        child: _AmountChip(
                          label: 'الإجمالي',
                          amount: '${_numFmt.format(plan.totalAmount)} د.ع',
                          labelColor: mutedC,
                          valueColor: titleC,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'فاتورة #${plan.invoiceId}',
                        style: _planTextStyle(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedC,
                        ),
                      ),
                      Text(
                        '·',
                        style: _planTextStyle(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: mutedC,
                        ),
                      ),
                      Text(
                        'خطة #${plan.id}',
                        style: _planTextStyle(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedC,
                        ),
                      ),
                      if (plan.customerId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeC.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'عميل #${plan.customerId}',
                            style: _planTextStyle(
                              context,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeC,
                              height: 1.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (nextDue != null && !settled) ...[
                    const SizedBox(height: 8),
                    Text(
                      'القسط التالي: ${_numFmt.format(nextDue.amount)} د.ع — ${_dateFmt.format(nextDue.dueDate)}',
                      style: _planTextStyle(
                        context,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleC,
                      ),
                    ),
                  ],
                  if (overdue)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'تنبيه: يوجد قسط متأخر',
                        style: _planTextStyle(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFCA5A5),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'اضغط للتفاصيل الكاملة والجدول',
                    style: _planTextStyle(
                      context,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: mutedC.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ColoredBox(
                color: statusColor,
                child: const SizedBox(width: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final String amount;
  final Color labelColor;
  final Color valueColor;

  const _AmountChip({
    required this.label,
    required this.amount,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ) ??
              TextStyle(fontSize: 10, color: labelColor),
        ),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: valueColor,
              ) ??
              TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: valueColor,
              ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasPlans;
  final ColorScheme colorScheme;
  final bool filterActive;

  const _EmptyState({
    required this.hasPlans,
    required this.colorScheme,
    this.filterActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasPlans ? Icons.filter_alt_off_rounded : Icons.payments_outlined,
              size: 52,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              hasPlans
                  ? (filterActive
                        ? 'لا توجد خطط ضمن البحث أو التصفية الحالية'
                        : 'لا نتائج')
                  : 'لا توجد خطط تقسيط',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              hasPlans
                  ? 'امسح البحث (×) أو انتقل لتبويب «الكل» أو غيّر التبويب أعلاه.'
                  : 'بعد حفظ فاتورة تقسيط تُنشأ الخطة تلقائياً وتظهر هنا.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
