import 'dart:async' show Timer, unawaited;
import 'dart:convert';

import '../../../printing/receipt_printer.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../guides/guide_anchor.dart';
import '../models/car_wash_service_item.dart';
import '../services/car_wash_checkout_service.dart';
import '../services/car_wash_services_repository.dart';
import '../services/wash_offer_engine.dart';
import '../../../models/store_policy.dart';
import '../../../owner/services/business_audit_log_service.dart';
import '../../../providers/shift_provider.dart';
import '../../../services/permission_service.dart';
import '../../../services/store_policy_settings_repository.dart';
import '../../../widgets/returns/return_approval_dialog.dart';
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
  const CarWashFormScreen({super.key, this.prefillFromOrder});

  /// غسلة سابقة (صف service_orders) لتعبئة غسلة جديدة منها: اللوحة والزبون
  /// ونفس أنواع الغسيل بأسعارها الحالية. الغسلة القديمة لا تُمس.
  final Map<String, dynamic>? prefillFromOrder;

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

  // عروض الغسيل.
  StorePolicy? _policy;
  bool _elevated = false;
  WashOfferResult _offer = WashOfferResult.none;
  int? _manualDiscountFils;
  Timer? _offerDebounce;
  int _offerSeq = 0;

  @override
  void initState() {
    super.initState();
    _plate.addListener(_scheduleOffer);
    unawaited(_loadPolicyAndAccess());
    _total.addListener(_onTotalEdited);
    _paid.addListener(_onPaidEdited);
    _customerName.addListener(_onCustomerNameTyped);
    FocusManager.instance.addListener(_onGlobalFocusChange);
    _applyPrefill();
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

  Future<void> _loadPolicyAndAccess() async {
    try {
      final policy = await StorePolicySettingsRepository.instance.load();
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final shift = context.read<ShiftProvider>().activeShift;
      final elevated = await PermissionService.instance
          .hasElevatedAccessForSession(
            sessionUserId: auth.userId,
            sessionRoleKey: auth.roleKey,
            activeShift: shift,
          );
      if (!mounted) return;
      _policy = policy;
      _elevated = elevated;
      _scheduleOffer();
    } catch (e) {
      AppLogger.warn('car_wash_form', 'policy load failed: $e');
    }
  }

  bool get _offersEnabled =>
      (_policy?.washRepeat.enabled ?? false) ||
      (_policy?.oilWash.enabled ?? false);

  /// يعيد حساب العرض بعد توقف الكتابة قليلاً.
  void _scheduleOffer() {
    _offerDebounce?.cancel();
    _offerDebounce = Timer(const Duration(milliseconds: 350), _recomputeOffer);
  }

  Map<String, int> _currentServicePrices() {
    if (_totalManual) {
      final t = _totalFils;
      return t > 0 ? {'سعر يدوي': t} : const {};
    }
    return {
      for (final item in _catalog)
        if (_selectedIds.contains(item.id) && item.priceFils > 0)
          item.name: item.priceFils,
    };
  }

  Future<void> _recomputeOffer() async {
    final policy = _policy;
    final seq = ++_offerSeq;
    final plate = _plate.text.trim();
    if (policy == null || !_offersEnabled || plate.isEmpty) {
      if (_offer != WashOfferResult.none) {
        _offer = WashOfferResult.none;
        _afterDiscountChanged();
      }
      return;
    }
    final maxDays = [
      policy.washRepeat.enabled ? policy.washRepeat.periodDays : 0,
      policy.oilWash.enabled ? policy.oilWash.countingPeriodDays : 0,
    ].reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    try {
      final history = await _repo.offerHistory(
        plate,
        since: now.subtract(Duration(days: maxDays + 1)),
      );
      if (!mounted || seq != _offerSeq) return;
      _offer = WashOfferEngine.evaluate(
        policy: policy,
        history: history,
        currentServicePrices: _currentServicePrices(),
        now: now,
      );
      _afterDiscountChanged();
    } catch (e) {
      AppLogger.warn('car_wash_form', 'offer failed: $e');
    }
  }

  /// الخصم المطبَّق: اليدوي إن عُدّل، وإلا خصم العرض.
  int get _discountFils {
    final d = _manualDiscountFils ?? _offer.discountFils;
    final t = _totalFils;
    if (d < 0) return 0;
    return d > t ? t : d;
  }

  int get _netFils => _totalFils - _discountFils;

  bool get _discountOverridden =>
      _manualDiscountFils != null && _manualDiscountFils != _offer.discountFils;

  void _afterDiscountChanged() {
    _lastSyncedTotalFils = null;
    _syncPaidFromTotal();
    _clampPaidToTotal();
    if (mounted) setState(() {});
  }

  Future<void> _editDiscount() async {
    final ctrl = TextEditingController(
      text: _discountFils > 0 ? _formatFilsAsIqd(_discountFils) : '',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الخصم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'الخصم (د.ع)',
                border: OutlineInputBorder(),
              ),
            ),
            if (!_elevated && !context.read<AuthProvider>().isOwner) ...[
              const SizedBox(height: 8),
              const Text(
                'تغيير الخصم يحتاج موافقة المالك أو موظف كامل الصلاحية عند الحفظ.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (_manualDiscountFils != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('إرجاع خصم العرض'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _parseFils(ctrl.text)),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || !mounted) return;
    _manualDiscountFils = value < 0 ? null : value.clamp(0, _totalFils);
    _afterDiscountChanged();
  }

  @override
  void dispose() {
    _offerDebounce?.cancel();
    _plate.removeListener(_scheduleOffer);
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

  /// أسماء أنواع الغسيل في الغسلة السابقة — تُختار بعد تحميل الكتالوج.
  Set<String> _prefillServiceNames = const {};

  void _applyPrefill() {
    final o = widget.prefillFromOrder;
    if (o == null) return;
    _plate.text = (o['deviceSerial'] ?? '').toString().trim();
    final name = (o['customerNameSnapshot'] ?? '').toString().trim();
    if (name.isNotEmpty &&
        name != CarWashCheckoutService.fallbackCustomerName) {
      final cid = (o['customerId'] as num?)?.toInt();
      if (cid != null && cid > 0) {
        _customerId = cid;
        _linkedCustomerName = name;
      }
      _customerName.text = name;
    }
    _customerPhone.text = (o['customerPhone'] ?? '').toString().trim();
    _prefillServiceNames = (o['requestedServices'] ?? '')
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<void> _loadCatalog({int? selectId}) async {
    setState(() => _loadingCatalog = true);
    try {
      final list = await _repo.listActive();
      if (!mounted) return;
      final ids = list.map((e) => e.id).toSet();
      _selectedIds.removeWhere((id) => !ids.contains(id));
      if (_prefillServiceNames.isNotEmpty) {
        // نفس أنواع الغسلة السابقة، بأسعار الكتالوج الحالية.
        for (final item in list) {
          if (_prefillServiceNames.contains(item.name.trim())) {
            _selectedIds.add(item.id);
          }
        }
        _prefillServiceNames = const {};
      }
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
    final total = _netFils;
    if (paid < 0) return 0;
    return paid > total ? total : paid;
  }

  int get _remainderFils => _netFils - _paidFils;

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
    _scheduleOffer();
    if (mounted) setState(() {});
  }

  /// المستلم يساوي الإجمالي تلقائياً — الدين قرار صريح من المستخدم.
  void _syncPaidFromTotal() {
    final total = _netFils;
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
    final total = _netFils;
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
    _scheduleOffer();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر إضافة النوع: $e')));
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

    // الموظف المحدود لا يغيّر السعر أو الخصم إلا بموافقة، والتغيير يُسجَّل.
    final auth = context.read<AuthProvider>();
    final selection = _selectionTotalFils;
    final change = WashPriceChange.evaluate(
      totalManual: _totalManual,
      selectionFils: selection,
      totalFils: total,
      discountOverridden: _discountOverridden,
      elevated: _elevated,
      isOwner: auth.isOwner,
    );
    final priceChanged = change.priceChanged;
    final discountChanged = change.discountChanged;
    String? approverName;
    if (change.changed) {
      if (change.needsApproval) {
        final approval = await requestReturnApproval(
          context,
          title: 'موافقة على تعديل السعر أو الخصم',
          auditEntity: 'car_wash_discount',
          invoiceKey: 'wash:${_plate.text.trim()}',
          amount: IqdMoney.fromFils(_discountFils),
          reasonsAr: [
            if (priceChanged) 'تعديل سعر الغسلة',
            if (discountChanged) 'تعديل الخصم',
          ].join('، '),
          blockSelfApproval: _policy?.returns.blockSelfApproval ?? true,
        );
        if (approval == null || !mounted) return;
        approverName = approval.approverName;
      }
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'wash_discount_override',
          entityType: 'car_wash',
          entityId: _plate.text.trim(),
          oldValueJson: jsonEncode({
            'price': IqdMoney.fromFils(selection),
            'offerDiscount': IqdMoney.fromFils(_offer.discountFils),
          }),
          newValueJson: jsonEncode({
            'plate': _plate.text.trim(),
            'price': IqdMoney.fromFils(total),
            'discount': IqdMoney.fromFils(_discountFils),
            if (approverName != null) 'approver': approverName,
          }),
          userId: auth.userId,
          username: auth.displayName,
        ),
      );
    }

    final discount = _discountFils;
    final offerLines = <String>[
      if (discount > 0)
        discountChanged ? 'خصم يدوي' : (_offer.reasonAr ?? 'خصم'),
      if (_offer.encouragementAr != null) _offer.encouragementAr!,
    ];

    setState(() => _saving = true);
    final staff = auth.username.trim();
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
        discountFils: discount,
        offerCode: discountChanged ? null : _offer.code,
        offerNote: offerLines.isEmpty ? null : offerLines.join('\n'),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      // إيصال الغسيل على طابعة الجهاز (إن رُبطت والطباعة التلقائية مفعّلة).
      unawaited(
        ReceiptPrinter.autoPrintAfterSave(context, invoiceId: result.invoiceId),
      );
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
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      AppLogger.error('car_wash_form', 'save failed', e);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر الحفظ: $e')));
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
                        foregroundColor:
                            OilChangeLogStitchMetrics.onSecondaryContainer,
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OilChangeLogStitchMetrics
                                    .onSecondaryContainer,
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
                  selectedColor: OilChangeFormTheme.gold.withValues(
                    alpha: 0.22,
                  ),
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
          inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
        ),
        if (_offersEnabled || _discountFils > 0) _buildOfferPanel(cs),
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
          inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
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

  /// السعر والخصم وسببه والإجمالي، والسطر التشجيعي — تظهر عند كتابة اللوحة.
  Widget _buildOfferPanel(ColorScheme cs) {
    final discount = _discountFils;
    final reason = _discountOverridden ? 'خصم يدوي' : _offer.reasonAr;
    String money(int f) => IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(f));
    Widget row(
      String label,
      String value, {
      bool strong = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              fontSize: strong ? 16 : 14,
              color: color,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('السعر', money(_totalFils)),
            Row(
              children: [
                Expanded(
                  child: row(
                    discount > 0 ? 'الخصم — ${reason ?? ''}' : 'الخصم',
                    discount > 0 ? '- ${money(discount)}' : '0',
                    color: discount > 0 ? Colors.green.shade800 : null,
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل الخصم',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || _totalFils <= 0 ? null : _editDiscount,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ),
            const Divider(height: 12),
            row('الإجمالي', money(_netFils), strong: true),
            if (_offer.encouragementAr != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.local_car_wash_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _offer.encouragementAr!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
