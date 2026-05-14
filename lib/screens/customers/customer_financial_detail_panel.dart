import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/credit_debt_invoice.dart';
import '../../models/customer_record.dart';
import '../../models/installment.dart';
import '../../theme/design_tokens.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../services/database_helper.dart';
import '../../widgets/invoice_detail_sheet.dart';
import '../debts/customer_debt_detail_screen.dart';
import '../installments/installment_details_screen.dart';

final _dateFmt = DateFormat('yyyy/MM/dd', 'en');

/// لوحة تفاصيل العميل المالية — قابلة لإعادة الاستخدام داخل
/// `MasterDetailLayout` على الديسكتوب أو داخل `Scaffold` كصفحة كاملة على الموبايل.
///
/// **مرجع معماري**: `InvoiceDetailPanel` في `widgets/invoice_detail_panel.dart`.
///
/// السلوك:
/// - عندما يكون [customer] = null → تظهر حالة فارغة "اختر عميلاً لعرض تفاصيله".
/// - يُعيد التحميل تلقائياً عند تغيير `customer.id` عبر `didUpdateWidget`.
/// - [onClose] يظهر زر إغلاق إن وُفِّر (مفيد في وضع MasterDetail الديسكتوب).
class CustomerFinancialDetailPanel extends StatefulWidget {
  const CustomerFinancialDetailPanel({
    super.key,
    required this.customer,
    this.onClose,
    this.onEdit,
  });

  final CustomerRecord? customer;
  final VoidCallback? onClose;

  /// تعديل بيانات العميل — يُستدعى عند الضغط على زر "تعديل".
  /// إن لم يُمرَّر، يُخفى الزر.
  final VoidCallback? onEdit;

  @override
  State<CustomerFinancialDetailPanel> createState() =>
      _CustomerFinancialDetailPanelState();
}

