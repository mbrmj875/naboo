import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/credit_debt_invoice.dart';
import '../../models/customer_debt_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/customer_phone_launch.dart';
import '../../widgets/customer_contact_bar.dart';
import '../../widgets/invoice_detail_sheet.dart';

final _numFmt = NumberFormat('#,##0', 'ar');
final _dateFmt = DateFormat('dd/MM/yyyy', 'ar');

/// تفاصيل ديون عميل (آجل) — منتجات وبائعون، تسديد جزئي.
class CustomerDebtDetailScreen extends StatefulWidget {
  /// من قائمة «العملاء» في الديون.
  const CustomerDebtDetailScreen.fromParty({
    super.key,
    required this.party,
  }) : registeredCustomerId = null;

  /// من مسح QR أو رابط عميل مسجّل.
  const CustomerDebtDetailScreen.fromCustomerId({
    super.key,
    required this.registeredCustomerId,
  }) : party = null;

  final CustomerDebtParty? party;
  final int? registeredCustomerId;

  @override
  State<CustomerDebtDetailScreen> createState() => _CustomerDebtDetailScreenState();
}

class _CustomerDebtDetailScreenState extends State<CustomerDebtDetailScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  CustomerDebtParty? _party;
  List<CustomerDebtLineItem> _lines = [];
  List<CreditDebtInvoice> _invoices = [];
  double _openTotal = 0;
  List<String> _contactPhones = [];
  bool _loading = true;
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    if (widget.party != null) {
      _party = widget.party;
      _load();
    } else if (widget.registeredCustomerId != null) {
      _resolveParty(widget.registeredCustomerId!);
    } else {
      _resolveError = 'بيانات غير صالحة';
      _loading = false;
    }
  }

  Future<void> _resolveParty(int customerId) async {
    setState(() => _loading = true);
    final row = await _db.getCustomerById(customerId);
    final name = (row?['name'] as String?)?.trim();
    final display =
        (name != null && name.isNotEmpty) ? name : 'عميل #$customerId';
    if (!mounted) return;
    setState(() {
      _party = CustomerDebtParty(
        customerId: customerId,
        displayName: display,
        normalizedName: display.toLowerCase(),
      );
    });
    await _load();
  }

  Future<void> _load() async {
    final p = _party;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final lines = await _db.getCustomerDebtLineItems(p);
      final inv = await _db.getCreditDebtInvoicesForParty(p);
      final open = await _db.sumOpenCreditDebtForParty(p);
      var contactPhones = <String>[];
      final cid = p.customerId;
      if (cid != null) {
        final row = await _db.getCustomerById(cid);
        if (row != null) {
          contactPhones = mergeCustomerPhoneChoices(
            primaryPhone: row['phone'] as String?,
            extraPhones: await _db.getCustomerExtraPhones(cid),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _invoices = inv;
        _openTotal = open;
        _contactPhones = contactPhones;
        _loading = false;
        _resolveError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolveError = '$e';
      });
    }
  }

  Future<void> _openPayDialog() async {
    final p = _party;
    if (p == null || _openTotal < 0.009) return;
    final ctrl = TextEditingController(
      text: _openTotal.toStringAsFixed(0),
    );
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          title: const Text('تسديد دين'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المتبقي الحالي: ${_numFmt.format(_openTotal)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ (د.ع)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يُوزَّع تلقائياً على الفواتير من الأقدم إلى الأحدث.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (submitted == null || !mounted) return;
    final raw = submitted.replaceAll(',', '').trim();
    final amt = double.tryParse(raw) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صالحاً')),
      );
      return;
    }
    try {
      final user = context.read<AuthProvider>().username.trim();
      final res = await _db.recordCustomerDebtPayment(
        party: p,
        amount: amt,
        recordedByUserName: user.isEmpty ? '—' : user,
      );
      if (!mounted) return;
      if (res == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد متبقٍ للتسديد أو المبلغ غير صالح'),
          ),
        );
        return;
      }
      unawaited(context.read<InvoiceProvider>().refresh());
      unawaited(context.read<NotificationProvider>().refresh());
      await _load();
      if (!mounted) return;
      await SaleReceiptPdf.presentCustomerDebtPaymentReceipt(
        context,
        customerDisplayName: p.displayName,
        customerId: p.customerId,
        amountApplied: res.amountApplied,
        debtBefore: res.debtBefore,
        debtAfter: res.debtAfter,
        paymentRowId: res.paymentRowId,
        receiptInvoiceId: res.receiptInvoiceId,
        recordedByUserName: user.isEmpty ? null : user,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('customer debt pay: $e');
        debugPrintStack(stackTrace: st);
        return true;
      }());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إكمال التسديد: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final card = isDark ? AppColors.cardDark : cs.surface;

    if (_resolveError != null && _party == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('ديون عميل')),
          body: Center(child: Text(_resolveError!)),
        ),
      );
    }

    final title = _party?.displayName ?? '…';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        children: [
                          _SummaryHeader(
                            openTotal: _openTotal,
                            invoiceCount: _invoices.length,
                            openInvoiceCount:
                                _invoices.where((e) => !e.isSettled).length,
                            cardColor: card,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'فواتير آجل',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._invoices.map(
                            (inv) => _InvoiceMiniTile(
                              inv: inv,
                              cardColor: card,
                              isDark: isDark,
                              onOpen: () => showInvoiceDetailSheet(
                                context,
                                _db,
                                inv.invoiceId,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'المنتجات المأخوذة بالدين',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_lines.isEmpty)
                            Text(
                              'لا توجد بنود مسجّلة.',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            )
                          else
                            ..._lines.map(
                              (line) => _ProductDebtTile(
                                line: line,
                                cardColor: card,
                                isDark: isDark,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  CustomerContactBar(phones: _contactPhones),
                  _PayBar(
                    enabled: _openTotal >= 0.009,
                    openTotal: _openTotal,
                    onPay: _openPayDialog,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.openTotal,
    required this.invoiceCount,
    required this.openInvoiceCount,
    required this.cardColor,
    required this.isDark,
  });

  final double openTotal;
  final int invoiceCount;
  final int openInvoiceCount;
  final Color cardColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجمالي المتبقي',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_numFmt.format(openTotal)} د.ع',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: openTotal >= 0.009
                  ? const Color(0xFF0EA5E9)
                  : const Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _chip(context, cs, 'فواتير', '$invoiceCount'),
              const SizedBox(width: 10),
              _chip(context, cs, 'مفتوحة', '$openInvoiceCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs, String k, String v) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _InvoiceMiniTile extends StatelessWidget {
  const _InvoiceMiniTile({
    required this.inv,
    required this.cardColor,
    required this.isDark,
    required this.onOpen,
  });

  final CreditDebtInvoice inv;
  final Color cardColor;
  final bool isDark;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final settled = inv.isSettled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فاتورة #${inv.invoiceId}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _dateFmt.format(inv.date),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_numFmt.format(inv.remaining)} د.ع',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: settled
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF0EA5E9),
                      ),
                    ),
                    Text(
                      settled ? 'مغلقة' : 'متبقٍّ',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductDebtTile extends StatelessWidget {
  const _ProductDebtTile({
    required this.line,
    required this.cardColor,
    required this.isDark,
  });

  final CustomerDebtLineItem line;
  final Color cardColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final seller = (line.sellerName ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          right: BorderSide(
            color: cs.primary,
            width: 3,
          ),
          top: BorderSide(color: border),
          left: BorderSide(color: border),
          bottom: BorderSide(color: border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.productName.isEmpty ? '—' : line.productName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            'فاتورة #${line.invoiceId} · ${_dateFmt.format(line.invoiceDate)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (seller.isNotEmpty)
            Text(
              'البائع: $seller',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0369A1),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'الكمية: ${line.quantity}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Text(
                'السعر: ${_numFmt.format(line.unitPrice)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${_numFmt.format(line.lineTotal)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.enabled,
    required this.openTotal,
    required this.onPay,
  });

  final bool enabled;
  final double openTotal;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton.icon(
            onPressed: enabled ? onPay : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
              backgroundColor: AppColors.accent,
            ),
            icon: const Icon(Icons.payments_rounded),
            label: Text(
              enabled
                  ? 'تسديد دين (متبقٍّ ${_numFmt.format(openTotal)} د.ع)'
                  : 'لا يوجد متبقٍ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
