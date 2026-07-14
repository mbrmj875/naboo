import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../models/expense.dart';
import '../../../utils/iraqi_currency_format.dart';

/// مقاسات وألوان Stitch — Expenses Ledger (موبايل).
abstract final class ExpensesStitchMetrics {
  ExpensesStitchMetrics._();

  static const double pagePadding = 16;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double kpiCardWidth = 280;
  static const double kpiHeight = 112;
  static const double rowRadius = 12;

  static const Color background = Color(0xFFFBF8FC);
  static const Color navy = Color(0xFF081B37);
  static const Color gold = Color(0xFFFED752);
  static const Color onGold = Color(0xFF735D00);
  static const Color surfaceGray = Color(0xFFE4E1E5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderMuted = Color(0xFFC5C6CE);
  static const Color textPrimary = Color(0xFF1B1B1E);
  static const Color textMuted = Color(0xFF44474D);
}

/// KPI أفقي — «مصروف هذا الشهر» (بطاقة داكنة) + «مصروف اليوم».
class ExpensesStitchKpiCarousel extends StatelessWidget {
  const ExpensesStitchKpiCarousel({
    super.key,
    required this.items,
    required this.monthTotal,
    required this.todayTotal,
  });

  final List<ExpenseEntry> items;
  final double monthTotal;
  final double todayTotal;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    var todayCount = 0;
    var monthCount = 0;
    for (final e in items) {
      final d = e.occurredAt;
      final dKey = DateTime(d.year, d.month, d.day);
      if (dKey == todayKey) todayCount++;
      if (d.year == now.year && d.month == now.month) monthCount++;
    }

