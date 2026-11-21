
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

import '../models/print_settings_data.dart';
import '../services/effective_store_branding.dart';
import '../services/print_settings_repository.dart';
import '../services/thermal_network_printer_service.dart';
import '../utils/app_logger.dart';
import 'escpos_raster.dart';
import 'printer_connection.dart';
import 'receipt_builders.dart';
import 'receipt_model.dart';
import 'receipt_renderer.dart';
import 'transports/bluetooth_transport.dart';

enum PrintOutcome {
  /// أُرسل للطابعة.
  printed,

  /// الطباعة التلقائية مطفأة لهذا العمل.
  disabled,

  /// لا طابعة مربوطة بهذا الجهاز.
  notConfigured,

  /// فشلت (الرسالة في [PrintResult.message]).
  failed,
}

class PrintResult {
  const PrintResult(this.outcome, [this.message]);
  final PrintOutcome outcome;
  final String? message;
  bool get ok => outcome == PrintOutcome.printed;
}

/// نقطة الطباعة الوحيدة لكل الإيصالات: ترسم القالب ثم ترسله لطابعة الجهاز.
abstract final class ReceiptPrinter {
  /// لاستبدال الإعدادات في الاختبارات.
  @visibleForTesting
  static Future<PrintSettingsData> Function() loadSettings =
      PrintSettingsRepository.instance.load;

  @visibleForTesting
  static Future<PrinterConnection> Function(PrintSettingsData) loadConnection =
      (s) => PrinterConnection.load(legacy: s);

  /// يطبع إيصال الفاتورة بالقالب المناسب لنوع العمل.
  static Future<PrintResult> printInvoice(
    int invoiceId, {
    bool auto = false,
    PrintSettingsData? settings,
  }) async {
    try {
      final doc = await ReceiptBuilders.forInvoiceId(invoiceId);
      if (doc == null) {
        return const PrintResult(PrintOutcome.failed, 'الفاتورة غير موجودة.');
      }
      return printDocument(doc, auto: auto, settings: settings);
    } catch (e, st) {
      AppLogger.error('ReceiptPrinter', 'printInvoice', e, st);
      return PrintResult(PrintOutcome.failed, 'تعذر تجهيز الإيصال: $e');
    }
  }

  /// [auto] = طباعة بعد الحفظ: تُتخطى بصمت إن كانت مطفأة أو لا طابعة.
  static Future<PrintResult> printDocument(
    ReceiptDocument doc, {
    bool auto = false,
    PrinterConnection? connection,
    PrintSettingsData? settings,
  }) async {
    try {
      settings ??= await loadSettings();
      final template = ReceiptTemplates(settings.receiptTemplates).of(doc.kind);
      if (auto && !template.autoPrint) {
        return const PrintResult(PrintOutcome.disabled);
      }
      final conn = connection ?? await loadConnection(settings);
      if (!conn.isConfigured) {
        return const PrintResult(
          PrintOutcome.notConfigured,
          'لم تُربط طابعة بهذا الجهاز. اربطها من «الطباعة».',
        );
      }
      final rendered = await ReceiptRenderer.render(
        doc,
        settings: settings,
        template: template,
        paper: conn.effectivePaper,
        style: ReceiptTemplates(settings.receiptTemplates).style,
        monochrome: conn.isThermal,
      );
      try {
        await _send(conn, rendered, copies: template.copies, auto: auto);
      } finally {
        rendered.dispose();
      }
      return const PrintResult(PrintOutcome.printed);
    } catch (e, st) {
      AppLogger.error('ReceiptPrinter', 'printDocument ${doc.kind.name}', e, st);
      return PrintResult(PrintOutcome.failed, _friendly(e));
    }
  }

  /// بايتات ESC/POS للإيصال (للطابعة الحرارية والاختبارات).
  static Future<Uint8List> escPosBytes(
    RenderedReceipt rendered, {
    int copies = 1,
  }) async {
    final bmp = await MonoBitmap.fromRendered(rendered);
    return EscPosRaster.encode(bmp, copies: copies);
  }

  static Future<void> _send(
    PrinterConnection conn,
    RenderedReceipt rendered, {
    required int copies,
    required bool auto,
  }) async {
    switch (conn.type) {
      case PrinterType.none:
        return;
      case PrinterType.bluetooth:
        await BluetoothTransport.send(
          conn.btAddress,
          await escPosBytes(rendered, copies: copies),
        );
      case PrinterType.lan:
        await ThermalNetworkPrinterService.instance.sendBytes(
          host: conn.lanHost,
          port: conn.lanPort,
          payload: await escPosBytes(rendered, copies: copies),
          timeoutMs: 6000,
        );
      case PrinterType.system:
        await _systemPrint(conn, rendered, auto: auto);
    }
  }

