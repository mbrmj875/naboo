import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../providers/invoice_provider.dart';
import '../../models/invoice.dart';
import '../../services/database_helper.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/invoice_detail_sheet.dart';
import '../../theme/design_tokens.dart';
import '../shift/work_shifts_calendar_screen.dart';
import 'add_invoice_screen.dart';
import 'parked_sales_screen.dart';

Color _invoiceStatusColor(Invoice invoice, ColorScheme cs) {
  if (invoice.isReturned) return cs.error;
  switch (invoice.type) {
    case InvoiceType.cash:
      return const Color(0xFF16A34A);
    case InvoiceType.credit:
      return const Color(0xFFF59E0B);
    case InvoiceType.installment:
      return cs.primary;
    case InvoiceType.delivery:
      return cs.secondary;
    case InvoiceType.debtCollection:
    case InvoiceType.installmentCollection:
      return cs.secondary;
    case InvoiceType.supplierPayment:
      return const Color(0xFFB45309);
  }
}

final _numFmt  = NumberFormat('#,##0', 'ar');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'ar');

// ═════════════════════════════════════════════════════════════════════════════
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.openInvoiceIdAfterLoad});

  /// بعد التحميل (مثلاً من تنبيه «بيع سالب») — فتح تفاصيل الفاتورة تلقائياً.
  final int? openInvoiceIdAfterLoad;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  final DatabaseHelper _db = DatabaseHelper();
  String _query = '';
  String _sort  = 'date_desc'; // date_desc | date_asc | amount_desc | amount_asc
  /// تجميع الفواتير تحت عناوين الورديات (فتح → إغلاق + اسم موظف الوردية).
  bool _groupByShift = true;
  Map<int, Map<String, dynamic>> _shiftById = {};
  String _shiftIdsSig = '';

  static const _tabLabels = ['الكل', 'مدفوعة', 'غير مدفوعة', 'مرتجع', 'تقسيط'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _search.addListener(() {
      setState(() => _query = _search.text.trim());
      _syncFiltersToProvider();
    });
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {});
        _syncFiltersToProvider();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFiltersToProvider(initial: true);
    });
    if (widget.openInvoiceIdAfterLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_tryOpenInvoiceAfterLoad());
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _syncFiltersToProvider({bool initial = false}) {
    if (!mounted) return;
    final prov = Provider.of<InvoiceProvider>(context, listen: false);
    unawaited(
      prov.setFilters(
        tabIndex: _tabs.index,
        sort: _sort,
        query: _query,
      ),
    );
    if (initial && prov.invoices.isEmpty && !prov.isLoading) {
      unawaited(prov.refresh());
    }
  }

  Future<void> _openInvoiceDetails(Invoice inv) async {
    final id = inv.id;
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن عرض فاتورة بدون رقم')),
      );
      return;
    }
    final full = await _db.getInvoiceById(id);
    if (!mounted) return;
    if (full == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الفاتورة غير موجودة')),
      );
      return;
    }
    final subtotalBeforeDiscount =
        full.items.fold<double>(0, (sum, e) => sum + e.total);
    try {
      if (!mounted) return;
      await SaleReceiptPdf.presentReceipt(
        context,
        invoice: full,
        subtotalBeforeDiscount: subtotalBeforeDiscount,
        onOpenDetailsFromPdf: (pdfCtx) {
          showInvoiceDetailSheet(pdfCtx, _db, id);
        },
      );
    } catch (_) {}
  }

  Future<void> _tryOpenInvoiceAfterLoad() async {
    final targetId = widget.openInvoiceIdAfterLoad;
    if (targetId == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    final inv = await _db.getInvoiceById(targetId);
    if (!mounted || inv == null) return;
    await _openInvoiceDetails(inv);
  }

  Future<void> _ensureShiftMetaLoaded(List<Invoice> invoices) async {
    final ids = invoices.map((e) => e.workShiftId).whereType<int>().toSet();
    final sig = ids.join(',');
    if (sig == _shiftIdsSig) return;
    _shiftIdsSig = sig;
    if (ids.isEmpty) {
      if (mounted) setState(() => _shiftById = {});
      return;
    }
    final map = await _db.getWorkShiftsMapByIds(ids);
    if (!mounted) return;
    setState(() => _shiftById = map);
  }

  int _compareShiftKeys(
    int? a,
    int? b,
  ) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final ta = DateTime.tryParse(
      _shiftById[a]?['openedAt']?.toString() ?? '',
    );
    final tb = DateTime.tryParse(
      _shiftById[b]?['openedAt']?.toString() ?? '',
    );
    if (ta == null && tb == null) return b.compareTo(a);
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(cs),
        body: Consumer<InvoiceProvider>(
          builder: (_, provider, __) {
            final all      = provider.invoices;
            Future.microtask(() => _ensureShiftMetaLoaded(all));
            // NestedScrollView: يجعل شريط الإحصاء والبحث يطويان عند التمرير
            // بينما تبقى التبويبات ثابتة في الأعلى (Sticky). عند العودة للأعلى،
            // تعود كل الأقسام طبيعياً.
            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _StatsBar(invoices: all, colorScheme: cs),
                      _SearchSortBar(
                        controller: _search,
                        sort: _sort,
                        onSort: (v) {
                          setState(() => _sort = v);
                          _syncFiltersToProvider();
                        },
                        colorScheme: cs,
                      ),
                    ],
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabBarDelegate(
                    tabBar: _buildTabBar(cs),
                    backgroundColor: cs.surface,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(
                  _tabLabels.length,
                  (_) => _InvoiceList(
                    invoices: all,
                    onAdd: () => _addInvoice(),
                    isDark: isDark,
                    groupByShift: _groupByShift,
                    shiftById: _shiftById,
                    compareShiftKeys: _compareShiftKeys,
                    dateTimeFmt: _dateTimeFmt,
                    onInvoiceTap: _openInvoiceDetails,
                    onLoadMore: provider.hasMore ? provider.loadMore : null,
                    isLoadingMore: provider.isLoadingMore,
                    isLoading: provider.isLoading,
                  ),
                ),
              ),
            );
          },
        ),
        floatingActionButton: _buildFAB(cs),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      title: const Text('الفواتير',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      actions: [
        IconButton(
          icon: Icon(
            _groupByShift ? Icons.view_agenda_rounded : Icons.view_list_rounded,
          ),
          tooltip: _groupByShift
              ? 'عرض مفرد (بدون تجميع بالوردية)'
              : 'تجميع حسب الوردية',
          onPressed: () => setState(() => _groupByShift = !_groupByShift),
        ),
        IconButton(
          icon: const Icon(Icons.calendar_month_rounded),
          tooltip: 'تقويم الورديات',
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const WorkShiftsCalendarScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.pause_circle_outline_rounded),
          tooltip: 'فواتير معلّقة مؤقتاً',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ParkedSalesScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.filter_list_rounded),
          tooltip: 'تصفية متقدمة',
          onPressed: _showFilterSheet,
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
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

  /// على الهاتف (أضيق بعد < 600dp) لا نعرض زر البيع العائم — يشغل زاوية الشاشة فوق القائمة.
  /// يبقى [FloatingActionButton.extended] على التابلت والشاشات العريضة.
  Widget? _buildFAB(ColorScheme cs) {
    final layout = ScreenLayout.of(context);
    if (layout.isHandsetForLayout) {
      return null;
    }
    return FloatingActionButton.extended(
      onPressed: _addInvoice,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      icon: const Icon(Icons.add_rounded),
      label: const Text('البيع',
          style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _addInvoice() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AddInvoiceScreen()));
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        currentSort: _sort,
        onApply: (sort) {
          setState(() => _sort = sort);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── SliverPersistentHeader Delegate لإبقاء التبويبات ثابتة أعلى الشاشة ───────
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  _StickyTabBarDelegate({
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
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

// ── شريط الإحصاء ──────────────────────────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final List<Invoice> invoices;
  final ColorScheme colorScheme;
  const _StatsBar({required this.invoices, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final total   = invoices.fold(0.0, (s, i) => s + i.total);
    final paid = invoices
        .where(
          (i) =>
              !i.isReturned &&
              (i.type == InvoiceType.cash ||
                  i.type == InvoiceType.debtCollection ||
                  i.type == InvoiceType.installmentCollection),
        )
        .fold(0.0, (s, i) => s + i.total);
    final unpaid  = invoices.where((i) => i.type == InvoiceType.credit && !i.isReturned).fold(0.0, (s, i) => s + i.total);
    final returns = invoices.where((i) => i.isReturned).fold(0.0, (s, i) => s + i.total);

    final cs = colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(gap, 12, gap, 12),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 380) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'الإجمالي',
                        value: _numFmt.format(total),
                        color: cs.primary,
                        icon: Icons.receipt_long_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        label: 'مدفوعة',
                        value: _numFmt.format(paid),
                        color: const Color(0xFF16A34A),
                        icon: Icons.check_circle_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'دين',
                        value: _numFmt.format(unpaid),
                        color: const Color(0xFFF59E0B),
                        icon: Icons.access_time_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        label: 'مرتجع',
                        value: _numFmt.format(returns),
                        color: cs.error,
                        icon: Icons.reply_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              _StatChip(
                label: 'الإجمالي',
                value: _numFmt.format(total),
                color: cs.primary,
                icon: Icons.receipt_long_rounded,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'مدفوعة',
                value: _numFmt.format(paid),
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'دين',
                value: _numFmt.format(unpaid),
                color: const Color(0xFFF59E0B),
                icon: Icons.access_time_rounded,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'مرتجع',
                value: _numFmt.format(returns),
                color: cs.error,
                icon: Icons.reply_rounded,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                overflow: TextOverflow.ellipsis),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شريط البحث والترتيب ───────────────────────────────────────────────────────
class _SearchSortBar extends StatelessWidget {
  final TextEditingController controller;
  final String sort;
  final ValueChanged<String> onSort;
  final ColorScheme colorScheme;
  const _SearchSortBar({
    required this.controller,
    required this.sort,
    required this.onSort,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          // فلتر الترتيب
          PopupMenuButton<String>(
            initialValue: sort,
            onSelected: onSort,
            tooltip: 'ترتيب',
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: AppShape.none,
              ),
              child: Icon(Icons.sort_rounded, size: 20, color: cs.primary),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'date_desc',   child: Text('الأحدث أولاً')),
              const PopupMenuItem(value: 'date_asc',    child: Text('الأقدم أولاً')),
              const PopupMenuItem(value: 'amount_desc', child: Text('الأعلى مبلغاً')),
              const PopupMenuItem(value: 'amount_asc',  child: Text('الأقل مبلغاً')),
            ],
          ),
          const SizedBox(width: 8),
          // حقل البحث
          Expanded(
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'بحث باسم العميل أو رقم الفاتورة أو هاتف العميل...',
                hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                border: OutlineInputBorder(
                  borderRadius: AppShape.none,
                  borderSide: BorderSide.none,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: controller.clear,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── قائمة الفواتير ────────────────────────────────────────────────────────────
class _InvoiceList extends StatelessWidget {
  final List<Invoice> invoices;
  final VoidCallback onAdd;
  final bool isDark;
  final bool groupByShift;
  final Map<int, Map<String, dynamic>> shiftById;
  final int Function(int? a, int? b) compareShiftKeys;
  final DateFormat dateTimeFmt;
  final Future<void> Function(Invoice) onInvoiceTap;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool isLoading;

  const _InvoiceList({
    required this.invoices,
    required this.onAdd,
    required this.isDark,
    required this.groupByShift,
    required this.shiftById,
    required this.compareShiftKeys,
    required this.dateTimeFmt,
    required this.onInvoiceTap,
    required this.onLoadMore,
    required this.isLoadingMore,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(onAdd: onAdd);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final cb = onLoadMore;
        if (cb == null) return false;
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 420) {
          unawaited(cb());
        }
        return false;
      },
      child: _buildList(),
    );
  }

  Widget _buildList() {
    final baseCount = invoices.length;
    final tail = (isLoadingMore ? 1 : 0);

    if (!groupByShift) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        itemCount: baseCount + tail,
        itemBuilder: (_, i) {
          if (i >= baseCount) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final inv = invoices[i];
          return _InvoiceCard(
            invoice: inv,
            isDark: isDark,
            shiftStaffLabel: _labelFor(inv.workShiftId),
            onTap: () => onInvoiceTap(inv),
          );
        },
      );
    }

    /// ترتيب الفواتير كما بعد الفلترة وخيار الترتيب في الشاشة — فقط تفصيل حسب الوردية دون إعادة ترتيب داخل كل وردية.
    final groups = <int?, List<Invoice>>{};
    for (final inv in invoices) {
      groups.putIfAbsent(inv.workShiftId, () => []).add(inv);
    }
    final keys = groups.keys.toList()..sort(compareShiftKeys);
    // Flatten groups إلى قائمة عناصر: [Header, inv, inv, Header, inv...]
    final entries = <Object?>[];
    for (final k in keys) {
      entries.add(k); // shiftId marker for header
      entries.addAll(groups[k]!);
    }
    final itemCount = entries.length + tail;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i >= itemCount - tail && isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (i >= entries.length) return const SizedBox.shrink();
        final e = entries[i];
        if (e == null || e is int) {
          final shiftId = e as int?;
          final list = groups[shiftId] ?? const <Invoice>[];
          return _ShiftSectionHeader(
            shiftId: shiftId,
            shiftRow: shiftId == null ? null : shiftById[shiftId],
            invoiceCount: list.length,
            dateTimeFmt: dateTimeFmt,
            isDark: isDark,
          );
        }
        final inv = e as Invoice;
        return _InvoiceCard(
          invoice: inv,
          isDark: isDark,
          shiftStaffLabel: _labelFor(inv.workShiftId),
          onTap: () => onInvoiceTap(inv),
        );
      },
    );
  }

  String? _labelFor(int? shiftId) {
    if (shiftId == null) return null;
    final name = shiftById[shiftId]?['shiftStaffName']?.toString().trim();
    if (name == null || name.isEmpty) return 'وردية #$shiftId';
    return name;
  }
}

class _ShiftSectionHeader extends StatelessWidget {
  final int? shiftId;
  final Map<String, dynamic>? shiftRow;
  final int invoiceCount;
  final DateFormat dateTimeFmt;
  final bool isDark;

  const _ShiftSectionHeader({
    required this.shiftId,
    required this.shiftRow,
    required this.invoiceCount,
    required this.dateTimeFmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.12 : 0.08),
      cs.surface,
    );
    final border = cs.outlineVariant;

    if (shiftId == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'بدون وردية — فواتير قديمة أو خارج جلسة وردية ($invoiceCount)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (shiftRow == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
        ),
        child: Text(
          'وردية #$shiftId — تعذر تحميل تفاصيل الوردية ($invoiceCount فاتورة)',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );
    }

    final Map<String, dynamic> row = shiftRow!;
    final name =
        (row['shiftStaffName'] as String?)?.trim().isNotEmpty == true
            ? (row['shiftStaffName'] as String).trim()
            : 'موظف الوردية';
    final opened = DateTime.tryParse(row['openedAt']?.toString() ?? '');
    final closed = row['closedAt'] != null &&
            row['closedAt'].toString().isNotEmpty
        ? DateTime.tryParse(row['closedAt'].toString())
        : null;
    final openS =
        opened != null ? dateTimeFmt.format(opened) : '—';
    final closeS = closed != null
        ? dateTimeFmt.format(closed)
        : 'مفتوحة';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: cs.secondary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: cs.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'وردية #$shiftId — $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '$invoiceCount فاتورة',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: cs.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$openS  ←  $closeS',
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final bool isDark;
  /// اسم موظف الوردية من جدول الورديات (يُعرض على البطاقة).
  final String? shiftStaffLabel;
  final VoidCallback onTap;
  const _InvoiceCard({
    required this.invoice,
    required this.isDark,
    this.shiftStaffLabel,
    required this.onTap,
  });

  String get _statusLabel {
    if (invoice.isReturned) return 'مرتجع';
    switch (invoice.type) {
      case InvoiceType.cash:        return 'مدفوعة';
      case InvoiceType.credit:      return 'غير مدفوعة';
      case InvoiceType.installment: return 'تقسيط';
      case InvoiceType.delivery:    return 'توصيل';
      case InvoiceType.debtCollection:
        return 'تحصيل دين';
      case InvoiceType.installmentCollection:
        return 'تسديد قسط';
      case InvoiceType.supplierPayment:
        return 'دفع مورد';
    }
  }

  IconData get _typeIcon {
    switch (invoice.type) {
      case InvoiceType.cash:        return Icons.payments_rounded;
      case InvoiceType.credit:      return Icons.credit_score_rounded;
      case InvoiceType.installment: return Icons.calendar_month_rounded;
      case InvoiceType.delivery:    return Icons.local_shipping_rounded;
      case InvoiceType.debtCollection:
        return Icons.account_balance_wallet_rounded;
      case InvoiceType.installmentCollection:
        return Icons.receipt_long_rounded;
      case InvoiceType.supplierPayment:
        return Icons.storefront_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _invoiceStatusColor(invoice, cs);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppShape.none,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // أيقونة النوع
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: AppShape.none,
                  ),
                  child: Icon(_typeIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                // بيانات الفاتورة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              invoice.customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${_numFmt.format(invoice.total)} د.ع',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            '#${invoice.id?.toString().padLeft(5, '0') ?? '-----'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 4, height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _dateFmt.format(invoice.date),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: AppShape.none,
                            ),
                            child: Text(
                              _statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (invoice.items.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${invoice.items.length} صنف · خصم ${_numFmt.format(invoice.discount)} د.ع',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (shiftStaffLabel != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 13,
                              color: cs.secondary.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'وردية: $shiftStaffLabel',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.secondary.withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_left_rounded,
                  color: cs.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── الحالة الفارغة ────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: 44,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد فواتير',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'أضف أول فاتورة الآن',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppShape.none,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'البيع',
                    style: TextStyle(fontWeight: FontWeight.bold),
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

// ── ورقة الفلتر ───────────────────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final String currentSort;
  final ValueChanged<String> onApply;
  const _FilterSheet({required this.currentSort, required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort;
  @override
  void initState() { super.initState(); _sort = widget.currentSort; }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor == Colors.transparent
            ? cs.surface
            : Theme.of(context).cardColor,
        borderRadius: AppShape.none,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('خيارات الترتيب',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...[
                ('date_desc',   'الأحدث أولاً',    Icons.arrow_downward_rounded),
                ('date_asc',    'الأقدم أولاً',     Icons.arrow_upward_rounded),
                ('amount_desc', 'الأعلى مبلغاً',    Icons.trending_up_rounded),
                ('amount_asc',  'الأقل مبلغاً',     Icons.trending_down_rounded),
              ].map((e) {
                final selected = _sort == e.$1;
                return RadioListTile<String>(
                  value: e.$1,
                  groupValue: _sort,
                  onChanged: (v) => setState(() => _sort = v!),
                  activeColor: cs.secondary,
                  title: Row(
                    children: [
                      Icon(
                        e.$3,
                        size: 18,
                        color: selected ? cs.secondary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(e.$2),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => widget.onApply(_sort),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppShape.none,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
