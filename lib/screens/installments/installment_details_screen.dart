import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../providers/invoice_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/installment.dart';
import '../../models/invoice.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/customer_phone_launch.dart';
import '../../widgets/customer_contact_bar.dart';

final _numFmt = NumberFormat('#,##0', 'ar');
final _dateFmt = DateFormat('dd/MM/yyyy', 'ar');

abstract class _Heritage {
  static const Color gold = Color(0xFFC4A574);
}

bool _planHasStoredSaleFinance(InstallmentPlan p) {
  return p.plannedMonths > 0 ||
      p.interestPct.abs() > 1e-9 ||
      p.financedAtSale.abs() > 1e-9 ||
      p.interestAmount.abs() > 1e-9 ||
      p.totalWithInterest.abs() > 1e-9 ||
      p.suggestedMonthly.abs() > 1e-9;
}

class InstallmentDetailsScreen extends StatefulWidget {
  final int planId;
  const InstallmentDetailsScreen({super.key, required this.planId});

  @override
  State<InstallmentDetailsScreen> createState() => _InstallmentDetailsScreenState();
}

class _InstallmentDetailsScreenState extends State<InstallmentDetailsScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  InstallmentPlan? _plan;
  Invoice? _invoice;
  Map<String, dynamic>? _customerRow;
  List<String> _contactPhones = [];
  Map<int, double> _stock = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plan = await _db.getInstallmentPlanById(widget.planId);
    Invoice? inv;
    Map<String, dynamic>? cust;
    Map<int, double> stock = {};
    var contactPhones = <String>[];

    if (plan != null) {
      if (plan.invoiceId > 0) {
        inv = await _db.getInvoiceById(plan.invoiceId);
      }
      if (plan.customerId != null) {
        cust = await _db.getCustomerById(plan.customerId!);
      }
      if (cust == null && plan.customerName.trim().isNotEmpty) {
        final all = await _db.getAllCustomers();
        final t = plan.customerName.trim().toLowerCase();
        for (final c in all) {
          if ((c['name'] as String).trim().toLowerCase() == t) {
            cust = c;
            break;
          }
        }
      }
      if (cust != null) {
        final cid = cust['id'] as int;
        contactPhones = mergeCustomerPhoneChoices(
          primaryPhone: cust['phone'] as String?,
          extraPhones: await _db.getCustomerExtraPhones(cid),
        );
      }
      final ids = <int>{};
      if (inv != null) {
        for (final it in inv.items) {
          if (it.productId != null) ids.add(it.productId!);
        }
      }
      stock = await _db.getProductQtyMap(ids);
    }

    if (!mounted) return;
    setState(() {
      _plan = plan;
      _invoice = inv;
      _customerRow = cust;
      _contactPhones = contactPhones;
      _stock = stock;
      _loading = false;
    });
  }

  Future<void> _recordPayment(Installment installment) async {
    final amountController =
        TextEditingController(text: installment.amount.toStringAsFixed(0));
    final payOutcome = await showDialog<RecordInstallmentPaymentResult?>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          title: const Text('تسديد قسط'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المستحق: ${_numFmt.format(installment.amount)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'يُسجَّل كاملاً في الصندوق (لا دفع جزئي حالياً).',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المدفوع',
                  border: OutlineInputBorder(borderRadius: AppShape.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final paid =
                    double.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                if (paid <= 0) return;
                final payRes =
                    await _db.recordInstallmentPayment(installment.id!, paid);
                if (!ctx.mounted) return;
                if (payRes.success) {
                  Navigator.pop(ctx, payRes);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        paid + 1e-6 < installment.amount
                            ? 'يجب تسديد قيمة القسط كاملة (${_numFmt.format(installment.amount)} د.ع)'
                            : 'تعذر التسجيل (قد يكون القسط مدفوعاً)',
                      ),
                    ),
                  );
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (payOutcome != null && payOutcome.success) {
      if (!mounted) return;
      unawaited(context.read<NotificationProvider>().refresh());
      unawaited(context.read<InvoiceProvider>().refresh());
      final paidId = installment.id;
      await _load();
      if (!mounted || paidId == null) return;
      final planAfter = _plan;
      if (planAfter != null) {
        await SaleReceiptPdf.presentInstallmentPaymentReceipt(
          context,
          plan: planAfter,
          justPaidInstallmentId: paidId,
          invoice: _invoice,
          receiptInvoiceId: payOutcome.receiptInvoiceId,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final card = isDark ? AppColors.cardDark : AppColors.cardLight;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('تفاصيل خطة التقسيط'),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _plan == null
                ? const Center(child: Text('الخطة غير موجودة'))
                : Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                        _CustomerPanel(
                          plan: _plan!,
                          customer: _customerRow,
                          cardColor: card,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 14),
                        if (_invoice != null)
                          _InvoicePanel(
                            invoice: _invoice!,
                            cardColor: card,
                            isDark: isDark,
                          ),
                        if (_invoice != null) const SizedBox(height: 14),
                        if (_invoice != null && _invoice!.items.isNotEmpty)
                          _ItemsPanel(
                            invoice: _invoice!,
                            stock: _stock,
                            cardColor: card,
                            isDark: isDark,
                          ),
                        if (_invoice != null && _invoice!.items.isNotEmpty)
                          const SizedBox(height: 14),
                        if (_planHasStoredSaleFinance(_plan!)) ...[
                          _SaleFinanceSnapshotPanel(
                            plan: _plan!,
                            cardColor: card,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                        ],
                        _ProgressPanel(
                          plan: _plan!,
                          invoice: _invoice,
                          cardColor: card,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'جدول الأقساط',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        ..._plan!.installments.asMap().entries.map((e) {
                          final i = e.value;
                          final idx = e.key + 1;
                          return _InstallmentRow(
                            index: idx,
                            installment: i,
                            cardColor: card,
                            isDark: isDark,
                            onPay: i.paid ? null : () => _recordPayment(i),
                          );
                        }),
                            ],
                          ),
                        ),
                      ),
                      CustomerContactBar(phones: _contactPhones),
                    ],
                  ),
      ),
    );
  }
}

