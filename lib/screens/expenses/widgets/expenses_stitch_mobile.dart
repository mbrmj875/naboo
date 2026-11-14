import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../models/expense.dart';
import '../../../utils/iraqi_currency_format.dart';

/// مقاسات صفحة المصروفات (موبايل).
abstract final class ExpensesStitchMetrics {
  ExpensesStitchMetrics._();

  static const double pagePadding = 16;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double rowRadius = 12;

  /// توافق خلفي — يُفضّل [ExpensesStitchPalette.of].
  static const Color background = Color(0xFFF7F6F4);
  static const Color navy = Color(0xFF0B1F3A);
  static const Color gold = Color(0xFFE8C547);
  static const Color onGold = Color(0xFF5C4A00);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderMuted = Color(0xFFD8D6D2);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textMuted = Color(0xFF5C5C5C);
}

/// ألوان تتبع وضع الثيم (فاتح/ليلي).
@immutable
class ExpensesStitchPalette {
  const ExpensesStitchPalette({
    required this.background,
    required this.card,
    required this.summary,
    required this.gold,
    required this.onGold,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    required this.amount,
  });

  final Color background;
  final Color card;
  final Color summary;
  final Color gold;
  final Color onGold;
  final Color textPrimary;
  final Color textMuted;
  final Color border;
  final Color amount;

  factory ExpensesStitchPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gold = cs.secondary;
    return ExpensesStitchPalette(
      background: theme.scaffoldBackgroundColor,
      card: isDark ? const Color(0xFF1E293B) : cs.surface,
      summary: isDark ? const Color(0xFF0F172A) : const Color(0xFF0B1F3A),
      gold: gold,
      onGold: isDark ? cs.onSecondary : const Color(0xFF5C4A00),
      textPrimary: cs.onSurface,
      textMuted: cs.onSurfaceVariant,
      border: cs.outline.withValues(alpha: isDark ? 0.45 : 0.55),
      amount: isDark ? gold : const Color(0xFF0B1F3A),
    );
  }
}

/// ملخص واحد: إجمالي الفترة + اليوم/الشهر.
class ExpensesStitchSummaryHeader extends StatelessWidget {
  const ExpensesStitchSummaryHeader({
    super.key,
    required this.periodTotal,
    required this.monthTotal,
    required this.todayTotal,
    required this.periodCount,
  });

  final double periodTotal;
  final double monthTotal;
  final double todayTotal;
  final int periodCount;

  @override
  Widget build(BuildContext context) {
    final p = ExpensesStitchPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ExpensesStitchMetrics.pagePadding,
        8,
        ExpensesStitchMetrics.pagePadding,
        4,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: p.summary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              periodCount > 0
                  ? 'إجمالي الفترة · $periodCount عملية'
                  : 'إجمالي الفترة',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              IraqiCurrencyFormat.formatIqd(periodTotal),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: p.gold,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(label: 'اليوم', amount: todayTotal),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                Expanded(
                  child: _MiniStat(label: 'هذا الشهر', amount: monthTotal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            IraqiCurrencyFormat.formatIqd(amount),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط فلاتر مضغوط — تاريخ / فئة / حالة.
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
            icon: Icons.calendar_month_rounded,
            label: dateLabel,
            active: true,
            onTap: onDateTap,
          ),
          const SizedBox(width: ExpensesStitchMetrics.gapSm),
          _FilterChip(
            icon: Icons.category_outlined,
            label: categoryLabel,
            onTap: onCategoryTap,
          ),
          const SizedBox(width: ExpensesStitchMetrics.gapSm),
          _FilterChip(
            icon: Icons.filter_list_rounded,
            label: statusLabel,
            onTap: onStatusTap,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    required this.icon,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = ExpensesStitchPalette.of(context);
    final fg = active ? p.onGold : p.textPrimary;
    return Material(
      color: active ? p.gold.withValues(alpha: 0.28) : p.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? p.gold : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// توافق خلفي.
class ExpensesStitchTotalStrip extends StatelessWidget {
  const ExpensesStitchTotalStrip({super.key, required this.total});

  final double total;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// توافق خلفي لاسم الـ KPI القديم.
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
    return ExpensesStitchSummaryHeader(
      periodTotal: monthTotal,
      monthTotal: monthTotal,
      todayTotal: todayTotal,
      periodCount: items.length,
    );
  }
}

/// حقل بحث مضغوط.
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
    final p = ExpensesStitchPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ExpensesStitchMetrics.pagePadding,
        4,
        ExpensesStitchMetrics.pagePadding,
        0,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: p.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'بحث بالوصف أو الفئة…',
          hintStyle: TextStyle(fontSize: 13, color: p.textMuted),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: p.textMuted),
          suffixIcon: controller.text.trim().isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: p.textMuted),
                  onPressed: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                ),
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.gold, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// صف مصروف في السجل.
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

