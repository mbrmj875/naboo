import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../guides/guide_anchor.dart';
import '../models/car_wash_service_item.dart';
import '../services/car_wash_checkout_service.dart';
import '../services/car_wash_services_repository.dart';
import '../widgets/car_wash_service_dialog.dart';
import 'car_wash_services_screen.dart';
import '../../oil_change/utils/oil_change_advance_autofill.dart';
import '../../oil_change/widgets/oil_change_customer_name_field.dart';
import '../../oil_change/widgets/oil_change_form_theme.dart';
import '../../oil_change/widgets/oil_change_log_stitch.dart';
import '../../oil_change/widgets/oil_change_royal_card.dart';
import '../../oil_change/widgets/oil_change_save_success_overlay.dart';
import '../../../models/customer_record.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/customer_search_index.dart';
import '../../../services/database_helper.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/adaptive_form_container.dart';
import '../../../widgets/raw_keyboard_inset.dart';

/// بطاقة غسيل سيارة — رقم اللوحة ونوع الغسيل وسعره، ثم حفظ وبيع.
class CarWashFormScreen extends StatefulWidget {
  const CarWashFormScreen({super.key});

  @override
  State<CarWashFormScreen> createState() => _CarWashFormScreenState();
}

class _CarWashFormScreenState extends State<CarWashFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _note = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController();
  final _customerFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  final _repo = CarWashServicesRepository.instance;

  List<CarWashServiceItem> _catalog = const [];
  final Set<int> _selectedIds = <int>{};
  bool _loadingCatalog = true;

  int? _customerId;
  String _linkedCustomerName = '';
  bool _totalManual = false;
  bool _paidManual = false;
  bool _syncingTotal = false;
  bool _syncingPaid = false;
  int? _lastSyncedTotalFils;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _total.addListener(_onTotalEdited);
    _paid.addListener(_onPaidEdited);
    _customerName.addListener(_onCustomerNameTyped);
    FocusManager.instance.addListener(_onGlobalFocusChange);
    _loadCatalog();
    // تجهيز فهرس العملاء للبحث تحت حقل الاسم (مثل بطاقة غيار الزيت).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        unawaited(CustomerSearchIndex.instance.ensureFresh());
      });
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    _total.removeListener(_onTotalEdited);
    _paid.removeListener(_onPaidEdited);
    _customerName.removeListener(_onCustomerNameTyped);
    _scrollCtrl.dispose();
    _plate.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _note.dispose();
    _total.dispose();
    _paid.dispose();
    _customerFocus.dispose();
    super.dispose();
  }

  void _onGlobalFocusChange() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final ctx = focus.context;
    if (ctx == null) return;
    if (ctx.findAncestorStateOfType<_CarWashFormScreenState>() != this) {
      return;
    }
    _scheduleBringFocusedFieldAboveKeyboard();
  }

  void _scheduleBringFocusedFieldAboveKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bringFocusedFieldAboveKeyboard();
    });
  }

  /// يرفع الحقل المركّز فوق الكيبورد بتمرير الـ ListView مباشرة (بدون ensureVisible البطيء).
  void _bringFocusedFieldAboveKeyboard() {
    if (!_scrollCtrl.hasClients) return;

    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final ctx = focus.context;
    if (ctx == null) return;
    if (ctx.findAncestorStateOfType<_CarWashFormScreenState>() != this) {
      return;
    }

    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;

    final keyboard = rawKeyboardBottomInset(context);
    if (keyboard <= 0) return;

    final screenH = MediaQuery.sizeOf(context).height;
    final fieldTop = box.localToGlobal(Offset.zero).dy;
    final fieldBottom = fieldTop + box.size.height;
    // هامش مريح فوق حد الكيبورد.
    const comfort = 36.0;
    final clearBottom = screenH - keyboard - comfort;
    final overlap = fieldBottom - clearBottom;
    if (overlap <= 0) return;

    final pos = _scrollCtrl.position;
    final target = (pos.pixels + overlap).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() < 1) return;

    // قفزة فورية — بدون أنيميشن يسبب تهنيكاً مع إطارات فتح الـ IME.
    _scrollCtrl.jumpTo(target);
  }

  Future<void> _loadCatalog({int? selectId}) async {
    setState(() => _loadingCatalog = true);
    try {
      final list = await _repo.listActive();
      if (!mounted) return;
      final ids = list.map((e) => e.id).toSet();
      _selectedIds.removeWhere((id) => !ids.contains(id));
      if (selectId != null && selectId > 0 && ids.contains(selectId)) {
        _selectedIds.add(selectId);
      }
      setState(() {
        _catalog = list;
        _loadingCatalog = false;
      });
      _syncTotalFromSelection();
    } catch (e) {
      AppLogger.warn('car_wash_form', 'catalog load failed :: $e');
      if (!mounted) return;
      setState(() => _loadingCatalog = false);
    }
  }

  // ── حساب المبالغ ─────────────────────────────────────────────────────────

  static int _parseFils(String raw) {
    final dinars = IraqiCurrencyFormat.parseIqdInt(raw);
    return IqdMoney.toFils(dinars.toDouble());
  }

  static String _formatFilsAsIqd(int fils) {
    if (fils <= 0) return '';
    return IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(fils));
  }

  int get _selectionTotalFils {
    var sum = 0;
    for (final item in _catalog) {
      if (_selectedIds.contains(item.id) && item.priceFils > 0) {
        sum += item.priceFils;
      }
    }
    return sum;
  }

  int get _totalFils => _parseFils(_total.text);

  int get _paidFils {
    final paid = _parseFils(_paid.text);
    final total = _totalFils;
    if (paid < 0) return 0;
    return paid > total ? total : paid;
  }

  int get _remainderFils => _totalFils - _paidFils;

  void _assignText(TextEditingController c, String value) {
    if (c.text == value) return;
    c.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// الإجمالي يتبع الأنواع المختارة ما لم يكتبه المستخدم بنفسه.
  void _syncTotalFromSelection() {
    if (!_totalManual) {
      final fils = _selectionTotalFils;
      _syncingTotal = true;
      try {
        _assignText(_total, _formatFilsAsIqd(fils));
      } finally {
        _syncingTotal = false;
      }
    }
    _syncPaidFromTotal();
    _clampPaidToTotal();
    if (mounted) setState(() {});
  }

  /// المستلم يساوي الإجمالي تلقائياً — الدين قرار صريح من المستخدم.
  void _syncPaidFromTotal() {
    final total = _totalFils;
    final shouldSync = OilChangeAdvanceAutofill.shouldSync(
      manuallyEdited: _paidManual,
      currentAdvanceFils: _parseFils(_paid.text),
      totalFils: total,
      lastSyncedTotalFils: _lastSyncedTotalFils,
    );
    if (!shouldSync) return;
    _lastSyncedTotalFils = total;
    _syncingPaid = true;
    try {
      _assignText(_paid, _formatFilsAsIqd(total));
    } finally {
      _syncingPaid = false;
    }
  }

  /// المبلغ المستلم لا يتجاوز الإجمالي.
  void _clampPaidToTotal() {
    final total = _totalFils;
    final paidRaw = _parseFils(_paid.text);
    if (paidRaw <= total) return;
    _syncingPaid = true;
    try {
      _assignText(_paid, _formatFilsAsIqd(total));
    } finally {
      _syncingPaid = false;
    }
  }

  void _onTotalEdited() {
    if (_syncingTotal) return;
    _totalManual = true;
    _syncPaidFromTotal();
    _clampPaidToTotal();
    if (mounted) setState(() {});
  }

  void _onPaidEdited() {
    if (_syncingPaid) return;
    _paidManual = true;
    _clampPaidToTotal();
    if (mounted) setState(() {});
  }

  void _resetTotalToSelection() {
    _totalManual = false;
    _lastSyncedTotalFils = null;
    _syncTotalFromSelection();
  }

  void _toggleService(CarWashServiceItem item, bool selected) {
    if (selected) {
      _selectedIds.add(item.id);
    } else {
      _selectedIds.remove(item.id);
    }
    _lastSyncedTotalFils = null;
    _syncTotalFromSelection();
  }

  Future<void> _quickAddService() async {
    final draft = await showCarWashServiceDialog(context);
    if (draft == null) return;
    try {
      final id = await _repo.insert(
        name: draft.name,
        priceFils: draft.priceFils,
      );
      if (!mounted) return;
      await _loadCatalog(selectId: id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إضافة النوع: $e')),
      );
    }
  }

  Future<void> _onCustomerSelected(CustomerRecord record) async {
    var phone = (record.phone ?? '').trim();
    if (phone.isEmpty) {
      try {
        final row = await DatabaseHelper().getCustomerById(record.id);
        if (row != null) {
          phone = (row['phone'] ?? '').toString().trim();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final name = record.name.trim();
    // اربط الاسم أولاً حتى لا يفكّ المستمع الارتباط عند تعبئة الحقل.
    _linkedCustomerName = name;
    _customerId = record.id;
    _customerName.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    if (phone.isNotEmpty) {
      _customerPhone.text = phone;
    }
    setState(() {});
  }

  /// تعديل الاسم بعد الربط يفكّ الارتباط — وإلا سُجّل الدين على عميل آخر.
  void _onCustomerNameTyped() {
    if ((_customerId ?? 0) <= 0) return;
    if (_customerName.text.trim() == _linkedCustomerName) return;
    setState(() {
      _customerId = null;
      _linkedCustomerName = '';
    });
  }

  // ── الحفظ ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final total = _totalFils;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر نوع غسيل بسعر، أو اكتب السعر يدوياً.'),
        ),
      );
      return;
    }

    final lines = _catalog
        .where((item) => _selectedIds.contains(item.id))
        .map(CarWashLine.fromCatalog)
        .toList(growable: false);

    setState(() => _saving = true);
    final staff = context.read<AuthProvider>().username.trim();
    try {
      final result = await CarWashCheckoutService.instance.save(
        plate: _plate.text,
        lines: lines,
        totalFils: total,
        paidFils: _paidFils,
        customerName: _customerName.text,
        customerId: _customerId,
        customerPhone: _customerPhone.text,
        note: _note.text,
        createdByUserName: staff.isEmpty ? null : staff,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      await showOilChangeSaveSuccessOverlay(
        context,
        message: result.remainderFils > 0
            ? 'تم حفظ الغسيل — المتبقي دين'
            : 'تم الحفظ والبيع بنجاح',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on CarWashCheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), duration: const Duration(seconds: 6)),
      );
    } catch (e) {
      AppLogger.error('car_wash_form', 'save failed', e);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    }
  }

  // ── الواجهة ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = context.screenLayout.pageHorizontalGap;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
      backgroundColor: OilChangeLogStitchMetrics.background,
      resizeToAvoidBottomInset: false,
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: 'بطاقة غسيل سيارة',
        actions: [
          IconButton(
            tooltip: 'أنواع الغسيل وأسعارها',
            onPressed: _saving
                ? null
                : () async {
                    await CarWashServicesScreen.open(context);
                    if (!mounted) return;
                    await _loadCatalog();
                  },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AdaptiveFormContainer(
        // الحشو الخارجي يضيّق منطقة التمرير فوق الكيبورد بدون إعادة بناء النموذج.
        child: _CarWashKeyboardLift(
          onKeyboardInsetChanged: _scheduleBringFocusedFieldAboveKeyboard,
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsetsDirectional.fromSTEB(pad, 12, pad, 24),
              children: [
                GuideAnchor(
                  id: OilGuideAnchors.carWashFormPlate,
                  child: OilChangeRoyalCard.section(
                    context: context,
                    title: 'رقم السيارة',
                    icon: Icons.confirmation_number_outlined,
                    children: [
                      TextFormField(
                        controller: _plate,
                        textInputAction: TextInputAction.next,
                        scrollPadding: const EdgeInsets.only(bottom: 96),
                        decoration: OilChangeFormTheme.field(
                          context: context,
                          labelText: 'رقم السيارة',
                          hintText: 'مثال: 12345 بصرة',
                          prefixIcon: const Icon(
                            Icons.confirmation_number_outlined,
                            size: 20,
                          ),
                        ),
                        textAlign: TextAlign.start,
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) {
                            return 'رقم السيارة مطلوب';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                GuideAnchor(
                  id: OilGuideAnchors.carWashFormServices,
                  child: _buildServicesSection(cs),
                ),
                _buildMoneySection(cs),
                _buildCustomerSection(cs),
                OilChangeRoyalCard.section(
                  context: context,
                  title: 'ملاحظة',
                  icon: Icons.notes_rounded,
                  children: [
                    TextFormField(
                      controller: _note,
                      maxLines: 2,
                      scrollPadding: const EdgeInsets.only(bottom: 96),
                      decoration: OilChangeFormTheme.field(
                        context: context,
                        labelText: 'ملاحظة (اختياري)',
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ],
                ),
                GuideAnchor(
                  id: OilGuideAnchors.carWashFormSave,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: OilChangeFormTheme.gold,
                      foregroundColor: OilChangeLogStitchMetrics.onSecondaryContainer,
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OilChangeLogStitchMetrics.onSecondaryContainer,
                            ),
                          )
                        : const Icon(Icons.local_car_wash_rounded),
                    label: Text(
                      _saving ? 'جارٍ الحفظ…' : 'حفظ وبيع',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildServicesSection(ColorScheme cs) {
    return OilChangeRoyalCard.section(
      context: context,
      title: 'نوع الغسيل',
      icon: Icons.local_car_wash_outlined,
      children: [
        if (_loadingCatalog)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: OilChangeFormTheme.gold,
            ),
          )
        else if (_catalog.isEmpty)
          Text(
            'لا أنواع غسيل بعد. أضف نوعاً وسعره، ثم اختره ليُحسب الإجمالي.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
            textAlign: TextAlign.start,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _catalog)
                FilterChip(
                  selected: _selectedIds.contains(item.id),
                  onSelected: _saving ? null : (v) => _toggleService(item, v),
                  label: Text(
                    item.priceFils > 0
                        ? '${item.name} · ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(item.priceFils))}'
                        : item.name,
                  ),
                  selectedColor: OilChangeFormTheme.gold.withValues(alpha: 0.22),
                  checkmarkColor: OilChangeFormTheme.gold,
                ),
            ],
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _saving ? null : _quickAddService,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('إضافة نوع'),
          ),
        ),
      ],
    );
  }

  Widget _buildMoneySection(ColorScheme cs) {
    final remainder = _remainderFils;
    final selectionFils = _selectionTotalFils;
    final showReset = _totalManual && selectionFils > 0;

    return OilChangeRoyalCard.section(
      context: context,
      title: 'السعر والدفع',
      icon: Icons.payments_outlined,
      children: [
          TextFormField(
            controller: _total,
            scrollPadding: const EdgeInsets.only(bottom: 96),
            decoration: OilChangeFormTheme.field(
              context: context,
              labelText: 'الإجمالي (د.ع)',
              hintText: '0',
              suffixIcon: showReset
                  ? IconButton(
                      tooltip: 'إرجاع السعر لمجموع الأنواع',
                      onPressed: _resetTotalToSelection,
                      icon: const Icon(Icons.undo_rounded),
                    )
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            inputFormatters: [
              IraqiCurrencyFormat.moneyInputFormatter(),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _paid,
            scrollPadding: const EdgeInsets.only(bottom: 96),
            decoration: OilChangeFormTheme.field(
              context: context,
              labelText: 'المبلغ المستلم (د.ع)',
              hintText: '0',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            inputFormatters: [
              IraqiCurrencyFormat.moneyInputFormatter(),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                remainder > 0
                    ? Icons.account_balance_wallet_outlined
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: remainder > 0 ? cs.error : Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remainder > 0
                      ? 'المتبقي دين: '
                          '${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(remainder))}'
                          ' — يلزم اختيار عميل مسجّل'
                      : 'مدفوعة بالكامل',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: remainder > 0 ? cs.error : Colors.green.shade700,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCustomerSection(ColorScheme cs) {
    return OilChangeRoyalCard.section(
      context: context,
      title: 'العميل',
      icon: Icons.person_outline_rounded,
      children: [
          OilChangeCustomerNameField(
            controller: _customerName,
            focusNode: _customerFocus,
            onSelected: (rec) => unawaited(_onCustomerSelected(rec)),
            customerLinked: (_customerId ?? 0) > 0,
            enabled: !_saving,
            hintText: 'ابحث بالاسم',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _customerPhone,
            scrollPadding: const EdgeInsets.only(bottom: 96),
            decoration: OilChangeFormTheme.field(
              context: context,
              labelText: 'رقم الهاتف (اختياري)',
            ),
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d+ ]')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (_customerId ?? 0) > 0
                ? 'عميل مرتبط من السجل — يمكن استخدامه للدين إن وُجد متبقٍ.'
                : 'ابحث بالاسم واختر من القائمة، أو اتركه فارغاً لتسجيل '
                    '«${CarWashCheckoutService.fallbackCustomerName}».',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.start,
          ),
      ],
    );
  }
}

/// يرفع منطقة النموذج فوق الكيبورد دون إعادة بناء الـ Form في كل إطار IME.
class _CarWashKeyboardLift extends StatefulWidget {
  const _CarWashKeyboardLift({
    required this.child,
    required this.onKeyboardInsetChanged,
  });

  final Widget child;
  final VoidCallback onKeyboardInsetChanged;

  @override
  State<_CarWashKeyboardLift> createState() => _CarWashKeyboardLiftState();
}

class _CarWashKeyboardLiftState extends State<_CarWashKeyboardLift>
    with WidgetsBindingObserver {
  double _lastInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final next = rawKeyboardBottomInset(context);
    if ((next - _lastInset).abs() < 0.5) return;
    _lastInset = next;
    if (!mounted) return;
    setState(() {});
    widget.onKeyboardInsetChanged();
  }

  @override
  Widget build(BuildContext context) {
    final inset = rawKeyboardBottomInset(context);
    _lastInset = inset;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: widget.child,
    );
  }
}