    return SizedBox(
      height: ExpensesStitchMetrics.kpiHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(
          start: ExpensesStitchMetrics.pagePadding,
          end: ExpensesStitchMetrics.pagePadding,
        ),
        children: [
          _KpiCard(
            label: 'مصروف هذا الشهر',
            amount: monthTotal,
            dark: true,
            footerIcon: Icons.receipt_long_outlined,
            footer: monthCount > 0
                ? '$monthCount ${monthCount == 1 ? 'عملية' : 'عمليات'} في الشهر'
                : 'لا عمليات هذا الشهر',
          ),
          const SizedBox(width: ExpensesStitchMetrics.gapMd),
          _KpiCard(
            label: 'مصروف اليوم',
            amount: todayTotal,
            dark: false,
            footerIcon: Icons.event_rounded,
            footer: todayCount > 0
                ? 'تم تسجيل $todayCount ${todayCount == 1 ? 'عملية' : 'عمليات'}'
                : 'لا عمليات اليوم',
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.amount,
    required this.dark,
    required this.footerIcon,
    required this.footer,
  });

  final String label;
  final double amount;
  final bool dark;
  final IconData footerIcon;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ExpensesStitchMetrics.kpiCardWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? ExpensesStitchMetrics.navy : ExpensesStitchMetrics.surfaceGray,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dark
                  ? Colors.white.withValues(alpha: 0.82)
                  : ExpensesStitchMetrics.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            IraqiCurrencyFormat.formatIqd(amount),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: dark ? ExpensesStitchMetrics.gold : ExpensesStitchMetrics.textPrimary,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                footerIcon,
                size: 16,
                color: dark
                    ? ExpensesStitchMetrics.gold.withValues(alpha: 0.9)
                    : ExpensesStitchMetrics.onGold,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: dark
                        ? Colors.white.withValues(alpha: 0.72)
                        : ExpensesStitchMetrics.onGold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شريط فلاتر أفقي — تاريخ، فئة، حالة (+ بحث اختياري).
class ExpensesStitchFilterStrip extends StatelessWidget {
  const ExpensesStitchFilterStrip({
    super.key,
    required this.dateLabel,
    required this.categoryLabel,
    required this.statusLabel,
    required this.onDateTap,
    required this.onCategoryTap,
    required this.onStatusTap,
    this.onSearchTap,
    this.searchActive = false,
  });

  final String dateLabel;
  final String categoryLabel;
  final String statusLabel;
  final VoidCallback onDateTap;
  final VoidCallback onCategoryTap;
  final VoidCallback onStatusTap;
  final VoidCallback? onSearchTap;
  final bool searchActive;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ExpensesStitchMetrics.pagePadding,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: '📅 $dateLabel',
            active: true,
            onTap: onDateTap,
          ),
          const SizedBox(width: ExpensesStitchMetrics.gapSm),
          _FilterChip(label: categoryLabel, onTap: onCategoryTap),
          const SizedBox(width: ExpensesStitchMetrics.gapSm),
          _FilterChip(label: statusLabel, onTap: onStatusTap),
          if (onSearchTap != null) ...[
            const SizedBox(width: ExpensesStitchMetrics.gapSm),
            _FilterChip(
              label: searchActive ? '🔍 بحث نشط' : '🔍 بحث',
              active: searchActive,
              onTap: onSearchTap!,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? ExpensesStitchMetrics.gold.withValues(alpha: 0.22)
          : const Color(0xFFEAE7EB),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? ExpensesStitchMetrics.gold
                  : ExpensesStitchMetrics.borderMuted,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active
                  ? ExpensesStitchMetrics.onGold
                  : ExpensesStitchMetrics.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط إجمالي الفترة — مضغوط.
class ExpensesStitchTotalStrip extends StatelessWidget {
  const ExpensesStitchTotalStrip({super.key, required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(
        horizontal: ExpensesStitchMetrics.pagePadding,
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ExpensesStitchMetrics.gold.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ExpensesStitchMetrics.gold),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              IraqiCurrencyFormat.formatIqd(total),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ExpensesStitchMetrics.onGold,
              ),
            ),
          ),
          Text(
            'إجمالي الفترة',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ExpensesStitchMetrics.onGold.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل بحث مضغوط للموبايل (بدون اختصارات لوحة مفاتيح).
class ExpensesStitchSearchField extends StatelessWidget {
  const ExpensesStitchSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ExpensesStitchMetrics.pagePadding,
        8,
        ExpensesStitchMetrics.pagePadding,
        4,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'بحث بالوصف أو الفئة…',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: controller.text.trim().isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                ),
          filled: true,
          fillColor: ExpensesStitchMetrics.surfaceWhite,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: ExpensesStitchMetrics.borderMuted),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: ExpensesStitchMetrics.borderMuted),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: ExpensesStitchMetrics.gold,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// صف مصروف مضغوط — Stitch Ledger row.
class ExpensesStitchLedgerRow extends StatelessWidget {
  const ExpensesStitchLedgerRow({
    super.key,
    required this.entry,
    required this.categoryColor,
    required this.highlighted,
    required this.onTap,
  });

  final ExpenseEntry entry;
  final Color categoryColor;
  final bool highlighted;
  final VoidCallback onTap;

  static final _rowDateFmt = DateFormat('d MMM', 'en');

  @override
  Widget build(BuildContext context) {
    final title = entry.description.trim().isNotEmpty
        ? entry.description.trim()
        : entry.categoryName;
    final subtitle =
        '${_rowDateFmt.format(entry.occurredAt)} - ${entry.categoryName}';

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: ExpensesStitchMetrics.pagePadding,
        end: ExpensesStitchMetrics.pagePadding,
        bottom: 8,
      ),
      child: Material(
        color: highlighted
            ? ExpensesStitchMetrics.gold.withValues(alpha: 0.12)
            : ExpensesStitchMetrics.surfaceWhite,
        borderRadius: BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
              border: Border.all(
                color: highlighted
                    ? ExpensesStitchMetrics.gold
                    : ExpensesStitchMetrics.surfaceGray,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ExpensesStitchMetrics.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: ExpensesStitchMetrics.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  IraqiCurrencyFormat.formatIqd(entry.amount),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ExpensesStitchMetrics.textPrimary,
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

Future<void> showExpensesStitchCategorySheet({
  required BuildContext context,
  required List<ExpenseCategory> categories,
  required int? selectedId,
  required ValueChanged<int?> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'اختر الفئة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          ListTile(
            title: const Text('كل الفئات'),
            trailing: selectedId == null ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              onSelected(null);
              Navigator.pop(ctx);
            },
          ),
          for (final cat in categories)
            ListTile(
              title: Text(cat.name),
              trailing: selectedId == cat.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                onSelected(cat.id);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> showExpensesStitchStatusSheet({
  required BuildContext context,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  const options = <String, String>{
    'all': 'الكل',
    'paid': 'مدفوع',
    'pending': 'غير مدفوع',
    'recurring': 'متكرر',
  };
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'حالة المصروف',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          for (final e in options.entries)
            ListTile(
              title: Text(e.value),
              trailing: selected == e.key ? const Icon(Icons.check_rounded) : null,
              onTap: () {
                onSelected(e.key);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

String expensesStitchStatusLabel(String status) {
  return switch (status) {
    'paid' => 'مدفوع ▾',
    'pending' => 'غير مدفوع ▾',
    'recurring' => 'متكرر ▾',
    _ => 'الكل ▾',
  };
}

String expensesStitchCategoryLabel(
  List<ExpenseCategory> categories,
  int? categoryId,
) {
  if (categoryId == null) return 'كل الفئات ▾';
  for (final c in categories) {
    if (c.id == categoryId) return '${c.name} ▾';
  }
  return 'كل الفئات ▾';
}

/// قائمة السجل — تخطيط Stitch للموبايل.
class ExpensesStitchLedgerList extends StatelessWidget {
  const ExpensesStitchLedgerList({
    super.key,
    required this.loading,
    required this.categories,
    required this.items,
    required this.total,
    required this.dateChipLabel,
    required this.searchCtrl,
    required this.searchFocus,
    required this.highlightExpenseId,
    required this.categoryId,
    required this.status,
    required this.onShowDateSheet,
    required this.onCategoryChanged,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onAddExpense,
  });

  final bool loading;
  final List<ExpenseCategory> categories;
  final List<ExpenseEntry> items;
  final double total;
  final String dateChipLabel;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final int? highlightExpenseId;
  final int? categoryId;
  final String status;
  final VoidCallback onShowDateSheet;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<ExpenseEntry> onEdit;
  final VoidCallback onAddExpense;

  double _todayTotal(List<ExpenseEntry> entries) {
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    var sum = 0.0;
    for (final e in entries) {
      final d = e.occurredAt;
      if (DateTime(d.year, d.month, d.day) == todayKey) sum += e.amount;
    }
    return sum;
  }

  double _monthTotal(List<ExpenseEntry> entries) {
    final now = DateTime.now();
    var sum = 0.0;
    for (final e in entries) {
      final d = e.occurredAt;
      if (d.year == now.year && d.month == now.month) sum += e.amount;
    }
    return sum;
  }

  String _dateChipLabel() => dateChipLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contentCount = loading ? 1 : (items.isEmpty ? 1 : items.length);
    const headerCount = 4;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: headerCount + contentCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: ExpensesStitchKpiCarousel(
              items: items,
              monthTotal: _monthTotal(items),
              todayTotal: _todayTotal(items),
            ),
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ExpensesStitchFilterStrip(
              dateLabel: _dateChipLabel(),
              categoryLabel: expensesStitchCategoryLabel(categories, categoryId),
              statusLabel: expensesStitchStatusLabel(status),
              searchActive: searchCtrl.text.trim().isNotEmpty,
              onDateTap: onShowDateSheet,
              onCategoryTap: () => unawaited(
                showExpensesStitchCategorySheet(
                  context: context,
                  categories: categories,
                  selectedId: categoryId,
                  onSelected: onCategoryChanged,
                ),
              ),
              onStatusTap: () => unawaited(
                showExpensesStitchStatusSheet(
                  context: context,
                  selected: status,
                  onSelected: onStatusChanged,
                ),
              ),
              onSearchTap: () => searchFocus.requestFocus(),
            ),
          );
        }
        if (index == 2) {
          return ExpensesStitchSearchField(
            controller: searchCtrl,
            focusNode: searchFocus,
          );
        }
        if (index == 3) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: ExpensesStitchTotalStrip(total: total),
          );
        }

        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ExpensesStitchMetrics.pagePadding,
              vertical: 24,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 48,
                  color: ExpensesStitchMetrics.gold.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا توجد مصروفات في هذه الفترة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'جرّب تغيير الفترة أو أضف مصروفاً جديداً',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAddExpense,
                  style: FilledButton.styleFrom(
                    backgroundColor: ExpensesStitchMetrics.gold,
                    foregroundColor: ExpensesStitchMetrics.onGold,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة مصروف'),
                ),
              ],
            ),
          );
        }

        final i = index - headerCount;
        final e = items[i];
        return ExpensesStitchLedgerRow(
          entry: e,
          categoryColor: expenseCategoryColor(e.categoryName, cs),
          highlighted: highlightExpenseId == e.id,
          onTap: () => onEdit(e),
        );
      },
    );
  }
}
