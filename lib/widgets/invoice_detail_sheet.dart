import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/invoice.dart';
import '../services/database_helper.dart';
import '../theme/design_tokens.dart';
import '../utils/screen_layout.dart';

final _numFmt = NumberFormat('#,##0', 'ar');
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'ar');

bool _invoiceShowsStoredInstallmentFinance(Invoice inv) {
  if (inv.type != InvoiceType.installment) return false;
  return inv.installmentPlannedMonths > 0 ||
      inv.installmentInterestPct.abs() > 1e-9 ||
      inv.installmentFinancedAmount.abs() > 1e-9 ||
      inv.installmentInterestAmount.abs() > 1e-9 ||
      inv.installmentTotalWithInterest.abs() > 1e-9 ||
      inv.installmentSuggestedMonthly.abs() > 1e-9;
}

String _invoiceTypeAr(InvoiceType t) {
  switch (t) {
    case InvoiceType.cash:
      return 'نقدي';
    case InvoiceType.credit:
      return 'آجل';
    case InvoiceType.installment:
      return 'تقسيط';
    case InvoiceType.delivery:
      return 'توصيل';
    case InvoiceType.debtCollection:
      return 'سند تحصيل دين';
    case InvoiceType.installmentCollection:
      return 'سند تسديد قسط';
    case InvoiceType.supplierPayment:
      return 'سند دفع مورد';
  }
}

/// عرض تفاصيل فاتورة كاملة (بنود، إجماليات، ولاء، وردية…) من [invoiceId]
/// عبر `showModalBottomSheet`. يُستخدم على الموبايل والتابلت الصغير.
///
/// على الديسكتوب يفضّل استخدام [InvoiceDetailPanel] مباشرة داخل
/// `MasterDetailLayout` لعرض إنلاين (جنباً إلى جنب مع القائمة).
Future<void> showInvoiceDetailSheet(
  BuildContext context,
  DatabaseHelper db,
  int invoiceId,
) async {
  final inv = await db.getInvoiceById(invoiceId);
  if (!context.mounted) return;
  if (inv == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الفاتورة غير موجودة')),
    );
    return;
  }

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final border = isDark ? AppColors.borderDark : AppColors.borderLight;
  final sl = ScreenLayout.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          initialChildSize: sl.sheetInitialFraction,
          minChildSize: sl.sheetMinFraction,
          maxChildSize: 0.98,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                border: Border.all(color: border),
              ),
              child: _InvoiceDetailContent(
                invoice: inv,
                isDark: isDark,
                scrollController: scrollController,
                showDragHandle: true,
                onClose: () => Navigator.pop(ctx),
              ),
            );
          },
        ),
      );
    },
  );
}

/// لوحة تفاصيل الفاتورة كودجت Inline — تُستخدم في `MasterDetailLayout`
/// على الديسكتوب لعرض التفاصيل جنباً إلى جنب مع القائمة.
///
/// تتعامل مع التحميل الـ async داخلياً وتعرض حالة فارغة عند `invoiceId == null`.
class InvoiceDetailPanel extends StatefulWidget {
  const InvoiceDetailPanel({
    super.key,
    required this.invoiceId,
    required this.db,
    this.onClose,
  });

  /// `null` ⇒ يعرض حالة "لم يُختر شيء".
  final int? invoiceId;
  final DatabaseHelper db;

  /// زر إغلاق (X). على الديسكتوب يمسح الاختيار. `null` ⇒ يُخفى.
  final VoidCallback? onClose;

  @override
  State<InvoiceDetailPanel> createState() => _InvoiceDetailPanelState();
}

