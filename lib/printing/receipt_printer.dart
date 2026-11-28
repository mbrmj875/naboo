import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;
import 'package:share_plus/share_plus.dart';

import '../models/print_settings_data.dart';
import '../services/effective_store_branding.dart';
import '../services/print_settings_repository.dart';
import '../services/thermal_network_printer_service.dart';
import '../utils/app_logger.dart';
import 'escpos_raster.dart';
import 'printer_connection.dart';
import 'public_receipt.dart';
import 'receipt_builders.dart';
import 'receipt_design.dart';
import 'receipt_model.dart';
import 'receipt_renderer.dart';
import 'transports/bluetooth_transport.dart';

/// صيغة المشاركة.
enum ReceiptShareFormat { image, pdf }

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

  /// رابط صفحة الفاتورة على naboo.fun في QR (قابل للاستبدال في الاختبارات).
  static Future<ReceiptDocument> Function(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptTemplate template,
    ReceiptDesign? design,
  })
  publicLink = PublicReceiptLinks.attach;

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
      final design = ReceiptTemplates(
        settings.receiptTemplates,
      ).designFor(doc.kind);
      doc = await publicLink(
        doc,
        settings: settings,
        template: template,
        design: design,
      );
      final rendered = await ReceiptRenderer.render(
        doc,
        settings: settings,
        template: template,
        paper: conn.effectivePaper,
        design: design,
        monochrome: conn.isThermal,
      );
      try {
        await _send(conn, rendered, copies: template.copies, auto: auto);
      } finally {
        rendered.dispose();
      }
      return const PrintResult(PrintOutcome.printed);
    } catch (e, st) {
      AppLogger.error(
        'ReceiptPrinter',
        'printDocument ${doc.kind.name}',
        e,
        st,
      );
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
        await _systemPrint(conn, rendered, copies: copies, auto: auto);
    }
  }

  /// PDF بمقاس الورق وفيه صورة الإيصال نفسها. اللفافة صفحة واحدة بطول
  /// الإيصال، والورق الكبير (A5/A4) يُقسَّم على صفحات بارتفاع الورقة.
  ///
  /// [copies]: تتكرر صفحات الإيصال كلها بعدد النسخ (طابعة النظام لا تعرف
  /// نسخ القالب). المشاركة تبقى نسخة واحدة.
  static Future<Uint8List> pdfBytes(
    RenderedReceipt rendered,
    ReceiptPaper paper, {
    int copies = 1,
  }) async {
    const mm = PdfPageFormat.mm;
    final widthMm = paper.widthMm;
    final pdf = pw.Document();
    final sheetMm = paper.sheetHeightMm;
    final n = copies.clamp(1, 3);
    if (sheetMm == null) {
      final image = pw.MemoryImage(await rendered.pngBytes());
      for (var i = 0; i < n; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              widthMm * mm,
              widthMm * rendered.height / rendered.width * mm,
            ),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
          ),
        );
      }
      return pdf.save();
    }
    final pagePx = (rendered.width * sheetMm / widthMm).floor();
    final slices = <(pw.MemoryImage, int)>[];
    for (var top = 0; top < rendered.height; top += pagePx) {
      final h = math.min(pagePx, rendered.height - top);
      slices.add((pw.MemoryImage(await _slicePng(rendered.image, top, h)), h));
    }
    for (var i = 0; i < n; i++) {
      for (final (image, h) in slices) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(widthMm * mm, sheetMm * mm),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Image(
                image,
                width: widthMm * mm,
                height: widthMm * h / rendered.width * mm,
              ),
            ),
          ),
        );
      }
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
    required int copies,
    required bool auto,
  }) async {
    final paper = conn.effectivePaper;
    final bytes = await pdfBytes(rendered, paper, copies: copies);
    final format = PdfPageFormat(
      paper.widthMm * PdfPageFormat.mm,
      paper.sheetHeightMm == null
          ? double.infinity
          : paper.sheetHeightMm! * PdfPageFormat.mm,
    );
    // على الحاسوب: طباعة صامتة على الطابعة الافتراضية عند الطباعة التلقائية.
    final desktop =
        !kIsWeb &&
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

  /// يرسم الإيصال PDF بطابعة هذا الجهاز ومقاسها وقالب نوعه ومظهر المحل.
  static Future<(Uint8List, ReceiptPaper, int)> _documentPdf(
    BuildContext context,
    ReceiptDocument doc, {
    required bool forPrint,
  }) async {
    final settings = await _branding(context) ?? await loadSettings();
    final conn = await loadConnection(settings);
    final templates = ReceiptTemplates(settings.receiptTemplates);
    final template = templates.of(doc.kind);
    final paper = conn.effectivePaper;
    doc = await publicLink(
      doc,
      settings: settings,
      template: template,
      design: templates.designFor(doc.kind),
    );
    final rendered = await ReceiptRenderer.render(
      doc,
      settings: settings,
      template: template,
      paper: paper,
      design: templates.designFor(doc.kind),
      monochrome: conn.isThermal,
    );
    try {
      final copies = forPrint ? template.copies : 1;
      return (await pdfBytes(rendered, paper, copies: copies), paper, copies);
    } finally {
      rendered.dispose();
    }
  }

  /// زر «طباعة» خارج شاشة الإيصال: طابعة الجهاز (بلوتوث/شبكة) مباشرة، وإلا
  /// نافذة طباعة النظام بنفس صورة الإيصال وعدد نسخ قالبه.
  static Future<void> printOrSystemDialog(
    BuildContext context,
    ReceiptDocument doc,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final conn = await loadConnection(await loadSettings());
      if (conn.isConfigured && conn.type != PrinterType.system) {
        if (!context.mounted) return;
        await printWithFeedback(context, () async => doc);
        return;
      }
      if (!context.mounted) return;
      final (bytes, paper, _) = await _documentPdf(
        context,
        doc,
        forPrint: true,
      );
      await printing.Printing.layoutPdf(
        name: 'receipt-${doc.number ?? doc.kind.name}',
        format: PdfPageFormat(
          paper.widthMm * PdfPageFormat.mm,
          paper.sheetHeightMm == null
              ? double.infinity
              : paper.sheetHeightMm! * PdfPageFormat.mm,
        ),
        onLayout: (_) async => bytes,
      );
    } catch (e, st) {
      AppLogger.error('ReceiptPrinter', 'printOrSystemDialog', e, st);
      messenger?.showSnackBar(
        const SnackBar(content: Text('تعذّرت الطباعة. راجع اتصال الطابعة.')),
      );
    }
  }

  /// مشاركة الإيصال: يسأل صورةً أم PDF، ثم يرسل بنفس تصميم الإيصال.
  static Future<void> shareDocument(
    BuildContext context,
    ReceiptDocument doc, {
    String? filename,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final format = await pickShareFormat(context);
    if (format == null || !context.mounted) return;
    final base = (filename ?? 'receipt-${doc.number ?? doc.kind.name}')
        .replaceAll(RegExp(r'\.pdf$'), '');
    try {
      final settings = await _branding(context) ?? await loadSettings();
      final conn = await loadConnection(settings);
      if (format == ReceiptShareFormat.image) {
        final png = await shareImageBytes(
          doc,
          settings: settings,
          paper: conn.effectivePaper,
        );
        await shareImageFile(png, '$base.png');
      } else {
        if (!context.mounted) return;
        final (bytes, _, _) = await _documentPdf(context, doc, forPrint: false);
        await printing.Printing.sharePdf(bytes: bytes, filename: '$base.pdf');
      }
    } catch (e, st) {
      AppLogger.error('ReceiptPrinter', 'shareDocument', e, st);
      messenger?.showSnackBar(
        const SnackBar(content: Text('تعذّرت مشاركة الإيصال.')),
      );
    }
  }

  /// يسأل: صورة (تُفتح مباشرة في واتساب) أم ملف PDF. `null` = أُلغي.
  static Future<ReceiptShareFormat?> pickShareFormat(BuildContext context) =>
      showModalBottomSheet<ReceiptShareFormat>(
        context: context,
        showDragHandle: true,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const ValueKey('share-image'),
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('صورة'),
                  subtitle: const Text('تُفتح مباشرة في واتساب بألوان الإيصال'),
                  onTap: () => Navigator.pop(context, ReceiptShareFormat.image),
                ),
                ListTile(
                  key: const ValueKey('share-pdf'),
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('ملف PDF'),
                  subtitle: const Text('للطباعة أو الأرشيف'),
                  onTap: () => Navigator.pop(context, ReceiptShareFormat.pdf),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );

  /// صورة الإيصال للمشاركة: دائماً بالألوان (الشاشة ليست طابعة حرارية)،
  /// وبعرض 80 مم للفافة حتى تُقرأ على الهاتف، أو بمقاس الصفحة الكبيرة.
  static Future<Uint8List> shareImageBytes(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptPaper paper,
  }) async {
    final templates = ReceiptTemplates(settings.receiptTemplates);
    doc = await publicLink(
      doc,
      settings: settings,
      template: templates.of(doc.kind),
      design: templates.designFor(doc.kind),
    );
    final rendered = await ReceiptRenderer.render(
      doc,
      settings: settings,
      template: templates.of(doc.kind),
      paper: paper.isRoll ? ReceiptPaper.mm80 : paper,
      design: templates.designFor(doc.kind),
      monochrome: false,
    );
    try {
      return await rendered.pngBytes();
    } finally {
      rendered.dispose();
    }
  }

  /// يفتح نافذة المشاركة بصورة PNG.
  static Future<void> shareImageFile(Uint8List png, String name) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, name: name, mimeType: 'image/png')],
        fileNameOverrides: [name],
      ),
    );
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
