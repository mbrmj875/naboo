import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart' as printing;

import '../models/print_settings_data.dart';
import '../services/effective_store_branding.dart';
import '../services/print_settings_repository.dart';
import '../utils/app_logger.dart';
import 'printer_connection.dart';
import 'receipt_model.dart';
import 'receipt_preview.dart';
import 'receipt_printer.dart';
import 'receipt_renderer.dart';

/// إيصال فاتورة محفوظة بقالب نوع عملها (غيار زيت، غسيل، بيع مباشر، استرجاع).
///
/// ما يظهر على الشاشة هو نفسه ما يُطبع ويُشارك: صورة واحدة من [ReceiptRenderer].
class InvoiceReceiptScreen extends StatefulWidget {
  const InvoiceReceiptScreen({
    super.key,
    required this.document,
    this.onOpenDetails,
    @visibleForTesting this.loadSetup,
  });

  final ReceiptDocument document;

  /// يفتح تفاصيل الفاتورة كاملة (الأصناف والدفعات).
  final void Function(BuildContext context)? onOpenDetails;

  /// بديل تحميل الإعدادات والطابعة في الاختبارات.
  final Future<(PrintSettingsData, PrinterConnection)> Function()? loadSetup;

  @override
  State<InvoiceReceiptScreen> createState() => _InvoiceReceiptScreenState();
}

class _InvoiceReceiptScreenState extends State<InvoiceReceiptScreen> {
  PrintSettingsData? _settings;
  PrinterConnection? _connection;
  Object? _loadError;
  bool _busy = false;

  ReceiptDocument get _doc => widget.document;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (settings, conn) = await (widget.loadSetup ?? _defaultSetup)();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _connection = conn;
      });
    } catch (e, st) {
      AppLogger.error('InvoiceReceipt', 'load', e, st);
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// بيانات المحل (أو فرع الموظف) وطابعة هذا الجهاز.
  Future<(PrintSettingsData, PrinterConnection)> _defaultSetup() async {
    PrintSettingsData settings;
    try {
      settings = await EffectiveStoreBranding.resolveFromContext(context);
    } catch (_) {
      settings = await PrintSettingsRepository.instance.load();
    }
    return (settings, await PrinterConnection.load(legacy: settings));
  }

  ReceiptTemplates get _templates =>
      ReceiptTemplates(_settings!.receiptTemplates);

  ReceiptPaper get _paper => _connection!.effectivePaper;

  bool get _hasDevicePrinter =>
      _connection!.isConfigured && _connection!.type != PrinterType.system;

  Future<Uint8List> _pdf() async {
    final rendered = await ReceiptRenderer.render(
      _doc,
      settings: _settings!,
      template: _templates.of(_doc.kind),
      paper: _paper,
      style: _templates.style,
      monochrome: _connection!.isThermal,
    );
    try {
      return await ReceiptPrinter.pdfBytes(rendered, _paper);
    } finally {
      rendered.dispose();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// طابعة الجهاز (بلوتوث/شبكة) مباشرة، وإلا نافذة طباعة النظام بنفس الصورة.
  Future<void> _print() => _run(() async {
    if (_hasDevicePrinter) {
      await ReceiptPrinter.printWithFeedback(context, () async => _doc);
      return;
    }
    try {
      final bytes = await _pdf();
      final paper = _paper;
      await printing.Printing.layoutPdf(
        name: 'receipt-${_doc.number ?? 'invoice'}',
        format: PdfPageFormat(
          paper.widthMm * PdfPageFormat.mm,
          paper.sheetHeightMm == null
              ? double.infinity
              : paper.sheetHeightMm! * PdfPageFormat.mm,
        ),
        onLayout: (_) async => bytes,
      );
    } catch (e, st) {
      AppLogger.error('InvoiceReceipt', 'print', e, st);
      _snack('تعذّرت الطباعة. راجع اتصال الطابعة.');
    }
  });

  Future<void> _share() => _run(() async {
    try {
      final bytes = await _pdf();
      await printing.Printing.sharePdf(
        bytes: bytes,
        filename: 'receipt-${_doc.number ?? 'invoice'}.pdf',
      );
    } catch (e, st) {
      AppLogger.error('InvoiceReceipt', 'share', e, st);
      _snack('تعذّرت مشاركة الإيصال.');
    }
  });

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = _settings;
    final ready = settings != null && _connection != null;
    final details = widget.onOpenDetails;

    Widget body;
    if (_loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'تعذّر تجهيز الإيصال.',
            style: TextStyle(color: cs.error),
          ),
        ),
      );
    } else if (!ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ReceiptPreview(
            document: _doc,
            settings: settings,
            template: _templates.of(_doc.kind),
            paper: _paper,
            style: _templates.style,
            monochrome: _connection!.isThermal,
            maxWidth: _paper.isRoll ? 340 : 380,
          ),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          title: Text(_doc.title),
          actions: [
            if (details != null)
              IconButton(
                key: const ValueKey('invoice-receipt-details'),
                tooltip: 'تفاصيل الفاتورة كاملة',
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => details(context),
              ),
          ],
        ),
        body: body,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('invoice-receipt-print'),
                  onPressed: ready && !_busy ? _print : null,
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('طباعة'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('invoice-receipt-share'),
                  onPressed: ready && !_busy ? _share : null,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