class _InvoiceDetailPanelState extends State<InvoiceDetailPanel> {
  Invoice? _invoice;
  bool _loading = false;
  int? _loadedId;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant InvoiceDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoiceId != widget.invoiceId) {
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    final id = widget.invoiceId;
    if (id == null) {
      setState(() {
        _invoice = null;
        _loadedId = null;
        _loading = false;
      });
      return;
    }
    if (_loadedId == id) return;
    setState(() => _loading = true);
    final inv = await widget.db.getInvoiceById(id);
    if (!mounted) return;
    setState(() {
      _invoice = inv;
      _loadedId = id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    if (widget.invoiceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                'اختر فاتورة لعرض تفاصيلها',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_loading || _invoice == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: _InvoiceDetailContent(
        invoice: _invoice!,
        isDark: isDark,
        scrollController: null,
        showDragHandle: false,
        onClose: widget.onClose,
      ),
    );
  }
}

/// محتوى تفاصيل الفاتورة (المشترك بين BottomSheet و Inline Panel).
class _InvoiceDetailContent extends StatelessWidget {
  const _InvoiceDetailContent({
    required this.invoice,
    required this.isDark,
    required this.scrollController,
    required this.showDragHandle,
    required this.onClose,
  });

  final Invoice invoice;
  final bool isDark;
  final ScrollController? scrollController;
  final bool showDragHandle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final itemsSum = inv.items.fold<double>(0, (s, e) => s + e.total);

    return Column(
      children: [
        if (showDragHandle) ...[
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'فاتورة #${inv.id}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إغلاق',
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
                        _kv('العميل', inv.customerName.isEmpty ? '—' : inv.customerName),
                        _kv('التاريخ', _dateFmt.format(inv.date)),
                        _kv('نوع الفاتورة', _invoiceTypeAr(inv.type)),
                        if (inv.createdByUserName != null &&
                            inv.createdByUserName!.trim().isNotEmpty)
                          _kv('سجّلها', inv.createdByUserName!.trim()),
                        if (inv.workShiftId != null)
                          _kv('الوردية', '#${inv.workShiftId}'),
                        if (inv.customerId != null)
                          _kv('معرّف العميل', '${inv.customerId}'),
                        if (inv.isReturned) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'مرتجع',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (inv.originalInvoiceId != null)
                            _kv('فاتورة الأصل', '#${inv.originalInvoiceId}'),
                        ],
                        if (inv.deliveryAddress != null &&
                            inv.deliveryAddress!.trim().isNotEmpty)
                          _kv('عنوان التوصيل', inv.deliveryAddress!.trim()),
                        if (inv.discountPercent > 0)
                          _kv('نسبة الخصم %', _numFmt.format(inv.discountPercent)),
                        const SizedBox(height: 14),
                        const Text(
                          'البنود',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (inv.items.isEmpty)
                          Text(
                            'لا توجد بنود',
                            style: TextStyle(color: Colors.grey.shade600),
                          )
                        else
                          ...inv.items.map((it) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'الكمية: ${it.quantity} × ${_numFmt.format(it.price)} د.ع',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${_numFmt.format(it.total)} د.ع',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        const Divider(height: 28),
                        _totalRow('مجموع البنود', itemsSum),
                        if (inv.discount > 0)
                          _totalRow('خصم الفاتورة', -inv.discount, negative: true),
                        if (inv.loyaltyDiscount > 0)
                          _totalRow('خصم الولاء', -inv.loyaltyDiscount, negative: true),
                        if (inv.loyaltyPointsRedeemed > 0)
                          _kv('نقاط مُستبدَلة', '${inv.loyaltyPointsRedeemed}'),
                        if (inv.loyaltyPointsEarned > 0)
                          _kv('نقاط مُكتسبة', '${inv.loyaltyPointsEarned}'),
                        if (inv.tax > 0) _totalRow('الضريبة', inv.tax),
                        if (inv.advancePayment > 0)
                          _totalRow('المقدم / الدفعة الأولى', inv.advancePayment),
                        if (_invoiceShowsStoredInstallmentFinance(inv)) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey.shade100,
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'معلومات الفائدة (محفوظة عند البيع)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _kv(
                                  'نسبة الفائدة %',
                                  inv.installmentInterestPct % 1 == 0
                                      ? '${inv.installmentInterestPct.toInt()}'
                                      : inv.installmentInterestPct
                                          .toStringAsFixed(2),
                                ),
                                _kv(
                                  'عدد الأشهر',
                                  '${inv.installmentPlannedMonths}',
                                ),
                                _totalRow(
                                  'المبلغ المموّل',
                                  inv.installmentFinancedAmount,
                                ),
                                if (inv.installmentInterestAmount > 1e-9)
                                  _totalRow(
                                    'قيمة الفائدة',
                                    inv.installmentInterestAmount,
                                  ),
                                _totalRow(
                                  'الإجمالي مع الفائدة',
                                  inv.installmentTotalWithInterest,
                                ),
                                if (inv.installmentSuggestedMonthly > 1e-9)
                                  _totalRow(
                                    'القسط الشهري المقترح',
                                    inv.installmentSuggestedMonthly,
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'الإجمالي',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
              Text(
                '${_numFmt.format(inv.total)} د.ع',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
      ],
    );
  }
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
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontSize: 13, height: 1.35)),
        ),
      ],
    ),
  );
}

Widget _totalRow(String label, double amount, {bool negative = false}) {
  final prefix = negative ? '−' : '';
  final abs = amount.abs();
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '$prefix${_numFmt.format(abs)} د.ع',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: negative ? Colors.red.shade700 : null,
          ),
        ),
      ],
    ),
  );
}
