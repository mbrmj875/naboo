import 'package:flutter/material.dart';

import '../../../services/database_helper.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/sale_receipt_pdf.dart';
import '../models/pharmacy_invoice_detail.dart';
import '../models/pharmacy_invoice_line_view.dart';
import '../models/pharmacy_rx_schedule.dart';
import '../services/pharmacy_invoices_repository.dart';

/// تفاصيل فاتورة صيدلية — بنود الأدوية + ملخص مالي + طباعة.
class PharmacyInvoiceDetailScreen extends StatefulWidget {
  const PharmacyInvoiceDetailScreen({
    super.key,
    required this.invoiceId,
    this.repository,
    this.db,
  });

  final int invoiceId;
  final PharmacyInvoicesRepository? repository;
  final DatabaseHelper? db;

  @override
  State<PharmacyInvoiceDetailScreen> createState() =>
      _PharmacyInvoiceDetailScreenState();
}

class _PharmacyInvoiceDetailScreenState
    extends State<PharmacyInvoiceDetailScreen> {
  late final PharmacyInvoicesRepository _repo =
      widget.repository ?? PharmacyInvoicesRepository();
  late final DatabaseHelper _db = widget.db ?? DatabaseHelper();

  PharmacyInvoiceDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = await _repo.resolveTenantId();
      final detail = await _repo.getInvoiceDetail(
        tenantId: tenantId,
        invoiceId: widget.invoiceId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (detail == null) _error = 'الفاتورة غير موجودة';
      });
    } catch (e, st) {
      AppLogger.error('PharmacyInvoiceDetail', 'load failed', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل تفاصيل الفاتورة';
      });
    }
  }

  Future<void> _printOrShare() async {
    final invoice = await _db.getInvoiceById(widget.invoiceId);
    if (!mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الفاتورة غير موجودة')),
      );
      return;
    }
    final subtotal =
        invoice.items.fold<double>(0, (sum, item) => sum + item.total);
    try {
      await SaleReceiptPdf.presentReceipt(
        context,
        invoice: invoice,
        subtotalBeforeDiscount: subtotal,
      );
    } catch (e, st) {
      AppLogger.error('PharmacyInvoiceDetail', 'print failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح معاينة الطباعة')),
      );
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _rxLabel(String? schedule) {
    return switch (schedule) {
      PharmacyRxSchedule.rx => 'Rx',
      PharmacyRxSchedule.monitored => 'مراقب',
      _ => 'OTC',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('فاتورة #${widget.invoiceId}'),
        actions: [
          IconButton(
            tooltip: 'طباعة / مشاركة',
            onPressed: _detail == null ? null : _printOrShare,
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.start),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    final detail = _detail!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'فاتورة #${detail.id}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 6),
                Text(
                  'التاريخ: ${_formatDate(detail.date)}',
                  textAlign: TextAlign.start,
                ),
                Text(
                  'العميل: ${detail.customerName}',
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'الأدوية',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        ...detail.lines.map(_lineCard),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _moneyRow('إجمالي البنود', detail.subtotalDinars),
                if (detail.discountDinars > 0)
                  _moneyRow('الخصم', detail.discountDinars),
                if (detail.taxDinars > 0)
                  _moneyRow('الضريبة', detail.taxDinars),
                const Divider(height: 20),
                _moneyRow(
                  'المبلغ النهائي',
                  detail.totalDinars,
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _printOrShare,
          icon: const Icon(Icons.share_rounded),
          label: const Text('طباعة / مشاركة'),
        ),
      ],
    );
  }

  Widget _lineCard(PharmacyInvoiceLineView line) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meta = <String>[
      if (line.innName != null && line.innName!.isNotEmpty)
        'INN: ${line.innName}',
      if (line.atcCode != null && line.atcCode!.isNotEmpty)
        'ATC: ${line.atcCode}',
      'Rx/OTC: ${_rxLabel(line.rxSchedule)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              line.displayName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.start,
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.start,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الكمية: ${line.qty == line.qty.roundToDouble() ? line.qty.toInt() : line.qty} ص',
                    textAlign: TextAlign.start,
                  ),
                ),
                Text(IraqiCurrencyFormat.formatIqd(line.unitPriceDinars)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'إجمالي السطر: ${IraqiCurrencyFormat.formatIqd(line.lineTotalDinars)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool emphasized = false}) {
    final theme = Theme.of(context);
    final style = emphasized
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style, textAlign: TextAlign.start)),
          Text(IraqiCurrencyFormat.formatIqd(amount), style: style),
        ],
      ),
    );
  }
}
