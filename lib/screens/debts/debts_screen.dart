import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/credit_debt_invoice.dart';
import '../../models/customer_debt_models.dart';
import '../../models/debt_settings_data.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/invoice_detail_sheet.dart';
import 'customer_debt_detail_screen.dart';
import 'debt_settings_screen.dart';
import 'supplier_ap_tab.dart';

final _numFmt = NumberFormat('#,##0', 'en');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

enum _DebtFilter { all, open, aged, settled }

/// لوحة ديون «آجل» — مرتبطة بفواتير النوع دين، مع تصفية وبحث وملخص.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _search = TextEditingController();

  List<CreditDebtInvoice> _rows = [];
  List<CustomerDebtSummary> _summaries = [];
  DebtSettingsData _settings = DebtSettingsData.defaults();
  bool _loading = true;
  _DebtFilter _filter = _DebtFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getAllNonReturnedCreditInvoices();
    final sums = await _db.getCustomerDebtSummaries();
    final s = await _db.getDebtSettings();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _summaries = sums;
      _settings = s;
      _loading = false;
    });
  }

  bool _isAged(CreditDebtInvoice r, DateTime now) {
    if (_settings.warnDebtAgeDays <= 0) return false;
    if (r.isSettled) return false;
    return r.daysSinceInvoice(now) >= _settings.warnDebtAgeDays;
  }

  List<CreditDebtInvoice> _filteredList(DateTime now) {
    var list = List<CreditDebtInvoice>.from(_rows);
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) {
            return r.customerName.toLowerCase().contains(q) ||
                r.invoiceId.toString().contains(q) ||
                (r.customerId?.toString().contains(q) ?? false);
          })
          .toList();
    }
    switch (_filter) {
      case _DebtFilter.all:
        break;
      case _DebtFilter.open:
        list = list.where((r) => !r.isSettled).toList();
        break;
      case _DebtFilter.aged:
        list = list.where((r) => _isAged(r, now)).toList();
        break;
      case _DebtFilter.settled:
        list = list.where((r) => r.isSettled).toList();
        break;
    }
    return list;
  }

  List<CustomerDebtSummary> _filteredSummaries() {
    var list = List<CustomerDebtSummary>.from(_summaries);
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        return s.displayName.toLowerCase().contains(q) ||
            (s.customerId?.toString().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final now = DateTime.now();
    final filtered = _filteredList(now);
    final totalOpen =
        _rows.where((r) => !r.isSettled).fold<double>(0, (s, r) => s + r.remaining);
    final openCount = _rows.where((r) => !r.isSettled).length;
    final agedCount = _rows.where((r) => _isAged(r, now)).length;
    final listScope = filtered.length != _rows.length;
    final sumFiltered = _filteredSummaries();
    final sumScope = sumFiltered.length != _summaries.length;
    final sl = ScreenLayout.of(context);

    return DefaultTabController(
      length: 3,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('الديون — آجل'),
            bottom: TabBar(
              isScrollable: sl.isNarrowWidth,
              labelStyle: TextStyle(
                fontSize: sl.isNarrowWidth ? 12 : 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: sl.isNarrowWidth ? 12 : 14,
              ),
              tabs: const [
                Tab(text: 'فواتير'),
                Tab(text: 'عملاء'),
                Tab(text: 'موردون'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'إعدادات الدين',
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DebtSettingsScreen(),
                    ),
                  );
                  _load();
                },
                icon: const Icon(Icons.tune_rounded),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    RefreshIndicator(
                      color: cs.primary,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: _InfoBanner(
                              colorScheme: cs,
                              warnDays: _settings.warnDebtAgeDays,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _SummaryStrip(
                              totalOpen: totalOpen,
                              openInvoices: openCount,
                              agedInvoices: agedCount,
                              colorScheme: cs,
                              isDark: isDark,
                              onSelectFilter: (f) => setState(() => _filter = f),
                            ),
                          ),
                          if (listScope)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              child: Text(
                                'القائمة: ${filtered.length} من ${_rows.length} فاتورة (بحث أو تصفية)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: TextField(
                              controller: _search,
                              style: TextStyle(color: cs.onSurface),
                              cursorColor: cs.primary,
                              decoration: InputDecoration(
                                hintText:
                                    'بحث: عميل، رقم فاتورة، معرّف عميل…',
                                hintStyle:
                                    TextStyle(color: cs.onSurfaceVariant),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                                suffixIcon: _search.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'مسح البحث',
                                        onPressed: () {
                                          _search.clear();
                                          setState(() {});
                                        },
                                        icon: Icon(
                                          Icons.clear_rounded,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark
                                    ? cs.surfaceContainerHighest
                                    : cs.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: cs.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SegmentedButton<_DebtFilter>(
                                segments: const [
                                  ButtonSegment(
                                    value: _DebtFilter.all,
                                    label: Text('الكل'),
                                  ),
                                  ButtonSegment(
                                    value: _DebtFilter.open,
                                    label: Text('مفتوحة'),
                                  ),
                                  ButtonSegment(
                                    value: _DebtFilter.aged,
                                    label: Text('تحذير عمر'),
                                  ),
                                  ButtonSegment(
                                    value: _DebtFilter.settled,
                                    label: Text('مغلقة'),
                                  ),
                                ],
                                selected: {_filter},
                                emptySelectionAllowed: false,
                                multiSelectionEnabled: false,
                                onSelectionChanged: (s) {
                                  if (s.isEmpty) return;
                                  setState(() => _filter = s.first);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (filtered.isEmpty)
                            SizedBox(
                              height: 260,
                              child: _EmptyState(
                                hasRows: _rows.isNotEmpty,
                                colorScheme: cs,
                                filterActive: listScope ||
                                    _filter != _DebtFilter.all,
                              ),
                            )
                          else
                            for (final r in filtered)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: _DebtCard(
                                  row: r,
                                  warnDays: _settings.warnDebtAgeDays,
                                  colorScheme: cs,
                                  isDark: isDark,
                                  onTap: () => showInvoiceDetailSheet(
                                    context,
                                    _db,
                                    r.invoiceId,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                    RefreshIndicator(
                      color: cs.primary,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: _InfoBanner(
                              colorScheme: cs,
                              warnDays: _settings.warnDebtAgeDays,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text(
                              'تجميع حسب العميل: المنتجات والبائعون وتسديد جزئي من شاشة التفاصيل. QR على الإيصال للعملاء المسجّلين فقط.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: TextField(
                              controller: _search,
                              style: TextStyle(color: cs.onSurface),
                              cursorColor: cs.primary,
                              decoration: InputDecoration(
                                hintText: 'بحث باسم العميل أو المعرف…',
                                hintStyle:
                                    TextStyle(color: cs.onSurfaceVariant),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                                suffixIcon: _search.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'مسح البحث',
                                        onPressed: () {
                                          _search.clear();
                                          setState(() {});
                                        },
                                        icon: Icon(
                                          Icons.clear_rounded,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark
                                    ? cs.surfaceContainerHighest
                                    : cs.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      BorderSide(color: cs.outlineVariant),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: cs.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          if (sumScope)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                '${sumFiltered.length} من ${_summaries.length} عميل',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (sumFiltered.isEmpty)
                            SizedBox(
                              height: 220,
                              child: Center(
                                child: Text(
                                  _summaries.isEmpty
                                      ? 'لا يوجد متبقٍ آجل مجمّع بالعملاء'
                                      : 'لا نتائج للبحث',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            )
                          else
                            for (final s in sumFiltered)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: _CustomerDebtSummaryCard(
                                  summary: s,
                                  colorScheme: cs,
                                  isDark: isDark,
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SupplierApTab(),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CustomerDebtSummaryCard extends StatelessWidget {
  const _CustomerDebtSummaryCard({
    required this.summary,
    required this.colorScheme,
    required this.isDark,
  });

  final CustomerDebtSummary summary;
  final ColorScheme colorScheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? AppColors.cardDark : colorScheme.surface;
    final titleC =
        isDark ? const Color(0xFFF8FAFC) : colorScheme.onSurface;
    final mutedC =
        isDark ? const Color(0xFF94A3B8) : colorScheme.onSurfaceVariant;
    final r = BorderRadius.circular(12);
    return Material(
      elevation: isDark ? 3 : 1,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => CustomerDebtDetailScreen.fromParty(
                party: summary.toParty(),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.displayName.isEmpty
                          ? 'عميل'
                          : summary.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: titleC,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary.customerId != null
                          ? 'عميل مسجّل #${summary.customerId}'
                          : 'غير مربوط بجدول العملاء (بالاسم)',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: mutedC,
                      ),
                    ),
                    Text(
                      '${summary.invoiceCount} فاتورة آجل',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: mutedC,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_numFmt.format(summary.openRemaining)} د.ع',
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  Text(
                    'المتبقي',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: mutedC,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_left_rounded, color: mutedC, size: 26),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final ColorScheme colorScheme;
  final int warnDays;

  const _InfoBanner({
    required this.colorScheme,
    required this.warnDays,
  });

  @override
  Widget build(BuildContext context) {
    final ageHint = warnDays > 0
        ? ' التحذير بالعمر يبدأ بعد $warnDays يوماً من تاريخ الفاتورة.'
        : ' فعّل «أيام تحذير العمر» من إعدادات الدين لتمييز الفواتير القديمة.';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تُحسب الديون من فواتير النوع «دين / آجل». المتبقي = إجمالي الفاتورة − المقدّم. حدود البيع تُضبط من إعدادات الديون.$ageHint',
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

class _SummaryStrip extends StatelessWidget {
  final double totalOpen;
  final int openInvoices;
  final int agedInvoices;
  final ColorScheme colorScheme;
  final bool isDark;
  final ValueChanged<_DebtFilter> onSelectFilter;

  const _SummaryStrip({
    required this.totalOpen,
    required this.openInvoices,
    required this.agedInvoices,
    required this.colorScheme,
    required this.isDark,
    required this.onSelectFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricBox(
            title: 'إجمالي المتبقي',
            value: '${_numFmt.format(totalOpen)} د.ع',
            icon: Icons.account_balance_wallet_outlined,
            colorScheme: colorScheme,
            isDark: isDark,
            tooltip: 'عرض كل الفواتير',
            onTap: () => onSelectFilter(_DebtFilter.all),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricBox(
            title: 'فواتير مفتوحة',
            value: '$openInvoices',
            icon: Icons.description_outlined,
            colorScheme: colorScheme,
            isDark: isDark,
            tooltip: 'تصفية: مفتوحة فقط',
            onTap: () => onSelectFilter(_DebtFilter.open),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricBox(
            title: 'تحذير عمر',
            value: '$agedInvoices',
            icon: Icons.schedule_rounded,
            colorScheme: colorScheme,
            isDark: isDark,
            accent: agedInvoices > 0 ? const Color(0xFFF59E0B) : null,
            tooltip: 'تصفية: تحذير عمر',
            onTap: () => onSelectFilter(_DebtFilter.aged),
          ),
        ),
      ],
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final ColorScheme colorScheme;
  final bool isDark;
  final Color? accent;
  final String tooltip;
  final VoidCallback onTap;

  const _MetricBox({
    required this.title,
    required this.value,
    required this.icon,
    required this.colorScheme,
    required this.isDark,
    this.accent,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? colorScheme.primary;
    final fill = colorScheme.surface;
    final onSurf = colorScheme.onSurface;
    final onVar = colorScheme.onSurfaceVariant;
    final r = BorderRadius.circular(8);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: r,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: c),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(fontSize: 10, color: onVar),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: accent != null ? c : onSurf,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final CreditDebtInvoice row;
  final int warnDays;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  const _DebtCard({
    required this.row,
    required this.warnDays,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final settled = row.isSettled;
    final aged = warnDays > 0 && !settled && row.daysSinceInvoice(now) >= warnDays;
    final statusColor = settled
        ? const Color(0xFF15803D)
        : (aged ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6));
    final statusLabel = settled ? 'مغلقة' : (aged ? 'تنبيه عمر' : 'مفتوحة');
    final titleC =
        isDark ? const Color(0xFFF8FAFC) : colorScheme.onSurface;
    final mutedC =
        isDark ? const Color(0xFF94A3B8) : colorScheme.onSurfaceVariant;
    final fill = isDark ? AppColors.cardDark : colorScheme.surface;
    final r = BorderRadius.circular(12);
    final rem = row.remaining;
    final ratio = row.total > 1e-6
        ? ((row.total - rem) / row.total).clamp(0.0, 1.0)
        : 0.0;
    final ratioSafe = ratio.isFinite ? ratio : 0.0;

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_left_rounded,
                          color: mutedC, size: 26),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    row.customerName.isEmpty ? 'عميل' : row.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: titleC,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'فاتورة #${row.invoiceId} · ${_dateFmt.format(row.date)} · ${row.daysSinceInvoice(now)} يوماً',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: mutedC,
                    ),
                  ),
                  if (row.customerId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'عميل مسجّل #${row.customerId}',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 11,
                        color: mutedC,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratioSafe,
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
                    'المقدّم ${_numFmt.format(row.advancePayment)} / ${_numFmt.format(row.total)} د.ع',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: mutedC,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'المتبقي',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: mutedC,
                    ),
                  ),
                  Text(
                    '${_numFmt.format(rem)} د.ع',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: aged
                          ? const Color(0xFFFBBF24)
                          : (settled
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFF38BDF8)),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'اضغط لعرض تفاصيل الفاتورة',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
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

class _EmptyState extends StatelessWidget {
  final bool hasRows;
  final ColorScheme colorScheme;
  final bool filterActive;

  const _EmptyState({
    required this.hasRows,
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
              hasRows ? Icons.filter_alt_off_rounded : Icons.payments_outlined,
              size: 52,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              hasRows
                  ? (filterActive
                      ? 'لا توجد فواتير ضمن البحث أو التصفية الحالية'
                      : 'لا نتائج')
                  : 'لا توجد فواتير دين مسجّلة',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              hasRows
                  ? 'امسح البحث أو اختر «الكل» في شريط التصفية.'
                  : 'من «بيع جديد» اختر نوع «دين» ليظهر المبلغ المؤجل هنا.',
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