class _CustomerFinancialDetailPanelState
    extends State<CustomerFinancialDetailPanel> {
  final DatabaseHelper _db = DatabaseHelper();

  List<CreditDebtInvoice> _creditInvoices = [];
  List<InstallmentPlan> _plans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) _load();
  }

  @override
  void didUpdateWidget(covariant CustomerFinancialDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer?.id != widget.customer?.id) {
      if (widget.customer != null) {
        _load();
      } else {
        setState(() {
          _creditInvoices = [];
          _plans = [];
          _loading = false;
          _error = null;
        });
      }
    }
  }

  Future<void> _load() async {
    final c = widget.customer;
    if (c == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credits = await _db.getCreditDebtInvoicesForCustomerId(c.id);
      final plans = await _db.getInstallmentPlansForCustomerId(c.id);
      if (!mounted) return;
      setState(() {
        _creditInvoices = credits;
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    if (c == null) return const _PanelEmpty();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          _PanelHeader(
            customer: c,
            onClose: widget.onClose,
            onEdit: widget.onEdit,
          ),
          const SizedBox(height: 12),
          _SummaryCard(customer: c),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
                    registeredCustomerId: c.id,
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
              shape: const RoundedRectangleBorder(
                borderRadius: AppShape.none,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('شاشة الديون الكاملة (تسديد وتفاصيل)'),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.receipt_long_outlined,
            title: 'مبيعات بالأجل (دين)',
            subtitle:
                'كل فاتورة مرتبطة بإيصال البيع — اضغط لعرض التفاصيل',
            color: AppSemanticColors.warning,
          ),
          const SizedBox(height: 8),
          if (_creditInvoices.isEmpty)
            const _EmptyHint(
              text:
                  'لا توجد فواتير «آجل» مربوطة بهذا العميل. استخدم البيع بالدين مع اختيار العميل من القائمة.',
            )
          else
            ..._creditInvoices.map(
              (inv) => _CreditInvoiceTile(
                inv: inv,
                onReceipt: () => showInvoiceDetailSheet(
                  context,
                  _db,
                  inv.invoiceId,
                ),
              ),
            ),
          const SizedBox(height: 22),
          _SectionTitle(
            icon: Icons.calendar_month_rounded,
            title: 'التقسيط',
            subtitle: 'خطط الأقساط المرتبطة بفواتير البيع',
            color: cs.primary,
          ),
          const SizedBox(height: 8),
          if (_plans.isEmpty)
            const _EmptyHint(
              text:
                  'لا توجد خطط تقسيط مربوطة بهذا العميل. استخدم نوع البيع «تقسيط» مع اختيار العميل.',
            )
          else
            ..._plans.map(
              (p) => _InstallmentPlanTile(
                plan: p,
                onReceipt: () => showInvoiceDetailSheet(
                  context,
                  _db,
                  p.invoiceId,
                ),
                onPlanDetails: p.id != null
                    ? () {
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => InstallmentDetailsScreen(
                              planId: p.id!,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// رأس اللوحة — يعرض اسم العميل + زر تعديل + زر إغلاق (في وضع MasterDetail).
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.customer,
    this.onClose,
    this.onEdit,
  });

  final CustomerRecord customer;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: AppShape.none,
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: cs.onPrimary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'تعديل بيانات العميل',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: cs.onPrimary),
            ),
          if (onClose != null)
            IconButton(
              tooltip: 'إغلاق اللوحة (Esc)',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: cs.onPrimary),
            ),
        ],
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              'اختر عميلاً من القائمة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ستظهر تفاصيل ديون العميل وأقساطه هنا.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets منقولة من customer_financial_detail_screen.dart ───────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.customer});

  final CustomerRecord customer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        borderRadius: AppShape.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(
            'الهاتف',
            customer.phone?.trim().isNotEmpty == true ? customer.phone! : '—',
          ),
          _kv(
            'البريد',
            customer.email?.trim().isNotEmpty == true ? customer.email! : '—',
          ),
          _kv(
            'رصيد المحفظة',
            IraqiCurrencyFormat.formatIqd(customer.balance),
          ),
          _kv('نقاط الولاء', '${customer.loyaltyPoints}'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: AppShape.none,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CreditInvoiceTile extends StatelessWidget {
  const _CreditInvoiceTile({
    required this.inv,
    required this.onReceipt,
  });

  final CreditDebtInvoice inv;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settled = inv.isSettled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
          borderRadius: AppShape.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'فاتورة بيع #${inv.invoiceId}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dateFmt.format(inv.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        IraqiCurrencyFormat.formatIqd(inv.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        settled
                            ? 'مغلقة'
                            : 'متبقٍّ: ${IraqiCurrencyFormat.formatIqd(inv.remaining)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: settled
                              ? AppSemanticColors.success
                              : AppSemanticColors.supplier,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextButton.icon(
                onPressed: onReceipt,
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                label: const Text('عرض إيصال / تفاصيل الفاتورة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallmentPlanTile extends StatelessWidget {
  const _InstallmentPlanTile({
    required this.plan,
    required this.onReceipt,
    this.onPlanDetails,
  });

  final InstallmentPlan plan;
  final VoidCallback onReceipt;
  final VoidCallback? onPlanDetails;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paidCount = plan.installments.where((e) => e.paid).length;
    final n = plan.installments.length;
    final remaining = plan.totalAmount - plan.paidAmount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
          borderRadius: AppShape.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فاتورة تقسيط #${plan.invoiceId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'المبلغ الكلي: ${IraqiCurrencyFormat.formatIqd(plan.totalAmount)} · المدفوع: ${IraqiCurrencyFormat.formatIqd(plan.paidAmount)}',
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الأقساط: $paidCount / $n مدفوعة · متبقٍّ تقريباً: ${IraqiCurrencyFormat.formatIqd(remaining)}',
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onReceipt,
                    icon: const Icon(Icons.receipt_long_outlined, size: 20),
                    label: const Text('إيصال البيع'),
                  ),
                ),
                if (onPlanDetails != null)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onPlanDetails,
                      icon: const Icon(Icons.view_list_outlined, size: 20),
                      label: const Text('جدول الأقساط'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
