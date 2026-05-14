import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

class BarcodeLabelProduct {
  const BarcodeLabelProduct({
    required this.id,
    required this.name,
    required this.barcode,
    required this.sellPrice,
    required this.stockBaseKind,
  });

  final int id;
  final String name;
  final String barcode;
  final double sellPrice;
  final int stockBaseKind; // 1 = وزن
}

enum BarcodeLabelSize {
  mm50x30,
  mm40x30,
  mm30x50,
}

extension BarcodeLabelSizeX on BarcodeLabelSize {
  PdfPageFormat get pageFormat {
    const mm = PdfPageFormat.mm;
    return switch (this) {
      BarcodeLabelSize.mm40x30 => const PdfPageFormat(40 * mm, 30 * mm),
      BarcodeLabelSize.mm50x30 => const PdfPageFormat(50 * mm, 30 * mm),
      BarcodeLabelSize.mm30x50 => const PdfPageFormat(30 * mm, 50 * mm),
    };
  }

  /// عرض ملصق مبسّط لقائمة الاختيار (نفس نسب الصفحة).
  Size get thumbnailLogicalSize => switch (this) {
        BarcodeLabelSize.mm40x30 => const Size(40, 30),
        BarcodeLabelSize.mm50x30 => const Size(50, 30),
        BarcodeLabelSize.mm30x50 => const Size(30, 50),
      };

  /// نص المواصفات: عرض × ارتفاع (مثل واجهة الطابعة الشائعة).
  String get labelAr => switch (this) {
        BarcodeLabelSize.mm50x30 => '50 × 30 مم',
        BarcodeLabelSize.mm40x30 => '40 × 30 مم',
        BarcodeLabelSize.mm30x50 => '30 × 50 مم',
      };
}

/// ترتيب عرض مقاسات الملصقات الشائعة أولاً.
const List<BarcodeLabelSize> kBarcodeLabelSizesCommonFirst = [
  BarcodeLabelSize.mm50x30,
  BarcodeLabelSize.mm40x30,
  BarcodeLabelSize.mm30x50,
];

class BarcodeLabelsPdf {
  static Future<Uint8List> build({
    required List<BarcodeLabelProduct> products,
    required Map<int, int> copiesByProductId,
    required BarcodeLabelSize size,
    required bool showName,
    required bool showPrice,
  }) async {
    final font = await printing.PdfGoogleFonts.notoNaskhArabicRegular();
    final fontBold = await printing.PdfGoogleFonts.notoNaskhArabicBold();

    final pdf = pw.Document();
    final fmt = size.pageFormat;
    final pad = 2.0 * PdfPageFormat.mm;
    final inner = fmt.copyWith(
      marginLeft: pad,
      marginRight: pad,
      marginTop: pad,
      marginBottom: pad,
    );

    pw.Widget one(BarcodeLabelProduct p) {
      final name = p.name.trim().isEmpty ? 'صنف' : p.name.trim();
      final bcText = p.barcode.trim();
      final price = p.sellPrice;
      final isWeight = p.stockBaseKind == 1;

      final titleStyle = pw.TextStyle(font: fontBold, fontSize: 10);
      final smallStyle = pw.TextStyle(font: font, fontSize: 9);

      return pw.Container(
        width: inner.width,
        height: inner.height,
        padding: const pw.EdgeInsets.all(0),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (showName)
              pw.Text(
                name,
                style: titleStyle,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                textAlign: pw.TextAlign.right,
                textDirection: pw.TextDirection.rtl,
              ),
            if (showName) pw.SizedBox(height: 2),
            pw.Expanded(
              child: pw.Center(
                child: pw.BarcodeWidget(
                  barcode: bc.Barcode.code128(),
                  data: bcText,
                  drawText: false,
                  width: inner.width,
                  height: math.max(22, inner.height - (showName ? 14 : 0) - (showPrice ? 12 : 0)),
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  bcText,
                  style: pw.TextStyle(font: font, fontSize: 8),
                  textDirection: pw.TextDirection.ltr,
                ),
                if (showPrice)
                  pw.Text(
                    isWeight
                        ? '${_fmtIqd(price)} د.ع/كغم'
                        : '${_fmtIqd(price)} د.ع',
                    style: smallStyle,
                    textDirection: pw.TextDirection.rtl,
                  ),
              ],
            ),
          ],
        ),
      );
    }

    for (final p in products) {
      final c = (copiesByProductId[p.id] ?? 0).clamp(0, 999);
      for (var i = 0; i < c; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: inner,
            build: (_) => one(p),
          ),
        );
      }
    }

    return pdf.save();
  }

  static String _fmtIqd(double v) {
    final n = v.isFinite ? v.round() : 0;
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  static Future<void> present(
    BuildContext context, {
    required String title,
    required List<BarcodeLabelProduct> products,
    required Map<int, int> copiesByProductId,
    required BarcodeLabelSize size,
    required bool showName,
    required bool showPrice,
  }) async {
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: Text(title),
              ),
              body: printing.PdfPreview(
                padding: const EdgeInsets.all(8),
                maxPageWidth: math.min(MediaQuery.sizeOf(ctx).width - 16, 560),
                initialPageFormat: size.pageFormat,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowPrinting: false,
                allowSharing: true,
                canDebug: false,
                actions: [
                  printing.PdfPreviewAction(
                    icon: const Icon(Icons.print_rounded),
                    onPressed: (c, b, f) => _safePrintAction(c, b, f),
                  ),
                ],
                pdfFileName: 'barcode-labels.pdf',
                onPrintError: (context, error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'لم يتم العثور على طابعة متصلة بالجهاز. يرجى مراجعة توصيل الطابعة.',
                        style: TextStyle(fontFamily: 'NotoNaskhArabic'),
                      ),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                build: (_) => build(
                  products: products,
                  copiesByProductId: copiesByProductId,
                  size: size,
                  showName: showName,
                  showPrice: showPrice,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _safePrintAction(
    BuildContext context,
    FutureOr<Uint8List> Function(PdfPageFormat) buildPdf,
    PdfPageFormat pageFormat,
  ) async {
    final scaffoldMsg = ScaffoldMessenger.of(context);
    try {
      final printers = await printing.Printing.listPrinters();
      if (printers.isEmpty) {
        scaffoldMsg.showSnackBar(
          const SnackBar(
            content: Text(
              'لم يتم العثور على أي طابعة متصلة بالجهاز. يرجى توصيل طابعة للمتابعة.',
              style: TextStyle(fontFamily: 'NotoNaskhArabic'),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      
      final printer = printers.firstWhere(
        (p) => p.isDefault,
        orElse: () => printers.first,
      );
      
      final bytes = await buildPdf(pageFormat);
      
      await printing.Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) => bytes,
        format: pageFormat,
      );
    } catch (e) {
      scaffoldMsg.showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تشغيل الطباعة المباشرة. يرجى مراجعة إعدادات جهاز الطباعة لديك.',
            style: TextStyle(fontFamily: 'NotoNaskhArabic'),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