  @override
  Widget build(BuildContext context) {
    final p = ExpensesStitchPalette.of(context);
    final dateLabel = DateFormat('dd/MM', 'en').format(entry.occurredAt);
    final cat = entry.categoryName.trim();
    final desc = entry.description.trim().isEmpty
        ? (cat.isEmpty ? 'بدون وصف' : cat)
        : entry.description.trim();
    final statusLabel = entry.isRecurring
        ? 'متكرر'
        : switch (entry.status) {
            ExpenseStatus.paid => 'مدفوع',
            ExpenseStatus.pending => 'غير مدفوع',
          };

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ExpensesStitchMetrics.pagePadding,
        0,
        ExpensesStitchMetrics.pagePadding,
        8,
      ),
      child: Material(
        color: highlighted ? p.gold.withValues(alpha: 0.18) : p.card,
        borderRadius: BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(ExpensesStitchMetrics.rowRadius),
              border: Border.all(
                color: highlighted ? p.gold : p.border.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (cat.isNotEmpty) cat,
                          dateLabel,
                          statusLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  IraqiCurrencyFormat.formatIqd(entry.amount),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: p.amount,
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
    isScrollControlled: true,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'فئة المصروف',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: const Text('كل الفئات'),
                      trailing: selectedId == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () {
                        onSelected(null);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final c in categories)
                      ListTile(
                        title: Text(c.name),
                        trailing: selectedId == c.id
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () {
                          onSelected(c.id);
                          Navigator.pop(ctx);
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
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
      child: SingleChildScrollView(
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
                trailing:
                    selected == e.key ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  onSelected(e.key);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

String expensesStitchStatusLabel(String status) {
  return switch (status) {
    'paid' => 'مدفوع',
    'pending' => 'غير مدفوع',
    'recurring' => 'متكرر',
    _ => 'الكل',
  };
}

String expensesStitchCategoryLabel(
  List<ExpenseCategory> categories,
  int? categoryId,
) {
  if (categoryId == null) return 'كل الفئات';
  for (final c in categories) {
    if (c.id == categoryId) return c.name;
  }
  return 'كل الفئات';
}

/// قائمة السجل — تخطيط موبايل مضغوط.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = ExpensesStitchPalette.of(context);
    final contentCount = loading ? 1 : (items.isEmpty ? 1 : items.length);
    const headerCount = 3;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: headerCount + contentCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ExpensesStitchSummaryHeader(
            periodTotal: total,
            monthTotal: _monthTotal(items),
            todayTotal: _todayTotal(items),
            periodCount: items.length,
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ExpensesStitchFilterStrip(
              dateLabel: dateChipLabel,
              categoryLabel:
                  expensesStitchCategoryLabel(categories, categoryId),
              statusLabel: expensesStitchStatusLabel(status),
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
            ),
          );
        }
        if (index == 2) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ExpensesStitchSearchField(
              controller: searchCtrl,
              focusNode: searchFocus,
            ),
          );
        }

        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ExpensesStitchMetrics.pagePadding,
              vertical: 40,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 44,
                  color: p.textMuted.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 12),
                Text(
                  'لا توجد مصروفات في هذه الفترة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'غيّر الفترة من الأعلى أو اضغط + لإضافة مصروف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
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