  /// PDF بمقاس الورق وفيه صورة الإيصال نفسها. اللفافة صفحة واحدة بطول
  /// الإيصال، والورق الكبير (A5/A4) يُقسَّم على صفحات بارتفاع الورقة.
  static Future<Uint8List> pdfBytes(
    RenderedReceipt rendered,
    ReceiptPaper paper,
  ) async {
    const mm = PdfPageFormat.mm;
    final widthMm = paper.widthMm;
    final pdf = pw.Document();
    final sheetMm = paper.sheetHeightMm;
    if (sheetMm == null) {
      final png = await rendered.pngBytes();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            widthMm * mm,
            widthMm * rendered.height / rendered.width * mm,
          ),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ),
      );
      return pdf.save();
    }
    final pagePx = (rendered.width * sheetMm / widthMm).floor();
    for (var top = 0; top < rendered.height; top += pagePx) {
      final h = math.min(pagePx, rendered.height - top);
      final png = await _slicePng(rendered.image, top, h);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(widthMm * mm, sheetMm * mm),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Align(
            alignment: pw.Alignment.topCenter,
            child: pw.Image(
              pw.MemoryImage(png),
              width: widthMm * mm,
              height: widthMm * h / rendered.width * mm,
            ),
          ),
        ),
      );
    }
    return pdf.save();
  }

  static Future<Uint8List> _slicePng(ui.Image src, int top, int h) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawImageRect(
      src,
      ui.Rect.fromLTWH(0, top.toDouble(), src.width.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), h.toDouble()),
      ui.Paint(),
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(src.width, h);
    pic.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<void> _systemPrint(
    PrinterConnection conn,
    RenderedReceipt rendered, {
    required bool auto,
  }) async {
    final paper = conn.effectivePaper;
    final bytes = await pdfBytes(rendered, paper);
    final format = PdfPageFormat(
      paper.widthMm * PdfPageFormat.mm,
      paper.sheetHeightMm == null
          ? double.infinity
          : paper.sheetHeightMm! * PdfPageFormat.mm,
    );
    // على الحاسوب: طباعة صامتة على الطابعة الافتراضية عند الطباعة التلقائية.
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (auto && desktop) {
      final printers = await printing.Printing.listPrinters();
      if (printers.isNotEmpty) {
        final p = printers.firstWhere(
          (p) => p.isDefault,
          orElse: () => printers.first,
        );
        await printing.Printing.directPrintPdf(
          printer: p,
          onLayout: (_) => bytes,
          format: format,
        );
        return;
      }
    }
    await printing.Printing.layoutPdf(
      onLayout: (_) => bytes,
      format: format,
      name: 'receipt',
    );
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (e is StateError) return e.message;
    if (s.contains('SocketException') || s.contains('Connection refused')) {
      return 'تعذر الوصول لطابعة الشبكة. تأكد أنها مشغّلة وعلى نفس الشبكة.';
    }
    if (s.contains('مهلة')) return 'انتهت مهلة الاتصال بالطابعة.';
    return 'تعذرت الطباعة: $s';
  }

  /// بيانات المحل في الإيصال: فرع الموظف إن كان له فرع، وإلا بيانات المحل.
  static Future<PrintSettingsData?> _branding(BuildContext context) async {
    if (!context.mounted) return null;
    try {
      return await EffectiveStoreBranding.resolveFromContext(context);
    } catch (_) {
      return null;
    }
  }

  /// بعد حفظ عمل: يطبع تلقائياً إن كان مفعّلاً، ويُظهر رسالة عند الفشل فقط.
  /// لا يرمي أبداً، فالحفظ تمّ ولا يجوز أن يفشل بسبب الطابعة.
  static Future<void> autoPrintAfterSave(
    BuildContext context, {
    int? invoiceId,
    ReceiptDocument? document,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final settings = await _branding(context);
    final PrintResult r;
    if (document != null) {
      r = await printDocument(document, auto: true, settings: settings);
    } else if (invoiceId != null) {
      r = await printInvoice(invoiceId, auto: true, settings: settings);
    } else {
      return;
    }
    if (r.outcome == PrintOutcome.failed && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('حُفظ العمل، لكن الطباعة فشلت: ${r.message}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// طباعة يدوية بزر: يُظهر النتيجة دائماً.
  static Future<PrintResult> printWithFeedback(
    BuildContext context,
    Future<ReceiptDocument?> Function() build,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final settings = await _branding(context);
    final doc = await build();
    if (doc == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('تعذر تجهيز الإيصال.')),
      );
      return const PrintResult(PrintOutcome.failed, 'تعذر تجهيز الإيصال.');
    }
    final r = await printDocument(doc, settings: settings);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(switch (r.outcome) {
          PrintOutcome.printed => 'أُرسل الإيصال للطابعة.',
          _ => r.message ?? 'تعذرت الطباعة.',
        }),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return r;
  }
}
