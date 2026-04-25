import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/expense.dart';
import '../../services/database_helper.dart';
import '../../services/expense_attachment_store.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/iraqi_currency_format.dart';
import 'expense_receipt_printer.dart';
import 'expense_report_printer.dart';

final _dateFmt = DateFormat('yyyy/MM/dd', 'en');

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  List<ExpenseCategory> _categories = const [];
  List<ExpenseEntry> _items = const [];
  List<Map<String, dynamic>> _byCategory = const [];
  List<Map<String, dynamic>> _daily = const [];
  List<Map<String, dynamic>> _dailyByCategory = const [];
  bool _loading = true;

  int? _categoryId;
  String _status = 'all'; // all|paid|pending
  final TextEditingController _searchCtrl = TextEditingController();

  double _total = 0.0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      unawaited(_reload());
    });
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // توليد نسخ الشهر الحالي للمصروفات المتكررة قبل تحميل البيانات.
    try {
      await DatabaseHelper().generateDueRecurringExpenses();
    } catch (_) {}
    await _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final db = DatabaseHelper();
    final cats = (await db.getExpenseCategories()).map(ExpenseCategory.fromMap).toList();
    final rows = await db.getExpenses(
      from: _from,
      to: _to,
      categoryId: _categoryId,
      status: _status,
      query: _searchCtrl.text,
    );
    final items = rows.map(ExpenseEntry.fromJoinedRow).toList();
    final total = await db.sumExpenses(from: _from, to: _to);
    final byCategory = await db.sumExpensesByCategory(from: _from, to: _to, status: _status);
    final daily = await db.sumExpensesDaily(from: _from, to: _to, status: _status);
    final dailyByCategory = await db.sumExpensesDailyByCategory(
      from: _from,
      to: _to,
      status: _status,
    );
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _items = items;
      _total = total;
      _byCategory = byCategory;
      _daily = daily;
      _dailyByCategory = dailyByCategory;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
    await _reload();
  }

  Future<void> _openEditor({ExpenseEntry? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ExpenseEditorDialog(
        categories: _categories,
        existing: existing,
      ),
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _openReportDialog() async {
    final range = await showExpenseReportRangePicker(
      context,
      DateTimeRange(start: _from, end: _to),
    );
    if (range == null) return;
    if (!mounted) return;
    await ExpenseReportPrinter.show(
      context: context,
      from: range.start,
      to: range.end,
    );
  }

  Future<void> _delete(ExpenseEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف المصروف؟'),
            content: Text(
              'سيتم حذف «${e.categoryName}» بمبلغ ${IraqiCurrencyFormat.formatIqd(e.amount)}',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    await DatabaseHelper().deleteExpense(id: e.id);
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rangeLabel = '${_dateFmt.format(_from)}  ←  ${_dateFmt.format(_to)}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: cs.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('المصروفات'),
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'السجل'),
                Tab(text: 'تحليلات'),
              ],
            ),
          ),
          floatingActionButton: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'exp_print_btn',
                tooltip: 'طباعة تقرير فترة',
                onPressed: _openReportDialog,
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
                child: const Icon(Icons.print_outlined),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'exp_add_btn',
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة مصروف'),
              ),
            ],
          ),
          body: TabBarView(
            children: [
              _ExpensesLedgerTab(
                loading: _loading,
                categories: _categories,
                items: _items,
                total: _total,
                rangeLabel: rangeLabel,
                onPickRange: _pickRange,
                searchCtrl: _searchCtrl,
                categoryId: _categoryId,
                status: _status,
                onCategoryChanged: (v) async {
                  setState(() => _categoryId = v);
                  await _reload();
                },
                onStatusChanged: (v) async {
                  setState(() => _status = v);
                  await _reload();
                },
                onEdit: (e) => _openEditor(existing: e),
                onDelete: _delete,
              ),
              _ExpensesAnalyticsTab(
                loading: _loading,
                total: _total,
                byCategory: _byCategory,
                daily: _daily,
                dailyByCategory: _dailyByCategory,
                from: _from,
                to: _to,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpensesLedgerTab extends StatelessWidget {
  const _ExpensesLedgerTab({
    required this.loading,
    required this.categories,
    required this.items,
    required this.total,
    required this.rangeLabel,
    required this.onPickRange,
    required this.searchCtrl,
    required this.categoryId,
    required this.status,
    required this.onCategoryChanged,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final bool loading;
  final List<ExpenseCategory> categories;
  final List<ExpenseEntry> items;
  final double total;
  final String rangeLabel;
  final VoidCallback onPickRange;
  final TextEditingController searchCtrl;
  final int? categoryId;
  final String status;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<ExpenseEntry> onEdit;
  final ValueChanged<ExpenseEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;

    final contentCount = loading ? 1 : (items.isEmpty ? 1 : items.length);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: 1 + contentCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Material(
              color: cs.surface,
              borderRadius: ac.md,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final compact = c.maxWidth < 360;
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'إجمالي المصروفات ضمن الفترة',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: onPickRange,
                                  icon: const Icon(Icons.date_range_rounded, size: 18),
                                  label: Text(
                                    rangeLabel,
                                    textDirection: TextDirection.ltr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                'إجمالي المصروفات ضمن الفترة',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Flexible(
                              child: TextButton.icon(
                                onPressed: onPickRange,
                                icon: const Icon(Icons.date_range_rounded, size: 18),
                                label: Text(
                                  rangeLabel,
                                  textDirection: TextDirection.ltr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.35),
                              borderRadius: ac.sm,
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.payments_outlined, color: cs.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    IraqiCurrencyFormat.formatIqd(total),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, c) {
                        final row = c.maxWidth >= 520;
                        final search = TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'بحث (وصف أو فئة)',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                            border: OutlineInputBorder(
                              borderRadius: ac.md,
                              borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.7),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: ac.md,
                              borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.7),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        );

                        final category = DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: categoryId,
                            isExpanded: true,
                            borderRadius: ac.md,
                            hint: const Text('الفئة'),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('كل الفئات'),
                              ),
                              for (final c in categories)
                                DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: onCategoryChanged,
                          ),
                        );

                        final statusPick = DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: status,
                            isExpanded: true,
                            borderRadius: ac.md,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('الكل')),
                              DropdownMenuItem(value: 'paid', child: Text('مدفوع')),
                              DropdownMenuItem(value: 'pending', child: Text('معلق')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              onStatusChanged(v);
                            },
                          ),
                        );

                        if (row) {
                          return Row(
                            children: [
                              Expanded(child: search),
                              const SizedBox(width: 10),
                              SizedBox(width: 160, child: category),
                              const SizedBox(width: 10),
                              SizedBox(width: 120, child: statusPick),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            search,
                            const SizedBox(height: 10),
                            category,
                            const SizedBox(height: 10),
                            statusPick,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // content
        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(
              child: Text(
                'لا توجد مصروفات ضمن هذه الفترة.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          );
        }

        final i = index - 1;
        final e = items[i];
        final color = expenseCategoryColor(e.categoryName, cs);
        final icon = expenseCategoryIcon(e.categoryName);
        final pending = e.status == ExpenseStatus.pending;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            i == items.length - 1 ? 0 : 10,
          ),
          child: Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: InkWell(
              borderRadius: ac.md,
              onTap: () => onEdit(e),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: ac.md,
                        border: Border.all(
                          color: color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.categoryName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: pending
                                      ? const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.15)
                                      : const Color(0xFF16A34A)
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  pending ? 'معلق' : 'مدفوع',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: pending
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (e.employeeName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    e.employeeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 2),
                          if (e.description.isNotEmpty)
                            Text(
                              e.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                _dateFmt.format(e.occurredAt),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                              if (e.attachmentPath != null &&
                                  e.attachmentPath!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.attach_file_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'فاتورة مرفقة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (e.isRecurring || e.recurringOriginId != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.replay_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'متكرر',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          IraqiCurrencyFormat.formatIqd(e.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'طباعة إيصال',
                              onPressed: () => ExpenseReceiptPrinter.show(e),
                              icon: const Icon(Icons.print_rounded),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => onDelete(e),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: cs.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpensesAnalyticsTab extends StatelessWidget {
  const _ExpensesAnalyticsTab({
    required this.loading,
    required this.total,
    required this.byCategory,
    required this.daily,
    required this.dailyByCategory,
    required this.from,
    required this.to,
  });

  final bool loading;
  final double total;
  final List<Map<String, dynamic>> byCategory;
  final List<Map<String, dynamic>> daily;
  final List<Map<String, dynamic>> dailyByCategory;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    if (loading) return const Center(child: CircularProgressIndicator());

    final maxDaily = daily.fold<double>(
      1,
      (m, r) => math.max(m, (r['total'] as num?)?.toDouble() ?? 0),
    );
    final slices = byCategory
        .where((r) => ((r['total'] as num?)?.toDouble() ?? 0) > 1e-9)
        .map(
          (r) => _PieSlice(
            label: r['categoryName']?.toString() ?? '',
            value: (r['total'] as num?)?.toDouble() ?? 0.0,
            color: expenseCategoryColor(r['categoryName']?.toString() ?? '', cs),
          ),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'تحليلات المصروفات ضمن الفترة',
                      style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                    ),
                  ),
                  Text(
                    IraqiCurrencyFormat.formatIqd(total),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'توزيع حسب الفئة',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  if (slices.isNotEmpty)
                    SizedBox(
                      height: 290,
                      child: _InteractivePie(
                        slices: slices,
                        total: total,
                      ),
                    ),
                  if (slices.isNotEmpty) const SizedBox(height: 12),
                  if (byCategory.isEmpty)
                    Text('لا توجد بيانات.', style: TextStyle(color: cs.onSurfaceVariant))
                  else
                    for (final r in byCategory)
                      _CategoryBarRow(
                        name: r['categoryName']?.toString() ?? '',
                        value: (r['total'] as num?)?.toDouble() ?? 0.0,
                        total: total,
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'اتجاه يومي',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    child: _MiniBars(
                      points: daily
                          .map(
                            (r) => (
                              (r['d']?.toString() ?? ''),
                              (r['total'] as num?)?.toDouble() ?? 0.0
                            ),
                          )
                          .toList(),
                      maxY: maxDaily,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'نسب إنفاق الفئات (Gauges)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'كل قوس يمثل نسبة فئة من إجمالي المصروفات في الفترة.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 260,
                    child: _CategoryGauges(
                      byCategory: byCategory,
                      total: total,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surface,
            borderRadius: ac.md,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.stacked_line_chart_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'اتجاه الفئات المكدّس عبر الزمن',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'يعرض مجموع كل فئة يوميًا بشكل تراكمي، مع محور قيم واضح ومسافات مريحة.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: _StackedAreaChart(
                      dailyByCategory: dailyByCategory,
                      byCategory: byCategory,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ملاحظة: التحليلات تعتمد على تجميع SQL مباشر من جدول المصروفات ضمن الفترة المختارة.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({
    required this.name,
    required this.value,
    required this.total,
  });
  final String name;
  final double value;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (value / total);
    final color = expenseCategoryColor(name, cs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
              Text(
                IraqiCurrencyFormat.formatIqd(value),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
              const SizedBox(width: 10),
              Text(
                '${(pct * 100).toStringAsFixed(pct * 100 < 10 ? 1 : 0)}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct.clamp(0, 1),
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.points, required this.maxY});
  final List<(String label, double value)> points;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Center(
        child: Text('لا توجد بيانات.', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    final max = maxY <= 0 ? 1.0 : maxY;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final n = points.length;
        final barW = (w / n).clamp(6.0, 20.0);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: barW,
                    height: (p.$2 / max).clamp(0.0, 1.0) * 160,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _formatPct(double pct) {
  if (!pct.isFinite || pct <= 0) return '0%';
  if (pct < 0.01) return '<0.01%';
  if (pct < 0.1) return '${pct.toStringAsFixed(2)}%';
  if (pct < 10) return '${pct.toStringAsFixed(1)}%';
  return '${pct.toStringAsFixed(0)}%';
}

class _CategoryGauges extends StatelessWidget {
  const _CategoryGauges({
    required this.byCategory,
    required this.total,
  });

  final List<Map<String, dynamic>> byCategory;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (byCategory.isEmpty || total <= 0) {
      return Center(
        child: Text(
          'لا توجد بيانات لعرض المقاييس.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final items = [
      for (final r in byCategory)
        (
          name: (r['categoryName']?.toString() ?? ''),
          value: (r['total'] as num?)?.toDouble() ?? 0.0,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final top = items.take(6).toList();

    return LayoutBuilder(
      builder: (context, c) {
        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight - 40),
                painter: _CategoryGaugesPainter(
                  items: top
                      .map(
                        (e) => (
                          name: e.name,
                          value: e.value,
                          color: expenseCategoryColor(e.name, cs),
                        ),
                      )
                      .toList(),
                  total: total,
                  trackColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  labelColor: cs.onSurface,
                  subLabelColor: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final e in top)
                  _LegendDot(
                    color: expenseCategoryColor(e.name, cs),
                    label: e.name,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.onSurface),
        ),
      ],
    );
  }
}

class _CategoryGaugesPainter extends CustomPainter {
  _CategoryGaugesPainter({
    required this.items,
    required this.total,
    required this.trackColor,
    required this.labelColor,
    required this.subLabelColor,
  });

  final List<({String name, double value, Color color})> items;
  final double total;
  final Color trackColor;
  final Color labelColor;
  final Color subLabelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || total <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.92);
    final maxRadius = math.min(size.width * 0.46, size.height * 0.85);
    final n = items.length;
    final innerRadius = maxRadius * 0.32;
    final spacing = (maxRadius - innerRadius) / (n + 1);

    for (var i = 0; i < n; i++) {
      final item = items[i];
      final radius = maxRadius - (i * spacing);
      final thickness = math.max(8.0, spacing * 0.55);
      final pct = (item.value / total).clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: center, radius: radius);

      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness
        ..color = trackColor;
      canvas.drawArc(rect, math.pi, math.pi, false, track);

      final value = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness
        ..color = item.color;
      canvas.drawArc(rect, math.pi, math.pi * pct, false, value);

      // Label on the right side of the arc end.
      final endAngle = math.pi + math.pi * pct;
      final endOffset = Offset(
        center.dx + math.cos(endAngle) * radius,
        center.dy + math.sin(endAngle) * radius,
      );
      final pctText = _formatPct(pct * 100);
      final tp = TextPainter(
        text: TextSpan(
          text: pctText,
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelOffset = Offset(
        endOffset.dx + (pct < 0.5 ? 6 : -tp.width - 6),
        endOffset.dy - tp.height - 2,
      );
      tp.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryGaugesPainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.items.length != items.length ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.labelColor != labelColor;
  }
}

class _StackedAreaChart extends StatelessWidget {
  const _StackedAreaChart({
    required this.dailyByCategory,
    required this.byCategory,
  });

  final List<Map<String, dynamic>> dailyByCategory;
  final List<Map<String, dynamic>> byCategory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (dailyByCategory.isEmpty || byCategory.isEmpty) {
      return Center(
        child: Text(
          'لا توجد بيانات اتجاه عبر الزمن لعرضها.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    // Build ordered list of categories (by total desc), and ordered dates.
    final categories = [
      for (final r in byCategory) r['categoryName']?.toString() ?? '',
    ];
    final dates = <String>{};
    for (final r in dailyByCategory) {
      dates.add(r['d']?.toString() ?? '');
    }
    final sortedDates = dates.where((e) => e.isNotEmpty).toList()..sort();

    // date -> category -> value
    final map = <String, Map<String, double>>{};
    for (final r in dailyByCategory) {
      final d = r['d']?.toString() ?? '';
      final cat = r['categoryName']?.toString() ?? '';
      final v = (r['total'] as num?)?.toDouble() ?? 0.0;
      map.putIfAbsent(d, () => <String, double>{})[cat] = v;
    }

    // Compute max stacked total for y-axis scaling.
    var maxStack = 0.0;
    for (final d in sortedDates) {
      final row = map[d] ?? const <String, double>{};
      var s = 0.0;
      for (final c in categories) {
        s += row[c] ?? 0.0;
      }
      if (s > maxStack) maxStack = s;
    }
    if (maxStack <= 0) maxStack = 1.0;

    final series = [
      for (final c in categories)
        _SeriesData(
          name: c,
          color: expenseCategoryColor(c, cs),
          values: [for (final d in sortedDates) (map[d]?[c] ?? 0.0)],
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              return CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _StackedAreaPainter(
                  series: series,
                  dates: sortedDates,
                  maxStack: maxStack,
                  axisColor: cs.outlineVariant.withValues(alpha: 0.6),
                  gridColor: cs.outlineVariant.withValues(alpha: 0.35),
                  labelColor: cs.onSurfaceVariant,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final s in series)
              _LegendDot(color: s.color, label: s.name),
          ],
        ),
      ],
    );
  }
}

class _SeriesData {
  _SeriesData({
    required this.name,
    required this.color,
    required this.values,
  });
  final String name;
  final Color color;
  final List<double> values;
}

class _StackedAreaPainter extends CustomPainter {
  _StackedAreaPainter({
    required this.series,
    required this.dates,
    required this.maxStack,
    required this.axisColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<_SeriesData> series;
  final List<String> dates;
  final double maxStack;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || dates.isEmpty) return;

    const leftPad = 44.0;
    const rightPad = 14.0;
    const topPad = 10.0;
    const bottomPad = 30.0;

    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    final origin = Offset(leftPad, topPad + chartHeight);
    final n = dates.length;

    final xStep = n > 1 ? chartWidth / (n - 1) : 0.0;

    double xFor(int i) => leftPad + (n > 1 ? xStep * i : chartWidth / 2);
    double yFor(double v) => topPad + chartHeight - (v / maxStack) * chartHeight;

    // Grid lines (4 steps).
    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + chartHeight * (i / 4.0);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        grid,
      );
      final value = maxStack * (1 - i / 4.0);
      final label = _shortNumber(value);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Axis
    final axis = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(leftPad, origin.dy),
        Offset(size.width - rightPad, origin.dy), axis);
    canvas.drawLine(Offset(leftPad, topPad),
        Offset(leftPad, origin.dy), axis);

    // Build stacked values
    final cumulative = List<double>.filled(n, 0.0);

    for (var s = 0; s < series.length; s++) {
      final srs = series[s];
      final topY = <double>[];
      final bottomY = <double>[];
      for (var i = 0; i < n; i++) {
        final prev = cumulative[i];
        final next = prev + (i < srs.values.length ? srs.values[i] : 0.0);
        topY.add(yFor(next));
        bottomY.add(yFor(prev));
        cumulative[i] = next;
      }

      final path = Path();
      path.moveTo(xFor(0), topY[0]);
      for (var i = 1; i < n; i++) {
        path.lineTo(xFor(i), topY[i]);
      }
      for (var i = n - 1; i >= 0; i--) {
        path.lineTo(xFor(i), bottomY[i]);
      }
      path.close();

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = srs.color.withValues(alpha: 0.78);
      canvas.drawPath(path, fill);

      // Top line
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = srs.color.withValues(alpha: 0.95);
      final top = Path();
      top.moveTo(xFor(0), topY[0]);
      for (var i = 1; i < n; i++) {
        top.lineTo(xFor(i), topY[i]);
      }
      canvas.drawPath(top, line);
    }

    // X-axis labels (first, middle, last) to avoid crowding.
    final labelsIdx = <int>{0, n - 1};
    if (n >= 3) labelsIdx.add(n ~/ 2);
    for (final i in labelsIdx) {
      final x = xFor(i);
      final raw = dates[i];
      final label = raw.length >= 10 ? raw.substring(5, 10) : raw;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, origin.dy + 6));
    }
  }

  String _shortNumber(double v) {
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _StackedAreaPainter oldDelegate) {
    return oldDelegate.maxStack != maxStack ||
        oldDelegate.dates.length != dates.length ||
        oldDelegate.series.length != series.length ||
        oldDelegate.axisColor != axisColor;
  }
}

class _PieSlice {
  const _PieSlice({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

class _InteractivePie extends StatefulWidget {
  const _InteractivePie({required this.slices, required this.total});
  final List<_PieSlice> slices;
  final double total;

  @override
  State<_InteractivePie> createState() => _InteractivePieState();
}

class _InteractivePieState extends State<_InteractivePie> {
  int? _activeIndex;
  Offset? _lastPointer;

  int? _sliceIndexAt(Offset localPosition, Size size) {
    if (widget.slices.isEmpty || widget.total <= 0) return null;
    final center = Offset(size.width / 2, size.height * 0.56);
    final radius = math.min(size.height * 0.38, size.width * 0.30);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt((dx * dx) + (dy * dy));
    if (distance > radius + 12) return null;
    var angle = math.atan2(dy, dx);
    if (angle < -math.pi / 2) angle += 2 * math.pi;
    final normalized = angle + math.pi / 2;
    var sweepStart = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      final sweep = (widget.slices[i].value / widget.total) * 2 * math.pi;
      if (normalized >= sweepStart && normalized <= sweepStart + sweep) return i;
      sweepStart += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final active =
            (_activeIndex != null && _activeIndex! >= 0 && _activeIndex! < widget.slices.length)
                ? widget.slices[_activeIndex!]
                : null;
        return MouseRegion(
          onHover: (e) {
            _lastPointer = e.localPosition;
            final idx = _sliceIndexAt(e.localPosition, size);
            if (idx != _activeIndex) setState(() => _activeIndex = idx);
          },
          onExit: (_) {
            if (_activeIndex != null || _lastPointer != null) {
              setState(() {
                _activeIndex = null;
                _lastPointer = null;
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => setState(() {
              _lastPointer = e.localPosition;
              _activeIndex = _sliceIndexAt(e.localPosition, size);
            }),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: size,
                  painter: _PiePainter(
                    slices: widget.slices,
                    total: widget.total,
                    activeIndex: _activeIndex,
                    textColor: Theme.of(context).colorScheme.onSurface,
                    subTextColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (active != null && _lastPointer != null)
                  _PieTooltip(
                    anchor: _lastPointer!,
                    bounds: size,
                    title: active.label,
                    amount: active.value,
                    total: widget.total,
                    color: active.color,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PieTooltip extends StatelessWidget {
  const _PieTooltip({
    required this.anchor,
    required this.bounds,
    required this.title,
    required this.amount,
    required this.total,
    required this.color,
  });

  final Offset anchor;
  final Size bounds;
  final String title;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (amount / total) * 100;
    const w = 215.0;
    const h = 74.0;
    final desired = Offset(anchor.dx + 12, anchor.dy - h - 10);
    final x =
        desired.dx.clamp(8.0, math.max(8.0, bounds.width - w - 8)).toDouble();
    final y =
        desired.dy.clamp(8.0, math.max(8.0, bounds.height - h - 8)).toDouble();

    return Positioned(
      left: x,
      top: y,
      width: w,
      height: h,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 120),
          child: Material(
            color: cs.surface,
            elevation: 12,
            shadowColor: cs.shadow.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        _formatPct(pct),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'المبلغ:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        IraqiCurrencyFormat.formatIqd(amount),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.slices,
    required this.total,
    required this.activeIndex,
    required this.textColor,
    required this.subTextColor,
  });

  final List<_PieSlice> slices;
  final double total;
  final int? activeIndex;
  final Color textColor;
  final Color subTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || total <= 0) return;
    final radius = math.min(size.height * 0.36, size.width * 0.26);
    final center = Offset(size.width / 2, size.height * 0.56);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * 2 * math.pi;
      final mid = start + (sweep / 2);
      final isActive = activeIndex == i;
      final offset = isActive ? Offset(math.cos(mid) * 7, math.sin(mid) * 7) : Offset.zero;
      final rect = Rect.fromCircle(
        center: center + offset,
        radius: isActive ? radius + 4 : radius,
      );
      paint.color = s.color.withValues(alpha: isActive ? 1.0 : 0.95);
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }

    // Callouts
    start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * 2 * math.pi;
      final mid = start + (sweep / 2);
      final isRight = math.cos(mid) >= 0;
      final anchor = Offset(
        center.dx + math.cos(mid) * radius,
        center.dy + math.sin(mid) * radius,
      );
      final knee = Offset(
        center.dx + math.cos(mid) * (radius + 10),
        center.dy + math.sin(mid) * (radius + 10),
      );
      final end = Offset(isRight ? size.width - 10 : 10, knee.dy);

      final linePaint = Paint()
        ..color = Colors.grey.shade500
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(anchor, knee, linePaint);
      canvas.drawLine(knee, end, linePaint);
      canvas.drawCircle(anchor, 2, Paint()..color = s.color);

      final pct = (s.value / total) * 100;
      final labelTp = TextPainter(
        text: TextSpan(
          text: s.label,
          style: TextStyle(
            color: textColor,
            fontSize: 11.5,
            fontWeight: activeIndex == i ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: isRight ? TextAlign.right : TextAlign.left,
      )..layout(maxWidth: size.width * 0.30);

      final pctTp = TextPainter(
        text: TextSpan(
          text: _formatPct(pct),
          style: TextStyle(
            color: subTextColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: isRight ? TextAlign.right : TextAlign.left,
      )..layout(maxWidth: size.width * 0.30);

      final textX = isRight ? end.dx - math.max(labelTp.width, pctTp.width) : end.dx;
      final textY = end.dy - (labelTp.height + pctTp.height + 2) / 2;
      labelTp.paint(canvas, Offset(textX, textY));
      pctTp.paint(canvas, Offset(textX, textY + labelTp.height + 2));

      start += sweep;
    }
  }

  int _sig() => Object.hashAll(
        slices.map((s) => Object.hash(s.label, s.value, s.color.value)),
      );

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.activeIndex != activeIndex ||
        oldDelegate.textColor != textColor ||
        oldDelegate.subTextColor != subTextColor ||
        oldDelegate._sig() != _sig();
  }
}

class _ExpenseEditorDialog extends StatefulWidget {
  const _ExpenseEditorDialog({required this.categories, this.existing});
  final List<ExpenseCategory> categories;
  final ExpenseEntry? existing;

  @override
  State<_ExpenseEditorDialog> createState() => _ExpenseEditorDialogState();
}

class _ExpenseEditorDialogState extends State<_ExpenseEditorDialog> {
  late int _categoryId;
  late ExpenseStatus _status;
  late DateTime _date;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _saving = false;

  int? _employeeId;
  String _employeeLabel = '';
  bool _isRecurring = false;
  int? _recurringDay;
  String? _attachmentPath;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _categoryId =
        e?.categoryId ?? (widget.categories.isNotEmpty ? widget.categories.first.id : 0);
    _status = e?.status ?? ExpenseStatus.paid;
    _date = e?.occurredAt ?? DateTime.now();
    if (e != null) {
      _amountCtrl.text = e.amount.toStringAsFixed(0);
      _descCtrl.text = e.description;
      _employeeId = e.employeeUserId;
      _employeeLabel = e.employeeName;
      _isRecurring = e.isRecurring;
      _recurringDay = e.recurringDay;
      _attachmentPath = e.attachmentPath;
    } else {
      final catName = _currentCategoryName();
      _isRecurring = expenseCategorySuggestsRecurring(catName);
      _recurringDay = _isRecurring ? DateTime.now().day : null;
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (xfile == null) return;
      final saved =
          await ExpenseAttachmentStore.instance.save(File(xfile.path));
      if (!mounted) return;
      setState(() => _attachmentPath = saved);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الصورة.')),
      );
    }
  }

  Future<void> _clearAttachment() async {
    final path = _attachmentPath;
    if (path == null) return;
    setState(() => _attachmentPath = null);
    await ExpenseAttachmentStore.instance.delete(path);
  }

  String _currentCategoryName() {
    for (final c in widget.categories) {
      if (c.id == _categoryId) return c.name;
    }
    return '';
  }

  void _onCategoryChanged(int? v) {
    setState(() {
      _categoryId = v ?? 0;
      final catName = _currentCategoryName();
      if (!expenseCategoryRequiresEmployee(catName)) {
        _employeeId = null;
        _employeeLabel = '';
      }
      _isRecurring = expenseCategorySuggestsRecurring(catName);
      _recurringDay = _isRecurring ? (_recurringDay ?? _date.day) : null;
    });
  }

  Future<void> _pickEmployee() async {
    final picked = await showDialog<ExpenseEmployeeOption>(
      context: context,
      builder: (ctx) => const _EmployeePickerDialog(),
    );
    if (picked != null) {
      setState(() {
        _employeeId = picked.id;
        _employeeLabel =
            picked.name.isNotEmpty ? picked.name : 'موظف #${picked.id}';
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDate: _date,
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _save() async {
    final amount = _parseAmount();
    if (_categoryId <= 0 || amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار فئة وإدخال مبلغ صحيح.')),
      );
      return;
    }
    final catName = _currentCategoryName();
    if (expenseCategoryRequiresEmployee(catName) && _employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الموظف المستفيد من الراتب.')),
      );
      return;
    }
    setState(() => _saving = true);
    final db = DatabaseHelper();
    final desc = _descCtrl.text.trim();
    final statusDb = expenseStatusToDb(_status);
    final existing = widget.existing;
    final effectiveDay = _isRecurring
        ? (_recurringDay ?? _date.day).clamp(1, 28)
        : null;
    if (existing == null) {
      await db.insertExpense(
        categoryId: _categoryId,
        amount: amount,
        occurredAt: _date,
        status: statusDb,
        description: desc.isEmpty ? null : desc,
        employeeUserId: _employeeId,
        isRecurring: _isRecurring,
        recurringDay: effectiveDay,
        attachmentPath: _attachmentPath,
      );
    } else {
      await db.updateExpense(
        id: existing.id,
        categoryId: _categoryId,
        amount: amount,
        occurredAt: _date,
        status: statusDb,
        description: desc.isEmpty ? null : desc,
        employeeUserId: _employeeId,
        isRecurring: _isRecurring,
        recurringDay: effectiveDay,
        attachmentPath: _attachmentPath,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final title = widget.existing == null ? 'إضافة مصروف' : 'تعديل مصروف';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: _categoryId == 0 ? null : _categoryId,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: [
                  for (final c in widget.categories)
                    DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
                ],
                onChanged: _onCategoryChanged,
              ),
              if (expenseCategoryRequiresEmployee(_currentCategoryName())) ...[
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: ac.md,
                  onTap: _pickEmployee,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الموظف (المستفيد)',
                      suffixIcon: Icon(Icons.search_rounded),
                    ),
                    child: Text(
                      _employeeLabel.isEmpty
                          ? 'اختر موظفًا'
                          : _employeeLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _employeeLabel.isEmpty
                            ? cs.onSurfaceVariant
                            : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'المبلغ (د.ع)'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: ac.md,
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                          borderRadius: ac.md,
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_rounded, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              _dateFmt.format(_date),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<ExpenseStatus>(
                      value: _status,
                      borderRadius: ac.md,
                      items: const [
                        DropdownMenuItem(
                          value: ExpenseStatus.paid,
                          child: Text('مدفوع'),
                        ),
                        DropdownMenuItem(
                          value: ExpenseStatus.pending,
                          child: Text('معلق'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? ExpenseStatus.paid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _RecurringPicker(
                enabled: _isRecurring,
                day: _recurringDay,
                onToggle: (v) => setState(() {
                  _isRecurring = v;
                  if (v && _recurringDay == null) _recurringDay = _date.day;
                }),
                onDayChanged: (d) => setState(() => _recurringDay = d),
              ),
              if (expenseCategoryAllowsAttachment(_currentCategoryName())) ...[
                const SizedBox(height: 10),
                _AttachmentPicker(
                  path: _attachmentPath,
                  onPick: _pickAttachment,
                  onClear: _clearAttachment,
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: _currentCategoryName() == 'مصاريف متنوعة' ? 2 : 1,
                decoration: InputDecoration(
                  labelText: _currentCategoryName() == 'مصاريف متنوعة'
                      ? 'سبب الصرف (يُطبع مع الفاتورة)'
                      : 'الوصف (اختياري)',
                  helperText: _currentCategoryName() == 'مصاريف متنوعة'
                      ? 'اكتب هنا تعليقًا يوضح لماذا تم صرف هذا المبلغ.'
                      : null,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(widget.existing == null ? 'حفظ' : 'تحديث'),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPicker extends StatelessWidget {
  const _AttachmentPicker({
    required this.path,
    required this.onPick,
    required this.onClear,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final has = (path ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: ac.sm,
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: has
                ? Image.file(
                    File(path!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : Icon(Icons.receipt_long_outlined, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  has ? 'تم إرفاق صورة الفاتورة' : 'إرفاق صورة الفاتورة (اختياري)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  has
                      ? 'يمكنك تغييرها أو إزالتها في أي وقت.'
                      : 'مفيد لفواتير الماء/الكهرباء/الضرائب.',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (has)
            IconButton(
              tooltip: 'إزالة',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded, color: cs.error),
            ),
          FilledButton.tonalIcon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(has ? 'تغيير' : 'اختيار'),
          ),
        ],
      ),
    );
  }
}

class _RecurringPicker extends StatelessWidget {
  const _RecurringPicker({
    required this.enabled,
    required this.day,
    required this.onToggle,
    required this.onDayChanged,
  });

  final bool enabled;
  final int? day;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onDayChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.replay_rounded, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'مصروف شهري متكرر',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'يُستحق يوم',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: (day ?? 1).clamp(1, 28),
                    items: [
                      for (var d = 1; d <= 28; d++)
                        DropdownMenuItem<int>(
                          value: d,
                          child: Text('$d', textDirection: TextDirection.ltr),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) onDayChanged(v);
                    },
                  ),
                ),
                const Spacer(),
                Text(
                  'من كل شهر',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeePickerDialog extends StatefulWidget {
  const _EmployeePickerDialog();

  @override
  State<_EmployeePickerDialog> createState() => _EmployeePickerDialogState();
}

class _EmployeePickerDialogState extends State<_EmployeePickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ExpenseEmployeeOption> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => unawaited(_reload()));
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final rows =
        await DatabaseHelper().searchEmployeesForExpense(query: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _items = rows.map(ExpenseEmployeeOption.fromMap).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختيار موظف'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'ابحث بالاسم أو اسم المستخدم أو الهاتف',
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد نتائج.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                (e.name.isNotEmpty ? e.name[0] : '?'),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(
                              e.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              [
                                if (e.jobTitle.isNotEmpty) e.jobTitle,
                                if (e.phone.isNotEmpty) e.phone,
                              ].join(' • '),
                              textDirection: TextDirection.ltr,
                            ),
                            onTap: () => Navigator.of(context).pop(e),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}

