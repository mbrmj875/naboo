import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/expense.dart';
import '../../services/database_helper.dart';

/// نافذة اختيار فترة فاتورة التقرير.
class _ReportRangeQuickOption {
  const _ReportRangeQuickOption({
    required this.label,
    required this.compute,
  });
  final String label;
  final DateTimeRange Function() compute;
}

class _ReportRangePickerDialog extends StatefulWidget {
  const _ReportRangePickerDialog({required this.initial});
  final DateTimeRange initial;

  @override
  State<_ReportRangePickerDialog> createState() => _ReportRangePickerDialogState();
}

class _ReportRangePickerDialogState extends State<_ReportRangePickerDialog> {
  late DateTimeRange _range = widget.initial;

  DateTime get _today => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  List<_ReportRangeQuickOption> _options() => [
        _ReportRangeQuickOption(
          label: 'يومي',
          compute: () {
            final d = _today;
            return DateTimeRange(start: d, end: d);
          },
        ),
        _ReportRangeQuickOption(
          label: 'أسبوعي',
          compute: () {
            final end = _today;
            final start = end.subtract(const Duration(days: 6));
            return DateTimeRange(start: start, end: end);
          },
        ),
        _ReportRangeQuickOption(
          label: 'شهري',
          compute: () {
            final now = DateTime.now();
            return DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: _today,
            );
          },
        ),
        _ReportRangeQuickOption(
          label: 'سنوي',
          compute: () {
            final now = DateTime.now();
            return DateTimeRange(
              start: DateTime(now.year, 1, 1),
              end: _today,
            );
          },
        ),
      ];

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: _today,
      initialDateRange: _range,
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('yyyy/MM/dd', 'en');
    final label = '${dateFmt.format(_range.start)}  ->  ${dateFmt.format(_range.end)}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('طباعة تقرير مصروفات'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اختر الفترة الزمنية للفاتورة:',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in _options())
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _range = opt.compute()),
                      icon: const Icon(Icons.event_rounded, size: 16),
                      label: Text(opt.label),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickCustom,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('مخصص'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'الفترة المختارة:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      label,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
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
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_range),
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('طباعة'),
          ),
        ],
      ),
    );
  }
}

Future<DateTimeRange?> showExpenseReportRangePicker(
  BuildContext context,
  DateTimeRange initial,
) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _ReportRangePickerDialog(initial: initial),
  );
}

/// مُولّد فاتورة تقرير المصروفات (PDF) مع دعم RTL العربية.
class ExpenseReportPrinter {
  ExpenseReportPrinter._();

  static final _moneyFmt = NumberFormat('#,##0', 'en');
  static final _dateFmt = DateFormat('yyyy/MM/dd', 'en');

  static Future<pw.Font> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  static Future<void> show({
    required BuildContext context,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = DatabaseHelper();

    // نعيد استخدام نفس استعلامات قاعدة البيانات الحالية للمصروفات.
    final rows = await db.getExpenses(
      from: from,
      to: to,
      status: 'all',
      limit: 10000,
    );
    final items = rows.map(ExpenseEntry.fromJoinedRow).toList();
    final total = items.fold<double>(0, (a, b) => a + b.amount);
    final paid = items
        .where((e) => e.status == ExpenseStatus.paid)
        .fold<double>(0, (a, b) => a + b.amount);
    final pending = total - paid;

    final byCategory = <String, List<ExpenseEntry>>{};
    for (final e in items) {
      byCategory.putIfAbsent(e.categoryName, () => <ExpenseEntry>[]).add(e);
    }
    final sortedCategoryKeys = byCategory.keys.toList()
      ..sort((a, b) {
        final ta = byCategory[a]!.fold<double>(0, (s, e) => s + e.amount);
        final tb = byCategory[b]!.fold<double>(0, (s, e) => s + e.amount);
        return tb.compareTo(ta);
      });

    final arFont = await _loadAsset('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final arBold = await _loadAsset('assets/fonts/NotoNaskhArabic-Bold.ttf');
    final latinFont = await _loadAsset('assets/fonts/Tajawal-Regular.ttf');
    final latinBold = await _loadAsset('assets/fonts/Tajawal-Bold.ttf');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: arFont,
          bold: arBold,
          fontFallback: [latinFont, latinBold],
        ),
        header: (ctx) => _pdfHeader(from, to),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          _pdfSummary(total: total, paid: paid, pending: pending, count: items.length),
          pw.SizedBox(height: 10),
          _pdfCategoryBreakdownTable(
            categoriesOrder: sortedCategoryKeys,
            byCategory: byCategory,
            total: total,
          ),
          pw.SizedBox(height: 14),
          ..._pdfCategoriesDetails(
            categoriesOrder: sortedCategoryKeys,
            byCategory: byCategory,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static pw.Widget _pdfHeader(DateTime from, DateTime to) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'فاتورة تقرير المصروفات',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'الفترة: ${_dateFmt.format(from)}  ->  ${_dateFmt.format(to)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 0.6, color: PdfColors.grey500),
      ],
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        children: [
          pw.Text(
            'تم الإنشاء: ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.Spacer(),
          pw.Text(
            'صفحة ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfSummary({
    required double total,
    required double paid,
    required double pending,
    required int count,
  }) {
    pw.Widget box(String label, String value, {PdfColor? color}) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(
                value,
                textDirection: pw.TextDirection.ltr,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: [
        box('الإجمالي', '${_moneyFmt.format(total)} د.ع', color: PdfColors.indigo900),
        box('المدفوع', '${_moneyFmt.format(paid)} د.ع', color: PdfColors.green800),
        box('المعلق', '${_moneyFmt.format(pending)} د.ع', color: PdfColors.amber900),
        box('عدد العمليات', '$count'),
      ],
    );
  }

  static pw.Widget _pdfCategoryBreakdownTable({
    required List<String> categoriesOrder,
    required Map<String, List<ExpenseEntry>> byCategory,
    required double total,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _pdfCell('الفئة', isHeader: true),
            _pdfCell('الإجمالي', isHeader: true, ltr: true),
            _pdfCell('النسبة', isHeader: true, ltr: true),
            _pdfCell('عدد العمليات', isHeader: true, ltr: true),
          ],
        ),
        for (final key in categoriesOrder)
          pw.TableRow(children: [
            _pdfCell(key),
            _pdfCell(
              '${_moneyFmt.format(byCategory[key]!.fold<double>(0, (s, e) => s + e.amount))} د.ع',
              ltr: true,
            ),
            _pdfCell(
              total <= 0
                  ? '0%'
                  : '${(byCategory[key]!.fold<double>(0, (s, e) => s + e.amount) / total * 100).toStringAsFixed(1)}%',
              ltr: true,
            ),
            _pdfCell('${byCategory[key]!.length}', ltr: true),
          ]),
      ],
    );
  }

