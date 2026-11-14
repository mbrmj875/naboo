import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart' as printing;

import '../../theme/design_tokens.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/sale_receipt_pdf.dart';

/// صفحة إيصال تسديد دين — عرض منسّق داخل التطبيق (ليست شاشة PDF كاملة ولا منبثقة).
class CustomerDebtPaymentReceiptScreen extends StatelessWidget {
  const CustomerDebtPaymentReceiptScreen({
    super.key,
    required this.customerDisplayName,
    this.customerId,
    required this.amountApplied,
    required this.debtBefore,
    required this.debtAfter,
    required this.paymentRowId,
    this.receiptInvoiceId,
    this.recordedByUserName,
  });

  final String customerDisplayName;
  final int? customerId;
  final double amountApplied;
  final double debtBefore;
  final double debtAfter;
  final int paymentRowId;
  final int? receiptInvoiceId;
  final String? recordedByUserName;

  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en_US');

  Future<void> _print(BuildContext context) async {
    try {
      await printing.Printing.layoutPdf(
        name: 'debt-receipt-$paymentRowId',
        onLayout: (format) => SaleReceiptPdf.buildCustomerDebtPaymentReceiptBytes(
          customerDisplayName: customerDisplayName,
          customerId: customerId,
          amountApplied: amountApplied,
          debtBefore: debtBefore,
          debtAfter: debtAfter,
          paymentRowId: paymentRowId,
          receiptInvoiceId: receiptInvoiceId,
          recordedByUserName: recordedByUserName,
          pageFormat: format,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّرت الطباعة. راجع اتصال الطابعة.'),
        ),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await SaleReceiptPdf.buildCustomerDebtPaymentReceiptBytes(
        customerDisplayName: customerDisplayName,
        customerId: customerId,
        amountApplied: amountApplied,
        debtBefore: debtBefore,
        debtAfter: debtAfter,
        paymentRowId: paymentRowId,
        receiptInvoiceId: receiptInvoiceId,
        recordedByUserName: recordedByUserName,
      );
      await printing.Printing.sharePdf(
        bytes: bytes,
        filename: 'debt-receipt-$paymentRowId.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت مشاركة الإيصال')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final card = isDark ? AppColors.cardDark : cs.surface;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final muted = cs.onSurfaceVariant;
    final name = customerDisplayName.trim().isEmpty
        ? 'عميل'
        : customerDisplayName.trim();
    final when = _dateFmt.format(DateTime.now());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          elevation: 0,
          title: const Text(
            'إيصال تسديد دين',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'طباعة',
              icon: const Icon(Icons.print_rounded),
              onPressed: () => _print(context),
            ),
            IconButton(
              tooltip: 'مشاركة',
              icon: const Icon(Icons.share_rounded),
              onPressed: () => _share(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إيصال تسديد دين آجل',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _kv('التاريخ والوقت', when, muted),
                  _kv('العميل', name, muted),
                  if (customerId != null && customerId! > 0)
                    _kv('رقم العميل', '#$customerId', muted),
                  if ((recordedByUserName ?? '').trim().isNotEmpty)
                    _kv('سجّل العملية', recordedByUserName!.trim(), muted),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ملخص المبالغ',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _amountRow(
                    label: 'المبلغ المُسدَّد',
                    value: IraqiCurrencyFormat.formatIqd(amountApplied),
                    emphasize: true,
                    color: AppColors.accentGold,
                  ),
                  const SizedBox(height: 10),
                  _amountRow(
                    label: 'الدين قبل التسديد',
                    value: IraqiCurrencyFormat.formatIqd(debtBefore),
                  ),
                  const SizedBox(height: 8),
                  _amountRow(
                    label: 'المتبقي بعد التسديد',
                    value: IraqiCurrencyFormat.formatIqd(debtAfter),
                    color: debtAfter > 0.01
                        ? AppSemanticColors.warning
                        : AppSemanticColors.success,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'تُوزَّع الدفعات تلقائياً على فواتير الآجل من الأقدم إلى الأحدث.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مراجع العملية',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _kv('سجل الدفعة', '#$paymentRowId', muted),
                  if (receiptInvoiceId != null && receiptInvoiceId! > 0)
                    _kv(
                      'سند التحصيل (قائمة الفواتير)',
                      '#$receiptInvoiceId',
                      muted,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppShape.none,
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text(
                'تم',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }

  Widget _amountRow({
    required String label,
    required String value,
    bool emphasize = false,
    Color? color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              fontSize: emphasize ? 20 : 15,
              color: color,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