class _CustomerPanel extends StatelessWidget {
  final InstallmentPlan plan;
  final Map<String, dynamic>? customer;
  final Color cardColor;
  final bool isDark;
  const _CustomerPanel({
    required this.plan,
    required this.customer,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final phone = customer?['phone']?.toString();
    final email = customer?['email']?.toString();
    final address = customer?['address']?.toString();
    final balance = customer != null ? (customer!['balance'] as num?)?.toDouble() : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          top: BorderSide(color: isDark ? _Heritage.gold.withValues(alpha: 0.5) : _Heritage.gold, width: 3),
          left: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          right: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          bottom: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_rounded, color: AppColors.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  plan.customerName.isEmpty ? 'عميل' : plan.customerName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (customer != null) ...[
            const SizedBox(height: 10),
            _InfoLine(Icons.link_rounded, 'مرتبط بسجل العملاء #${customer!['id']}'),
            if (phone != null && phone.isNotEmpty) _InfoLine(Icons.phone_rounded, phone),
            if (email != null && email.isNotEmpty) _InfoLine(Icons.email_outlined, email),
            if (address != null && address.isNotEmpty) _InfoLine(Icons.location_on_outlined, address),
            if (balance != null)
              _InfoLine(Icons.account_balance_wallet_outlined, 'رصيد العميل المسجّل: ${_numFmt.format(balance)} د.ع'),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'لا يوجد تطابق في جدول العملاء — الاسم مأخوذ من الفاتورة فقط. يمكنك ربط عميل عند إنشاء خطة جديدة من شاشة «إضافة خطة».',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _InvoicePanel extends StatelessWidget {
  final Invoice invoice;
  final Color cardColor;
  final bool isDark;
  const _InvoicePanel({required this.invoice, required this.cardColor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الفاتورة المرتبطة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('رقم الفاتورة: #${invoice.id}'),
          Text('التاريخ: ${_dateFmt.format(invoice.date)}'),
          Text('الإجمالي: ${_numFmt.format(invoice.total)} د.ع'),
          if (invoice.advancePayment > 0)
            Text('المقدم المحصّل: ${_numFmt.format(invoice.advancePayment)} د.ع'),
        ],
      ),
    );
  }
}

class _ItemsPanel extends StatelessWidget {
  final Invoice invoice;
  final Map<int, double> stock;
  final Color cardColor;
  final bool isDark;
  const _ItemsPanel({
    required this.invoice,
    required this.stock,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('البضاعة المسحوبة من المخزون', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'الكميات المباعة من الفاتورة مع رصيد المخزون الحالي للمنتج المرتبط.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 10),
          ...invoice.items.map((it) {
            final pid = it.productId;
            final q = pid != null ? stock[pid] : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  Expanded(
                    child: Text('بيع: ${it.quantity}', textAlign: TextAlign.center),
                  ),
                  Expanded(
                    child: Text(
                      pid == null
                          ? '—'
                          : (q != null ? 'مخزون: ${_numFmt.format(q)}' : 'غير مرتبط'),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: q != null && q < 0 ? Colors.red : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SaleFinanceSnapshotPanel extends StatelessWidget {
  final InstallmentPlan plan;
  final Color cardColor;
  final bool isDark;

  const _SaleFinanceSnapshotPanel({
    required this.plan,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final pct = plan.interestPct;
    final pctStr =
        pct % 1 == 0 ? '${pct.toInt()}' : pct.toStringAsFixed(2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'معلومات الفائدة (عند البيع)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text('نسبة الفائدة: $pctStr%'),
          Text('عدد الأشهر: ${plan.plannedMonths}'),
          Text('المبلغ المموّل: ${_numFmt.format(plan.financedAtSale)} د.ع'),
          if (plan.interestAmount > 1e-9)
            Text('قيمة الفائدة: ${_numFmt.format(plan.interestAmount)} د.ع'),
          Text(
            'الإجمالي مع الفائدة: ${_numFmt.format(plan.totalWithInterest)} د.ع',
          ),
          if (plan.suggestedMonthly > 1e-9)
            Text(
              'القسط الشهري المقترح: ${_numFmt.format(plan.suggestedMonthly)} د.ع',
            ),
          SizedBox(height: 8),
          Text(
            'تنبيه: الأرقام أعلاه تقدير عند البيع. جدول الأقساط الفعلي يُوزَّع على «إجمالي الفاتورة − المقدّم» وقد يختلف عن القسط المقترح بالفلس.',
            style: TextStyle(
              fontSize: 10,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  final InstallmentPlan plan;
  final Invoice? invoice;
  final Color cardColor;
  final bool isDark;
  const _ProgressPanel({
    required this.plan,
    this.invoice,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = plan.totalAmount > 0 ? (plan.paidAmount / plan.totalAmount).clamp(0.0, 1.0) : 0.0;
    final rem = (plan.totalAmount - plan.paidAmount).clamp(0.0, double.infinity);
    final advance = invoice?.advancePayment ?? 0.0;
    var schedulePaid = 0.0;
    for (final i in plan.installments) {
      if (i.paid) schedulePaid += i.amount;
    }
    final hasAdvance = advance > 1e-6;
    final hasSchedule = schedulePaid > 1e-6;
    final rawParts = <String>[
      if (hasAdvance) 'مقدّم: ${_numFmt.format(advance)} د.ع',
      if (hasSchedule) 'أقساط من الجدول: ${_numFmt.format(schedulePaid)} د.ع',
    ];
    final combinedRaw = advance + schedulePaid;
    final capped =
        plan.totalAmount > 1e-6 && (combinedRaw - plan.paidAmount).abs() > 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تقدّم السداد', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ClipRect(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'المدفوع: ${_numFmt.format(plan.paidAmount)} / ${_numFmt.format(plan.totalAmount)} د.ع',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (rawParts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              rawParts.join(' · '),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (capped)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'يُقصى «المدفوع» على إجمالي الخطة عند التعارض.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text('المتبقي: ${_numFmt.format(rem)} د.ع'),
        ],
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  final int index;
  final Installment installment;
  final Color cardColor;
  final bool isDark;
  final VoidCallback? onPay;
  const _InstallmentRow({
    required this.index,
    required this.installment,
    required this.cardColor,
    required this.isDark,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final paid = installment.paid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          right: BorderSide(
            color: paid ? const Color(0xFF16A34A) : AppColors.accent,
            width: 3,
          ),
          top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          left: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          bottom: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القسط $index', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'الاستحقاق: ${_dateFmt.format(installment.dueDate)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
                if (paid && installment.paidDate != null)
                  Text(
                    'سُدد: ${_dateFmt.format(installment.paidDate!)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_numFmt.format(installment.amount)} د.ع', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (paid)
                const Chip(
                  label: Text('مدفوع', style: TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              else
                FilledButton(
                  onPressed: onPay,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
                  ),
                  child: const Text('تسديد'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