  static List<pw.Widget> _pdfCategoriesDetails({
    required List<String> categoriesOrder,
    required Map<String, List<ExpenseEntry>> byCategory,
  }) {
    final widgets = <pw.Widget>[];
    for (final key in categoriesOrder) {
      final list = byCategory[key]!;
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(
            key,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      if (key == 'رواتب') {
        widgets.add(_pdfSalariesTable(list));
      } else if (key == 'مصاريف متنوعة') {
        widgets.add(_pdfMiscTableWithNotes(list));
      } else {
        widgets.add(_pdfStandardCategoryTable(list));
      }
    }
    return widgets;
  }

  static pw.Widget _pdfStandardCategoryTable(List<ExpenseEntry> list) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _pdfCell('التاريخ', isHeader: true, ltr: true),
            _pdfCell('المبلغ', isHeader: true, ltr: true),
            _pdfCell('الوصف', isHeader: true),
          ],
        ),
        for (final e in list)
          pw.TableRow(children: [
            _pdfCell(_dateFmt.format(e.occurredAt), ltr: true),
            _pdfCell('${_moneyFmt.format(e.amount)} د.ع', ltr: true),
            _pdfCell(e.description.isEmpty ? '-' : e.description),
          ]),
      ],
    );
  }

  static pw.Widget _pdfSalariesTable(List<ExpenseEntry> list) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _pdfCell('الموظف', isHeader: true),
            _pdfCell('التاريخ', isHeader: true, ltr: true),
            _pdfCell('المبلغ', isHeader: true, ltr: true),
            _pdfCell('الوصف', isHeader: true),
          ],
        ),
        for (final e in list)
          pw.TableRow(children: [
            _pdfCell(e.employeeName.isEmpty ? '-' : e.employeeName),
            _pdfCell(_dateFmt.format(e.occurredAt), ltr: true),
            _pdfCell('${_moneyFmt.format(e.amount)} د.ع', ltr: true),
            _pdfCell(e.description.isEmpty ? '-' : e.description),
          ]),
      ],
    );
  }

  static pw.Widget _pdfMiscTableWithNotes(List<ExpenseEntry> list) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _pdfCell('التاريخ', isHeader: true, ltr: true),
            _pdfCell('المبلغ', isHeader: true, ltr: true),
            _pdfCell('سبب الصرف (تعليق)', isHeader: true),
          ],
        ),
        for (final e in list)
          pw.TableRow(children: [
            _pdfCell(_dateFmt.format(e.occurredAt), ltr: true),
            _pdfCell('${_moneyFmt.format(e.amount)} د.ع', ltr: true),
            _pdfCell(
              e.description.isEmpty
                  ? 'بدون تعليق - يُنصح بإضافة سبب الصرف.'
                  : e.description,
            ),
          ]),
      ],
    );
  }

  static pw.Widget _pdfCell(
    String value, {
    bool isHeader = false,
    bool ltr = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        value,
        textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
