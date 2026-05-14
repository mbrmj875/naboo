import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/expense.dart';

/// يطبع/يعاين إيصال مصروف بتصميم مبسط (A6 عمودي).
class ExpenseReceiptPrinter {
  ExpenseReceiptPrinter._();

  static final _moneyFmt = NumberFormat('#,##0', 'en');
  static final _dateFmt = DateFormat('yyyy/MM/dd HH:mm', 'en');

  static Future<pw.Font> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  static Future<void> show(ExpenseEntry entry) async {
    final arFont = await _loadAsset('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final arBold = await _loadAsset('assets/fonts/NotoNaskhArabic-Bold.ttf');
    final latinFont = await _loadAsset('assets/fonts/Tajawal-Regular.ttf');
    final latinBold = await _loadAsset('assets/fonts/Tajawal-Bold.ttf');

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(16),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: arFont,
          bold: arBold,
          fontFallback: [latinFont, latinBold],
        ),
        build: (context) {
          pw.Widget row(String label, String value) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      label,
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ),
                  pw.Text(
                    value,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  'إيصال مصروف',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  '#${entry.id}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ),
              pw.Divider(thickness: 0.6, color: PdfColors.grey400),
              row('الفئة', entry.categoryName),
              if (entry.employeeName.isNotEmpty) row('المستفيد', entry.employeeName),
              row('التاريخ', _dateFmt.format(entry.occurredAt)),
              row('الحالة', entry.status == ExpenseStatus.paid ? 'مدفوع' : 'معلق'),
              if (entry.description.isNotEmpty) row('الوصف', entry.description),
              if (entry.isRecurring)
                row('تكرار شهري', 'يوم ${entry.recurringDay ?? '-'}'),
              if (entry.affectsCash)
                row('أثر على الصندوق', 'نعم (خصم)')
              else
                row('أثر على الصندوق', 'لا'),
              pw.Divider(thickness: 0.6, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      'الإجمالي:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      '${_moneyFmt.format(entry.amount)} د.ع',
                      textDirection: pw.TextDirection.ltr,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  'شكرًا لاستخدام NaBoo',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }
}
