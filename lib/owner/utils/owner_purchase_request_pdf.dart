import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

import '../models/owner_kpi_models.dart';

class PurchaseRequestPdfInput {
  const PurchaseRequestPdfInput({
    required this.storeTitle,
    required this.generatedAtIso,
    required this.items,
  });

  final String storeTitle;
  final String generatedAtIso;
  final List<PurchaseRequestPdfItem> items;
}

class PurchaseRequestPdfItem {
  const PurchaseRequestPdfItem({
    required this.name,
    required this.qty,
    required this.threshold,
  });

  final String name;
  final double qty;
  final double threshold;

  factory PurchaseRequestPdfItem.fromRow(ShortageProductRow row) {
    return PurchaseRequestPdfItem(
      name: row.name,
      qty: row.qty,
      threshold: row.lowStockThreshold,
    );
  }

  /// كمية مقترحة للطلب — لتغطية النقص حتى حد التنبيه.
  double get suggestedOrderQty {
    if (threshold <= 0) return 1;
    final gap = threshold - qty;
    if (gap <= 0) return 1;
    return gap;
  }
}

/// يُبنى على isolate الرئيسي — [rootBundle] لا يعمل داخل [compute].
Future<Uint8List> buildOwnerPurchaseRequestPdf(
  PurchaseRequestPdfInput input,
) async {
  final regularBytes = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
  final boldBytes = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
  final regular = pw.Font.ttf(regularBytes);
  final bold = pw.Font.ttf(boldBytes);

  final generatedAt = DateTime.tryParse(input.generatedAtIso) ?? DateTime.now();
  final dateLabel = DateFormat('d/M/y HH:mm', 'ar_SA').format(generatedAt);
  final qtyFmt = NumberFormat('#,##0.##', 'ar_SA');
  final storeTitle =
      input.storeTitle.trim().isNotEmpty ? input.storeTitle.trim() : 'طلبية شراء';

  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      build: (ctx) {
        return [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    storeTitle,
                    style: pw.TextStyle(font: bold, fontSize: 18),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'طلبية شراء — نواقص المخزون',
                    style: pw.TextStyle(font: regular, fontSize: 12),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    dateLabel,
                    style: pw.TextStyle(font: regular, fontSize: 10),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${input.items.length} ${input.items.length == 1 ? 'صنف' : 'أصناف'}',
                    style: pw.TextStyle(font: bold, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'يرجى تجهيز الكميات المقترحة أدناه. '
              'الكمية المقترحة = النقص حتى حد التنبيه.',
              style: pw.TextStyle(font: regular, fontSize: 9.5),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'الصنف',
              'المتوفر',
              'حد التنبيه',
              'كمية مقترحة',
            ],
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 10,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: pw.TextStyle(font: regular, fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.2),
            },
            data: [
              for (var i = 0; i < input.items.length; i++)
                [
                  '${i + 1}',
                  input.items[i].name,
                  qtyFmt.format(input.items[i].qty),
                  qtyFmt.format(input.items[i].threshold),
                  qtyFmt.format(input.items[i].suggestedOrderQty),
                ],
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 6),
          pw.Text(
            'تم إنشاء هذا المستند تلقائياً من لوحة المالك — Naboo ERP',
            style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ];
      },
    ),
  );
  return pdf.save();
}

Future<void> previewOwnerPurchaseRequestPdf(
  BuildContext context, {
  required PurchaseRequestPdfInput input,
}) async {
  if (input.items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لا توجد أصناف ناقصة للطباعة')),
    );
    return;
  }

  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => _PurchaseRequestPdfPreviewPage(input: input),
    ),
  );
}

class _PurchaseRequestPdfPreviewPage extends StatefulWidget {
  const _PurchaseRequestPdfPreviewPage({required this.input});

  final PurchaseRequestPdfInput input;

  @override
  State<_PurchaseRequestPdfPreviewPage> createState() =>
      _PurchaseRequestPdfPreviewPageState();
}

class _PurchaseRequestPdfPreviewPageState
    extends State<_PurchaseRequestPdfPreviewPage> {
  Uint8List? _pdfBytes;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await buildOwnerPurchaseRequestPdf(widget.input);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final itemCount = widget.input.items.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'معاينة طلبية الشراء',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                '$itemCount ${itemCount == 1 ? 'صنف ناقص' : 'أصناف ناقصة'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onPrimary.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ إعداد ملف PDF…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'تعذّر إنشاء ملف طلبية الشراء',
                style: TextStyle(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _generatePdf,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final maxW = math.min(MediaQuery.sizeOf(context).width - 16, 720).toDouble();
    return printing.PdfPreview(
      padding: const EdgeInsets.all(8),
      maxPageWidth: maxW,
      canChangeOrientation: false,
      canChangePageFormat: false,
      allowPrinting: true,
      allowSharing: true,
      canDebug: false,
      pdfFileName: 'purchase-request.pdf',
      onPrintError: (ctx, error) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text('تعذّر الطباعة — تحقق من الطابعة أو الصلاحيات'),
            backgroundColor: Theme.of(ctx).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      build: (_) async => _pdfBytes!,
    );
  }
}
