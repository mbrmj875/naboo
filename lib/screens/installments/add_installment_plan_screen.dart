import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/installment.dart';
import '../../models/installment_settings_data.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';

final _numFmt = NumberFormat('#,##0', 'en');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

/// قيمة [Navigator.pop] لاختيار «بدون ربط» (معرّفات العملاء موجبة).
const _unlinkCustomerSentinel = -1;

/// بعد حفظ فاتورة تقسيط: الخطة تُنشأ مسبقاً في قاعدة البيانات؛ هذه الشاشة لضبط الجدول والربط.
class AddInstallmentPlanScreen extends StatefulWidget {
  /// معرّف الخطة المحفوظة (يُمرَّر من شاشة الفاتورة بعد [insertDefaultInstallmentPlanForInvoice]).
  final int planId;
  final int invoiceId;
  final String customerName;
  final double totalAmount;
  final double paidAmount;
  final DateTime invoiceDate;

  const AddInstallmentPlanScreen({
    super.key,
    required this.planId,
    required this.invoiceId,
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.invoiceDate,
  });

  @override
  State<AddInstallmentPlanScreen> createState() =>
      _AddInstallmentPlanScreenState();
}

class _AddInstallmentPlanScreenState extends State<AddInstallmentPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _countCtrl = TextEditingController();
  final _db = DatabaseHelper();

  InstallmentSettingsData _settings = InstallmentSettingsData.defaults();
  int? _linkedCustomerId;
  /// صف العميل المرتبط حالياً (للعرض فقط — لا نحمّل جدول العملاء كاملاً).
  Map<String, dynamic>? _linkedCustomerRow;
  DateTime _startDate = DateTime.now();
  bool _loading = true;
  String? _loadError;
  /// لقطة حقول الفائدة المحفوظة مع الخطة — تُعاد عند إعادة الجدولة دون مسحها من قاعدة البيانات.
  InstallmentPlan? _financeSnapshot;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = await _db.getInstallmentSettings();
    final loaded = await _db.getInstallmentPlanById(widget.planId);
    Map<String, dynamic>? linkedRow;
    if (loaded?.customerId != null) {
      linkedRow = await _db.getCustomerById(loaded!.customerId!);
    }
    if (!mounted) return;
    if (loaded == null) {
      setState(() {
        _loadError = 'تعذر تحميل خطة التقسيط.';
        _loading = false;
      });
      return;
    }
    final step = settings.paymentIntervalMonths.clamp(1, 24);
    DateTime anchor;
    if (loaded.installments.isNotEmpty) {
      final first = loaded.installments.first.dueDate;
      anchor = settings.useCalendarMonths
          ? installmentShiftCalendarMonths(first, -step)
          : first.subtract(Duration(days: 30 * step));
    } else {
      anchor = settings.defaultFirstDueAnchor ==
              InstallmentSettingsData.anchorInvoiceDate
          ? DateTime(
              widget.invoiceDate.year,
              widget.invoiceDate.month,
              widget.invoiceDate.day,
            )
          : DateTime.now();
    }
    setState(() {
      _settings = settings;
      _linkedCustomerId = loaded.customerId;
      _linkedCustomerRow = linkedRow;
      _startDate = DateTime(anchor.year, anchor.month, anchor.day);
      _countCtrl.text = '${loaded.numberOfInstallments}';
      _financeSnapshot = loaded;
      _loading = false;
    });
  }

  String get _linkedCustomerSummary {
    if (_linkedCustomerId == null) {
      return 'بدون ربط — الاعتماد على الاسم من الفاتورة';
    }
    final r = _linkedCustomerRow;
    if (r == null) {
      return 'عميل مسجّل #$_linkedCustomerId';
    }
    final n = (r['name'] as String?)?.trim() ?? '';
    final p = (r['phone'] as String?)?.trim() ?? '';
    if (n.isEmpty) return 'عميل #$_linkedCustomerId';
    if (p.isNotEmpty) return '$n — $p';
    return n;
  }

  Future<void> _openCustomerPicker() async {
    final choice = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _InstallmentCustomerPickerSheet(db: _db),
    );
    if (!mounted || choice == null) return;
    if (choice == _unlinkCustomerSentinel) {
      setState(() {
        _linkedCustomerId = null;
        _linkedCustomerRow = null;
      });
      return;
    }
    final row = await _db.getCustomerById(choice);
    if (!mounted) return;
    setState(() {
      _linkedCustomerId = choice;
      _linkedCustomerRow = row;
    });
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 8)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  DateTime _previewFirstDue() {
    final step = _settings.paymentIntervalMonths.clamp(1, 24);
    if (_settings.useCalendarMonths) {
      return installmentAddCalendarMonths(_startDate, step);
    }
    return _startDate.add(Duration(days: 30 * step));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final n = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (n < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عدد الأقساط يجب أن يكون 1 على الأقل')),
      );
      return;
    }
    final remaining = widget.totalAmount - widget.paidAmount;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد مبلغ متبقٍ للتقسيط بعد المقدم')),
      );
      return;
    }

    final fin = _financeSnapshot;
    final plan = InstallmentPlan(
      id: widget.planId,
      invoiceId: widget.invoiceId,
      customerName: widget.customerName.trim().isEmpty
          ? 'عميل'
          : widget.customerName.trim(),
      customerId: _linkedCustomerId,
      totalAmount: widget.totalAmount,
      paidAmount: widget.paidAmount,
      numberOfInstallments: n,
      installments: [],
      interestPct: fin?.interestPct ?? 0,
      interestAmount: fin?.interestAmount ?? 0,
      financedAtSale: fin?.financedAtSale ?? 0,
      totalWithInterest: fin?.totalWithInterest ?? 0,
      plannedMonths: fin?.plannedMonths ?? 0,
      suggestedMonthly: fin?.suggestedMonthly ?? 0,
    );
    plan.distributeInstallments(
      _startDate,
      paymentIntervalMonths: _settings.paymentIntervalMonths,
      useCalendarMonths: _settings.useCalendarMonths,
    );

    final ok = await _db.replaceInstallmentPlanSchedule(plan);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكن إعادة جدولة الأقساط بعد تسديد قسط من هذه الخطة.',
          ),
        ),
      );
      return;
    }
    Navigator.popUntil(context, (route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _linkedCustomerId != null
              ? 'تم حفظ الجدول وربط العميل #$_linkedCustomerId'
              : 'تم حفظ جدول الأقساط',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : cs.surface;
    final card = isDark ? AppColors.cardDark : cs.surfaceContainerLowest;

    if (_loading) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('ضبط جدول الأقساط'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_loadError != null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('ضبط جدول الأقساط'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        Navigator.popUntil(context, (r) => r.isFirst),
                    child: const Text('العودة للرئيسية'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final firstDue = _previewFirstDue();
    final step = _settings.paymentIntervalMonths;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('ضبط جدول الأقساط'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'الخطة مسجّلة بالفعل وتظهر تحت «خطط التقسيط». عدّل الربط أو عدد الأقساط أو المرجع ثم احفظ.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: card,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ملخص الفاتورة',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SummaryRow('رقم الفاتورة', '#${widget.invoiceId}'),
                      _SummaryRow(
                        'العميل',
                        widget.customerName.isEmpty
                            ? '—'
                            : widget.customerName,
                      ),
                      _SummaryRow(
                        'الإجمالي',
                        '${_numFmt.format(widget.totalAmount)} د.ع',
                      ),
                      _SummaryRow(
                        'المقدّم',
                        '${_numFmt.format(widget.paidAmount)} د.ع',
                      ),
                      const Divider(height: 20),
                      Text(
                        'متبقٍّ للتقسيط: ${_numFmt.format(widget.totalAmount - widget.paidAmount)} د.ع',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'ربط العميل',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'يُفضّل اختيار عميل مسجّل لتسهيل المتابعة والتقارير.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.hintColor,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: card,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'عميل مسجّل',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _linkedCustomerSummary,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openCustomerPicker,
                        icon: const Icon(Icons.person_search_rounded, size: 20),
                        label: const Text('اختيار عميل من القائمة'),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerRight,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _countCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'عدد أقساط المتبقي',
                  border: const OutlineInputBorder(borderRadius: AppShape.none),
                  helperText:
                      'التوزيع بالتساوي؛ آخر قسط يستوعب فرق الفلس. الفترة بين الأقساط من الإعدادات: $step شهر/أشهر.',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'أدخل عدد الأقساط';
                  final x = int.tryParse(v.trim());
                  if (x == null || x < 1) return 'قيمة غير صالحة';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Material(
                color: card,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _pickStartDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مرجع الجدولة (بداية العدّ)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                              ),
                              Text(
                                _dateFmt.format(_startDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'أول استحقاق: ${_dateFmt.format(firstDue)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _settings.useCalendarMonths
                                    ? 'جدولة: شهر تقويمي × $step لكل قسط من المرجع.'
                                    : 'جدولة: تقريب 30 يوماً × $step لكل قسط من المرجع.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_left, color: cs.outline),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppShape.none,
                  ),
                ),
                child: const Text('حفظ التعديلات على الجدول'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// بحث صفحي — لا يحمّل جدول العملاء كاملاً (يتجنّب تجمّد الواجهة مع قواعد كبيرة).
class _InstallmentCustomerPickerSheet extends StatefulWidget {
  const _InstallmentCustomerPickerSheet({required this.db});

  final DatabaseHelper db;

  @override
  State<_InstallmentCustomerPickerSheet> createState() =>
      _InstallmentCustomerPickerSheetState();
}

class _InstallmentCustomerPickerSheetState
    extends State<_InstallmentCustomerPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload(String q) async {
    setState(() => _loading = true);
    final rows = await widget.db.queryCustomersPage(
      query: q,
      statusArabic: 'الكل',
      sortKey: 'name_asc',
      limit: 80,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      _hits = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _reload(_searchCtrl.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: mq.size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'اختر عميلاً مسجّلاً',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'ابحث بالاسم أو الهاتف أو الرقم…',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: AppShape.none),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: const Text('بدون ربط — الاعتماد على الاسم من الفاتورة'),
                onTap: () =>
                    Navigator.pop(context, _unlinkCustomerSentinel),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        itemCount: _hits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final c = _hits[i];
                          final id = c['id'] as int;
                          final nm = (c['name'] as String?)?.trim() ?? '';
                          final ph = (c['phone'] as String?)?.trim() ?? '';
                          return ListTile(
                            title: Text(
                              nm.isEmpty ? 'عميل #$id' : nm,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: ph.isEmpty
                                ? null
                                : Text(ph, maxLines: 1),
                            onTap: () => Navigator.pop(context, id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
