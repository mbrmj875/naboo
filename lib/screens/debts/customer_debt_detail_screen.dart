import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/credit_debt_invoice.dart';
import '../../models/customer_debt_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/shift_provider.dart';
import '../../models/debt_settings_data.dart';
import '../../printing/invoice_receipt_screen.dart';
import '../../services/customer_debt_statement.dart';
import '../../services/database_helper.dart';
import '../../services/effective_store_branding.dart';
import '../../utils/iqd_money.dart';
import '../../theme/design_tokens.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/shift_actor_conflict_guard.dart';
import '../../utils/customer_phone_launch.dart';
import '../../widgets/invoice_detail_sheet.dart';
import 'void_payment_dialog.dart';

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
  int _openTotalFils = 0;
  List<String> _contactPhones = [];
  List<CustomerDebtPaymentRow> _payments = [];
  DebtSettingsData _settings = DebtSettingsData.defaults();
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
      final openFilsFromInvoices =
          inv.fold<int>(0, (s, x) => s + x.remainingFils);
      final open = openFilsFromInvoices / 1000.0;
      var contactPhones = <String>[];
      var payments = <CustomerDebtPaymentRow>[];
      final settings = await _db.getDebtSettings();
      final cid = p.customerId;
      if (cid != null) {
        payments = (await _db.getCustomerDebtPaymentRows(cid))
            .map(CustomerDebtPaymentRow.fromRow)
            .toList();
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
        _openTotalFils = openFilsFromInvoices;
        _contactPhones = contactPhones;
        _payments = payments;
        _settings = settings;
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
    if (p == null || _openTotalFils <= 0) return;
    if (p.customerId == null || p.customerId! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكن تسديد الدين لهذا السجل لأنه غير مربوط ببطاقة عميل. اربط العميل أولاً ثم أعد المحاولة.',
          ),
        ),
      );
      return;
    }
    final defaultText = (_openTotalFils / 1000.0).toStringAsFixed(0);
    final remainingLabel =
        '${_numFmt.format(_openTotalFils / 1000.0)} د.ع';
    final submitted = await showDialog<({String amount, String note})>(
      context: context,
      builder: (ctx) => _DebtPayAmountDialog(
        remainingLabel: remainingLabel,
        initialAmountText: defaultText,
        openFils: _openTotalFils,
      ),
    );
    if (submitted == null || !mounted) return;
    final raw = submitted.amount.replaceAll(',', '').trim();
    final amt = double.tryParse(raw) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صالحاً')),
      );
      return;
    }
    final conflict = ShiftActorConflictGuard.evaluate(
      sessionUserId: context.read<AuthProvider>().userId,
      activeShift: context.read<ShiftProvider>().activeShift,
    );
    if (conflict.hasConflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن تسجيل تسديد الدين من هذه الجلسة: الوردية المفتوحة باسم ${conflict.shiftStaffName}.',
          ),
        ),
      );
      return;
    }
    try {
      final user = context.read<AuthProvider>().username.trim();
      final res = await _db.recordCustomerDebtPayment(
        party: p,
        amount: amt,
        recordedByUserName: user.isEmpty ? '—' : user,
        note: submitted.note,
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

  Future<void> _voidPayment(CustomerDebtPaymentRow pay) async {
    if (!pay.canVoid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذه دفعة قديمة سُجّلت قبل تحديث الإلغاء، فلا يمكن إلغاؤها تلقائياً.',
          ),
        ),
      );
      return;
    }
    final amount = '${_numFmt.format(pay.amountFils / 1000.0)} د.ع';
    final reason = await confirmVoidPayment(
      context,
      title: 'إلغاء دفعة خاطئة',
      amountLabel: amount,
      effect:
          'يعود المبلغ ديناً على فواتيره كما كان، ويُخصم من الصندوق، '
          'وتبقى الدفعة في السجل بعلامة «ملغاة».',
    );
    if (reason == null || !mounted) return;
    try {
      final user = context.read<AuthProvider>().username.trim();
      await _db.voidCustomerDebtPayment(
        paymentId: pay.id,
        reason: reason,
        voidedByUserName: user,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُلغيت الدفعة ($amount) وعاد الدين.')),
      );
      unawaited(context.read<InvoiceProvider>().refresh());
      unawaited(context.read<NotificationProvider>().refresh());
      await _load();
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  CustomerDebtStatement _statement() => CustomerDebtStatement(
    customerName: _party?.displayName ?? '',
    invoices: _invoices,
    payments: _payments,
  );

  Future<String> _storeName() async {
    try {
      final s = await EffectiveStoreBranding.resolveFromContext(context);
      return s.storeTitleLine;
    } catch (_) {
      return '';
    }
  }

  bool get _canRemind =>
      _openTotalFils >= 500 &&
      _contactPhones.isNotEmpty &&
      _settings.reminderMode != DebtReminderMode.none;

  Future<void> _remind() async {
    final open = _invoices.where((i) => i.remainingFils >= 500).toList();
    DateTime? oldest;
    for (final i in open) {
      if (oldest == null || i.date.isBefore(oldest)) oldest = i.date;
    }
    final store = await _storeName();
    if (!mounted) return;
    await launchCustomerWhatsApp(
      context,
      _contactPhones,
      message: customerDebtReminderMessage(
        customerName: _party?.displayName ?? '',
        openFils: _openTotalFils,
        oldestDate: oldest,
        storeName: store,
      ),
    );
  }

  Future<void> _openStatement() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'كشف حساب العميل',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'الفواتير غير المسدَّدة وآخر 10 دفعات والرصيد الآن.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: const Text('طباعة الكشف'),
                onTap: () => Navigator.pop(ctx, 'print'),
              ),
              ListTile(
                enabled: _contactPhones.isNotEmpty,
                leading: const Icon(Icons.chat_rounded),
                title: const Text('إرسال الكشف بالواتساب'),
                subtitle: _contactPhones.isEmpty
                    ? const Text('لا يوجد رقم هاتف لهذا العميل')
                    : null,
                onTap: () => Navigator.pop(ctx, 'whatsapp'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final st = _statement();
    if (choice == 'print') {
      // معاينة أولاً (بالصورة نفسها التي تُطبع)، ثم «طباعة» أو «مشاركة».
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => InvoiceReceiptScreen(document: st.toReceipt()),
        ),
      );
    } else {
      final store = await _storeName();
      if (!mounted) return;
      await launchCustomerWhatsApp(
        context,
        _contactPhones,
        message: st.toWhatsAppText(storeName: store),
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
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_canRemind)
                                OutlinedButton.icon(
                                  key: const Key('debtRemindButton'),
                                  onPressed: _remind,
                                  icon: const Icon(
                                    Icons.notifications_active_outlined,
                                  ),
                                  label: const Text('ذكّره بالدين'),
                                ),
                              OutlinedButton.icon(
                                key: const Key('debtStatementButton'),
                                onPressed: _openStatement,
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text('كشف الحساب'),
                              ),
                            ],
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
                          if ((_party?.customerId ?? 0) > 0) ...[
                            const SizedBox(height: 18),
                            Text(
                              'الدفعات',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_payments.isEmpty)
                              Text(
                                'لم يسدّد شيئاً بعد.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              )
                            else
                              ..._payments.map(
                                (pay) => _PaymentTile(
                                  payment: pay,
                                  cardColor: card,
                                  onVoid: () => _voidPayment(pay),
                                ),
                              ),
                          ],
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
                  // شريط واحد: التسديد عريضاً، والاتصال وواتساب أيقونتان بجانبه
                  // (كانا شريطين يأكلان مساحة الفواتير والدفعات).
                  _PayBar(
                    enabled: _openTotalFils > 0 && (_party?.customerId ?? 0) > 0,
                    openTotal: _openTotal,
                    onPay: _openPayDialog,
                    phones: _contactPhones,
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
              color: openTotal > 0
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

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.cardColor,
    required this.onVoid,
  });

  final CustomerDebtPaymentRow payment;
  final Color cardColor;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = payment;
    final when = DateFormat('dd/MM/yyyy HH:mm', 'en').format(p.createdAt);
    final details = [
      when,
      if (p.recordedBy != null) 'استلمها ${p.recordedBy}',
      if (!p.isVoided)
        'الدين بعدها ${_numFmt.format(p.debtAfterFils / 1000.0)} د.ع',
    ].join(' · ');
    final lines = [
      details,
      if (p.note != null) 'ملاحظة: ${p.note}',
      if (p.isVoided)
        'ملغاة ${DateFormat('dd/MM/yyyy', 'en').format(p.voidedAt!)}'
            '${p.voidedBy == null ? '' : ' · ألغاها ${p.voidedBy}'}'
            '${p.voidReason == null ? '' : ' · السبب: ${p.voidReason}'}',
    ];
    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          p.isVoided ? Icons.block_rounded : Icons.payments_outlined,
          color: p.isVoided ? cs.error : AppSemanticColors.success,
        ),
        title: Row(
          children: [
            Text(
              '${_numFmt.format(p.amountFils / 1000.0)} د.ع',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                decoration: p.isVoided ? TextDecoration.lineThrough : null,
              ),
            ),
            if (p.isVoided) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: cs.errorContainer,
                child: Text(
                  'ملغاة',
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          lines.join('\n'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        trailing: p.isVoided
            ? null
            : IconButton(
                key: Key('debtPaymentVoid_${p.id}'),
                tooltip: 'إلغاء دفعة خاطئة',
                icon: const Icon(Icons.undo_rounded),
                onPressed: onVoid,
              ),
      ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.enabled,
    required this.openTotal,
    required this.onPay,
    required this.phones,
  });

  final bool enabled;
  final double openTotal;
  final VoidCallback onPay;
  final List<String> phones;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhones = phones.isNotEmpty;
    Widget contact({
      required Key key,
      required IconData icon,
      required String tip,
      required VoidCallback onTap,
      Color? color,
    }) {
      return Tooltip(
        message: hasPhones ? tip : 'لا يوجد رقم للعميل',
        child: IconButton.filledTonal(
          key: key,
          onPressed: hasPhones ? onTap : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          ),
          icon: Icon(icon, color: hasPhones ? color : null),
        ),
      );
    }

    return Material(
      elevation: 8,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? onPay : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppShape.none,
                    ),
                    backgroundColor: AppColors.accent,
                  ),
                  icon: const Icon(Icons.payments_rounded),
                  label: Text(
                    enabled
                        ? 'تسديد (متبقٍّ ${_numFmt.format(openTotal)} د.ع)'
                        : 'لا يوجد متبقٍ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              contact(
                key: const Key('debtCallButton'),
                icon: Icons.phone_rounded,
                tip: 'اتصال',
                onTap: () => launchCustomerDial(context, phones),
              ),
              const SizedBox(width: 8),
              contact(
                key: const Key('debtWhatsAppButton'),
                icon: Icons.chat_rounded,
                tip: 'واتساب',
                color: const Color(0xFF25D366),
                onTap: () => launchCustomerWhatsApp(context, phones),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حوار مبلغ التسديد — يملك [TextEditingController] داخلياً حتى لا يُستدعى
/// dispose أثناء إغلاق الـ dialog (كان يسبب الشاشة الحمراء).
class _DebtPayAmountDialog extends StatefulWidget {
  const _DebtPayAmountDialog({
    required this.remainingLabel,
    required this.initialAmountText,
    required this.openFils,
  });

  final String remainingLabel;
  final String initialAmountText;
  final int openFils;

  @override
  State<_DebtPayAmountDialog> createState() => _DebtPayAmountDialogState();
}

class _DebtPayAmountDialogState extends State<_DebtPayAmountDialog> {
  late final TextEditingController _ctrl;
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialAmountText);
    _ctrl.addListener(_onAmount);
  }

  void _onAmount() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onAmount);
    _ctrl.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, (amount: _ctrl.text, note: _note.text));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        title: const Text('تسديد دين'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المتبقي الحالي: ${widget.remainingLabel}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'المبلغ (د.ع)',
                  border: OutlineInputBorder(),
                ),
              ),
              Builder(
                builder: (context) {
                  final entered = IqdMoney.toFils(
                    double.tryParse(_ctrl.text.replaceAll(',', '').trim()) ??
                        0,
                  );
                  final warn = debtPaymentOverAmountWarning(
                    enteredFils: entered,
                    openFils: widget.openFils,
                  );
                  if (warn == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      warn,
                      key: const Key('debtPayOverWarning'),
                      style: const TextStyle(
                        color: AppSemanticColors.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('debtPayNote'),
                controller: _note,
                maxLength: 200,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  hintText: 'مثال: سدّد عن طريق أخيه',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يُوزَّع تلقائياً على الفواتير من الأقدم إلى الأحدث.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }
}
