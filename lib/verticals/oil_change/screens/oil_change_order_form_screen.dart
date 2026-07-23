// ignore_for_file: unused_field, unused_element

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../theme/design_tokens.dart';
import '../../../models/customer_record.dart';
import '../models/oil_change_hydraulic_card_slot.dart';
import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';
import '../models/oil_change_hydraulic_catalog_entry.dart';
import '../models/oil_change_oil_catalog_entry.dart';
import '../models/oil_change_product_line.dart';
import '../models/oil_change_service_item.dart';
import '../services/oil_change_filter_catalog_repository.dart';
import '../services/oil_change_hydraulic_catalog_repository.dart';
import '../services/oil_change_oil_catalog_repository.dart';
import '../../../screens/customers/customer_form_screen.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../../../services/product_repository.dart';
import '../models/oil_change_wa_notify_status.dart';
import '../services/oil_change_orders_repository.dart';
import '../services/oil_change_settings.dart';
import '../services/oil_change_services_repository.dart';
import '../services/oil_change_stock_service.dart';
import '../../../services/oil_product_grades_repository.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/customer_validation.dart';
import '../../../widgets/milliliter_quantity_stepper.dart';
import '../../../widgets/inputs/arabic_speech_mic_button.dart';
import '../widgets/customer_open_debt_banner.dart';
import '../../../widgets/barcode_input_launcher.dart';
import '../widgets/oil_change_customer_name_field.dart';
import '../widgets/oil_change_products_card.dart';
import '../widgets/oil_change_royal_card.dart';
import '../widgets/product_picker_dialog.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_save_success_overlay.dart';
import '../../../theme/sale_brand.dart';
import '../widgets/oil_change_filter_catalog_sheet.dart';
import '../widgets/oil_change_hydraulic_catalog_sheet.dart';
import '../widgets/oil_change_oil_catalog_sheet.dart';
import '../utils/oil_change_lookup_normalize.dart';
import '../utils/oil_change_prefill_guard.dart';
import '../utils/oil_change_customer_debt.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_change_log_format.dart';
import '../../../utils/shift_actor_conflict_guard.dart';
import '../../../services/print_settings_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/global_barcode_route_bridge.dart';
import '../../../providers/shift_provider.dart';
import '../services/oil_change_checkout_service.dart';
import '../services/oil_change_whatsapp_notify_service.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import '../services/oil_change_product_scan.dart';
import '../../../utils/customer_phone_launch.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_service_whatsapp_message.dart';
import '../utils/oil_change_service_pdf.dart';
import '../../../utils/sale_receipt_pdf.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/adaptive_form_container.dart';
import '../../../navigation/app_root_navigator_key.dart';
import '../../../models/print_settings_data.dart';
import '../../../navigation/content_navigation.dart';
import '../utils/oil_change_order_status.dart';
import 'oil_change_form_screen.dart';

enum _OilFormOptionalSection {
  products,
  filters,
  hydraulicGear,
  hydraulicPower,
  services,
}

enum _OilSubmitIntent { complete, suspend }

/// مهمة ما بعد الحفظ — طباعة وواتساب دون حجب واجهة البطاقة.
class _OilPostSaveJob {
  const _OilPostSaveJob({
    required this.order,
    required this.orderId,
    required this.invoiceId,
    required this.customerPhone,
    required this.printSettings,
    required this.waAuto,
    required this.waManual,
    required this.priorOpenDebtFils,
    required this.isEdit,
    this.checkoutError,
  });

  final Map<String, dynamic> order;
  final int? orderId;
  final int? invoiceId;
  final String customerPhone;
  final PrintSettingsData printSettings;
  final bool waAuto;
  final bool waManual;
  final int priorOpenDebtFils;
  final bool isEdit;
  final String? checkoutError;
}


class OilChangeOrderFormScreen extends StatefulWidget {
  const OilChangeOrderFormScreen({
    super.key,
    this.editOrderId,
    this.editOrderGlobalId,
    this.prefillFromOrder,
  }) : assert(
          editOrderId == null || prefillFromOrder == null,
          'لا يجمع التعديل مع التعبئة لبطاقة جديدة',
        );

  final int? editOrderId;
  final String? editOrderGlobalId;
  final Map<String, dynamic>? prefillFromOrder;

  bool get isEdit => editOrderId != null && editOrderId! > 0;
  bool get isNewCard => !isEdit;
  bool get oilChangeMode => true;
  bool get isOilNewCard => isNewCard;

  @override
  State<OilChangeOrderFormScreen> createState() =>
      _OilChangeOrderFormScreenState();
}

class _OilChangeOrderFormScreenState extends State<OilChangeOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _customerName = TextEditingController();
  final _customerFocus = FocusNode();
  final _customerPhone = TextEditingController();
  
  final _deviceName = TextEditingController(); // اسم السيارة
  final _carModel = TextEditingController();    // موديل السيارة
  final _deviceSerial = TextEditingController(); // رقم اللوحة
  final _engineSize = TextEditingController();   // حجم المحرك

  final _odometerCurrent = TextEditingController(); // القراءة الحالية
  final _odometerNext = TextEditingController();    // القراءة اللاحقة
  final _oilType = TextEditingController();         // نوع الزيت
  
  final _estimated = TextEditingController(text: '0');
  final _agreed = TextEditingController();
  final _advance = TextEditingController(text: '0');
  final _issue = TextEditingController(); // الملاحظات
  final _technicianName = TextEditingController(); // اسم الفني

  // Dropdowns Selection
  String? _selectedViscosity;
  final _oilSizeAmount = TextEditingController();
  String _selectedSizeUnit = 'ml';
  String? _selectedFilterType;

  // Checklist of 8 requested services
  final Set<String> _selectedServices = {};
  final Set<int> _selectedOilServiceIds = {};
  List<OilChangeServiceItem> _oilCatalog = [];
  int _basePriceFils = 0;
  bool _agreedTotalManual = false;
  bool _advanceManuallyEdited = false;
  /// يمنع اعتبار التعديلات البرمجية على `_agreed` / `_advance` تعديلاً يدوياً.
  bool _syncingCheckoutControllers = false;

  bool _oilCustomerProvided = false;
  /// إعداد المحل: ربط بطاقة الغيار بأصناف المخزون (زيت المحل).
  bool _stockFromWarehouseEnabled = true;
  int? _oilStockProductId;
  int? _oilWarehouseId;
  double _oilAvailableLiters = 0;
  List<Map<String, dynamic>> _oilProducts = const [];
  List<Map<String, dynamic>> _warehouses = const [];
  bool _oilStockMetaLoading = false;
  final _oilLitersStock = TextEditingController();
  double? _oilPickSellPerLiter;
  int? _catalogSellPerLiterFils;
  List<OilChangeOilCatalogEntry> _oilProductCatalog = const [];
  bool _oilProductCatalogLoading = false;
  String? _selectedOilBrand;
  List<OilChangeHydraulicCatalogEntry> _hydraulicProductCatalog = const [];
  bool _hydraulicProductCatalogLoading = false;
  List<OilPickLine> _oilStockPickLines = const [];
  bool _oilStockPickLinesLoading = false;
  /// مفتاح العائلة: [parentProductId] أو سالب [linkedProductId] للأصناف المفردة.
  int? _selectedOilFamilyKey;

  bool _hydraulicStockFromWarehouseEnabled = true;
  final _gearHydraulic = OilChangeHydraulicCardSlot.gear();
  final _powerHydraulic = OilChangeHydraulicCardSlot.power();
  List<OilChangeFilterCatalogEntry> _filterProductCatalog = const [];
  bool _filterProductCatalogLoading = false;
  final _engineFilter = OilChangeFilterSlot();
  final _airFilter = OilChangeFilterSlot();
  final _gearFilter = OilChangeFilterSlot();
  final _coolingFilter = OilChangeFilterSlot();
  List<OilPickLine> _hydraulicStockPickLines = const [];
  bool _hydraulicStockPickLinesLoading = false;

  /// لقطة مخزون عند فتح التعديل — لمزامنة الصرف.
  int? _editStockVoucherId;
  double _editOilLitersUsed = 0;
  int? _editOilProductId;
  int? _editOilWarehouseId;
  bool _editOilCustomerProvided = false;
  int _editInvoiceId = 0;

  bool _hydratingEdit = false;
  bool _saving = false;
  Object? _error;
  String? _errorText;

  int? _customerId;
  bool _suspendCustomerIdClear = false;
  /// يمنع مسح الهاتف بعد اختيار العميل من القائمة (سباق تحديث الحقل على التابلت/الحاسوب).
  String? _linkedCustomerName;

  DateTime? _openedAtUtc;
  DateTime? _workStartedAtUtc;
  String? _promisedDeliveryStoredIso;

  int _etaHours = 0;
  int _etaMinutes = 0;

  int? _serviceId;
  String? _serviceName;
  String _status = 'pending';
  bool _odometerNextTouched = false;
  final Set<_OilFormOptionalSection> _expandedOptional = {};
  final List<OilChangeProductLine> _oilProductLines = [];
  String? _orderGlobalId;
  GlobalBarcodeRouteBridge? _barcodeBridge;
  bool _oilBarcodeBusy = false;
  bool _isProductPickerOpen = false;
  int _customerOpenDebtFils = 0;
  bool _customerOpenDebtLoading = false;
  int _priorOpenDebtFilsAtCheckout = 0;
  PrintSettingsData? _cachedPrintSettings;
  bool? _waAutoAfterSave;
  bool? _waManualAfterSave;
  Timer? _plateVehicleSyncDebounce;
  Timer? _customerNameVisitSyncDebounce;
  bool _vehicleSyncInFlight = false;
  bool _vehicleSyncQueued = false;
  /// آخر لوحة جُلب لها سجل تلقائياً بنجاح — يمنع إعادة المزامنة لنفس اللوحة.
  String? _lastAutoSyncedPlate;
  String? _lastAutoSyncedCustomerKey;
  bool _applyingVehicleRecord = false;
  /// فتح من صف الجدول — لا جلب تلقائي من «آخر زيارة» حتى يغيّر المستخدم اللوحة أو يضغط مزامنة.
  bool _allowAutoVisitLookup = true;
  String? _prefillPlateAtOpen;
  /// منع إعادة تعبئة النموذج من `_prefill` أو مزامنة مخزون متأخرة بعد تعديل المستخدم.
  bool _initialPrefillApplied = false;
  bool _oilFluidUserEdited = false;
  bool _hydraulicGearUserEdited = false;
  bool _hydraulicPowerUserEdited = false;
  /// بعد أول مزامنة كتالوج/مخزون لبطاقة مفتوحة من الجدول — لا إعادة كتابة الزيت/الهيدروليك.
  bool _prefillCatalogSyncedOnce = false;
  bool _prefillBootstrapInProgress = false;

  final DatabaseHelper _customersDb = DatabaseHelper();

  // Static Lists
  static const _filterOptions = ['كوبي', 'أصلي', 'تجاري'];

  static const _serviceCheckboxes = [
    'تبديل هيدروليك الكبير بالجهاز',
    'تبديل هيدروليك الكبير يدوي',
    'تبديل هيدروليك الباور',
    'دهن بريك',
    'تبديل ماء الراديتر بالجهاز',
    'فلاش / غسل المحرك من الداخل',
    'تبريد',
    'شوطة',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.isEdit) {
      _status = 'pending';
    }
    _customerName.addListener(_onCustomerNameTyped);
    if (!widget.isEdit) {
      _customerName.addListener(_onCustomerNameChangedForVisitSync);
    }
    _odometerCurrent.addListener(_maybeSuggestNextOdometer);
    _odometerNext.addListener(() {
      if (_odometerDigits(_odometerNext.text).isNotEmpty) {
        _odometerNextTouched = true;
      }
    });
    _agreed.addListener(_onAgreedManualEdit);
    _advance.addListener(_onAdvanceManualEdit);
    if (!widget.isEdit) {
      _deviceSerial.addListener(_onPlateFieldChanged);
    }
    if (widget.isEdit) {
      _hydratingEdit = true;
      unawaited(_load());
    } else if (widget.prefillFromOrder != null) {
      _allowAutoVisitLookup = false;
      _applyInitialPrefillSnapshot(widget.prefillFromOrder!);
      final prefillPlate = _deviceSerial.text.trim();
      if (prefillPlate.length >= 3) {
        _prefillPlateAtOpen = prefillPlate;
        _lastAutoSyncedPlate = prefillPlate;
      }
      _prefillBootstrapInProgress = true;
      unawaited(_prefillAsyncBootstrap(widget.prefillFromOrder!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.prefillFromOrder != null) {
          unawaited(_refreshCustomerOpenDebt());
        }
      });
    } else {
      unawaited(_loadOilCatalog());
      unawaited(_loadOilProductCatalog());
      unawaited(_loadHydraulicProductCatalog());
      unawaited(_loadFilterProductCatalog());
      unawaited(_loadFluidStockSettings());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachOilBarcodeHandler();
    });
    if (widget.oilChangeMode) {
      unawaited(_warmPostSaveSettings());
    }
  }

  Future<void> _warmPostSaveSettings() async {
    if (_cachedPrintSettings != null &&
        _waAutoAfterSave != null &&
        _waManualAfterSave != null) {
      return;
    }
    final results = await Future.wait([
      PrintSettingsRepository.instance.load(),
      OilChangeSettings.whatsappAutoAfterSaveEnabled(),
      OilChangeSettings.whatsappManualAfterSaveEnabled(),
    ]);
    // حتى لو أُغلقت الشاشة، احتفظ بالإعدادات لمهمة ما بعد الحفظ.
    _cachedPrintSettings = results[0] as PrintSettingsData;
    _waAutoAfterSave = results[1] as bool;
    _waManualAfterSave = results[2] as bool;
  }

  /// رقم واتساب جاهز للإرسال: من الحقل أو البطاقة أو سجل العميل.
  Future<String> _resolveWhatsappPhoneForPostSave({
    required String preferredRaw,
    Map<String, dynamic>? order,
  }) async {
    String normalize(String? raw) {
      final western = OilChangeLookupNormalize.toWesternDigits(
        (raw ?? '').trim(),
      );
      return CustomerValidation.normalizePhoneDigits(western) ?? '';
    }

    var phone = normalize(preferredRaw);
    if (phone.isEmpty) {
      phone = normalize((order?['customerPhone'] ?? '').toString());
    }
    if (phone.isEmpty && _customerId != null && _customerId! > 0) {
      try {
        final row = await _customersDb.getCustomerById(_customerId!);
        phone = normalize((row?['phone'] ?? '').toString());
      } catch (_) {}
    }
    return phone;
  }

  Future<void> _loadFluidStockSettings({bool awaitStockLoads = false}) async {
    final oilOn = await OilChangeSettings.stockFromWarehouseEnabled();
    final hydOn = await OilChangeSettings.hydraulicStockFromWarehouseEnabled();
    if (!mounted) return;
    setState(() {
      _stockFromWarehouseEnabled = oilOn;
      _hydraulicStockFromWarehouseEnabled = hydOn;
      if (!oilOn) {
        _oilStockProductId = null;
        _oilWarehouseId = null;
        _oilLitersStock.clear();
      }
      if (!hydOn) {
        for (final slot in [_gearHydraulic, _powerHydraulic]) {
          slot.stockProductId = null;
          slot.warehouseId = null;
          slot.litersStock.clear();
        }
      }
    });
    if (oilOn) {
      if (awaitStockLoads) {
        await _loadOilStockMeta();
      } else {
        unawaited(_loadOilStockMeta());
      }
    }
    if (hydOn) {
      if (awaitStockLoads) {
        await _loadHydraulicStockMeta();
      } else {
        unawaited(_loadHydraulicStockMeta());
      }
    }
  }

  // ── Shared with repair (108 methods, 21 stubbed) ──

  void _markOilFluidUserEdited() {
    _oilFluidUserEdited = true;
    _plateVehicleSyncDebounce?.cancel();
    _customerNameVisitSyncDebounce?.cancel();
  }

  bool get _isPrefillFromLog => widget.prefillFromOrder != null;

  bool _shouldBlockFluidReconcileAfterPrefill() =>
      shouldBlockFluidReconcileAfterPrefill(
        isPrefillFromLog: _isPrefillFromLog,
        prefillCatalogSyncedOnce: _prefillCatalogSyncedOnce,
      );

  bool _blocksAutoVisitLookup({bool force = false}) =>
      shouldBlockAutoVisitLookup(
        isPrefillFromLog: widget.prefillFromOrder != null,
        allowAutoVisitLookup: _allowAutoVisitLookup,
        force: force,
      );

  void _sealPrefillFluidSnapshot() {
    if (_isPrefillFromLog) {
      _prefillCatalogSyncedOnce = true;
    }
  }

  void _enableAutoVisitLookupAfterPrefillEdit() {
    if (widget.prefillFromOrder == null || _allowAutoVisitLookup) return;
    _allowAutoVisitLookup = true;
    _lastAutoSyncedPlate = null;
  }

  void _onAgreedManualEdit() {
    if (_syncingCheckoutControllers) {
      _onOilCheckoutFieldsChanged();
      return;
    }
    _agreedTotalManual = true;
    if (!_advanceManuallyEdited) {
      _syncAdvanceFromTotal(_oilCheckoutTotalFils());
    }
    _onOilCheckoutFieldsChanged();
  }

  void _onAdvanceManualEdit() {
    if (_syncingCheckoutControllers) {
      _onOilCheckoutFieldsChanged();
      return;
    }
    _advanceManuallyEdited = true;
    _onOilCheckoutFieldsChanged();
  }

  void _syncAdvanceFromTotal(int totalFils) {
    final label = totalFils <= 0
        ? IraqiCurrencyFormat.formatDecimal2(0)
        : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(totalFils));
    _assignCheckoutControllerText(_advance, label);
  }

  void _resetOilCheckoutAutoAdvance() {
    _advanceManuallyEdited = false;
    _syncAdvanceFromTotal(_oilCheckoutTotalFils());
  }

  void _onOilCheckoutFieldsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _assignControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  /// تعيين نص حقول السعر/الدفع دون تفعيل أعلام «تعديل يدوي».
  void _assignCheckoutControllerText(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) return;
    _syncingCheckoutControllers = true;
    try {
      controller.text = value;
    } finally {
      _syncingCheckoutControllers = false;
    }
  }

  static final _carModelDigitFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
  ];

  String get _carModelForSave =>
      OilChangeLookupNormalize.toWesternDigits(_carModel.text.trim());

  static final _odometerInputFormatters = [
    IraqiCurrencyFormat.moneyInputFormatter(),
  ];

  String _odometerDigits(String display) =>
      display.replaceAll(',', '').trim();

  String _formatOdometerDisplay(String? raw) {
    final digits = OilChangeLookupNormalize.toWesternDigits(raw ?? '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final n = int.tryParse(digits);
    if (n == null || n <= 0) return digits;
    return IraqiCurrencyFormat.formatInt(n);
  }

  void _assignOdometerText(TextEditingController controller, String? raw) {
    final formatted = _formatOdometerDisplay(raw);
    if (controller.text != formatted) {
      controller.text = formatted;
    }
  }

  String get _odometerCurrentForSave => _odometerDigits(_odometerCurrent.text);

  String get _odometerNextForSave => _odometerDigits(_odometerNext.text);

  void _normalizeCarModelDisplay() {
    final normalized = OilChangeLookupNormalize.toWesternDigits(_carModel.text);
    if (_carModel.text != normalized) {
      _carModel.text = normalized;
      _carModel.selection = TextSelection.collapsed(offset: normalized.length);
    }
  }

  bool _hydraulicFluidUserEditedFor(OilChangeHydraulicCardSlot slot) {
    if (identical(slot, _gearHydraulic)) return _hydraulicGearUserEdited;
    if (identical(slot, _powerHydraulic)) return _hydraulicPowerUserEdited;
    return false;
  }

  void _syncOilCatalogPricingFromSelection() {
    final brand = _selectedOilBrand;
    final vis = _selectedViscosity;
    if (brand == null ||
        brand.isEmpty ||
        vis == null ||
        vis.isEmpty ||
        _oilProductCatalog.isEmpty) {
      return;
    }
    final entry = OilChangeOilCatalogRepository.entryForBrandViscosity(
      _oilProductCatalog,
      brandName: brand,
      viscosity: vis,
    );
    if (entry != null) {
      _catalogSellPerLiterFils = entry.sellPerLiterFils;
    }
  }

  void _syncHydraulicCatalogPricingFromSelectionFor(
    OilChangeHydraulicCardSlot slot,
  ) {
    final brand = slot.selectedBrand;
    final grade = slot.selectedGrade;
    if (brand == null ||
        brand.isEmpty ||
        grade == null ||
        grade.isEmpty ||
        _hydraulicProductCatalog.isEmpty) {
      return;
    }
    final entry = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
      _hydraulicProductCatalog,
      brandName: brand,
      grade: grade,
    );
    if (entry != null) {
      slot.catalogSellPerLiterFils = entry.sellPerLiterFils;
    }
  }

  int _oilCheckoutTotalFils() {
    final agreed = _parseFils(_agreed);
    return agreed > 0 ? agreed : _cardGrandTotalFils();
  }

  int _oilCheckoutPaidFils() => _parseFils(_advance);

  int _oilCheckoutRemainderFils() {
    final total = _oilCheckoutTotalFils();
    final paid = _oilCheckoutPaidFils();
    return (total - paid).clamp(0, total);
  }

  bool get _usesWarehouseOilPicker =>
      _stockFromWarehouseEnabled && !_oilCustomerProvided;

  bool get _showCatalogOilFields => !_usesWarehouseOilPicker;

  static int _oilFamilyKey(OilPickLine line) =>
      line.parentProductId ?? -line.linkedProductId;

  List<({int key, String label})> get _oilFamilyDropdownOptions {
    final seen = <int>{};
    final out = <({int key, String label})>[];
    for (final line in _oilStockPickLines) {
      final key = _oilFamilyKey(line);
      if (seen.add(key)) {
        out.add((key: key, label: line.parentName));
      }
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  List<OilPickLine> get _oilStockLinesForSelectedFamily {
    final key = _selectedOilFamilyKey;
    if (key == null) return const [];
    return _oilStockPickLines
        .where((l) => _oilFamilyKey(l) == key)
        .toList()
      ..sort(
        (a, b) => a.viscosity.toLowerCase().compareTo(b.viscosity.toLowerCase()),
      );
  }

  int? get _oilStockViscosityProductId {
    final pid = _oilStockProductId;
    if (pid == null || pid <= 0) return null;
    for (final l in _oilStockLinesForSelectedFamily) {
      if (l.linkedProductId == pid) return pid;
    }
    return null;
  }

  void _reconcileOilStockLineSelection() {
    if (_oilFluidUserEdited || _shouldBlockFluidReconcileAfterPrefill()) return;
    final pid = _oilStockProductId;
    if (pid == null || pid <= 0 || _oilStockPickLines.isEmpty) return;
    for (final line in _oilStockPickLines) {
      if (line.linkedProductId == pid) {
        _selectedOilFamilyKey = _oilFamilyKey(line);
        _oilType.text = line.parentName;
        _selectedViscosity =
            line.viscosity.isEmpty ? null : line.viscosity;
        _oilPickSellPerLiter = line.sellPerLiterIqd;
        return;
      }
    }
  }

  void _applyOilStockLine(OilPickLine line) {
    _markOilFluidUserEdited();
    _selectedOilFamilyKey = _oilFamilyKey(line);
    _oilStockProductId = line.linkedProductId;
    _oilType.text = line.parentName;
    _selectedViscosity = line.viscosity.isEmpty ? null : line.viscosity;
    _oilPickSellPerLiter = line.sellPerLiterIqd;
    _catalogSellPerLiterFils = null;
    _selectedOilBrand = null;
    _agreedTotalManual = false;
  }


  double _parseOilLitersStock() {
    final raw = _oilLitersStock.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return 0;
    return double.tryParse(raw) ?? 0;
  }

  void _syncStockLitersFromStepper() {
    final ml = parseOilVolumeDisplay(_oilSizeAmount.text);
    final liters = ml / 1000.0;
    if (liters <= 1e-9) {
      _oilLitersStock.clear();
      return;
    }
    _oilLitersStock.text = formatOilLitersDisplay(liters);
  }

  Future<void> _loadOilStockMeta() async {
    if (!_stockFromWarehouseEnabled) return;
    setState(() {
      _oilStockMetaLoading = true;
      _oilStockPickLinesLoading = true;
    });
    try {
      final wh = await OilChangeStockService.instance.listWarehouses();
      final prods = await OilChangeStockService.instance.listOilProducts();
      final lines = await OilChangeStockService.instance.listOilPickLines();
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        _oilProducts = prods;
        _oilStockPickLines = lines;
        if (_oilWarehouseId == null && wh.isNotEmpty) {
          _oilWarehouseId = (wh.first['id'] as num?)?.toInt();
        }
        _oilStockMetaLoading = false;
        _oilStockPickLinesLoading = false;
        if (!_oilFluidUserEdited) {
          _reconcileOilStockLineSelection();
        }
      });
      if (_oilStockProductId != null && _oilWarehouseId != null) {
        await _refreshAvailableLiters();
      }
    } catch (e, st) {
      AppLogger.error(
        'ServiceOrderForm',
        'loadOilStockMeta failed',
        e,
        st,
      );
      if (mounted) {
        setState(() {
          _oilStockMetaLoading = false;
          _oilStockPickLinesLoading = false;
          _oilStockPickLines = const [];
        });
      }
    }
  }

  Future<void> _refreshAvailableLiters() async {
    final pid = _oilStockProductId;
    final wid = _oilWarehouseId;
    if (pid == null || pid <= 0 || wid == null || wid <= 0) {
      if (mounted) setState(() => _oilAvailableLiters = 0);
      return;
    }
    try {
      final q = await OilChangeStockService.instance.availableLiters(
        productId: pid,
        warehouseId: wid,
      );
      if (mounted) setState(() => _oilAvailableLiters = q);
    } catch (_) {}
  }

  bool _effectiveHydraulicCustomerProvidedFor(OilChangeHydraulicCardSlot slot) =>
      !_hydraulicStockFromWarehouseEnabled || slot.customerProvided;

  bool _usesWarehouseHydraulicPickerFor(OilChangeHydraulicCardSlot slot) =>
      widget.oilChangeMode &&
      _hydraulicStockFromWarehouseEnabled &&
      !slot.customerProvided;

  List<({int key, String label})> get _hydraulicFamilyDropdownOptions {
    final seen = <int>{};
    final out = <({int key, String label})>[];
    for (final line in _hydraulicStockPickLines) {
      final key = _oilFamilyKey(line);
      if (seen.add(key)) out.add((key: key, label: line.parentName));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  void _reconcileHydraulicStockLineSelectionFor(OilChangeHydraulicCardSlot slot) {
    if (_hydraulicFluidUserEditedFor(slot) ||
        _shouldBlockFluidReconcileAfterPrefill()) {
      return;
    }
    final pid = slot.stockProductId;
    if (pid == null || pid <= 0 || _hydraulicStockPickLines.isEmpty) return;
    for (final line in _hydraulicStockPickLines) {
      if (line.linkedProductId == pid) {
        slot.selectedFamilyKey = _oilFamilyKey(line);
        slot.type.text = line.parentName;
        slot.selectedGrade =
            line.viscosity.isEmpty ? null : line.viscosity;
        slot.pickSellPerLiter = line.sellPerLiterIqd;
        return;
      }
    }
  }

  void _syncHydraulicLitersFromStepperFor(OilChangeHydraulicCardSlot slot) {
    slot.syncLitersFromStepper();
  }

  Future<void> _loadHydraulicStockMeta() async {
    if (!_hydraulicStockFromWarehouseEnabled) return;
    setState(() => _hydraulicStockPickLinesLoading = true);
    try {
      if (_warehouses.isEmpty) {
        final wh = await OilChangeStockService.instance.listWarehouses();
        if (!mounted) return;
        setState(() {
          _warehouses = wh;
          if (_gearHydraulic.warehouseId == null && wh.isNotEmpty) {
            _gearHydraulic.warehouseId = (wh.first['id'] as num?)?.toInt();
          }
          if (_powerHydraulic.warehouseId == null && wh.isNotEmpty) {
            _powerHydraulic.warehouseId = (wh.first['id'] as num?)?.toInt();
          }
        });
      }
      final lines =
          await OilChangeStockService.instance.listHydraulicPickLines();
      if (!mounted) return;
      setState(() {
        _hydraulicStockPickLines = lines;
        _hydraulicStockPickLinesLoading = false;
        _reconcileHydraulicStockLineSelectionFor(_gearHydraulic);
        _reconcileHydraulicStockLineSelectionFor(_powerHydraulic);
      });
      if (_gearHydraulic.stockProductId != null && _gearHydraulic.warehouseId != null) {
        await _refreshHydraulicAvailableLitersFor(_gearHydraulic);
      }
      if (_powerHydraulic.stockProductId != null &&
          _powerHydraulic.warehouseId != null) {
        await _refreshHydraulicAvailableLitersFor(_powerHydraulic);
      }
    } catch (e, st) {
      AppLogger.error(
        'ServiceOrderForm',
        'loadHydraulicStockMeta failed',
        e,
        st,
      );
      if (mounted) {
        setState(() {
          _hydraulicStockPickLinesLoading = false;
          _hydraulicStockPickLines = const [];
        });
      }
    }
  }

  Future<void> _refreshHydraulicAvailableLitersFor(
    OilChangeHydraulicCardSlot slot,
  ) async {
    final pid = slot.stockProductId;
    final wid = slot.warehouseId;
    if (pid == null || pid <= 0 || wid == null || wid <= 0) {
      if (mounted) setState(() => slot.availableLiters = 0);
      return;
    }
    try {
      final q = await OilChangeStockService.instance.availableLiters(
        productId: pid,
        warehouseId: wid,
      );
      if (mounted) setState(() => slot.availableLiters = q);
    } catch (_) {}
  }


  Future<void> _loadOilCatalog() async {
    try {
      final base = await OilChangeSettings.getBaseOilChangePriceFils();
      final list = await OilChangeServicesRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _basePriceFils = base;
        _oilCatalog = list;
      });
      if (widget.isOilNewCard && !_agreedTotalManual) {
        _recalculateOilTotal();
      }
    } catch (_) {}
  }

  Future<void> _loadOilProductCatalog() async {
    final firstLoad = _oilProductCatalog.isEmpty;
    if (firstLoad && mounted) {
      setState(() => _oilProductCatalogLoading = true);
    }
    try {
      final list =
          await OilChangeOilCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _oilProductCatalog = list;
        if (firstLoad) _oilProductCatalogLoading = false;
        if (_oilFluidUserEdited) {
          _syncOilCatalogPricingFromSelection();
        } else {
          _reconcileOilCatalogSelection();
        }
      });
      if (!_agreedTotalManual) _recalculateOilTotal();
    } catch (_) {
      if (mounted && firstLoad) {
        setState(() => _oilProductCatalogLoading = false);
      }
    }
  }

  List<String> get _oilBrandDropdownItems =>
      OilChangeOilCatalogRepository.brandNamesFrom(_oilProductCatalog);

  List<OilChangeOilCatalogEntry> get _oilViscosityDropdownEntries {
    final brand = _selectedOilBrand;
    if (brand == null || brand.isEmpty) return const [];
    return OilChangeOilCatalogRepository.entriesForBrand(
      _oilProductCatalog,
      brand,
    );
  }

  String? get _oilBrandDropdownValue {
    final brand = _selectedOilBrand ?? _oilType.text.trim();
    if (brand.isEmpty) return null;
    for (final b in _oilBrandDropdownItems) {
      if (b.toLowerCase() == brand.toLowerCase()) return b;
    }
    return null;
  }

  String? get _oilViscosityDropdownValue {
    final vis = _selectedViscosity;
    if (vis == null || vis.isEmpty) return null;
    for (final e in _oilViscosityDropdownEntries) {
      if (e.viscosity.toLowerCase() == vis.toLowerCase()) return e.viscosity;
    }
    return null;
  }

  OilChangeOilCatalogEntry? _uniqueCatalogEntryForBrand(String brand) {
    final entries = OilChangeOilCatalogRepository.entriesForBrand(
      _oilProductCatalog,
      brand,
    );
    return entries.length == 1 ? entries.first : null;
  }

  void _applyCatalogOilEntryFromReconcile(OilChangeOilCatalogEntry entry) {
    _selectedOilBrand = entry.brandName;
    _assignControllerText(_oilType, entry.brandName);
    _selectedViscosity = entry.viscosity;
    _catalogSellPerLiterFils = entry.sellPerLiterFils;
  }

  void _reconcileOilCatalogSelection() {
    if (_oilFluidUserEdited) {
      _syncOilCatalogPricingFromSelection();
      return;
    }
    if (_shouldBlockFluidReconcileAfterPrefill()) {
      _syncOilCatalogPricingFromSelection();
      return;
    }
    final brand = _oilType.text.trim();
    if (brand.isEmpty) {
      _selectedOilBrand = null;
      return;
    }
    for (final b in _oilBrandDropdownItems) {
      if (b.toLowerCase() == brand.toLowerCase()) {
        _selectedOilBrand = b;
        _assignControllerText(_oilType, b);
        break;
      }
    }
    if (_selectedOilBrand == null || _oilProductCatalog.isEmpty) return;

    final vis = _selectedViscosity;
    OilChangeOilCatalogEntry? entry;
    if (vis != null && vis.isNotEmpty) {
      entry = OilChangeOilCatalogRepository.entryForBrandViscosity(
        _oilProductCatalog,
        brandName: _selectedOilBrand!,
        viscosity: vis,
      );
    }
    entry ??= _uniqueCatalogEntryForBrand(_selectedOilBrand!);
    if (entry != null) {
      _applyCatalogOilEntryFromReconcile(entry);
    }
  }

  void _reconcileOilFluidAfterVisitLoad(Map<String, dynamic> r) {
    if (_oilFluidUserEdited) {
      _syncOilCatalogPricingFromSelection();
      return;
    }
    if (_shouldBlockFluidReconcileAfterPrefill()) {
      _syncOilCatalogPricingFromSelection();
      return;
    }
    _reconcileOilCatalogSelection();
    _reconcileOilStockLineSelection();
    if (_oilSizeAmount.text.trim().isEmpty) {
      _parseOilSize(r['oilSize']?.toString());
      if (_oilSizeAmount.text.trim().isEmpty) {
        final liters = (r['oilLitersUsed'] as num?)?.toDouble();
        if (liters != null && liters > 0) {
          _oilSizeAmount.text =
              formatOilVolumeDisplay((liters * 1000).round());
          _selectedSizeUnit = 'ml';
        }
      }
    }
    _syncOilSizeRecordFromStockLiters();
    if ((_catalogSellPerLiterFils ?? 0) <= 0) {
      final catSell = (r['oilSellPerLiterFils'] as num?)?.toInt();
      if (catSell != null && catSell > 0) {
        _catalogSellPerLiterFils = catSell;
      }
    }
  }

  void _applyOilCatalogEntry(OilChangeOilCatalogEntry entry) {
    _markOilFluidUserEdited();
    _selectedOilBrand = entry.brandName;
    _assignControllerText(_oilType, entry.brandName);
    _selectedViscosity = entry.viscosity;
    _catalogSellPerLiterFils = entry.sellPerLiterFils;
    _oilStockProductId = null;
    _oilPickSellPerLiter = null;
    _oilLitersStock.clear();
    _agreedTotalManual = false;
  }


  void _onOilBrandDropdownChanged(String? brand) {
    _markOilFluidUserEdited();
    _selectedOilBrand = brand;
    _assignControllerText(_oilType, brand ?? '');
    if (brand == null) {
      _selectedViscosity = null;
      _catalogSellPerLiterFils = null;
    } else {
      final entries = OilChangeOilCatalogRepository.entriesForBrand(
        _oilProductCatalog,
        brand,
      );
      final currentVis = _selectedViscosity;
      OilChangeOilCatalogEntry? keep;
      if (currentVis != null && currentVis.isNotEmpty) {
        keep = OilChangeOilCatalogRepository.entryForBrandViscosity(
          _oilProductCatalog,
          brandName: brand,
          viscosity: currentVis,
        );
      }
      if (keep != null) {
        _selectedOilBrand = keep.brandName;
        _assignControllerText(_oilType, keep.brandName);
        _selectedViscosity = keep.viscosity;
        _catalogSellPerLiterFils = keep.sellPerLiterFils;
        _oilStockProductId = null;
        _oilPickSellPerLiter = null;
        _oilLitersStock.clear();
      } else if (entries.length == 1) {
        final entry = entries.first;
        _selectedOilBrand = entry.brandName;
        _assignControllerText(_oilType, entry.brandName);
        _selectedViscosity = entry.viscosity;
        _catalogSellPerLiterFils = entry.sellPerLiterFils;
        _oilStockProductId = null;
        _oilPickSellPerLiter = null;
        _oilLitersStock.clear();
      } else {
        _selectedViscosity = null;
        _catalogSellPerLiterFils = null;
        _oilStockProductId = null;
        _oilPickSellPerLiter = null;
      }
    }
    _agreedTotalManual = false;
    setState(() {});
    _recalculateOilTotal();
  }

  void _onOilViscosityDropdownChanged(String? viscosity) {
    _markOilFluidUserEdited();
    if (viscosity == null || _selectedOilBrand == null) return;
    final entry = OilChangeOilCatalogRepository.entryForBrandViscosity(
      _oilProductCatalog,
      brandName: _selectedOilBrand!,
      viscosity: viscosity,
    );
    if (entry == null) return;
    setState(() => _applyOilCatalogEntry(entry));
    _recalculateOilTotal();
  }

  void _matchServiceNamesToIds(Iterable<String> names) {
    _selectedOilServiceIds.clear();
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      for (final s in _oilCatalog) {
        if (s.name == n) {
          _selectedOilServiceIds.add(s.id);
          break;
        }
      }
    }
  }

  String _oilServiceNamesForSave() {
    final names = <String>[];
    for (final s in _oilCatalog) {
      if (_selectedOilServiceIds.contains(s.id)) {
        names.add(s.name);
      }
    }
    return names.join(',');
  }


  void _recalculateOilTotal() {
    if (_agreedTotalManual) {
      // الإجمالي الظاهر قد يكون من بنود البطاقة حتى لو بقي مبلغ الخدمات فارغاً.
      if (!_advanceManuallyEdited) {
        _syncAdvanceFromTotal(_oilCheckoutTotalFils());
      }
      return;
    }
    final total = _cardGrandTotalFils();
    _assignCheckoutControllerText(
      _agreed,
      IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(total)),
    );
    if (!_advanceManuallyEdited) {
      _syncAdvanceFromTotal(total);
    }
  }

  Future<void> _loadHydraulicProductCatalog() async {
    final firstLoad = _hydraulicProductCatalog.isEmpty;
    if (firstLoad && mounted) {
      setState(() => _hydraulicProductCatalogLoading = true);
    }
    try {
      final list =
          await OilChangeHydraulicCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _hydraulicProductCatalog = list;
        if (firstLoad) _hydraulicProductCatalogLoading = false;
        _reconcileHydraulicCatalogSelectionFor(_gearHydraulic);
        _reconcileHydraulicCatalogSelectionFor(_powerHydraulic);
      });
    } catch (_) {
      if (mounted && firstLoad) {
        setState(() => _hydraulicProductCatalogLoading = false);
      }
    }
  }

  OilChangeFilterSlot _filterSlotFor(OilChangeFilterKind kind) {
    return switch (kind) {
      OilChangeFilterKind.engine => _engineFilter,
      OilChangeFilterKind.air => _airFilter,
      OilChangeFilterKind.gear => _gearFilter,
      OilChangeFilterKind.cooling => _coolingFilter,
    };
  }

  Future<void> _loadFilterProductCatalog() async {
    if (mounted) setState(() => _filterProductCatalogLoading = true);
    try {
      final list =
          await OilChangeFilterCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _filterProductCatalog = list;
        _filterProductCatalogLoading = false;
        _reconcileAllFilterSelections();
      });
    } catch (_) {
      if (mounted) setState(() => _filterProductCatalogLoading = false);
    }
  }

  void _reconcileFilterSelectionFor(OilChangeFilterKind kind) {
    final slot = _filterSlotFor(kind);
    final id = slot.catalogEntryId;
    if (id != null && id > 0) {
      final entry = OilChangeFilterCatalogRepository.entryById(
        _filterProductCatalog,
        id,
      );
      if (entry == null || entry.kind != kind) {
        slot.catalogEntryId = null;
      } else {
        slot.applyEntry(entry);
        return;
      }
    }
    final name = (slot.name ?? '').trim();
    if (name.isEmpty) return;
    for (final e in OilChangeFilterCatalogRepository.entriesForKind(
      _filterProductCatalog,
      kind,
    )) {
      if (e.name.toLowerCase() == name.toLowerCase()) {
        slot.applyEntry(e);
        return;
      }
    }
  }

  void _reconcileAllFilterSelections() {
    for (final kind in OilChangeFilterKind.all) {
      _reconcileFilterSelectionFor(kind);
    }
  }

  int _filtersTotalFils() {
    if (!widget.oilChangeMode) return 0;
    var total = 0;
    for (final kind in OilChangeFilterKind.all) {
      final slot = _filterSlotFor(kind);
      if (slot.hasSelection) total += slot.priceFils;
    }
    return total;
  }

  String? _filterTypeSummaryForSave() {
    if (!widget.oilChangeMode) return _selectedFilterType;
    final parts = <String>[];
    for (final kind in OilChangeFilterKind.all) {
      final slot = _filterSlotFor(kind);
      if (!slot.hasSelection) continue;
      final line = oilFilterLineLabel(
        kindLabel: kind.label,
        name: slot.name ?? '',
        priceFils: slot.priceFils,
      );
      if (line != null) parts.add(line);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  void _loadFiltersFromRow(Map<String, dynamic> row) {
    for (final kind in OilChangeFilterKind.all) {
      _filterSlotFor(kind).loadFromRow(
        row,
        nameKey: kind.nameColumnKey,
        priceKey: kind.priceColumnKey,
      );
    }
    final anySelected =
        OilChangeFilterKind.all.any((k) => _filterSlotFor(k).hasSelection);
    if (!anySelected) {
      final legacy = (row['filterType'] ?? '').toString().trim();
      if (legacy.isNotEmpty) {
        _engineFilter.name = legacy;
        _engineFilter.priceFils = 0;
      }
    }
    _reconcileAllFilterSelections();
    _expandOptionalSectionsFromData();
  }

  List<String> get _hydraulicBrandDropdownItems =>
      OilChangeHydraulicCatalogRepository.brandNamesFrom(
        _hydraulicProductCatalog,
      );

  void _reconcileHydraulicCatalogSelectionFor(OilChangeHydraulicCardSlot slot) {
    if (_hydraulicFluidUserEditedFor(slot)) {
      _syncHydraulicCatalogPricingFromSelectionFor(slot);
      return;
    }
    if (_shouldBlockFluidReconcileAfterPrefill()) {
      _syncHydraulicCatalogPricingFromSelectionFor(slot);
      return;
    }
    final brand = slot.type.text.trim();
    if (brand.isEmpty) {
      slot.selectedBrand = null;
      return;
    }
    for (final b in _hydraulicBrandDropdownItems) {
      if (b.toLowerCase() == brand.toLowerCase()) {
        slot.selectedBrand = b;
        slot.type.text = b;
        break;
      }
    }
    final grade = slot.selectedGrade;
    if (grade == null || grade.isEmpty || slot.selectedBrand == null) return;
    final entry = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
      _hydraulicProductCatalog,
      brandName: slot.selectedBrand!,
      grade: grade,
    );
    if (entry != null) {
      slot.selectedGrade = entry.grade;
      if (slot.catalogSellPerLiterFils == null || slot.catalogSellPerLiterFils! <= 0) {
        slot.catalogSellPerLiterFils = entry.sellPerLiterFils;
      }
    }
  }

  bool _usesCatalogHydraulicPricingFor(OilChangeHydraulicCardSlot slot) =>
      (slot.catalogSellPerLiterFils ?? 0) > 0;

  bool get _usesCatalogOilPricing =>
      _catalogSellPerLiterFils != null && _catalogSellPerLiterFils! > 0;


  bool get _showOilVolumeStepper {
    if (_oilCustomerProvided) return true;
    if (_usesCatalogOilPricing) return true;
    if (_showCatalogOilFields &&
        _oilBrandDropdownValue != null &&
        _oilViscosityDropdownValue != null) {
      return true;
    }
    if (_usesWarehouseOilPicker) {
      return (_oilStockProductId ?? 0) > 0;
    }
    return false;
  }

  double _oilLitersForPricing() {
    final ml = parseOilVolumeDisplay(_oilSizeAmount.text);
    return ml / 1000.0;
  }

  double? _selectedHydraulicSellPerLiterIqdFor(OilChangeHydraulicCardSlot slot) {
    if (slot.pickSellPerLiter != null && slot.pickSellPerLiter! > 0) {
      return slot.pickSellPerLiter;
    }
    final pid = slot.stockProductId;
    if (pid == null) return null;
    for (final p in _oilProducts) {
      if ((p['id'] as num).toInt() == pid) {
        return (p['sellPrice'] as num?)?.toDouble();
      }
    }
    return null;
  }

  int _hydraulicMaterialSellFilsEstFor(OilChangeHydraulicCardSlot slot) {
    final liters = slot.litersForPricing();
    if (liters <= 1e-9) return 0;
    if (slot.customerProvided) return 0;
    if (_usesWarehouseHydraulicPickerFor(slot)) {
      if ((slot.stockProductId ?? 0) <= 0) return 0;
      final sell = _selectedHydraulicSellPerLiterIqdFor(slot);
      if (sell == null || sell <= 0) return 0;
      return IqdMoney.toFils(sell * liters);
    }
    if (_usesCatalogHydraulicPricingFor(slot)) {
      return IqdMoney.toFils(
        IqdMoney.fromFils(slot.catalogSellPerLiterFils!) * liters,
      );
    }
    return 0;
  }

  int _cardGrandTotalFils() =>
      _oilServicesTotalFils() +
      _oilMaterialSellFilsEst() +
      _hydraulicMaterialSellFilsEstFor(_gearHydraulic) +
      _hydraulicMaterialSellFilsEstFor(_powerHydraulic) +
      _filtersTotalFils() +
      _oilProductLinesTotalFils();

  String? _hydraulicSizeValueForSaveFor(OilChangeHydraulicCardSlot slot) =>
      slot.sizeValueForSave(
        usesWarehousePicker: _usesWarehouseHydraulicPickerFor(slot),
        effectiveCustomerProvided: _effectiveHydraulicCustomerProvidedFor(slot),
      );

  void _maybeSuggestNextOdometer() {
    if (_odometerNextTouched) return;
    final raw = _odometerCurrent.text.replaceAll(',', '').trim();
    final cur = int.tryParse(raw);
    if (cur == null || cur <= 0) return;
    final suggested = cur + 5000;
    final nextRaw = _odometerNext.text.replaceAll(',', '').trim();
    final next = int.tryParse(nextRaw);
    if (nextRaw.isEmpty || next == suggested - 5000) {
      _odometerNext.text = IraqiCurrencyFormat.formatInt(suggested);
    }
  }

  void _parseOilSize(String? stored) {
    if (stored == null || stored.trim().isEmpty) {
      _oilSizeAmount.clear();
      _selectedSizeUnit = 'ml';
      return;
    }
    final raw = stored.trim();
    if (raw == 'Q') {
      _oilSizeAmount.clear();
      _selectedSizeUnit = 'Q';
      return;
    }
    final ml = oilSizeStoredToMilliliters(raw);
    if (ml > 0) {
      _oilSizeAmount.text = formatOilVolumeDisplay(ml);
      _selectedSizeUnit = 'ml';
      return;
    }
    _oilSizeAmount.clear();
    _selectedSizeUnit = 'ml';
  }

  void _applyVehicleRecord(
    Map<String, dynamic> r, {
    required bool replaceAll,
    bool skipOilAndHydraulic = false,
    bool skipHydraulicGear = false,
    bool skipHydraulicPower = false,
  }) {
    void textCtrl(TextEditingController c, String key) {
      final v = (r[key] ?? '').toString();
      if (replaceAll || c.text.trim().isEmpty) {
        _assignControllerText(c, v);
      }
    }

    _applyingVehicleRecord = true;
    try {
    if (replaceAll) {
      _customerId = (r['customerId'] as num?)?.toInt();
      textCtrl(_customerName, 'customerNameSnapshot');
      textCtrl(_customerPhone, 'customerPhone');
    } else {
      if (_customerId == null) {
        final cid = (r['customerId'] as num?)?.toInt();
        if (cid != null && cid > 0) _customerId = cid;
      }
      textCtrl(_customerName, 'customerNameSnapshot');
      textCtrl(_customerPhone, 'customerPhone');
    }

    textCtrl(_deviceName, 'deviceName');
    textCtrl(_carModel, 'carModel');
    _normalizeCarModelDisplay();
    textCtrl(_deviceSerial, 'deviceSerial');
    textCtrl(_engineSize, 'engineSize');
    if (replaceAll || _odometerDigits(_odometerCurrent.text).isEmpty) {
      _assignOdometerText(
        _odometerCurrent,
        (r['odometerCurrent'] ?? '').toString(),
      );
    }
    final nextOdo = (r['odometerNext'] ?? '').toString();
    if (replaceAll || _odometerDigits(_odometerNext.text).isEmpty) {
      _assignOdometerText(_odometerNext, nextOdo);
      if (_odometerDigits(nextOdo).isNotEmpty) _odometerNextTouched = true;
    }
    if (!skipOilAndHydraulic) {
      textCtrl(_oilType, 'oilType');
      if (replaceAll) {
        _oilCustomerProvided =
            ((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
        if (!_stockFromWarehouseEnabled) {
          _oilStockProductId = null;
          _oilWarehouseId = null;
          _oilLitersStock.clear();
        } else {
          _oilStockProductId = (r['oilProductId'] as num?)?.toInt();
          _oilWarehouseId = (r['oilWarehouseId'] as num?)?.toInt();
          final liters = (r['oilLitersUsed'] as num?)?.toDouble();
          if (liters != null && liters > 0) {
            _oilLitersStock.text = liters % 1 == 0
                ? liters.toInt().toString()
                : liters.toString();
          }
        }
      }
      if (replaceAll || _selectedViscosity == null) {
        final vis = r['oilViscosity']?.toString();
        _selectedViscosity =
            vis == null || vis.isEmpty ? null : vis;
      }
      if (replaceAll || _oilSizeAmount.text.trim().isEmpty) {
        _parseOilSize(r['oilSize']?.toString());
        if (_oilSizeAmount.text.trim().isEmpty) {
          final liters = (r['oilLitersUsed'] as num?)?.toDouble();
          if (liters != null && liters > 0) {
            _oilSizeAmount.text =
                formatOilVolumeDisplay((liters * 1000).round());
            _selectedSizeUnit = 'ml';
          }
        }
      }
      if (replaceAll || (_catalogSellPerLiterFils ?? 0) <= 0) {
        final catSell = (r['oilSellPerLiterFils'] as num?)?.toInt();
        if (catSell != null && catSell > 0) {
          _catalogSellPerLiterFils = catSell;
        }
      }
    }
    if (replaceAll) {
      if (!skipHydraulicGear) {
        _gearHydraulic.loadFromRow(
          r,
          stockEnabled: _hydraulicStockFromWarehouseEnabled,
        );
      }
      if (!skipHydraulicPower) {
        _powerHydraulic.loadFromRow(
          r,
          stockEnabled: _hydraulicStockFromWarehouseEnabled,
        );
      }
    }
    textCtrl(_technicianName, 'technicianName');
    textCtrl(_issue, 'issueDescription');
    if (replaceAll || _selectedFilterType == null) {
      final ft = r['filterType']?.toString();
      _selectedFilterType =
          ft == null || ft.isEmpty ? null : ft;
    }
    if (replaceAll) {
      _loadFiltersFromRow(r);
    }

    if (replaceAll) {
      _estimated.text = IraqiCurrencyFormat.formatDecimal2(
        IqdMoney.fromFils((r['estimatedPriceFils'] as num?)?.toInt() ?? 0),
      );
      final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
      _assignCheckoutControllerText(
        _agreed,
        agreedF == null
            ? ''
            : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF)),
      );
      _assignCheckoutControllerText(
        _advance,
        IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((r['advancePaymentFils'] as num?)?.toInt() ?? 0),
        ),
      );
      _serviceId = (r['serviceId'] as num?)?.toInt();
      final req = parseOilRequestedServices(r['requestedServices']?.toString());
      _selectedOilServiceIds.clear();
      _matchServiceNamesToIds(req);
    } else {
      if (_agreed.text.trim().isEmpty) {
        final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
        if (agreedF != null) {
          _assignCheckoutControllerText(
            _agreed,
            IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF)),
          );
        }
      }
      if (_selectedOilServiceIds.isEmpty) {
        final req = parseOilRequestedServices(r['requestedServices']?.toString());
        _matchServiceNamesToIds(req);
      }
    }

    if (_customerId != null && _customerId! > 0) {
      _linkedCustomerName = _customerName.text.trim();
    }
    } finally {
      _applyingVehicleRecord = false;
    }
  }

  Future<void> _loadServiceProductIfNeeded() async {
    if (_serviceId == null || _serviceId! <= 0) return;
    try {
      final row = await ProductRepository().getProductById(_serviceId!);
      if (row != null && mounted) {
        setState(() {
          _serviceName = (row['name'] ?? '').toString().trim();
          if (_estimated.text.trim().isEmpty ||
              _estimated.text.trim() == '0') {
            final sp = (row['sellPrice'] as num?)?.toDouble() ?? 0.0;
            _estimated.text = IraqiCurrencyFormat.formatDecimal2(sp);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _syncVehicleFromPlate({
    bool showFeedback = false,
    bool overwriteExisting = false,
    bool force = false,
  }) async {
    if (widget.isEdit) return;
    final plate = _deviceSerial.text.trim();
    if (plate.length < 3) return;
    final plateKey = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (!force &&
        plateKey.isNotEmpty &&
        plateKey == _lastAutoSyncedPlate) {
      return;
    }
    await _applyLastVisitFromRepository(
      fetch: () => OilChangeOrdersRepository.instance
          .getLatestOilChangeByPlate(plate),
      foundMessage: widget.isOilNewCard
          ? 'تم جلب آخر زيارة لهذه اللوحة — عدّل ثم «حفظ وبيع» لبطاقة جديدة'
          : 'تم جلب بيانات آخر زيارة لهذه اللوحة',
      notFoundMessage: 'لا يوجد سجل غيار سابق لهذه اللوحة',
      showFeedback: showFeedback,
      overwriteExisting: overwriteExisting,
      onPlateApplied: plateKey.isNotEmpty ? plateKey : plate,
      force: force,
    );
  }

  Future<void> _syncVehicleFromCustomer(
    int customerId, {
    String? fallbackName,
  }) async {
    if (widget.isEdit || customerId <= 0) return;
    if (_blocksAutoVisitLookup()) return;
    final customerKey = 'id:$customerId';
    if (customerKey == _lastAutoSyncedCustomerKey) return;

    await _applyLastVisitFromRepository(
      fetch: () async {
        final byId = await OilChangeOrdersRepository.instance
            .getLatestOilChangeByCustomerId(customerId);
        if (byId != null) return byId;
        final name = (fallbackName ?? _customerName.text).trim();
        if (name.isEmpty) return null;
        return OilChangeOrdersRepository.instance
            .getLatestOilChangeByCustomerName(name);
      },
      foundMessage: widget.isOilNewCard
          ? 'تم جلب آخر زيارة لهذا العميل — بطاقة جديدة (السجل السابق لم يُعدَّل)'
          : 'تم جلب بيانات آخر زيارة لهذا العميل',
      notFoundMessage: 'لا يوجد سجل غيار سابق لهذا العميل',
      showFeedback: false,
      overwriteExisting: false,
      onCustomerApplied: customerKey,
    );
  }

  Future<void> _syncVehicleFromCustomerName(String name) async {
    if (widget.isEdit) return;
    if (_blocksAutoVisitLookup()) return;
    final n = name.trim();
    if (n.isEmpty) return;
    final nameKey = OilChangeLookupNormalize.normalizeNameKey(n);
    if (nameKey.isNotEmpty && nameKey == _lastAutoSyncedCustomerKey) return;

    await _applyLastVisitFromRepository(
      fetch: () => OilChangeOrdersRepository.instance
          .getLatestOilChangeByCustomerName(n),
      foundMessage: widget.isOilNewCard
          ? 'تم جلب آخر زيارة لهذا الاسم — بطاقة جديدة'
          : 'تم جلب بيانات آخر زيارة لهذا الاسم',
      notFoundMessage: 'لا يوجد سجل غيار سابق بهذا الاسم',
      showFeedback: false,
      overwriteExisting: false,
      onCustomerApplied: nameKey.isNotEmpty ? nameKey : n,
    );
  }

  void _applyLastVisitForNewCard(Map<String, dynamic> r) {
    _applyVehicleRecord(r, replaceAll: true);
    _applyNewVisitOdometerFromLogRow(r);
    _reconcileOilFluidAfterVisitLoad(r);
    _advanceManuallyEdited = false;
    _agreedTotalManual = false;
    _recalculateOilTotal();
    if (_customerId != null && _customerId! > 0) {
      _linkedCustomerName = _customerName.text.trim();
    }
  }

  void _mergeLastVisitForNewCard(Map<String, dynamic> r) {
    _applyVehicleRecord(
      r,
      replaceAll: false,
      skipOilAndHydraulic: _oilFluidUserEdited,
      skipHydraulicGear: _hydraulicGearUserEdited,
      skipHydraulicPower: _hydraulicPowerUserEdited,
    );
    if (_odometerDigits(_odometerCurrent.text).isEmpty) {
      _applyNewVisitOdometerFromLogRow(r);
    }
    if (!_oilFluidUserEdited) {
      _reconcileOilFluidAfterVisitLoad(r);
    }
    if (!_agreedTotalManual) {
      _recalculateOilTotal();
    }
  }

  Future<void> _applyLastVisitFromRepository({
    required Future<Map<String, dynamic>?> Function() fetch,
    required String foundMessage,
    required String notFoundMessage,
    bool showFeedback = false,
    bool overwriteExisting = false,
    String? onPlateApplied,
    String? onCustomerApplied,
    bool force = false,
  }) async {
    if (!widget.isOilNewCard) return;
    if (_blocksAutoVisitLookup(force: force)) return;
    if (_vehicleSyncInFlight) {
      _vehicleSyncQueued = true;
      return;
    }
    _plateVehicleSyncDebounce?.cancel();
    _customerNameVisitSyncDebounce?.cancel();
    _vehicleSyncInFlight = true;
    try {
      final row = await fetch();
      if (!mounted) return;
      if (row == null) {
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(notFoundMessage)),
          );
        }
        return;
      }
      final catalogWasEmpty = _oilProductCatalog.isEmpty;
      setState(() {
        if (widget.isOilNewCard) {
          if (overwriteExisting && !_oilFluidUserEdited) {
            _applyLastVisitForNewCard(row);
          } else {
            _mergeLastVisitForNewCard(row);
          }
        } else {
          final cid = (row['customerId'] as num?)?.toInt();
          final name = (row['customerNameSnapshot'] ?? '').toString().trim();
          _applyVehicleRecord(row, replaceAll: false);
          if (cid != null && cid > 0 && _customerId == null) {
            _customerId = cid;
            if (name.isNotEmpty) {
              _customerName.text = name;
              _linkedCustomerName = name;
            }
          }
        }
      });
      if (widget.isOilNewCard &&
          !_oilFluidUserEdited &&
          catalogWasEmpty) {
        await _loadOilProductCatalog();
        if (mounted) {
          setState(() {
            _reconcileOilFluidAfterVisitLoad(row);
          });
          if (!_agreedTotalManual) {
            _recalculateOilTotal();
          }
        }
      }
      await _loadServiceProductIfNeeded();
      unawaited(_refreshCustomerOpenDebt());
      if (onPlateApplied != null && onPlateApplied.trim().isNotEmpty) {
        _lastAutoSyncedPlate = onPlateApplied.trim();
      }
      if (onCustomerApplied != null && onCustomerApplied.trim().isNotEmpty) {
        _lastAutoSyncedCustomerKey = onCustomerApplied.trim();
      }
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(foundMessage)),
        );
      }
    } finally {
      _vehicleSyncInFlight = false;
      if (_vehicleSyncQueued && mounted) {
        _vehicleSyncQueued = false;
        unawaited(_runQueuedVehicleSync());
      }
    }
  }

  Future<void> _runQueuedVehicleSync() async {
    if (!mounted || widget.isEdit) return;
    final plate = _deviceSerial.text.trim();
    if (plate.length >= 3) {
      await _syncVehicleFromPlate();
      return;
    }
    final name = _customerName.text.trim();
    if (name.length >= 2) {
      await _onCustomerNameSettled(expectedName: name);
    }
  }

  void _applyNewVisitOdometerFromLogRow(Map<String, dynamic> r) {
    final nextRaw =
        (r['odometerNext'] ?? '').toString().replaceAll(',', '').trim();
    final next = int.tryParse(nextRaw);
    if (next != null && next > 0) {
      _assignOdometerText(_odometerCurrent, next.toString());
      _odometerNextTouched = false;
      _maybeSuggestNextOdometer();
      return;
    }
    final nextOdo = (r['odometerNext'] ?? '').toString();
    if (nextOdo.trim().isNotEmpty) {
      _odometerNextTouched = true;
    }
  }

  bool get _oilEditCompletingSuspended =>
      widget.oilChangeMode &&
      widget.isEdit &&
      _status == OilChangeOrderStatus.suspended;

  bool get _oilCheckoutFinalized =>
      _status == 'delivered' || _status == 'cancelled';


  void _onPlateFieldChanged() {
    if (widget.isEdit ||
        _hydratingEdit ||
        _applyingVehicleRecord) {
      return;
    }
    final plate = _deviceSerial.text.trim();
    if (plate.length < 3) {
      _lastAutoSyncedPlate = null;
      return;
    }
    if (widget.prefillFromOrder != null &&
        _prefillPlateAtOpen != null &&
        plate != _prefillPlateAtOpen) {
      _enableAutoVisitLookupAfterPrefillEdit();
    }
    final plateKey = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (plateKey.isNotEmpty && plateKey == _lastAutoSyncedPlate) return;
    _plateVehicleSyncDebounce?.cancel();
    final expectedPlate = plate;
    _plateVehicleSyncDebounce = Timer(const Duration(milliseconds: 450), () {
      if (_deviceSerial.text.trim() != expectedPlate) return;
      unawaited(_syncVehicleFromPlate());
    });
  }

  /// تعبئة فورية عند فتح البطاقة من سجل الجدول — قبل أي تحميل غير متزامن.
  void _applyInitialPrefillSnapshot(Map<String, dynamic> r) {
    if (_initialPrefillApplied) return;
    if (widget.isOilNewCard) {
      _applyLastVisitForNewCard(r);
    } else {
      _applyVehicleRecord(r, replaceAll: true);
    }
    _applyOptionalExpansionFromData();
    _initialPrefillApplied = true;
  }

  /// كتالوجات وإعدادات بعد التعبئة الأولى — لا يعيد كتابة حقول الزيت إن عدّلها المستخدم.
  Future<void> _prefillAsyncBootstrap(Map<String, dynamic> r) async {
    try {
      await _loadFluidStockSettings(awaitStockLoads: true);
      if (widget.isOilNewCard) {
        await _loadOilCatalog();
        await _loadOilProductCatalog();
        await _loadHydraulicProductCatalog();
        await _loadFilterProductCatalog();
      }
      if (!mounted) return;
      setState(() {
        if (!_oilFluidUserEdited) {
          _reconcileOilCatalogSelection();
          _reconcileOilStockLineSelection();
        } else {
          _syncOilCatalogPricingFromSelection();
        }
        if (!_hydraulicGearUserEdited) {
          _reconcileHydraulicCatalogSelectionFor(_gearHydraulic);
          _reconcileHydraulicStockLineSelectionFor(_gearHydraulic);
        }
        if (!_hydraulicPowerUserEdited) {
          _reconcileHydraulicCatalogSelectionFor(_powerHydraulic);
          _reconcileHydraulicStockLineSelectionFor(_powerHydraulic);
        }
        _applyOptionalExpansionFromData();
      });
      _sealPrefillFluidSnapshot();
      await _resolveCustomerLinkFromPrefill(r);
      await _loadServiceProductIfNeeded();
    } finally {
      if (mounted) {
        setState(() => _prefillBootstrapInProgress = false);
      }
    }
  }

  void _onCustomerNameTyped() {
    if (_suspendCustomerIdClear) return;
    if (_customerId == null) return;
    final typed = _customerName.text.trim();
    if (_linkedCustomerName != null && typed == _linkedCustomerName) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _customerId = null;
      _linkedCustomerName = null;
      // لا تمسح رقم الهاتف — المستخدم غالباً يكتبه في البطاقة مباشرة.
      _lastAutoSyncedCustomerKey = null;
    });
    unawaited(_refreshCustomerOpenDebt());
  }

  void _onCustomerNameChangedForVisitSync() {
    if (!widget.isOilNewCard ||
        _suspendCustomerIdClear ||
        _applyingVehicleRecord) {
      return;
    }
    _customerNameVisitSyncDebounce?.cancel();
    final expectedName = _customerName.text.trim();
    _customerNameVisitSyncDebounce = Timer(
      const Duration(milliseconds: 550),
      () {
        if (_customerName.text.trim() != expectedName) return;
        unawaited(_onCustomerNameSettled(expectedName: expectedName));
      },
    );
  }

  /// عند فتح بطاقة من السجل: ربط [customerId] تلقائياً من السجل أو الاسم أو الهاتف.
  Future<void> _resolveCustomerLinkFromPrefill(Map<String, dynamic> r) async {
    if (!widget.isOilNewCard || widget.isEdit) return;

    final snapshotName =
        (r['customerNameSnapshot'] ?? _customerName.text).toString().trim();
    final snapshotPhone =
        (r['customerPhone'] ?? _customerPhone.text).toString().trim();

    if (_customerId != null &&
        _customerId! > 0 &&
        _linkedCustomerName != null &&
        OilChangeLookupNormalize.normalizeNameKey(_linkedCustomerName!) ==
            OilChangeLookupNormalize.normalizeNameKey(snapshotName)) {
      await _refreshCustomerOpenDebt();
      return;
    }

    _suspendCustomerIdClear = true;
    try {
      var cid = _customerId ?? (r['customerId'] as num?)?.toInt();
      if (cid != null && cid <= 0) cid = null;

      if (cid == null && snapshotPhone.isNotEmpty) {
        final digits = CustomerValidation.normalizePhoneDigits(snapshotPhone);
        if (digits != null && digits.isNotEmpty) {
          cid = await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(
            digits,
          );
        }
      }

      if (cid == null && snapshotName.isNotEmpty) {
        cid = await _customersDb.tryResolveCustomerIdByExactName(snapshotName);
      }

      if (cid != null && cid > 0) {
        if (!mounted) return;
        final row = await _customersDb.getCustomerById(cid);
        final dbName = row != null
            ? (row['name'] ?? '').toString().trim()
            : snapshotName;
        setState(() {
          _customerId = cid;
          _linkedCustomerName =
              dbName.isNotEmpty ? dbName : snapshotName;
          if (dbName.isNotEmpty &&
              OilChangeLookupNormalize.normalizeNameKey(_customerName.text) !=
                  OilChangeLookupNormalize.normalizeNameKey(dbName)) {
            _assignControllerText(_customerName, dbName);
          }
          if (snapshotPhone.isNotEmpty && _customerPhone.text.trim().isEmpty) {
            _customerPhone.text = snapshotPhone;
          } else if (row != null) {
            final phone = (row['phone'] ?? '').toString().trim();
            if (phone.isNotEmpty && _customerPhone.text.trim().isEmpty) {
              _customerPhone.text = phone;
            }
          }
        });
      } else if (snapshotName.length >= 2) {
        await _tryResolveCustomerFromTypedName(snapshotName);
      }
    } finally {
      _suspendCustomerIdClear = false;
    }

    await _refreshCustomerOpenDebt();
  }

  Future<bool> _tryResolveCustomerFromTypedName(String name) async {
    final q = name.trim();
    if (q.length < 2) return false;
    final qKey = OilChangeLookupNormalize.normalizeNameKey(q);
    try {
      final rows = await _customersDb.queryCustomersPage(
        query: q,
        statusArabic: 'الكل',
        sortKey: 'name_asc',
        limit: 24,
        offset: 0,
      );
      CustomerRecord? exact;
      for (final row in rows) {
        final c = CustomerRecord.fromMap(row);
        if (OilChangeLookupNormalize.normalizeNameKey(c.name) == qKey) {
          exact = c;
          break;
        }
      }
      if (exact == null || !mounted) return false;
      final phone = exact.phone?.trim() ?? '';
      _suspendCustomerIdClear = true;
      setState(() {
        _customerId = exact!.id;
        _linkedCustomerName = exact.name.trim();
        if (phone.isNotEmpty && _customerPhone.text.trim().isEmpty) {
          _customerPhone.text = phone;
        }
      });
      _suspendCustomerIdClear = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onCustomerNameSettled({String? expectedName}) async {
    if (!widget.isOilNewCard || widget.isEdit || _applyingVehicleRecord) return;
    if (_suspendCustomerIdClear) return;

    final name = _customerName.text.trim();
    if (expectedName != null && name != expectedName) return;
    if (name.length < 2) {
      if (_customerId == null && mounted) {
        setState(() {
          _customerOpenDebtFils = 0;
          _customerOpenDebtLoading = false;
        });
      }
      return;
    }

    final nameKey = OilChangeLookupNormalize.normalizeNameKey(name);
    final linkedKey = _linkedCustomerName == null
        ? null
        : OilChangeLookupNormalize.normalizeNameKey(_linkedCustomerName!);
    final alreadySynced =
        nameKey.isNotEmpty && nameKey == _lastAutoSyncedCustomerKey;

    if (_customerId != null && nameKey == linkedKey) {
      await _refreshCustomerOpenDebt();
      if (!alreadySynced && !_blocksAutoVisitLookup()) {
        await _syncVehicleFromCustomer(_customerId!, fallbackName: name);
      }
      return;
    }

    if (_customerId == null) {
      await _tryResolveCustomerFromTypedName(name);
    }

    await _refreshCustomerOpenDebt();

    if (_blocksAutoVisitLookup()) return;

    if (_customerId != null && _customerId! > 0) {
      await _syncVehicleFromCustomer(_customerId!, fallbackName: name);
    } else {
      await _syncVehicleFromCustomerName(name);
    }
  }

  Future<void> _loadOilProductLinesForOrder(String orderGlobalId) async {
    final og = orderGlobalId.trim();
    if (og.isEmpty) return;
    final rows =
        await OilChangeOrdersRepository.instance.getOilChangeItems(og);
    if (!mounted) return;
    setState(() {
      _orderGlobalId = og;
      _oilProductLines
        ..clear()
        ..addAll(rows.map(OilChangeProductLine.fromMap));
    });
  }

  void _syncOilSizeRecordFromStockLiters() {
    if (!_usesShopOilFromStock && !_usesWarehouseOilPicker) return;
    final liters = _parseOilLitersStock();
    if (liters <= 0) return;
    final ml = (liters * 1000).round();
    if (ml <= 0) return;
    _oilSizeAmount.text = formatOilVolumeDisplay(ml);
    _selectedSizeUnit = 'ml';
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _errorText = null;
    });
    try {
      Map<String, dynamic>? r;
      final gid = widget.editOrderGlobalId?.trim();
      if (gid != null && gid.isNotEmpty) {
        r = await OilChangeOrdersRepository.instance.getOilChangeOrderByGlobalId(gid);
      } else if (widget.editOrderId != null && widget.editOrderId! > 0) {
        r = await OilChangeOrdersRepository.instance.getOilChangeOrderById(
          widget.editOrderId!,
        );
      }
      if (!mounted) return;
      if (r == null) throw StateError('not_found');
      final row = r;

      await _loadFluidStockSettings();
      await _loadOilCatalog();
      await _loadOilProductCatalog();
      await _loadFilterProductCatalog();

      final svcId = (row['serviceId'] as num?)?.toInt();
      String? svcName;
      if (svcId != null && svcId > 0) {
        final prodRow = await ProductRepository().getProductById(svcId);
        svcName = prodRow == null ? null : (prodRow['name'] ?? '').toString().trim();
      }
      final edm = (r['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
      final h = edm > 0 ? edm ~/ 60 : 0;
      final m = edm > 0 ? edm % 60 : 0;

      setState(() {
        _customerId = (row['customerId'] as num?)?.toInt();
        _customerName.text = (row['customerNameSnapshot'] ?? '').toString();
        _customerPhone.text = (row['customerPhone'] ?? '').toString();

        _deviceName.text = (row['deviceName'] ?? '').toString();
        _carModel.text = OilChangeLookupNormalize.toWesternDigits(
          (row['carModel'] ?? '').toString(),
        );
        _deviceSerial.text = (row['deviceSerial'] ?? '').toString();
        _engineSize.text = (row['engineSize'] ?? '').toString();

        _assignOdometerText(
          _odometerCurrent,
          (row['odometerCurrent'] ?? '').toString(),
        );
        _assignOdometerText(
          _odometerNext,
          (row['odometerNext'] ?? '').toString(),
        );
        _oilType.text = (row['oilType'] ?? '').toString();
        _selectedViscosity = row['oilViscosity']?.toString().isEmpty == true
            ? null
            : row['oilViscosity']?.toString();
        final catSell = (row['oilSellPerLiterFils'] as num?)?.toInt();
        _catalogSellPerLiterFils =
            catSell != null && catSell > 0 ? catSell : null;
        _reconcileOilCatalogSelection();
        _reconcileOilStockLineSelection();
        _parseOilSize(row['oilSize']?.toString());
        _selectedFilterType = row['filterType']?.toString().isEmpty == true
            ? null
            : row['filterType']?.toString();
        _loadFiltersFromRow(row);

        _status = (row['status'] ?? 'pending').toString();
        _serviceId = svcId;
        _serviceName = svcName;
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((row['estimatedPriceFils'] as num?)?.toInt() ?? 0),
        );
        final agreedF = (row['agreedPriceFils'] as num?)?.toInt();
        _assignCheckoutControllerText(
          _agreed,
          agreedF == null
              ? ''
              : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF)),
        );
        final advF = (row['advancePaymentFils'] as num?)?.toInt() ?? 0;
        _assignCheckoutControllerText(
          _advance,
          IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(advF)),
        );
        _issue.text = (row['issueDescription'] ?? '').toString();
        _technicianName.text = (row['technicianName'] ?? '').toString();

        _openedAtUtc =
            DateTime.tryParse((row['createdAt'] ?? '').toString())?.toUtc();
        _workStartedAtUtc =
            DateTime.tryParse((row['workStartedAt'] ?? '').toString())?.toUtc();
        _etaHours = h;
        _etaMinutes = m;
        final pd = (row['promisedDeliveryAt'] ?? '').toString().trim();
        _promisedDeliveryStoredIso = pd.isEmpty ? null : pd;

        _matchServiceNamesToIds(
          parseOilRequestedServices(row['requestedServices']?.toString()),
        );
        _agreedTotalManual = agreedF != null && agreedF > 0;
        _advanceManuallyEdited = advF > 0 &&
            agreedF != null &&
            agreedF > 0 &&
            advF != agreedF;
        _oilCustomerProvided =
            ((row['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
        _oilStockProductId = (row['oilProductId'] as num?)?.toInt();
        _oilWarehouseId = (row['oilWarehouseId'] as num?)?.toInt();
        final liters = (row['oilLitersUsed'] as num?)?.toDouble();
        if (liters != null && liters > 0) {
          _oilLitersStock.text = liters % 1 == 0
              ? liters.toInt().toString()
              : liters.toString();
        }
        _editStockVoucherId = (row['stockVoucherId'] as num?)?.toInt();
        _editOilLitersUsed = liters ?? 0;
        _editOilProductId = _oilStockProductId;
        _editOilWarehouseId = _oilWarehouseId;
        _editOilCustomerProvided = _oilCustomerProvided;
        _editInvoiceId = (row['invoiceId'] as num?)?.toInt() ?? 0;
        if (_stockFromWarehouseEnabled &&
            _oilStockProductId != null &&
            _oilWarehouseId != null) {
          unawaited(_refreshAvailableLiters());
        }
        if (_usesWarehouseOilPicker &&
            _oilLitersStock.text.trim().isNotEmpty) {
          _syncOilSizeRecordFromStockLiters();
        }
        _gearHydraulic.loadFromRow(
          row,
          stockEnabled: _hydraulicStockFromWarehouseEnabled,
        );
        _powerHydraulic.loadFromRow(
          row,
          stockEnabled: _hydraulicStockFromWarehouseEnabled,
        );
        _reconcileHydraulicCatalogSelectionFor(_gearHydraulic);
        _reconcileHydraulicCatalogSelectionFor(_powerHydraulic);
        if (_hydraulicStockFromWarehouseEnabled) {
          _reconcileHydraulicStockLineSelectionFor(_gearHydraulic);
          _reconcileHydraulicStockLineSelectionFor(_powerHydraulic);
          if (_gearHydraulic.stockProductId != null &&
              _gearHydraulic.warehouseId != null) {
            unawaited(_refreshHydraulicAvailableLitersFor(_gearHydraulic));
          }
          if (_powerHydraulic.stockProductId != null &&
              _powerHydraulic.warehouseId != null) {
            unawaited(_refreshHydraulicAvailableLitersFor(_powerHydraulic));
          }
        }

        _applyOptionalExpansionFromData();
        _hydratingEdit = false;
      });
      final og = (row['global_id'] ?? '').toString().trim();
      if (og.isNotEmpty) {
        await _loadOilProductLinesForOrder(og);
      }
      if (mounted) _attachOilBarcodeHandler();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _hydratingEdit = false;
      });
    }
  }

  void _attachOilBarcodeHandler() {
    GlobalBarcodeRouteBridge? bridge;
    try {
      bridge = context.read<GlobalBarcodeRouteBridge>();
    } on ProviderNotFoundException {
      return;
    }
    _barcodeBridge = bridge;
    _barcodeBridge!.setBarcodePriorityHandler(this, _onOilChangeBarcodeScan);
  }

  Future<bool> _onOilChangeBarcodeScan(String code) async {
    if (!mounted) return false;
    if (_saving || _hydratingEdit || _prefillBootstrapInProgress) return false;
    await _handleOilProductBarcode(code);
    return true;
  }
  Future<void> _refreshCustomerOpenDebt() async {
    if (!widget.oilChangeMode) return;
    if (mounted) setState(() => _customerOpenDebtLoading = true);
    try {
      final fils = await loadCustomerOpenDebtFils(
        customerId: _customerId,
        customerName: _customerName.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _customerOpenDebtFils = fils;
        _customerOpenDebtLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _customerOpenDebtFils = 0;
          _customerOpenDebtLoading = false;
        });
      }
    }
  }


  Future<void> _applyCustomerSelection(CustomerRecord c) async {
    _suspendCustomerIdClear = true;
    var phone = c.phone?.trim() ?? '';
    if (phone.isEmpty) {
      try {
        final row = await _customersDb.getCustomerById(c.id);
        if (row != null) {
          phone = (row['phone'] ?? '').toString().trim();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final name = c.name.trim();
    setState(() {
      _customerId = c.id;
      _linkedCustomerName = name;
      _lastAutoSyncedCustomerKey = null;
      _lastAutoSyncedPlate = null;
      _customerName.text = name;
      if (phone.isNotEmpty) {
        _customerPhone.text = phone;
      }
      _customerName.selection = TextSelection.collapsed(offset: name.length);
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _suspendCustomerIdClear = false;
    await _refreshCustomerOpenDebt();
    if (!_blocksAutoVisitLookup()) {
      await _syncVehicleFromCustomer(c.id, fallbackName: name);
    }
  }

  void _showOilProductSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: success
              ? const TextStyle(
                  color: SaleBrandColors.navy,
                  fontWeight: FontWeight.w700,
                )
              : null,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? SaleBrandColors.gold.withValues(alpha: 0.95)
            : Theme.of(context).colorScheme.error,
        duration: Duration(seconds: success ? 2 : 3),
      ),
    );
  }

  Future<void> _handleOilProductBarcode(String barcode) async {
    if (_oilBarcodeBusy || !mounted) return;
    setState(() => _oilBarcodeBusy = true);
    try {
      final msg = await OilChangeProductScan.handleBarcode(
        context,
        lines: _oilProductLines,
        barcode: barcode,
        suppressAddProductDialog: _isProductPickerOpen,
      );
      if (!mounted) return;
      setState(() {
        _agreedTotalManual = false;
        _expandedOptional.add(_OilFormOptionalSection.products);
      });
      _recalculateOilTotal();
      if (msg == null || msg.isEmpty) return;
      if (msg == OilChangeProductScan.unknownBarcodeMessage) {
        unawaited(HapticFeedback.mediumImpact());
        _showOilProductSnack(msg, success: false);
        return;
      }
      _showOilProductSnack(msg, success: true);
    } finally {
      if (mounted) setState(() => _oilBarcodeBusy = false);
    }
  }


  void _onOilProductQuantityChanged(int index, int quantity) {
    if (index < 0 || index >= _oilProductLines.length) return;
    setState(() {
      _oilProductLines[index].quantity = quantity <= 0 ? 1 : quantity;
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _onOilProductLineRemoved(int index) {
    if (index < 0 || index >= _oilProductLines.length) return;
    setState(() {
      _oilProductLines.removeAt(index);
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  int _oilProductLinesTotalFils() {
    var sum = 0;
    for (final l in _oilProductLines) {
      sum += l.totalFils;
    }
    return sum;
  }

  Future<void> _persistOilProductLines(int orderId) async {
    if (!widget.oilChangeMode || orderId <= 0) return;
    var gid = (_orderGlobalId ?? '').trim();
    if (gid.isEmpty) {
      final row =
          await OilChangeOrdersRepository.instance.getOilChangeOrderById(orderId);
      gid = (row?['global_id'] ?? '').toString().trim();
    }
    if (gid.isEmpty) return;
    _orderGlobalId = gid;
    await OilChangeOrdersRepository.instance.replaceOilChangeItems(
      orderGlobalId: gid,
      lines: _oilProductLines
          .map(
            (l) => (
              productId: l.productId,
              productName: l.productName,
              quantity: l.quantity,
              priceFils: l.priceFils,
            ),
          )
          .toList(),
    );
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (_isTenantScopeError(raw)) {
      return 'تعذر تحديد بيانات المستأجر. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (raw.contains('no such table') || raw.contains('no such column')) {
      return 'قاعدة البيانات تحتاج تهيئة/تحديث. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (e is StateError) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) {
        if (msg.contains('تعذّر صرف الزيت') || msg.contains('تعذر صرف الزيت')) {
          return 'تعذّر صرف الزيت من المخزون. تحقق من الرصيد والمستودع.';
        }
        return msg;
      }
    }
    if (raw.contains('الرصيد غير كافٍ') || raw.contains('رصيد غير كاف')) {
      return raw.replaceFirst('StateError: ', '').trim();
    }
    if (raw.contains('تعذّر صرف الزيت') || raw.contains('تعذر صرف الزيت')) {
      return 'تعذّر صرف الزيت من المخزون. تحقق من الرصيد والمستودع.';
    }
    if (raw.contains('CHECK constraint failed') &&
        raw.toLowerCase().contains('status')) {
      return 'تعذّر حفظ حالة «معلّقة». أغلق التطبيق وافتحه من جديد لتحديث قاعدة البيانات.';
    }
    if (raw.contains('FOREIGN KEY') ||
        raw.contains('SQLITE_CONSTRAINT_FOREIGNKEY')) {
      return 'تعذّر الحفظ: بيانات العميل أو الخدمة غير موجودة في الجهاز. '
          'أعد اختيار العميل أو اكتب الاسم والهاتف ثم احفظ مجدداً.';
    }
    final cleaned = raw
        .replaceFirst(RegExp(r'^(Exception|Error|StateError|ArgumentError):\s*'), '')
        .split('\n')
        .first
        .trim();
    if (cleaned.isNotEmpty &&
        cleaned.length <= 140 &&
        cleaned != 'Null' &&
        !cleaned.startsWith('Instance of')) {
      return 'تعذّر الحفظ: $cleaned';
    }
    return 'حدث خطأ غير متوقع أثناء الحفظ.';
  }

  bool _isTenantScopeError(String raw) {
    return raw.contains('TenantContextService') ||
        raw.contains('TenantContext غير') ||
        raw.contains('لا يوجد مستأجر نشط') ||
        raw.contains('معرّف المستأجر النشط');
  }

  ({String customerName, String deviceName}) _oilSuspendSaveLabels(
    String plate,
  ) {
    final customer = _customerName.text.trim();
    final car = _deviceName.text.trim();
    return (
      customerName: customer.isEmpty ? '—' : customer,
      deviceName: car.isEmpty ? plate : car,
    );
  }

  int _parseFils(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '');
    final v = double.tryParse(raw) ?? 0;
    return IqdMoney.toFils(v);
  }

  int? _etaTotalMinutes() {
    final t = _etaHours * 60 + _etaMinutes;
    return t > 0 ? t : null;
  }


  Future<void> _openNewCustomer() async {
    if (_hydratingEdit || _saving) return;
    final rec = await Navigator.of(context).push<CustomerRecord>(
      MaterialPageRoute(
        builder: (_) => const CustomerFormScreen(),
      ),
    );
    if (!mounted || rec == null) return;
    await _applyCustomerSelection(rec);
  }

  /// عند الحفظ: إن لم يكن العميل مربوطاً (أو الربط قديم/محذوف)، اربط أو أنشئ من الاسم/الهاتف.
  Future<String?> _ensureCustomerLinkedForSave(String customerNameOut) async {
    if (!widget.oilChangeMode) return null;

    if (_customerId != null && _customerId! > 0) {
      final existing = await _customersDb.getCustomerById(_customerId!);
      if (existing != null) return null;
      AppLogger.warn(
        'oil_change_customer',
        'stale customerId=$_customerId — re-resolve by name/phone',
      );
      if (mounted) {
        _suspendCustomerIdClear = true;
        setState(() {
          _customerId = null;
          _linkedCustomerName = null;
        });
        _suspendCustomerIdClear = false;
      } else {
        _customerId = null;
        _linkedCustomerName = null;
      }
    }

    final name = customerNameOut.trim();
    if (name.isEmpty || name == '—') return null;

    final nameErr = CustomerValidation.name(name);
    if (nameErr != null) return nameErr;

    final phoneRaw = OilChangeLookupNormalize.toWesternDigits(
      _customerPhone.text.trim(),
    );
    if (phoneRaw.isNotEmpty) {
      final phoneErr = CustomerValidation.iraqiMobilePhone(phoneRaw);
      if (phoneErr != null) return phoneErr;
    }
    final phone = CustomerValidation.normalizePhoneDigits(phoneRaw);

    Future<void> bind(int cid) async {
      if (!mounted) {
        _customerId = cid;
        _linkedCustomerName = name;
        if (phone != null && phone.isNotEmpty) {
          _customerPhone.text = phone;
        }
        return;
      }
      _suspendCustomerIdClear = true;
      setState(() {
        _customerId = cid;
        _linkedCustomerName = name;
        if (phone != null && phone.isNotEmpty) {
          _customerPhone.text = phone;
        }
      });
      _suspendCustomerIdClear = false;
      unawaited(_refreshCustomerOpenDebt());
    }

    try {
      int? cid;
      if (phone != null && phone.isNotEmpty) {
        cid = await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(
          phone,
        );
      }
      cid ??= await _customersDb.tryResolveCustomerIdByExactName(name);

      if (cid == null) {
        final tenantCtx = TenantContextService.instance;
        if (!tenantCtx.loaded) await tenantCtx.load();
        cid = await _customersDb.insertCustomer(
          name: name,
          phone: phone,
          tenantId: tenantCtx.activeTenantId,
        );
        AppLogger.info(
          'oil_change_customer',
          'auto-created customer id=$cid name=$name',
        );
      }

      if (cid <= 0) return 'تعذّر ربط العميل';
      await bind(cid);
      return null;
    } on DuplicateCustomerPhoneException catch (e) {
      if (phone != null && phone.isNotEmpty) {
        final existing =
            await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(
          phone,
        );
        if (existing != null && existing > 0) {
          await bind(existing);
          return null;
        }
      }
      return e.toString().replaceFirst('Exception: ', '');
    } catch (e, st) {
      AppLogger.error('oil_change_customer', 'auto link/create failed', e, st);
      return 'تعذّر حفظ العميل في قاعدة البيانات';
    }
  }


  Future<void> _openDurationWheel() async {
    throw UnimplementedError('shared: _openDurationWheel');
  }

  Future<void> _applyServicePricing(int? productId) async {
    if (productId == null || productId <= 0) {
      if (!mounted) return;
      setState(() {
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(0);
      });
      return;
    }
    final row = await ProductRepository().getProductById(productId);
    if (!mounted) return;
    final sp = (row?['sellPrice'] as num?)?.toDouble() ?? 0.0;
    setState(() {
      _estimated.text = IraqiCurrencyFormat.formatDecimal2(sp);
      _assignCheckoutControllerText(_agreed, '');
    });
  }


  Future<void> _pickService() async {
    throw UnimplementedError('shared: _pickService');
  }

  Map<String, dynamic> _orderSnapshotFromForm() {
    final sizeAmt = _oilSizeAmount.text.trim();
    final sizeVal = sizeAmt.isEmpty ? null : '$sizeAmt $_selectedSizeUnit';
    final cardTotal = _cardGrandTotalFils();
    final estimatedFils =
        cardTotal > 0 ? cardTotal : _parseFils(_estimated);
    return {
      if (_customerId != null && _customerId! > 0) 'customerId': _customerId,
      'customerNameSnapshot': _customerName.text.trim(),
      'customerPhone': _customerPhone.text.trim(),
      'deviceName': _deviceName.text.trim(),
      'carModel': _carModelForSave,
      'engineSize': _engineSize.text.trim(),
      'deviceSerial': _deviceSerial.text.trim(),
      'odometerCurrent': _odometerCurrentForSave,
      'odometerNext': _odometerNextForSave,
      'oilType': _oilType.text.trim(),
      'oilViscosity': _selectedViscosity,
      'oilSize': sizeVal,
      'hydraulicType': _gearHydraulic.type.text.trim(),
      'hydraulicGrade': _gearHydraulic.selectedGrade,
      'hydraulicSize': _hydraulicSizeValueForSaveFor(_gearHydraulic),
      'hydraulicCustomerProvided': _gearHydraulic.customerProvided ? 1 : 0,
      'powerHydraulicType': _powerHydraulic.type.text.trim(),
      'powerHydraulicGrade': _powerHydraulic.selectedGrade,
      'powerHydraulicSize': _hydraulicSizeValueForSaveFor(_powerHydraulic),
      'powerHydraulicCustomerProvided':
          _powerHydraulic.customerProvided ? 1 : 0,
      'filterType': _filterTypeSummaryForSave(),
      'engineFilterName': _engineFilter.name,
      'engineFilterPriceFils': _engineFilter.priceFils,
      'airFilterName': _airFilter.name,
      'airFilterPriceFils': _airFilter.priceFils,
      'gearFilterName': _gearFilter.name,
      'gearFilterPriceFils': _gearFilter.priceFils,
      'coolingFilterName': _coolingFilter.name,
      'coolingFilterPriceFils': _coolingFilter.priceFils,
      'requestedServices': widget.oilChangeMode
          ? _oilServiceNamesForSave()
          : _selectedServices.join(','),
      'technicianName': _technicianName.text.trim(),
      'issueDescription': _issue.text.trim(),
      'agreedPriceFils': _oilCheckoutTotalFils(),
      'advancePaymentFils': _oilCheckoutPaidFils(),
      // سعر البنود قبل أي تعديل يدوي على مبلغ الخدمات (للتخفيض في واتساب).
      'estimatedPriceFils': estimatedFils,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _issueNewCardStockInParallel({
    required int savedId,
    required bool oilCustomer,
    required int? oilPid,
    required int? oilWh,
    required double oilLiters,
    required bool hydCustomer,
    required int? hydPid,
    required int? hydWh,
    required double hydLiters,
    required bool powerHydCustomer,
    required int? powerHydPid,
    required int? powerHydWh,
    required double powerHydLiters,
  }) async {
    final tasks = <Future<void>>[];

    if (_stockFromWarehouseEnabled &&
        !oilCustomer &&
        oilPid != null &&
        oilWh != null &&
        oilLiters > 0) {
      tasks.add(() async {
        final voucherId =
            await OilChangeStockService.instance.issueForOilChangeOrder(
          orderId: savedId,
          productId: oilPid,
          liters: oilLiters,
          warehouseId: oilWh,
          notes: 'صرف زيت',
        );
        await OilChangeOrdersRepository.instance.updateOilChangeOrder(
          savedId,
          patchOilStockFields: true,
          stockVoucherId: voucherId,
          oilProductId: oilPid,
          oilLitersUsed: oilLiters,
          oilCustomerProvided: false,
          oilWarehouseId: oilWh,
        );
      }());
    }

    if (_hydraulicStockFromWarehouseEnabled &&
        !hydCustomer &&
        hydPid != null &&
        hydWh != null &&
        hydLiters > 0) {
      tasks.add(() async {
        final hydVoucherId =
            await OilChangeStockService.instance.issueForOilChangeOrder(
          orderId: savedId,
          productId: hydPid,
          liters: hydLiters,
          warehouseId: hydWh,
          notes: 'صرف هيدروليك الكير',
        );
        await OilChangeOrdersRepository.instance.updateOilChangeOrder(
          savedId,
          patchHydraulicStockFields: true,
          hydraulicStockVoucherId: hydVoucherId,
          hydraulicProductId: hydPid,
          hydraulicLitersUsed: hydLiters,
          hydraulicCustomerProvided: false,
          hydraulicWarehouseId: hydWh,
        );
      }());
    }

    if (_hydraulicStockFromWarehouseEnabled &&
        !powerHydCustomer &&
        powerHydPid != null &&
        powerHydWh != null &&
        powerHydLiters > 0) {
      tasks.add(() async {
        final powerVoucherId =
            await OilChangeStockService.instance.issueForOilChangeOrder(
          orderId: savedId,
          productId: powerHydPid,
          liters: powerHydLiters,
          warehouseId: powerHydWh,
          notes: 'صرف هيدروليك الباور',
        );
        await OilChangeOrdersRepository.instance.updateOilChangeOrder(
          savedId,
          patchPowerHydraulicStockFields: true,
          powerHydraulicStockVoucherId: powerVoucherId,
          powerHydraulicProductId: powerHydPid,
          powerHydraulicLitersUsed: powerHydLiters,
          powerHydraulicCustomerProvided: false,
          powerHydraulicWarehouseId: powerHydWh,
        );
      }());
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  void _showRootSnackBar(String message, {Duration duration = const Duration(seconds: 6)}) {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(message), duration: duration),
    );
  }

  Future<_OilPostSaveJob?> _buildOilPostSaveJob({
    required Map<String, dynamic>? savedOrder,
    required int? orderId,
    required bool openInvoice,
    bool skipPostSaveActions = false,
  }) async {
    if (!widget.oilChangeMode) return null;
    if (skipPostSaveActions) return null;

    final order = Map<String, dynamic>.from(
      savedOrder ?? _orderSnapshotFromForm(),
    );
    if (_customerId != null && _customerId! > 0) {
      order['customerId'] = _customerId;
    }

    int? invoiceId;
    String? checkoutError;

    if (openInvoice && orderId != null && orderId > 0 && mounted) {
      final staff = context.read<AuthProvider>().username.trim();
      try {
        final result = await OilChangeCheckoutService.instance.completeFromOrder(
          order: order,
          orderId: orderId,
          createdByUserName: staff.isEmpty ? null : staff,
        );
        invoiceId = result.invoiceId;
      } on OilChangeCheckoutException catch (e) {
        checkoutError = 'حُفظت البطاقة لكن تعذر إتمام البيع: ${e.message}';
      } catch (e) {
        checkoutError = 'تعذر إتمام البيع: $e';
      }
    }

    await _warmPostSaveSettings();
    final printData =
        _cachedPrintSettings ?? await PrintSettingsRepository.instance.load();
    _cachedPrintSettings = printData;

    final waPhone = await _resolveWhatsappPhoneForPostSave(
      preferredRaw: _customerPhone.text,
      order: order,
    );
    if (waPhone.isNotEmpty) {
      order['customerPhone'] = waPhone;
      if (_customerPhone.text.trim() != waPhone) {
        _suspendCustomerIdClear = true;
        _customerPhone.text = waPhone;
        _suspendCustomerIdClear = false;
      }
    }

    return _OilPostSaveJob(
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      customerPhone: waPhone,
      printSettings: printData,
      waAuto: _waAutoAfterSave ?? false,
      waManual: _waManualAfterSave ?? false,
      priorOpenDebtFils: _priorOpenDebtFilsAtCheckout,
      isEdit: widget.isEdit,
      checkoutError: checkoutError,
    );
  }

  void _scheduleOilPostSaveJob(_OilPostSaveJob job) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runOilPostSaveJob(job));
    });
  }

  Future<void> _runOilPostSaveJob(_OilPostSaveJob job) async {
    if (job.checkoutError != null && job.checkoutError!.trim().isNotEmpty) {
      _showRootSnackBar(
        job.checkoutError!,
        duration: const Duration(seconds: 7),
      );
    }

    await Future.wait([
      _runOilPostSavePrint(job),
      _runOilPostSaveWhatsapp(job),
    ]);
  }

  Future<void> _runOilPostSavePrint(_OilPostSaveJob job) async {
    final invoiceId = job.invoiceId;
    if (invoiceId == null || invoiceId <= 0) return;
    try {
      final full = await DatabaseHelper().getInvoiceById(invoiceId);
      if (full == null) return;
      final subtotalForPrint =
          full.items.fold<double>(0, (sum, e) => sum + e.total);
      final printErr = await SaleReceiptPdf.tryAutoPrintReceipt(
        invoice: full,
        subtotalBeforeDiscount: subtotalForPrint,
        printSettings: job.printSettings,
      );
      if (printErr != null) {
        _showRootSnackBar(printErr);
      }
    } catch (e) {
      _showRootSnackBar('تعذرت الطباعة: $e');
    }
  }

  Future<void> _runOilPostSaveWhatsapp(_OilPostSaveJob job) async {
    final phone = job.customerPhone.trim().isNotEmpty
        ? job.customerPhone.trim()
        : CustomerValidation.normalizePhoneDigits(
              OilChangeLookupNormalize.toWesternDigits(
                (job.order['customerPhone'] ?? '').toString(),
              ),
            ) ??
            '';
    if (job.isEdit || phone.isEmpty) {
      if (!job.isEdit &&
          (job.waAuto || job.waManual) &&
          phone.isEmpty) {
        AppLogger.warn(
          'oil_change_wa',
          'skip whatsapp after save — empty customer phone',
        );
        final oid = job.orderId;
        if (oid != null && oid > 0) {
          try {
            await OilChangeOrdersRepository.instance.setWaNotifyStatus(
              orderId: oid,
              status: OilChangeWaNotifyStatus.notApplicable,
              lastError: 'empty_phone',
            );
          } catch (_) {}
        }
        _showRootSnackBar(
          'لم يُرسل واتساب: أدخل رقم هاتف الزبون في البطاقة',
          duration: const Duration(seconds: 6),
        );
      }
      return;
    }
    if (!job.waAuto && !job.waManual) return;

    if (job.waAuto) {
      try {
        final outcome = await OilChangeWhatsappNotifyService.instance
            .notifyAfterOilChangeSave(
          customerPhone: phone,
          order: job.order,
          printSettings: job.printSettings,
          orderId: job.orderId,
          invoiceId: job.invoiceId,
        );
        // أظهر دائماً نتيجة الإرسال (نجاح أو فشل) حتى لا يُظن أن النظام «صامت».
        final base = OilChangeWhatsappUserMessages.snackbarForOutcome(outcome);
        final msg = outcome.isSent
            ? base
            : '$base — أعد الإرسال من قائمة واتساب عند توفر الإنترنت';
        _showRootSnackBar(
          msg,
          duration: Duration(seconds: outcome.isSent ? 4 : 8),
        );
      } catch (e) {
        _showRootSnackBar('تعذّر إرسال واتساب: $e');
      }
      return;
    }

    if (!job.waManual) return;

    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    try {
      await OilChangeServicePdf.share(
        order: job.order,
        printSettings: job.printSettings,
      );
    } catch (e) {
      _showRootSnackBar('تعذّر إنشاء ملف PDF: $e');
      final msg = buildOilServiceWhatsAppMessage(
        order: job.order,
        storeTitle: job.printSettings.whatsappStoreTitle,
        storeFooter: job.printSettings.whatsappStoreFooter,
        priorOpenDebtFils: job.priorOpenDebtFils,
      );
      if (!ctx.mounted) return;
      await launchWhatsAppWithMessage(
        ctx,
        phone: phone,
        message: msg,
      );
    }
  }

  Future<bool> _validateHydraulicStockBeforeSave({
    required OilChangeHydraulicCardSlot slot,
    required String label,
    required bool customer,
    required double liters,
    required int? productId,
    required int? warehouseId,
  }) async {
    if (!widget.oilChangeMode || !_hydraulicStockFromWarehouseEnabled) {
      return true;
    }
    if (customer || liters <= 1e-9) return true;
    if (productId == null || productId <= 0) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اختر $label من المخزون والدرجة، أو فعّل «هيدروليك العميل»',
          ),
        ),
      );
      return false;
    }
    if (warehouseId == null) return true;
    var credit = 0.0;
    if (widget.isEdit &&
        _editInvoiceId <= 0 &&
        !customer &&
        !slot.editCustomerProvided &&
        slot.editProductId == productId &&
        slot.editWarehouseId == warehouseId) {
      credit = slot.editLitersUsed;
    }
    final avail = await OilChangeStockService.instance.availableLiters(
      productId: productId,
      warehouseId: warehouseId,
    );
    if (avail + credit + 1e-9 < liters) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'رصيد $label غير كافٍ: متوفر ${avail.toStringAsFixed(1)} لتر، '
            'المطلوب ${liters.toStringAsFixed(1)} لتر',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  List<String> _missingOilChangeCoreFields() {
    final missing = <String>[];

    if (_customerName.text.trim().isEmpty) {
      missing.add('بيانات العميل: اسم العميل');
    }

    if (_deviceName.text.trim().isEmpty) {
      missing.add('بيانات السيارة: اسم السيارة');
    }
    if (_deviceSerial.text.trim().isEmpty) {
      missing.add('بيانات السيارة: رقم اللوحة');
    }

    if (_odometerDigits(_odometerCurrent.text).isEmpty) {
      missing.add('تغيير الزيت: القراءة الحالية (كم)');
    }

    final liters = _oilLitersForPricing();
    if (_oilCustomerProvided) {
      if (liters <= 1e-9) {
        missing.add('تغيير الزيت: حجم الزيت المستعمل');
      }
    } else if (_usesWarehouseOilPicker) {
      if ((_oilStockProductId ?? 0) <= 0) {
        missing.add('تغيير الزيت: اختيار الزيت من المخزون');
      }
      if (liters <= 1e-9) {
        missing.add('تغيير الزيت: حجم الزيت المستعمل');
      }
    } else if (_showCatalogOilFields) {
      if ((_oilBrandDropdownValue ?? '').trim().isEmpty) {
        missing.add('تغيير الزيت: اسم الزيت');
      }
      if ((_oilViscosityDropdownValue ?? '').trim().isEmpty) {
        missing.add('تغيير الزيت: اللزوجة');
      }
      if (liters <= 1e-9) {
        missing.add('تغيير الزيت: حجم الزيت المستعمل');
      }
    } else {
      if (_oilType.text.trim().isEmpty) {
        missing.add('تغيير الزيت: نوع الزيت');
      }
      if (liters <= 1e-9) {
        missing.add('تغيير الزيت: حجم الزيت المستعمل');
      }
    }

    return missing;
  }

  Future<void> _showOilChangeCoreMissingDialog(List<String> missing) async {
    if (!mounted || missing.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بيانات البطاقة غير مكتملة'),
        content: SingleChildScrollView(
          child: Text(
            'أكمل البطاقات الأساسية التالية قبل الحفظ أو البيع:\n\n'
            '${missing.map((m) => '• $m').join('\n')}',
            textAlign: TextAlign.start,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOilChangeOrder({
    bool openInvoice = false,
    _OilSubmitIntent intent = _OilSubmitIntent.complete,
  }) async {
    final suspending = !widget.isEdit && intent == _OilSubmitIntent.suspend;

    if (!widget.isEdit && !suspending) {
      openInvoice = true;
    }
    if (_oilEditCompletingSuspended) {
      openInvoice = true;
    }
    if (_hydratingEdit || _saving) return;

    final conflict = ShiftActorConflictGuard.evaluate(
      sessionUserId: context.read<AuthProvider>().userId,
      activeShift: context.read<ShiftProvider>().activeShift,
    );
    if (conflict.hasConflict) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا يمكن حفظ البطاقة/البيع من هذه الجلسة: الوردية المفتوحة باسم ${conflict.shiftStaffName}.',
            ),
          ),
        );
      }
      return;
    }

    if (_oilCheckoutFinalized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذه البطاقة مُغلقة ولا يمكن تعديلها.')),
        );
      }
      return;
    }

    if (suspending) {
      if (_deviceSerial.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('أدخل رقم اللوحة على الأقل قبل تعليق الفاتورة.'),
            ),
          );
        }
        return;
      }
    } else {
      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;
    }

    if (suspending) {
      _status = OilChangeOrderStatus.suspended;
      openInvoice = false;
    } else {
      final missingCore = _missingOilChangeCoreFields();
      if (missingCore.isNotEmpty) {
        await _showOilChangeCoreMissingDialog(missingCore);
        return;
      }
      _status = OilChangeOrderStatus.completed;
    }

    final serialOut = _deviceSerial.text.trim();

    final suspendLabels = suspending
        ? _oilSuspendSaveLabels(serialOut)
        : null;
    final customerNameOut = suspendLabels?.customerName ??
        _customerName.text.trim();
    final deviceNameOut =
        suspendLabels?.deviceName ?? _deviceName.text.trim();

    final sizeVal = _oilSizeValueForSave();
    final hydSizeVal = _hydraulicSizeValueForSaveFor(_gearHydraulic);
    final powerHydSizeVal = _hydraulicSizeValueForSaveFor(_powerHydraulic);

    final cardTotal = _cardGrandTotalFils();
    // تقديري = مجموع البنود؛ عند التخفيض اليدوي يبقى أعلى من السعر المتفق عليه.
    final estF = cardTotal > 0 ? cardTotal : _parseFils(_estimated);
    final agreedRaw = _agreed.text.trim().replaceAll(',', '');
    final agreedD = agreedRaw.isEmpty ? null : double.tryParse(agreedRaw);
    var agreedF = agreedD == null ? null : IqdMoney.toFils(agreedD);
    {
      if (agreedF == null || agreedF <= 0) {
        agreedF = cardTotal > 0 ? cardTotal : null;
      }
    }
    final advF = _parseFils(_advance);

    final customerLinkErr = await _ensureCustomerLinkedForSave(customerNameOut);
    if (customerLinkErr != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(customerLinkErr)),
        );
      }
      return;
    }

    if (openInvoice) {
      final totalF = agreedF ?? _cardGrandTotalFils();
      final remainderF = totalF > 0 ? (totalF - advF).clamp(0, totalF) : 0;
      if (remainderF > 500 && (_customerId == null || _customerId! <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لتسجيل المتبقي كدين: أدخل اسم العميل ورقم هاتفه أو اختره من القائمة قبل «حفظ وبيع».',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }
    }

    final etaMins = _etaTotalMinutes();
    String? promIso;
    if (_workStartedAtUtc != null && etaMins != null && etaMins > 0) {
      promIso = _workStartedAtUtc!
          .add(Duration(minutes: etaMins))
          .toIso8601String();
    }

    if (_usesWarehouseOilPicker) {
      _syncStockLitersFromStepper();
    }
    if (_usesWarehouseHydraulicPickerFor(_gearHydraulic)) {
      _syncHydraulicLitersFromStepperFor(_gearHydraulic);
    }
    if (_usesWarehouseHydraulicPickerFor(_powerHydraulic)) {
      _syncHydraulicLitersFromStepperFor(_powerHydraulic);
    }

    final oilCustomer = _oilCustomerProvided;
    final oilLiters =
        _oilLitersForPricing();
    final oilSellPerLiterFils = _usesCatalogOilPricing
        ? _catalogSellPerLiterFils
        : null;
    final oilPid = oilCustomer ? null : _oilStockProductId;
    final oilWh = oilCustomer ? null : _oilWarehouseId;

    final hydCustomer =
        _gearHydraulic.customerProvided;
    final hydLiters =
        _gearHydraulic.litersForPricing();
    final hydPid = hydCustomer ? null : _gearHydraulic.stockProductId;
    final hydWh = hydCustomer ? null : _gearHydraulic.warehouseId;

    final powerHydCustomer =
        _powerHydraulic.customerProvided;
    final powerHydLiters =
        _powerHydraulic.litersForPricing();
    final powerHydPid =
        powerHydCustomer ? null : _powerHydraulic.stockProductId;
    final powerHydWh = powerHydCustomer ? null : _powerHydraulic.warehouseId;

    if (!suspending &&
        _stockFromWarehouseEnabled &&
        !oilCustomer &&
        !_usesCatalogOilPricing &&
        oilLiters > 0 &&
        (oilPid == null || oilPid <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اختر زيت المحل واللزوجة من القائمة، أو فعّل «زيت العميل»',
          ),
        ),
      );
      return;
    }
    if (!suspending &&
        _stockFromWarehouseEnabled &&
        !oilCustomer &&
        oilLiters > 0 &&
        oilWh != null &&
        oilPid != null &&
        oilPid > 0) {
      var creditLiters = 0.0;
      if (widget.isEdit &&
          _editInvoiceId <= 0 &&
          !oilCustomer &&
          !_editOilCustomerProvided &&
          _editOilProductId == oilPid &&
          _editOilWarehouseId == oilWh) {
        creditLiters = _editOilLitersUsed;
      }
      final avail = await OilChangeStockService.instance.availableLiters(
        productId: oilPid,
        warehouseId: oilWh,
      );
      if (avail + creditLiters + 1e-9 < oilLiters) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'الرصيد غير كافٍ: متوفر ${avail.toStringAsFixed(1)} لتر، '
              'المطلوب ${oilLiters.toStringAsFixed(1)} لتر',
            ),
          ),
        );
        return;
      }
    }

    if (!suspending) {
      if (!await _validateHydraulicStockBeforeSave(
        slot: _gearHydraulic,
        label: 'هيدروليك الكير',
        customer: hydCustomer,
        liters: hydLiters,
        productId: hydPid,
        warehouseId: hydWh,
      )) {
        return;
      }
      if (!await _validateHydraulicStockBeforeSave(
        slot: _powerHydraulic,
        label: 'هيدروليك الباور',
        customer: powerHydCustomer,
        liters: powerHydLiters,
        productId: powerHydPid,
        warehouseId: powerHydWh,
      )) {
        return;
      }
    }

    {
      _priorOpenDebtFilsAtCheckout = _customerOpenDebtFils;
    }

    final postSaveWarmup = _warmPostSaveSettings();

    {
      await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
      final tenantCtx = TenantContextService.instance;
      if (!tenantCtx.loaded) {
        await tenantCtx.load();
      }
    }

    setState(() {
      _saving = true;
      _error = null;
      _errorText = null;
    });
    try {
      await postSaveWarmup;
      int? savedId;
      Map<String, dynamic>? savedOrder;

      if (widget.isEdit) {
        await OilChangeOrdersRepository.instance.updateOilChangeOrder(
          widget.editOrderId!,
          patchCustomerIdField: true,
          customerId: _customerId,
          customerNameSnapshot: customerNameOut,
          deviceName: deviceNameOut,
          deviceSerial: serialOut,
          serviceId: _serviceId,
          estimatedPriceFils: estF,
          agreedPriceFils: agreedF,
          advancePaymentFils: advF,
          status: _status,
          issueDescription: _issue.text.trim(),
          patchEtaFields: true,
          expectedDurationMinutes: etaMins,
          promisedDeliveryAt: promIso,
          carModel: _carModelForSave,
          engineSize: _engineSize.text.trim(),
          odometerCurrent: _odometerCurrentForSave,
          odometerNext: _odometerNextForSave,
          oilType: _oilType.text.trim(),
          oilViscosity: _selectedViscosity,
          oilSize: sizeVal,
          filterType: _filterTypeSummaryForSave(),
          engineFilterName:
              _engineFilter.hasSelection ? (_engineFilter.name ?? '') : null,
          engineFilterPriceFils:
              _engineFilter.hasSelection ? _engineFilter.priceFils : null,
          airFilterName: _airFilter.hasSelection ? (_airFilter.name ?? '') : null,
          airFilterPriceFils:
              _airFilter.hasSelection ? _airFilter.priceFils : null,
          gearFilterName: _gearFilter.hasSelection ? (_gearFilter.name ?? '') : null,
          gearFilterPriceFils:
              _gearFilter.hasSelection ? _gearFilter.priceFils : null,
          coolingFilterName:
              _coolingFilter.hasSelection ? (_coolingFilter.name ?? '') : null,
          coolingFilterPriceFils:
              _coolingFilter.hasSelection ? _coolingFilter.priceFils : null,
          requestedServices: widget.oilChangeMode
              ? _oilServiceNamesForSave()
              : _selectedServices.join(','),
          customerPhone: CustomerValidation.normalizePhoneDigits(
                OilChangeLookupNormalize.toWesternDigits(
                  _customerPhone.text.trim(),
                ),
              ) ??
              _customerPhone.text.trim(),
          technicianName: _technicianName.text.trim(),
          patchOilStockFields: true,
          oilProductId: oilPid,
          oilLitersUsed: oilLiters > 0 ? oilLiters : null,
          oilCustomerProvided: oilCustomer,
          oilWarehouseId: oilWh,
          oilSellPerLiterFils: oilSellPerLiterFils,
          hydraulicType: _gearHydraulic.type.text.trim(),
          hydraulicGrade: _gearHydraulic.selectedGrade,
          hydraulicSize: hydSizeVal,
          patchHydraulicStockFields: true,
          hydraulicProductId: hydPid,
          hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
          hydraulicCustomerProvided: hydCustomer,
          hydraulicWarehouseId: hydWh,
          powerHydraulicType: _powerHydraulic.type.text.trim(),
          powerHydraulicGrade: _powerHydraulic.selectedGrade,
          powerHydraulicSize: powerHydSizeVal,
          patchPowerHydraulicStockFields: true,
          powerHydraulicProductId: powerHydPid,
          powerHydraulicLitersUsed: powerHydLiters > 0 ? powerHydLiters : null,
          powerHydraulicCustomerProvided: powerHydCustomer,
          powerHydraulicWarehouseId: powerHydWh,
        );
        savedId = widget.editOrderId;
        final editId = widget.editOrderId!;
        if (_editInvoiceId <= 0) {
          try {
            if (_stockFromWarehouseEnabled) {
              final newOilVoucherId =
                  await OilChangeStockService.instance.syncStockOnEdit(
                orderId: editId,
                existingVoucherId: _editStockVoucherId,
                previousLiters: _editOilLitersUsed,
                previousProductId: _editOilProductId,
                previousWarehouseId: _editOilWarehouseId,
                previousCustomerProvided: _editOilCustomerProvided,
                newCustomerProvided: oilCustomer,
                newProductId: oilPid,
                newWarehouseId: oilWh,
                newLiters: oilLiters,
              );
              await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                editId,
                patchOilStockFields: true,
                stockVoucherId: newOilVoucherId ?? 0,
                oilProductId: oilPid,
                oilLitersUsed: oilLiters > 0 ? oilLiters : null,
                oilCustomerProvided: oilCustomer,
                oilWarehouseId: oilWh,
              );
            }
            if (_hydraulicStockFromWarehouseEnabled) {
              final newGearVoucherId =
                  await OilChangeStockService.instance.syncStockOnEdit(
                orderId: editId,
                existingVoucherId: _gearHydraulic.editStockVoucherId,
                previousLiters: _gearHydraulic.editLitersUsed,
                previousProductId: _gearHydraulic.editProductId,
                previousWarehouseId: _gearHydraulic.editWarehouseId,
                previousCustomerProvided: _gearHydraulic.editCustomerProvided,
                newCustomerProvided: hydCustomer,
                newProductId: hydPid,
                newWarehouseId: hydWh,
                newLiters: hydLiters,
              );
              await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                editId,
                patchHydraulicStockFields: true,
                hydraulicStockVoucherId: newGearVoucherId ?? 0,
                hydraulicProductId: hydPid,
                hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
                hydraulicCustomerProvided: hydCustomer,
                hydraulicWarehouseId: hydWh,
              );
              final newPowerVoucherId =
                  await OilChangeStockService.instance.syncStockOnEdit(
                orderId: editId,
                existingVoucherId: _powerHydraulic.editStockVoucherId,
                previousLiters: _powerHydraulic.editLitersUsed,
                previousProductId: _powerHydraulic.editProductId,
                previousWarehouseId: _powerHydraulic.editWarehouseId,
                previousCustomerProvided: _powerHydraulic.editCustomerProvided,
                newCustomerProvided: powerHydCustomer,
                newProductId: powerHydPid,
                newWarehouseId: powerHydWh,
                newLiters: powerHydLiters,
              );
              await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                editId,
                patchPowerHydraulicStockFields: true,
                powerHydraulicStockVoucherId: newPowerVoucherId ?? 0,
                powerHydraulicProductId: powerHydPid,
                powerHydraulicLitersUsed:
                    powerHydLiters > 0 ? powerHydLiters : null,
                powerHydraulicCustomerProvided: powerHydCustomer,
                powerHydraulicWarehouseId: powerHydWh,
              );
            }
          } catch (e) {
            if (!mounted) return;
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
            return;
          }
        } else if (_editInvoiceId > 0 &&
            (oilCustomer != _editOilCustomerProvided ||
                oilPid != _editOilProductId ||
                oilWh != _editOilWarehouseId ||
                (oilLiters - _editOilLitersUsed).abs() > 1e-9)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تم حفظ البطاقة. المخزون لم يُغيّر لأنها مرتبطة بفاتورة — '
                  'عدّل الفاتورة يدوياً إن لزم.',
                ),
              ),
            );
          }
        }
        savedOrder = await OilChangeOrdersRepository.instance.getOilChangeOrderById(
          widget.editOrderId!,
        );
      } else {
        savedId = await OilChangeOrdersRepository.instance.createOilChangeOrder(
          customerId: _customerId,
          customerNameSnapshot: customerNameOut,
          deviceName: deviceNameOut,
          deviceSerial: serialOut,
          serviceId: _serviceId,
          estimatedPriceFils: estF,
          agreedPriceFils: agreedF,
          advancePaymentFils: advF,
          status: _status,
          issueDescription: _issue.text.trim(),
          expectedDurationMinutes: etaMins,
          promisedDeliveryAt: null,
          carModel: _carModelForSave,
          engineSize: _engineSize.text.trim(),
          odometerCurrent: _odometerCurrentForSave,
          odometerNext: _odometerNextForSave,
          oilType: _oilType.text.trim(),
          oilViscosity: _selectedViscosity,
          oilSize: sizeVal,
          filterType: _filterTypeSummaryForSave(),
          engineFilterName:
              _engineFilter.hasSelection ? (_engineFilter.name ?? '') : null,
          engineFilterPriceFils:
              _engineFilter.hasSelection ? _engineFilter.priceFils : null,
          airFilterName: _airFilter.hasSelection ? (_airFilter.name ?? '') : null,
          airFilterPriceFils:
              _airFilter.hasSelection ? _airFilter.priceFils : null,
          gearFilterName: _gearFilter.hasSelection ? (_gearFilter.name ?? '') : null,
          gearFilterPriceFils:
              _gearFilter.hasSelection ? _gearFilter.priceFils : null,
          coolingFilterName:
              _coolingFilter.hasSelection ? (_coolingFilter.name ?? '') : null,
          coolingFilterPriceFils:
              _coolingFilter.hasSelection ? _coolingFilter.priceFils : null,
          requestedServices: _oilServiceNamesForSave(),
          customerPhone: CustomerValidation.normalizePhoneDigits(
                OilChangeLookupNormalize.toWesternDigits(
                  _customerPhone.text.trim(),
                ),
              ) ??
              _customerPhone.text.trim(),
          technicianName: _technicianName.text.trim(),
          oilProductId: oilPid,
          oilLitersUsed: oilLiters > 0 ? oilLiters : null,
          oilCustomerProvided: oilCustomer,
          oilWarehouseId: oilWh,
          oilSellPerLiterFils: oilSellPerLiterFils,
          hydraulicType: _gearHydraulic.type.text.trim(),
          hydraulicGrade: _gearHydraulic.selectedGrade,
          hydraulicSize: hydSizeVal,
          hydraulicProductId: hydPid,
          hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
          hydraulicCustomerProvided: hydCustomer,
          hydraulicWarehouseId: hydWh,
          powerHydraulicType: _powerHydraulic.type.text.trim(),
          powerHydraulicGrade: _powerHydraulic.selectedGrade,
          powerHydraulicSize: powerHydSizeVal,
          powerHydraulicProductId: powerHydPid,
          powerHydraulicLitersUsed: powerHydLiters > 0 ? powerHydLiters : null,
          powerHydraulicCustomerProvided: powerHydCustomer,
          powerHydraulicWarehouseId: powerHydWh,
        );
        if (!widget.isEdit && !suspending) {
          await _issueNewCardStockInParallel(
            savedId: savedId,
            oilCustomer: oilCustomer,
            oilPid: oilPid,
            oilWh: oilWh,
            oilLiters: oilLiters,
            hydCustomer: hydCustomer,
            hydPid: hydPid,
            hydWh: hydWh,
            hydLiters: hydLiters,
            powerHydCustomer: powerHydCustomer,
            powerHydPid: powerHydPid,
            powerHydWh: powerHydWh,
            powerHydLiters: powerHydLiters,
          );
        }
      }
      if (savedId != null) {
        if (!suspending || _oilProductLines.isNotEmpty) {
          await _persistOilProductLines(savedId);
        }
        savedOrder = await OilChangeOrdersRepository.instance.getOilChangeOrderById(
          savedId,
        );
      }
      if (!mounted) return;

      final postSaveJob = await _buildOilPostSaveJob(
        savedOrder: savedOrder,
        orderId: savedId,
        openInvoice: openInvoice,
        skipPostSaveActions: suspending,
      );
      if (!mounted) return;

      if (suspending) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تعليق الفاتورة — يمكنك استكمالها لاحقاً')),
        );
        unawaited(
          Navigator.of(context).pushReplacement(
            contentMaterialRoute(
              routeId: AppContentRoutes.oilChangeCreate,
              breadcrumbTitle: 'بطاقة غيار زيت جديدة',
              builder: (_) => const OilChangeFormScreen(),
            ),
          ),
        );
        return;
      }

      setState(() => _saving = false);

      final celebrateSale = openInvoice &&
          postSaveJob != null &&
          postSaveJob.checkoutError == null &&
          (postSaveJob.invoiceId ?? 0) > 0;
      if (celebrateSale && mounted) {
        await showOilChangeSaveSuccessOverlay(context);
      }
      if (!mounted) return;

      // ابدأ واتساب/الطباعة قبل إغلاق الشاشة حتى لا يُفقد الرقم مع dispose.
      if (postSaveJob != null) {
        _scheduleOilPostSaveJob(postSaveJob);
      }
      Navigator.pop(context, true);
    } catch (e, st) {
      AppLogger.error('oil_change_save', 'submitOilChangeOrder failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _saving = false;
      });
    }
  }

  Future<void> _submit({
    bool openInvoice = false,
    _OilSubmitIntent intent = _OilSubmitIntent.complete,
  }) async {
    await _submitOilChangeOrder(
      openInvoice: openInvoice,
      intent: intent,
    );
  }

  bool _hydraulicSlotHasData(OilChangeHydraulicCardSlot slot) {
    return slot.type.text.trim().isNotEmpty ||
        (slot.selectedGrade ?? '').trim().isNotEmpty ||
        slot.litersForPricing() > 1e-9 ||
        (slot.stockProductId ?? 0) > 0 ||
        slot.customerProvided;
  }

  void _applyOptionalExpansionFromData() {
    if (_oilProductLines.isNotEmpty) {
      _expandedOptional.add(_OilFormOptionalSection.products);
    }
    if (_engineFilter.hasSelection ||
        _airFilter.hasSelection ||
        _gearFilter.hasSelection ||
        _coolingFilter.hasSelection) {
      _expandedOptional.add(_OilFormOptionalSection.filters);
    }
    if (_hydraulicSlotHasData(_gearHydraulic)) {
      _expandedOptional.add(_OilFormOptionalSection.hydraulicGear);
    }
    if (_hydraulicSlotHasData(_powerHydraulic)) {
      _expandedOptional.add(_OilFormOptionalSection.hydraulicPower);
    }
    if (_selectedOilServiceIds.isNotEmpty) {
      _expandedOptional.add(_OilFormOptionalSection.services);
    }
  }

  void _expandOptionalSectionsFromData() {
    setState(_applyOptionalExpansionFromData);
  }

  Widget _buildOilPriceBreakdownSummary(ColorScheme cs) {
    if (_basePriceFils <= 0 &&
        _selectedOilServiceIds.isEmpty &&
        _oilMaterialSellFilsEst() <= 0 &&
        _hydraulicMaterialSellFilsEstFor(_gearHydraulic) <= 0 &&
        _hydraulicMaterialSellFilsEstFor(_powerHydraulic) <= 0 &&
        _filtersTotalFils() <= 0) {
      return const SizedBox.shrink();
    }

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_basePriceFils > 0)
              Text(
                'تبديل الزيت: ${_formatFilsLabel(_basePriceFils)}',
                textAlign: TextAlign.start,
              ),
            if (_selectedOilServiceIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'خدمات إضافية: ${_formatFilsLabel(_oilExtrasFils())}',
                textAlign: TextAlign.start,
              ),
            ],
            if (_basePriceFils > 0 || _selectedOilServiceIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'مجموع الخدمات: ${_formatFilsLabel(_oilServicesTotalFils())}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
                textAlign: TextAlign.start,
              ),
            ],
            if (_oilMaterialSellFilsEst() > 0) ...[
              const SizedBox(height: 4),
              Text(
                'زيت (${formatOilLitersDisplay(_oilLitersForPricing())} لتر): '
                '${_formatFilsLabel(_oilMaterialSellFilsEst())}',
                textAlign: TextAlign.start,
              ),
            ],
            if (_hydraulicMaterialSellFilsEstFor(_gearHydraulic) > 0) ...[
              const SizedBox(height: 4),
              Text(
                'هيدروليك الكير (${formatOilLitersDisplay(_gearHydraulic.litersForPricing())} لتر): '
                '${_formatFilsLabel(_hydraulicMaterialSellFilsEstFor(_gearHydraulic))}',
                textAlign: TextAlign.start,
              ),
            ],
            if (_hydraulicMaterialSellFilsEstFor(_powerHydraulic) > 0) ...[
              const SizedBox(height: 4),
              Text(
                'هيدروليك الباور (${formatOilLitersDisplay(_powerHydraulic.litersForPricing())} لتر): '
                '${_formatFilsLabel(_hydraulicMaterialSellFilsEstFor(_powerHydraulic))}',
                textAlign: TextAlign.start,
              ),
            ],
            if (_filtersTotalFils() > 0) ...[
              const SizedBox(height: 4),
              Text(
                'الفلاتر: ${_formatFilsLabel(_filtersTotalFils())}',
                textAlign: TextAlign.start,
              ),
            ],
            if (_oilProductLinesTotalFils() > 0) ...[
              const SizedBox(height: 4),
              Text(
                'منتجات إضافية: ${_formatFilsLabel(_oilProductLinesTotalFils())}',
                textAlign: TextAlign.start,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'إجمالي البيع: ${_formatFilsLabel(_cardGrandTotalFils())}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.tertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilTechnicianNotesSection(BuildContext context, bool busy) {
    return OilChangeRoyalCard.section(
      context: context,
      title: 'الفني والملاحظات',
      icon: Icons.edit_note_rounded,
      children: _buildOilTechnicianAndNotesFields(
        context,
        busy,
        compact: true,
      ),
    );
  }

  List<Widget> _buildOilTechnicianAndNotesFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    return [
      TextFormField(
        controller: _technicianName,
        enabled: !busy,
        decoration: InputDecoration(
          labelText: 'اسم الفني المسؤول',
          border: const OutlineInputBorder(),
          isDense: compact,
          prefixIcon: const Icon(Icons.handyman_rounded, size: 20),
          hintText: 'مثال: أحمد علي',
        ),
        textAlign: TextAlign.start,
      ),
      SizedBox(height: compact ? 8 : 10),
      TextFormField(
        controller: _issue,
        enabled: !busy,
        decoration: InputDecoration(
          labelText: 'ملاحظات وتفاصيل إضافية',
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
          suffixIcon: ArabicSpeechMicButton(
            controller: _issue,
            enabled: !busy,
            onTextUpdated: () => setState(() {}),
          ),
        ),
        minLines: compact ? 2 : 3,
        maxLines: compact ? 4 : 6,
        textAlign: TextAlign.start,
      ),
    ];
  }

  List<Widget> _oilPaymentFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    final cs = Theme.of(context).colorScheme;
    final totalF = _oilCheckoutTotalFils();
    final paidF = _oilCheckoutPaidFils();
    final remainderF = _oilCheckoutRemainderFils();
    final totalLabel = _formatFilsLabel(totalF);
    final remainderLabel = _formatFilsLabel(remainderF);
    final hasDebt = remainderF > 500;
    final customerName = _customerName.text.trim();
    final linkedCustomer = _customerId != null && _customerId! > 0;
    final showBreakdown = _basePriceFils > 0 ||
        _selectedOilServiceIds.isNotEmpty ||
        _oilMaterialSellFilsEst() > 0 ||
        _hydraulicMaterialSellFilsEstFor(_gearHydraulic) > 0 ||
        _hydraulicMaterialSellFilsEstFor(_powerHydraulic) > 0 ||
        _filtersTotalFils() > 0 ||
        _oilProductLinesTotalFils() > 0;

    final agreedField = TextFormField(
      controller: _agreed,
      enabled: !busy,
      decoration: InputDecoration(
        labelText: 'مبلغ الخدمات (د.ع)',
        border: const OutlineInputBorder(),
        isDense: true,
        helperText: _agreedTotalManual
            ? 'معدّل يدوياً — «إعادة الحساب» يجمع الكل'
            : 'تبديل الزيت + الخدمات + الزيت والهيدروليك',
        helperMaxLines: 2,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        final s = (v ?? '').trim().replaceAll(',', '');
        if (s.isEmpty) return null;
        final n = double.tryParse(s);
        if (n == null || n < 0) return 'مبلغ غير صحيح';
        return null;
      },
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
    );

    final advanceField = TextFormField(
      controller: _advance,
      enabled: !busy,
      decoration: InputDecoration(
        labelText: 'المبلغ المستلم',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
        helperText: _advanceManuallyEdited
            ? 'يمكنك تعديل المبلغ — الفرق يُسجَّل ديناً على العميل'
            : 'يُملأ تلقائياً من الإجمالي — عدّله إن دفع أقل',
        helperMaxLines: 2,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
    );

    Widget totalHero() {
      return Container(
        width: double.infinity,
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 12 : 14,
          compact ? 10 : 12,
          compact ? 12 : 14,
          compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_rounded,
              color: AppColors.accentGold,
              size: compact ? 20 : 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الإجمالي',
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  Text(
                    totalLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 18 : 22,
                      color: AppColors.accentGold,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
            if (totalF > 0 && !_advanceManuallyEdited)
              IconButton(
                tooltip: 'إعادة ملء المبلغ المستلم',
                onPressed: busy
                    ? null
                    : () => setState(_resetOilCheckoutAutoAdvance),
                icon: Icon(Icons.sync_rounded, color: cs.primary, size: 20),
              ),
          ],
        ),
      );
    }

    Widget debtBanner() {
      if (totalF <= 0) return const SizedBox.shrink();
      if (!hasDebt) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: cs.tertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مسدّد بالكامل — لا دين',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onTertiaryContainer,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
        );
      }

      final debtText = linkedCustomer && customerName.isNotEmpty
          ? 'دين على $customerName: $remainderLabel'
          : 'متبقي (دين): $remainderLabel';

      return Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debtText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                  if (!linkedCustomer) ...[
                    const SizedBox(height: 4),
                    Text(
                      'اختر عميلاً مسجّلاً لربط الدين بحسابه',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onErrorContainer.withValues(alpha: 0.85),
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return [
      totalHero(),
      SizedBox(height: compact ? 8 : 10),
      advanceField,
      SizedBox(height: compact ? 8 : 10),
      debtBanner(),
      if (showBreakdown) ...[
        SizedBox(height: compact ? 8 : 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              'تفاصيل الأسعار',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: cs.primary,
              ),
              textAlign: TextAlign.start,
            ),
            children: [
              if (compact) _buildOilPriceBreakdownSummary(cs) else ...[
                _buildOilPriceBreakdownSummary(cs),
                const SizedBox(height: 8),
              ],
              agreedField,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            _agreedTotalManual = false;
                            _advanceManuallyEdited = false;
                            _recalculateOilTotal();
                          });
                        },
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                  label: const Text('إعادة حساب الإجمالي'),
                  style: TextButton.styleFrom(
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    padding: compact ? EdgeInsets.zero : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ] else ...[
        SizedBox(height: compact ? 6 : 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: busy
                ? null
                : () {
                    setState(() {
                      _agreedTotalManual = false;
                      _advanceManuallyEdited = false;
                      _recalculateOilTotal();
                    });
                  },
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('إعادة حساب الإجمالي'),
            style: TextButton.styleFrom(
              visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
              padding: compact ? EdgeInsets.zero : null,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildOilCheckoutActionButtons(BuildContext context, bool busy) {
    return [
      const SizedBox(height: 12),
      if (widget.isOilNewCard) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentGold,
              side: BorderSide(
                color: AppColors.accentGold.withValues(alpha: 0.65),
              ),
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
            ),
            onPressed: busy
                ? null
                : () => _submit(intent: _OilSubmitIntent.suspend),
            icon: const Icon(Icons.pause_circle_outline_rounded),
            label: Text(
              _saving ? 'جارٍ التعليق…' : 'تعليق الفاتورة',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      SizedBox(
        width: double.infinity,
        child: widget.isEdit
            ? FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                onPressed: busy
                    ? null
                    : () => _submit(openInvoice: _oilEditCompletingSuspended),
                icon: Icon(
                  _oilEditCompletingSuspended
                      ? Icons.point_of_sale_rounded
                      : Icons.save_rounded,
                ),
                label: Text(
                  _saving
                      ? 'جارٍ الحفظ…'
                      : (_oilEditCompletingSuspended ? 'حفظ وبيع' : 'حفظ'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                onPressed: busy ? null : () => _submit(openInvoice: true),
                icon: const Icon(Icons.point_of_sale_rounded),
                label: Text(
                  _saving ? 'جارٍ الحفظ…' : 'حفظ وبيع',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
    ];
  }

  List<Widget> _oilCheckoutFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    return [
      ..._oilPaymentFields(context, busy, compact: compact),
      ..._buildOilCheckoutActionButtons(context, busy),
    ];
  }


  String _formatFilsLabel(int fils) {
    if (fils <= 0) return '—';
    return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
  }

  int _oilExtrasFils() {
    var extras = 0;
    for (final s in _oilCatalog) {
      if (_selectedOilServiceIds.contains(s.id)) {
        extras += s.priceFils;
      }
    }
    return extras;
  }

  int _oilServicesTotalFils() => _basePriceFils + _oilExtrasFils();

  double? _selectedOilSellPerLiterIqd() {
    if (_oilPickSellPerLiter != null && _oilPickSellPerLiter! > 0) {
      return _oilPickSellPerLiter;
    }
    final pid = _oilStockProductId;
    if (pid == null) return null;
    for (final p in _oilProducts) {
      if ((p['id'] as num).toInt() == pid) {
        return (p['sellPrice'] as num?)?.toDouble();
      }
    }
    return null;
  }

  int _oilMaterialSellFilsEst() {
    if (_oilCustomerProvided) return 0;
    final liters = _oilLitersForPricing();
    if (liters <= 1e-9) return 0;
    if (_usesShopOilFromStock || _usesWarehouseOilPicker) {
      final sell = _selectedOilSellPerLiterIqd();
      if (sell == null || sell <= 0) return 0;
      if ((_oilStockProductId ?? 0) <= 0) return 0;
      return IqdMoney.toFils(sell * liters);
    }
    if (_usesCatalogOilPricing) {
      return IqdMoney.toFils(
        IqdMoney.fromFils(_catalogSellPerLiterFils!) * liters,
      );
    }
    return 0;
  }

  bool get _usesShopOilFromStock =>
      _stockFromWarehouseEnabled &&
      !_oilCustomerProvided &&
      _oilStockProductId != null &&
      _oilStockProductId! > 0;

  void _onOilFamilyDropdownChanged(int? familyKey) {
    _markOilFluidUserEdited();
    setState(() {
      _selectedOilFamilyKey = familyKey;
      _oilStockProductId = null;
      _oilPickSellPerLiter = null;
      _selectedViscosity = null;
      _oilAvailableLiters = 0;
      _catalogSellPerLiterFils = null;
      if (familyKey != null) {
        final lines = _oilStockPickLines
            .where((l) => _oilFamilyKey(l) == familyKey)
            .toList();
        if (lines.length == 1) {
          _applyOilStockLine(lines.first);
        }
      }
    });
    if ((_oilStockProductId ?? 0) > 0) {
      unawaited(_refreshAvailableLiters());
      _recalculateOilTotal();
    }
  }

  void _onOilStockViscosityChanged(int? linkedProductId) {
    _markOilFluidUserEdited();
    if (linkedProductId == null) {
      setState(() {
        _oilStockProductId = null;
        _oilPickSellPerLiter = null;
        _selectedViscosity = null;
        _oilAvailableLiters = 0;
      });
      _recalculateOilTotal();
      return;
    }
    OilPickLine? line;
    for (final l in _oilStockLinesForSelectedFamily) {
      if (l.linkedProductId == linkedProductId) {
        line = l;
        break;
      }
    }
    if (line == null) return;
    final picked = line;
    setState(() => _applyOilStockLine(picked));
    _syncStockLitersFromStepper();
    unawaited(_refreshAvailableLiters());
    _recalculateOilTotal();
  }

  String? _oilSizeValueForSave() {
    if (_usesShopOilFromStock || _usesWarehouseOilPicker) {
      final liters = _oilLitersForPricing();
      if (liters <= 0) return null;
      final ml = (liters * 1000).round();
      return '${formatOilVolumeDisplay(ml)} L';
    }
    if (_selectedSizeUnit == 'Q') return 'Q';
    final stored = oilSizeDisplayToStored(_oilSizeAmount.text);
    if (stored.isEmpty) return null;
    return stored;
  }

  // ── Moved methods (45) ──

  void _markHydraulicFluidUserEdited(OilChangeHydraulicCardSlot slot) {
    if (identical(slot, _gearHydraulic)) {
      _hydraulicGearUserEdited = true;
    } else if (identical(slot, _powerHydraulic)) {
      _hydraulicPowerUserEdited = true;
    }
    _plateVehicleSyncDebounce?.cancel();
    _customerNameVisitSyncDebounce?.cancel();
  }

  void _clearOilStockSelection() {
    _selectedOilFamilyKey = null;
    _oilStockProductId = null;
    _oilPickSellPerLiter = null;
    _oilAvailableLiters = 0;
    _selectedViscosity = null;
  }

  List<OilPickLine> _hydraulicStockLinesForFamily(OilChangeHydraulicCardSlot slot) {
    final key = slot.selectedFamilyKey;
    if (key == null) return const [];
    return _hydraulicStockPickLines
        .where((l) => _oilFamilyKey(l) == key)
        .toList()
      ..sort(
        (a, b) => a.viscosity.toLowerCase().compareTo(b.viscosity.toLowerCase()),
      );
  }

  int? _hydraulicStockGradeProductIdFor(OilChangeHydraulicCardSlot slot) {
    final pid = slot.stockProductId;
    if (pid == null || pid <= 0) return null;
    for (final l in _hydraulicStockLinesForFamily(slot)) {
      if (l.linkedProductId == pid) return pid;
    }
    return null;
  }

  void _applyHydraulicStockLineFor(OilChangeHydraulicCardSlot slot, OilPickLine line) {
    _markHydraulicFluidUserEdited(slot);
    slot.selectedFamilyKey = _oilFamilyKey(line);
    slot.stockProductId = line.linkedProductId;
    slot.type.text = line.parentName;
    slot.selectedGrade = line.viscosity.isEmpty ? null : line.viscosity;
    slot.pickSellPerLiter = line.sellPerLiterIqd;
    slot.catalogSellPerLiterFils = null;
    slot.selectedBrand = null;
    _agreedTotalManual = false;
  }

  void _onHydraulicFamilyDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    int? familyKey,
  ) {
    _markHydraulicFluidUserEdited(slot);
    setState(() {
      slot.selectedFamilyKey = familyKey;
      slot.stockProductId = null;
      slot.pickSellPerLiter = null;
      slot.selectedGrade = null;
      slot.availableLiters = 0;
      if (familyKey != null) {
        final lines = _hydraulicStockPickLines
            .where((l) => _oilFamilyKey(l) == familyKey)
            .toList();
        if (lines.length == 1) _applyHydraulicStockLineFor(slot, lines.first);
      }
    });
    if ((slot.stockProductId ?? 0) > 0) {
      unawaited(_refreshHydraulicAvailableLitersFor(slot));
      _recalculateOilTotal();
    }
  }

  void _onHydraulicStockGradeDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    int? linkedProductId,
  ) {
    _markHydraulicFluidUserEdited(slot);
    if (linkedProductId == null) {
      setState(() {
        slot.stockProductId = null;
        slot.pickSellPerLiter = null;
        slot.selectedGrade = null;
        slot.availableLiters = 0;
      });
      _recalculateOilTotal();
      return;
    }
    OilPickLine? line;
    for (final l in _hydraulicStockLinesForFamily(slot)) {
      if (l.linkedProductId == linkedProductId) {
        line = l;
        break;
      }
    }
    if (line == null) return;
    final picked = line;
    setState(() => _applyHydraulicStockLineFor(slot, picked));
    _syncHydraulicLitersFromStepperFor(slot);
    unawaited(_refreshHydraulicAvailableLitersFor(slot));
    _recalculateOilTotal();
  }

  Future<void> _openOilCatalogManage() async {
    await showOilChangeOilCatalogSheet(
      context,
      manageOnly: true,
    );
    if (!mounted) return;
    await _loadOilProductCatalog();
    setState(() {
      if (_oilFluidUserEdited) {
        _syncOilCatalogPricingFromSelection();
      } else {
        _reconcileOilCatalogSelection();
      }
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _onFilterEntryChanged(OilChangeFilterKind kind, int? entryId) {
    final slot = _filterSlotFor(kind);
    if (entryId == null) {
      setState(() => slot.clear());
      _recalculateOilTotal();
      return;
    }
    final entry = OilChangeFilterCatalogRepository.entryById(
      _filterProductCatalog,
      entryId,
    );
    if (entry == null || entry.kind != kind) return;
    setState(() {
      slot.applyEntry(entry);
      _expandedOptional.add(_OilFormOptionalSection.filters);
    });
    _recalculateOilTotal();
  }

  Future<void> _openFilterCatalogManage(OilChangeFilterKind kind) async {
    await showOilChangeFilterCatalogSheet(
      context,
      manageOnly: true,
      initialKind: kind,
    );
    if (!mounted) return;
    await _loadFilterProductCatalog();
    setState(() {
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  Widget _buildFilterKindRow({
    required BuildContext context,
    required ColorScheme cs,
    required bool busy,
    required OilChangeFilterKind kind,
  }) {
    final slot = _filterSlotFor(kind);
    final entries = OilChangeFilterCatalogRepository.entriesForKind(
      _filterProductCatalog,
      kind,
    );
    final priceLabel = slot.priceFils > 0
        ? _formatFilsLabel(slot.priceFils)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: slot.catalogEntryId != null &&
                        entries.any((e) => e.id == slot.catalogEntryId)
                    ? slot.catalogEntryId
                    : null,
                decoration: InputDecoration(
                  labelText: kind.label,
                  border: const OutlineInputBorder(),
                  hintText: 'اختر ${kind.label.replaceFirst('فلتر ', '')}',
                  isDense: true,
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('بدون'),
                  ),
                  ...entries.map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        oilFilterCatalogEntryLabel(e),
                        textAlign: TextAlign.start,
                        textDirection: e.name.trim().isEmpty
                            ? TextDirection.ltr
                            : null,
                      ),
                    ),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (id) => _onFilterEntryChanged(kind, id),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              onPressed: busy
                  ? null
                  : () => unawaited(_openFilterCatalogManage(kind)),
              tooltip: 'إدارة أسعار ${kind.label}',
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (priceLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            'السعر: $priceLabel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
      ],
    );
  }

  List<OilChangeHydraulicCatalogEntry> _hydraulicGradeDropdownEntriesFor(
    OilChangeHydraulicCardSlot slot,
  ) {
    final brand = slot.selectedBrand;
    if (brand == null || brand.isEmpty) return const [];
    return OilChangeHydraulicCatalogRepository.entriesForBrand(
      _hydraulicProductCatalog,
      brand,
    );
  }

  String? _hydraulicBrandDropdownValueFor(OilChangeHydraulicCardSlot slot) {
    final brand = slot.selectedBrand ?? slot.type.text.trim();
    if (brand.isEmpty) return null;
    for (final b in _hydraulicBrandDropdownItems) {
      if (b.toLowerCase() == brand.toLowerCase()) return b;
    }
    return null;
  }

  String? _hydraulicGradeDropdownValueFor(OilChangeHydraulicCardSlot slot) {
    final grade = slot.selectedGrade;
    if (grade == null || grade.isEmpty) return null;
    for (final e in _hydraulicGradeDropdownEntriesFor(slot)) {
      if (e.grade.toLowerCase() == grade.toLowerCase()) return e.grade;
    }
    return null;
  }

  void _applyHydraulicCatalogEntryFor(
    OilChangeHydraulicCardSlot slot,
    OilChangeHydraulicCatalogEntry entry,
  ) {
    _markHydraulicFluidUserEdited(slot);
    slot.selectedBrand = entry.brandName;
    slot.type.text = entry.brandName;
    slot.selectedGrade = entry.grade;
    slot.catalogSellPerLiterFils = entry.sellPerLiterFils;
    slot.stockProductId = null;
    slot.pickSellPerLiter = null;
    slot.litersStock.clear();
    slot.selectedFamilyKey = null;
    _agreedTotalManual = false;
  }

  void _onHydraulicBrandDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    String? brand,
  ) {
    _markHydraulicFluidUserEdited(slot);
    setState(() {
      slot.selectedBrand = brand;
      slot.type.text = brand ?? '';
      if (brand == null) {
        slot.selectedGrade = null;
        slot.catalogSellPerLiterFils = null;
        return;
      }
      final entries = OilChangeHydraulicCatalogRepository.entriesForBrand(
        _hydraulicProductCatalog,
        brand,
      );
      final currentGrade = slot.selectedGrade;
      OilChangeHydraulicCatalogEntry? keep;
      if (currentGrade != null && currentGrade.isNotEmpty) {
        keep = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
          _hydraulicProductCatalog,
          brandName: brand,
          grade: currentGrade,
        );
      }
      if (keep != null) {
        _applyHydraulicCatalogEntryFor(slot, keep);
      } else if (entries.length == 1) {
        _applyHydraulicCatalogEntryFor(slot, entries.first);
      } else {
        slot.selectedGrade = null;
        slot.catalogSellPerLiterFils = null;
        slot.stockProductId = null;
        slot.pickSellPerLiter = null;
      }
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _onHydraulicGradeDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    String? grade,
  ) {
    _markHydraulicFluidUserEdited(slot);
    if (grade == null || slot.selectedBrand == null) return;
    final entry = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
      _hydraulicProductCatalog,
      brandName: slot.selectedBrand!,
      grade: grade,
    );
    if (entry == null) return;
    setState(() => _applyHydraulicCatalogEntryFor(slot, entry));
    _recalculateOilTotal();
  }

  Future<void> _openHydraulicCatalogManageFor(OilChangeHydraulicCardSlot slot) async {
    final seedBrand = _hydraulicBrandDropdownValueFor(slot) ??
        (slot.type.text.trim().isEmpty ? null : slot.type.text.trim());
    await showOilChangeHydraulicCatalogSheet(
      context,
      manageOnly: true,
      initialBrandName: seedBrand,
    );
    if (!mounted) return;
    await _loadHydraulicProductCatalog();
    setState(() {
      _reconcileHydraulicCatalogSelectionFor(slot);
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  bool _showCatalogHydraulicFieldsFor(OilChangeHydraulicCardSlot slot) =>
      widget.oilChangeMode && !_usesWarehouseHydraulicPickerFor(slot);

  bool _showHydraulicVolumeStepperFor(OilChangeHydraulicCardSlot slot) {
    if (!widget.oilChangeMode) return false;
    if (slot.customerProvided) return true;
    if (_usesCatalogHydraulicPricingFor(slot)) return true;
    if (_usesWarehouseHydraulicPickerFor(slot)) {
      return (slot.stockProductId ?? 0) > 0;
    }
    return false;
  }

  Widget _buildOilChangeContextBanner(ColorScheme cs) {
    if (!widget.isOilNewCard) return const SizedBox.shrink();
    final fromLog = widget.prefillFromOrder != null;
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 14),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fromLog ? Icons.content_copy_rounded : Icons.add_card_rounded,
            color: AppColors.accentGold,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fromLog ? 'من السجل → زيارة جديدة' : 'بطاقة غيار زيت جديدة',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: OilChangeFormTheme.emphasisText(context),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 4),
                Text(
                  fromLog
                      ? 'البيانات من آخر زيارة في السجل. «حفظ وبيع» يُنشئ بطاقة جديدة — السجل القديم لا يُعدَّل.'
                      : 'اللوحة أو العميل يجلبان آخر زيارة للتعبئة. «حفظ وبيع» يُنشئ بطاقة وفاتورة جديدة.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: OilChangeFormTheme.secondaryText(context),
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsivePair(
    BuildContext context, {
    required Widget first,
    required Widget second,
    double gap = 12,
    bool sideBySideOnPhone = false,
  }) {
    final layout = context.screenLayout;
    if (layout.isPhoneVariant && !sideBySideOnPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          SizedBox(height: gap),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        SizedBox(width: gap),
        Expanded(child: second),
      ],
    );
  }

  Widget _compactSideBySide({
    required Widget start,
    required Widget end,
    int startFlex = 1,
    int endFlex = 1,
    double gap = 8,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: startFlex, child: start),
        SizedBox(width: gap),
        Expanded(flex: endFlex, child: end),
      ],
    );
  }

  Future<void> _openOilProductBarcodeCapture() async {
    final raw = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'باركود صنف',
      preferCompactHandsetOverlay: true,
    );
    if (!mounted) return;
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return;
    await _handleOilProductBarcode(t);
  }

  Future<void> _openOilProductPicker() async {
    if (_oilBarcodeBusy || !mounted) return;
    setState(() => _isProductPickerOpen = true);
    try {
      final picked = await ProductPickerDialog.show(context);
      if (!mounted || picked == null) return;
      final msg = OilChangeProductScan.addFromProductMap(
        lines: _oilProductLines,
        product: picked,
      );
      setState(() {
        _agreedTotalManual = false;
        _expandedOptional.add(_OilFormOptionalSection.products);
      });
      _recalculateOilTotal();
      if (msg != null && msg.isNotEmpty) {
        _showOilProductSnack(msg, success: true);
      }
    } finally {
      if (mounted) setState(() => _isProductPickerOpen = false);
    }
  }

  String _durationSummaryLabel() {
    final t = _etaHours * 60 + _etaMinutes;
    if (t <= 0) return 'لم تُحدَّد — اضغط لاختيار الساعات والدقائق';
    if (_etaHours > 0 && _etaMinutes > 0) {
      return '$_etaHours س $_etaMinutes د — اضغط للتعديل';
    }
    if (_etaHours > 0) return '$_etaHours ساعة — اضغط للتعديل';
    return '$_etaMinutes دقيقة — اضغط للتعديل';
  }

  Widget _buildScheduleBanner(ColorScheme cs) {
    final mins = _etaTotalMinutes();
    DateTime? targetLocal;
    if (mins != null) {
      final base = (_workStartedAtUtc ?? _openedAtUtc ?? DateTime.now().toUtc())
          .toLocal();
      targetLocal = base.add(Duration(minutes: mins));
    } else if (_promisedDeliveryStoredIso != null) {
      targetLocal =
          DateTime.tryParse(_promisedDeliveryStoredIso!)?.toLocal();
    }

    if (targetLocal == null && mins == null) return const SizedBox.shrink();

    final formatter = DateFormat('EEEE، d MMMM yyyy • HH:mm', 'ar');
    final overdue = targetLocal != null &&
        DateTime.now().isAfter(targetLocal) &&
        _status != 'delivered' &&
        _status != 'cancelled';

    final subtitle = _workStartedAtUtc == null && mins != null
        ? 'بعد «بدء العمل» من قائمة التذاكر يُثبَّت الموعد بدقة من وقت البدء.'
        : (mins != null
            ? 'مدة العمل المتوقعة: $mins دقيقة'
            : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: overdue
            ? cs.errorContainer.withValues(alpha: 0.35)
            : cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue
              ? cs.error.withValues(alpha: 0.35)
              : cs.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                color: overdue ? cs.error : cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overdue
                      ? 'تجاوز موعد التسليم المتوقع'
                      : 'موعد التسليم المتوقع (للزبون)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: overdue ? cs.error : cs.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
          if (targetLocal != null) ...[
            const SizedBox(height: 6),
            Text(
              formatter.format(targetLocal),
              style: TextStyle(
                color: overdue ? cs.onErrorContainer : cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
          ],
          if (subtitle != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }

  void _toggleOptionalSection(_OilFormOptionalSection section) {
    setState(() {
      if (_expandedOptional.contains(section)) {
        _expandedOptional.remove(section);
      } else {
        _expandedOptional.add(section);
      }
    });
  }

  String? _hydraulicCollapsedHint(OilChangeHydraulicCardSlot slot) {
    if (!_hydraulicSlotHasData(slot)) return null;
    final brand = slot.selectedBrand ?? slot.type.text.trim();
    final grade = slot.selectedGrade ?? '';
    if (brand.isNotEmpty && grade.isNotEmpty) return '$brand · $grade';
    if (brand.isNotEmpty) return brand;
    if (grade.isNotEmpty) return grade;
    final liters = slot.litersForPricing();
    if (liters > 1e-9) return '${liters.toStringAsFixed(1)} لتر';
    if (slot.customerProvided) return 'من العميل';
    return 'مُحدَّد';
  }

  String _optionalSectionTitle(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.products => 'المنتجات',
      _OilFormOptionalSection.filters => 'الفلاتر',
      _OilFormOptionalSection.hydraulicGear => 'هيدروليك الكير',
      _OilFormOptionalSection.hydraulicPower => 'هيدروليك الباور',
      _OilFormOptionalSection.services => 'الخدمات الإضافية',
    };
  }

  IconData _optionalSectionIcon(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.products => Icons.inventory_2_outlined,
      _OilFormOptionalSection.filters => Icons.filter_alt_outlined,
      _OilFormOptionalSection.hydraulicGear => Icons.water_drop_outlined,
      _OilFormOptionalSection.hydraulicPower => Icons.water_drop_outlined,
      _OilFormOptionalSection.services => Icons.checklist_rounded,
    };
  }

  String? _optionalSectionCollapsedHint(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.products => _oilProductLines.isEmpty
          ? null
          : '${_oilProductLines.length} صنف',
      _OilFormOptionalSection.filters => () {
          final n = [
            if (_engineFilter.hasSelection) _engineFilter.name,
            if (_airFilter.hasSelection) _airFilter.name,
            if (_gearFilter.hasSelection) _gearFilter.name,
            if (_coolingFilter.hasSelection) _coolingFilter.name,
          ].whereType<String>().length;
          if (n == 0) return null;
          return '$n فلتر محدد';
        }(),
      _OilFormOptionalSection.hydraulicGear =>
          _hydraulicCollapsedHint(_gearHydraulic),
      _OilFormOptionalSection.hydraulicPower =>
          _hydraulicCollapsedHint(_powerHydraulic),
      _OilFormOptionalSection.services => _selectedOilServiceIds.isEmpty
          ? null
          : '${_selectedOilServiceIds.length} خدمة',
    };
  }

  Widget _buildOptionalSectionChip(
    ColorScheme cs,
    bool busy,
    _OilFormOptionalSection section,
  ) {
    return Tooltip(
      message: _optionalSectionCollapsedHint(section) ??
          _optionalSectionTitle(section),
      child: FilterChip(
        label: Text(
          _optionalSectionTitle(section),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        avatar: Icon(
          _optionalSectionIcon(section),
          size: 16,
          color: _expandedOptional.contains(section)
              ? cs.onPrimaryContainer
              : cs.onSurfaceVariant,
        ),
        selected: _expandedOptional.contains(section),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
        onSelected:
            busy ? null : (_) => _toggleOptionalSection(section),
      ),
    );
  }

  Widget _buildOilOptionalQuickBar(ColorScheme cs, bool busy) {
    const sections = _OilFormOptionalSection.values;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: OilChangeRoyalCard.gold.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إضافات عند الحاجة',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 2),
          Text(
            'اضغط الزر لفتح القسم — اضغط مرة أخرى لإخفائه',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _buildOptionalSectionChip(cs, busy, sections[i]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 3; i < sections.length; i++) ...[
                if (i > 3) const SizedBox(width: 6),
                Expanded(
                  child: _buildOptionalSectionChip(cs, busy, sections[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOilOptionalSection(
    BuildContext context, {
    required _OilFormOptionalSection section,
    required List<Widget> children,
  }) {
    final expanded = _expandedOptional.contains(section);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topCenter,
      child: expanded
          ? OilChangeRoyalCard.section(
              context: context,
              title: _optionalSectionTitle(section),
              icon: _optionalSectionIcon(section),
              children: children,
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _buildOilCheckoutSectionCard(BuildContext context, bool busy) {
    return OilChangeRoyalCard.section(
      context: context,
      title: 'السعر والدفع',
      icon: Icons.payments_outlined,
      children: _oilCheckoutFields(context, busy, compact: true),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    if (widget.oilChangeMode) {
      return OilChangeRoyalCard.section(
        context: context,
        title: title,
        icon: icon,
        children: children,
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOilSourceSegment(ColorScheme cs, bool busy) {
    if (!widget.oilChangeMode || !_stockFromWarehouseEnabled) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'مصدر الزيت',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            fontSize: 13,
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('زيت المحل'),
              icon: Icon(Icons.inventory_2_outlined, size: 18),
            ),
            ButtonSegment(
              value: true,
              label: Text('زيت العميل'),
              icon: Icon(Icons.person_outline, size: 18),
            ),
          ],
          selected: {_oilCustomerProvided},
          onSelectionChanged: busy
              ? null
              : (s) {
                  _markOilFluidUserEdited();
                  setState(() {
                    _oilCustomerProvided = s.first;
                    if (_oilCustomerProvided) {
                      _clearOilStockSelection();
                      _selectedOilFamilyKey = null;
                      _catalogSellPerLiterFils = null;
                      _oilLitersStock.clear();
                    } else {
                      _catalogSellPerLiterFils = null;
                      _selectedOilBrand = null;
                    }
                    _agreedTotalManual = false;
                  });
                  _recalculateOilTotal();
                },
        ),
        if (_oilCustomerProvided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'لن يُخصم مخزون — العميل أحضر الزيت بنفسه.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
          ),
      ],
    );
  }

  Widget _buildWarehouseOilPickRow(ColorScheme cs, bool busy) {
    if (!_usesWarehouseOilPicker) return const SizedBox.shrink();
    final families = _oilFamilyDropdownOptions;
    final visLines = _oilStockLinesForSelectedFamily;
    final showViscosityDropdown = visLines.any((l) => l.viscosity.isNotEmpty);
    final familyKeyValid = _selectedOilFamilyKey != null &&
        families.any((f) => f.key == _selectedOilFamilyKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (_oilStockMetaLoading || _oilStockPickLinesLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (families.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'لا توجد عائلات زيت في المخزون. أضف «زيت — عائلة» من المخزون ثم حدّث.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy ? null : () => unawaited(_loadOilStockMeta()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث قائمة المخزون'),
                ),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: familyKeyValid ? _selectedOilFamilyKey : null,
                  decoration: const InputDecoration(
                    labelText: 'زيت من المخزون',
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'اختر العائلة',
                  ),
                  isExpanded: true,
                  items: families
                      .map(
                        (f) => DropdownMenuItem(
                          value: f.key,
                          child: Text(
                            f.label,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : _onOilFamilyDropdownChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: showViscosityDropdown
                    ? DropdownButtonFormField<int>(
                        value: _oilStockViscosityProductId,
                        decoration: InputDecoration(
                          labelText: 'اللزوجة',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: familyKeyValid
                              ? 'اختر اللزوجة'
                              : 'اختر العائلة أولاً',
                        ),
                        isExpanded: true,
                        items: visLines
                            .where((l) => l.viscosity.isNotEmpty)
                            .map(
                              (l) => DropdownMenuItem(
                                value: l.linkedProductId,
                                child: Text(
                                  l.viscosity,
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: busy || !familyKeyValid
                            ? null
                            : _onOilStockViscosityChanged,
                      )
                    : InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'اللزوجة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text(
                          _selectedViscosity ??
                              (familyKeyValid && visLines.isNotEmpty
                                  ? '—'
                                  : '—'),
                          textAlign: TextAlign.start,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
            ],
          ),
        if ((_oilStockProductId ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            'متوفر في المخزون: ${_oilAvailableLiters.toStringAsFixed(1)} لتر',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
        if (_warehouses.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _oilWarehouseId,
            decoration: const InputDecoration(
              labelText: 'المستودع',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            isExpanded: true,
            items: _warehouses
                .map(
                  (w) => DropdownMenuItem<int>(
                    value: (w['id'] as num).toInt(),
                    child: Text(w['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    setState(() => _oilWarehouseId = v);
                    unawaited(_refreshAvailableLiters());
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildHydraulicSourceSegmentFor(
    ColorScheme cs,
    bool busy,
    OilChangeHydraulicCardSlot slot, {
    required String sourceTitle,
    required String shopLabel,
    required String customerLabel,
    required String customerHint,
  }) {
    if (!widget.oilChangeMode || !_hydraulicStockFromWarehouseEnabled) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          sourceTitle,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            fontSize: 13,
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(shopLabel),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
            ),
            ButtonSegment(
              value: true,
              label: Text(customerLabel),
              icon: const Icon(Icons.person_outline, size: 18),
            ),
          ],
          selected: {slot.customerProvided},
          onSelectionChanged: busy
              ? null
              : (s) {
                  setState(() {
                    slot.customerProvided = s.first;
                    if (slot.customerProvided) {
                      slot.clearStockSelection();
                      slot.litersStock.clear();
                    } else {
                      slot.clearCatalogSelection();
                    }
                    _agreedTotalManual = false;
                  });
                  _recalculateOilTotal();
                },
        ),
        if (slot.customerProvided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              customerHint,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
          ),
      ],
    );
  }

  Widget _buildWarehouseHydraulicPickRowFor(
    ColorScheme cs,
    bool busy,
    OilChangeHydraulicCardSlot slot, {
    required String stockLabel,
    required String warehouseLabel,
  }) {
    if (!_usesWarehouseHydraulicPickerFor(slot)) return const SizedBox.shrink();
    final families = _hydraulicFamilyDropdownOptions;
    final gradeLines = _hydraulicStockLinesForFamily(slot);
    final showGradeDropdown = gradeLines.any((l) => l.viscosity.isNotEmpty);
    final familyKeyValid = slot.selectedFamilyKey != null &&
        families.any((f) => f.key == slot.selectedFamilyKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (_hydraulicStockPickLinesLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (families.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'لا توجد عائلات هيدروليك في المخزون. أضف «هيدروليك — عائلة» من المخزون ثم حدّث.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed:
                      busy ? null : () => unawaited(_loadHydraulicStockMeta()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث قائمة المخزون'),
                ),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: familyKeyValid ? slot.selectedFamilyKey : null,
                  decoration: InputDecoration(
                    labelText: stockLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: 'اختر العائلة',
                  ),
                  isExpanded: true,
                  items: families
                      .map(
                        (f) => DropdownMenuItem(
                          value: f.key,
                          child: Text(
                            f.label,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => _onHydraulicFamilyDropdownChangedFor(slot, v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: showGradeDropdown
                    ? DropdownButtonFormField<int>(
                        value: _hydraulicStockGradeProductIdFor(slot),
                        decoration: InputDecoration(
                          labelText: 'الدرجة',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: familyKeyValid
                              ? 'اختر الدرجة'
                              : 'اختر العائلة أولاً',
                        ),
                        isExpanded: true,
                        items: gradeLines
                            .where((l) => l.viscosity.isNotEmpty)
                            .map(
                              (l) => DropdownMenuItem(
                                value: l.linkedProductId,
                                child: Text(
                                  l.viscosity,
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: busy || !familyKeyValid
                            ? null
                            : (v) =>
                                _onHydraulicStockGradeDropdownChangedFor(slot, v),
                      )
                    : InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'الدرجة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text(
                          slot.selectedGrade ??
                              (familyKeyValid && gradeLines.isNotEmpty
                                  ? '—'
                                  : '—'),
                          textAlign: TextAlign.start,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
            ],
          ),
        if ((slot.stockProductId ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            'متوفر في المخزون: ${slot.availableLiters.toStringAsFixed(1)} لتر',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
        if (_warehouses.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: slot.warehouseId,
            decoration: InputDecoration(
              labelText: warehouseLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            isExpanded: true,
            items: _warehouses
                .map(
                  (w) => DropdownMenuItem<int>(
                    value: (w['id'] as num).toInt(),
                    child: Text(w['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    _markHydraulicFluidUserEdited(slot);
                    setState(() => slot.warehouseId = v);
                    unawaited(_refreshHydraulicAvailableLitersFor(slot));
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildHydraulicFluidCard(
    BuildContext context, {
    required String title,
    required OilChangeHydraulicCardSlot slot,
    required bool busy,
    required ColorScheme cs,
    required String catalogNameLabel,
    required String volumeLabel,
    required String sourceTitle,
    required String shopLabel,
    required String customerLabel,
    required String customerHint,
    required String stockLabel,
    required String warehouseLabel,
    bool wrapInSectionCard = true,
  }) {
    final fields = <Widget>[
      if (!wrapInSectionCard)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
        ),
        if (_showCatalogHydraulicFieldsFor(slot))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _hydraulicBrandDropdownValueFor(slot),
                  decoration: InputDecoration(
                    labelText: catalogNameLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: _hydraulicProductCatalogLoading
                        ? 'جاري التحميل…'
                        : (_hydraulicBrandDropdownItems.isEmpty
                            ? 'أضف من +'
                            : 'اختر الاسم'),
                  ),
                  isExpanded: true,
                  items: _hydraulicBrandDropdownItems
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b, textAlign: TextAlign.start),
                        ),
                      )
                      .toList(),
                  onChanged: busy ||
                          (_hydraulicProductCatalogLoading &&
                              _hydraulicBrandDropdownItems.isEmpty)
                      ? null
                      : (b) => _onHydraulicBrandDropdownChangedFor(slot, b),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _hydraulicGradeDropdownValueFor(slot),
                  decoration: InputDecoration(
                    labelText: 'الدرجة',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: _hydraulicBrandDropdownValueFor(slot) == null
                        ? 'اختر الاسم أولاً'
                        : (_hydraulicGradeDropdownEntriesFor(slot).isEmpty
                            ? 'لا درجات'
                            : 'اختر الدرجة'),
                  ),
                  isExpanded: true,
                  items: _hydraulicGradeDropdownEntriesFor(slot)
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.grade,
                          child: Text(e.grade, textAlign: TextAlign.start),
                        ),
                      )
                      .toList(),
                  onChanged: busy ||
                          _hydraulicBrandDropdownValueFor(slot) == null ||
                          _hydraulicGradeDropdownEntriesFor(slot).isEmpty
                      ? null
                      : (g) => _onHydraulicGradeDropdownChangedFor(slot, g),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                onPressed: busy
                    ? null
                    : () => unawaited(_openHydraulicCatalogManageFor(slot)),
                tooltip: 'إضافة هيدروليك / درجة للكتالوج',
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        _buildHydraulicSourceSegmentFor(
          cs,
          busy,
          slot,
          sourceTitle: sourceTitle,
          shopLabel: shopLabel,
          customerLabel: customerLabel,
          customerHint: customerHint,
        ),
        _buildWarehouseHydraulicPickRowFor(
          cs,
          busy,
          slot,
          stockLabel: stockLabel,
          warehouseLabel: warehouseLabel,
        ),
        if (_showHydraulicVolumeStepperFor(slot)) ...[
          const SizedBox(height: 12),
          MilliliterQuantityStepper(
            controller: slot.sizeAmount,
            enabled: !busy,
            labelText: volumeLabel,
            onChanged: () {
              if (_usesWarehouseHydraulicPickerFor(slot)) {
                _syncHydraulicLitersFromStepperFor(slot);
              }
              setState(() {
                _agreedTotalManual = false;
                _recalculateOilTotal();
              });
            },
          ),
        ],
    ];
    if (wrapInSectionCard) {
      return _buildSectionCard(
        context,
        title: title,
        icon: Icons.water_drop_outlined,
        children: fields,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: fields,
    );
  }

  Widget _buildOilServiceCheckbox(
    OilChangeServiceItem s,
    ColorScheme cs,
    bool busy,
  ) {
    final checked = _selectedOilServiceIds.contains(s.id);
    final priceLbl = s.priceFils > 0
        ? IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(s.priceFils))
        : '—';
    return InkWell(
      onTap: busy
          ? null
          : () {
              setState(() {
                if (checked) {
                  _selectedOilServiceIds.remove(s.id);
                } else {
                  _selectedOilServiceIds.add(s.id);
                }
                _agreedTotalManual = false;
                _recalculateOilTotal();
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color: checked ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: checked ? cs.primary : cs.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${s.name} · $priceLbl',
                style: TextStyle(
                  fontWeight: checked ? FontWeight.w800 : FontWeight.w500,
                  color: checked ? cs.primary : cs.onSurface,
                  fontSize: 12,
                ),
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilLiterPriceHint(ColorScheme cs) {
    final liters = _oilLitersForPricing();
    if (_usesCatalogOilPricing) {
      final perLiter = _catalogSellPerLiterFils!;
      final material = _oilMaterialSellFilsEst();
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Text(
          liters > 1e-9
              ? 'سعر اللتر: ${_formatFilsLabel(perLiter)} × ${formatOilLitersDisplay(liters)} لتر = ${_formatFilsLabel(material)}'
              : 'سعر اللتر: ${_formatFilsLabel(perLiter)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
          textAlign: TextAlign.start,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        'أضف سعر اللتر من زر + بجانب اسم الزيت (ماركة ولزوجة).',
        style: TextStyle(
          fontSize: 12,
          color: cs.error,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.start,
      ),
    );
  }

  Widget _buildCheckboxItem(String label, ColorScheme cs) {
    final checked = _selectedServices.contains(label);
    return InkWell(
      onTap: () {
        setState(() {
          if (checked) {
            _selectedServices.remove(label);
          } else {
            _selectedServices.add(label);
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color: checked ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: checked ? cs.primary : cs.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: checked ? FontWeight.w800 : FontWeight.w500,
                color: checked ? cs.primary : cs.onSurface,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilFormScrollStack(
    BuildContext context, {
    required ColorScheme cs,
    required ScreenLayout layout,
    required double pagePad,
    required bool busy,
    double maxWidth = 720,
  }) {
    return Stack(
      children: [
        AdaptiveFormContainer(
          maxWidth: maxWidth,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                pagePad,
                14,
                pagePad,
                24,
              ),
              children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    (_errorText ?? 'حدث خطأ أثناء الحفظ. حاول مرة أخرى.'),
                    style: TextStyle(color: cs.error),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (!widget.oilChangeMode) _buildScheduleBanner(cs),
              if (widget.isOilNewCard) _buildOilChangeContextBanner(cs),

              // 1. بيانات العميل
              _buildSectionCard(
                context,
                title: 'بيانات العميل',
                icon: Icons.person_outline_rounded,
                children: [
                  if (widget.oilChangeMode)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: OilChangeCustomerNameField(
                            controller: _customerName,
                            focusNode: _customerFocus,
                            enabled: !busy,
                            customerLinked: _customerId != null,
                            onSelected: (c) =>
                                unawaited(_applyCustomerSelection(c)),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'اسم العميل مطلوب'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _customerPhone,
                            decoration: const InputDecoration(
                              labelText: 'رقم الهاتف',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.phone_rounded, size: 20),
                            ),
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9٠-٩۰-۹+\s-]'),
                              ),
                            ],
                            onChanged: (v) {
                              final western =
                                  OilChangeLookupNormalize.toWesternDigits(v);
                              if (western == v) return;
                              final cursor = _customerPhone.selection.baseOffset;
                              _customerPhone.value = TextEditingValue(
                                text: western,
                                selection: TextSelection.collapsed(
                                  offset: cursor.clamp(0, western.length),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'عميل جديد من النموذج الكامل',
                          onPressed: busy ? null : _openNewCustomer,
                          icon: const Icon(Icons.person_add_alt_rounded),
                        ),
                      ],
                    ),
                  if (widget.oilChangeMode)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 8),
                      child: Text(
                        'اكتب الاسم ورقم الواتساب — يُحفظ العميل تلقائياً إن لم يكن مسجّلاً، '
                        'أو ابحث واختر من القائمة، أو استخدم زر الإضافة للتفاصيل الكاملة.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                  if (!widget.oilChangeMode) ...[
                    _responsivePair(
                      context,
                      first: OilChangeCustomerNameField(
                        controller: _customerName,
                        focusNode: _customerFocus,
                        enabled: !busy,
                        customerLinked: _customerId != null,
                        hintText: 'ابدأ الكتابة للبحث في العملاء',
                        onSelected: (c) =>
                            unawaited(_applyCustomerSelection(c)),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'اسم العميل مطلوب'
                            : null,
                      ),
                      second: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IconButton.filledTonal(
                          tooltip: 'عميل جديد',
                          onPressed: busy ? null : _openNewCustomer,
                          icon: const Icon(Icons.person_add_alt_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customerPhone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_rounded),
                        hintText:
                            'يُملأ تلقائياً عند اختيار العميل أو يُدخل يدوياً',
                      ),
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
              if (widget.oilChangeMode)
                CustomerOpenDebtBanner(
                  openDebtFils: _customerOpenDebtFils,
                  customerId: _customerId,
                  customerName: _customerName.text.trim(),
                  loading: _customerOpenDebtLoading,
                ),

              // 2. بيانات السيارة
              _buildSectionCard(
                context,
                title: 'بيانات السيارة',
                icon: Icons.directions_car_outlined,
                children: [
                  if (widget.oilChangeMode) ...[
                    _compactSideBySide(
                      start: TextFormField(
                        controller: _deviceName,
                        decoration: const InputDecoration(
                          labelText: 'اسم السيارة',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'تويوتا كورولا',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'اسم السيارة مطلوب'
                            : null,
                        textAlign: TextAlign.start,
                      ),
                      end: TextFormField(
                        controller: _deviceSerial,
                        decoration: InputDecoration(
                          labelText: 'رقم اللوحة',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: 'بغداد - 12345',
                          suffixIcon: !widget.isEdit
                              ? IconButton(
                                  tooltip: 'جلب بيانات آخر زيارة',
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(
                                            _syncVehicleFromPlate(
                                              showFeedback: true,
                                              overwriteExisting: true,
                                              force: true,
                                            ),
                                          ),
                                  icon: const Icon(Icons.sync_rounded),
                                )
                              : null,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'رقم اللوحة مطلوب'
                            : null,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).unfocus(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _compactSideBySide(
                      start: TextFormField(
                        controller: _carModel,
                        decoration: const InputDecoration(
                          labelText: 'موديل السيارة',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '2022',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: _carModelDigitFormatters,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        onEditingComplete: _normalizeCarModelDisplay,
                      ),
                      end: TextFormField(
                        controller: _engineSize,
                        decoration: const InputDecoration(
                          labelText: 'حجم المحرك',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '1.8L',
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                    if (!widget.isEdit)
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.only(start: 4, top: 6),
                        child: Text(
                          'رقم اللوحة مطلوب. عند إدخاله تُحمَّل بيانات آخر زيارة تلقائياً إن وُجدت.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                  ] else ...[
                    TextFormField(
                      controller: _deviceName,
                      decoration: const InputDecoration(
                        labelText: 'اسم السيارة',
                        border: OutlineInputBorder(),
                        hintText: 'مثال: تويوتا كورولا',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'اسم السيارة مطلوب'
                          : null,
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      context,
                      first: TextFormField(
                        controller: _carModel,
                        decoration: const InputDecoration(
                          labelText: 'موديل السيارة',
                          border: OutlineInputBorder(),
                          hintText: 'مثال: 2022',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: _carModelDigitFormatters,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        onEditingComplete: _normalizeCarModelDisplay,
                      ),
                      second: TextFormField(
                        controller: _engineSize,
                        decoration: const InputDecoration(
                          labelText: 'حجم المحرك',
                          border: OutlineInputBorder(),
                          hintText: 'مثال: 1.8L',
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _deviceSerial,
                      decoration: const InputDecoration(
                        labelText: 'رقم اللوحة',
                        border: OutlineInputBorder(),
                        hintText: 'مثال: بغداد - 12345',
                      ),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.only(start: 4, top: 6),
                      child: Text(
                        'إن تُرِك رقم اللوحة فارغاً سيتم توليد رقم مرجعي داخلي تلقائياً.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ],
                ],
              ),

              // 3. تغيير الزيت
              _buildSectionCard(
                context,
                title: widget.oilChangeMode
                    ? 'تغيير الزيت'
                    : 'تغيير الزيت والفلتر',
                icon: Icons.opacity_rounded,
                children: [
                  _responsivePair(
                    context,
                    sideBySideOnPhone: true,
                    gap: 8,
                    first: TextFormField(
                      controller: _odometerCurrent,
                      decoration: const InputDecoration(
                        labelText: 'القراءة الحالية (كم)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: _odometerInputFormatters,
                      validator: widget.oilChangeMode
                          ? (v) => _odometerDigits(v ?? '').isEmpty
                              ? 'القراءة الحالية مطلوبة'
                              : null
                          : null,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                    second: TextFormField(
                      controller: _odometerNext,
                      decoration: const InputDecoration(
                        labelText: 'القراءة اللاحقة (كم)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: _odometerInputFormatters,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_showCatalogOilFields)
                    Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _oilBrandDropdownValue,
                          decoration: InputDecoration(
                            labelText: 'اسم الزيت',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: _oilProductCatalogLoading
                                ? 'جاري التحميل…'
                                : (_oilBrandDropdownItems.isEmpty
                                    ? 'أضف زيتاً من +'
                                    : 'اختر الزيت'),
                          ),
                          isExpanded: true,
                          items: _oilBrandDropdownItems
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(
                                    b,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy ||
                                  (_oilProductCatalogLoading &&
                                      _oilBrandDropdownItems.isEmpty)
                              ? null
                              : _onOilBrandDropdownChanged,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _oilViscosityDropdownValue,
                          decoration: InputDecoration(
                            labelText: 'اللزوجة',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: _oilBrandDropdownValue == null
                                ? 'اختر الاسم أولاً'
                                : (_oilViscosityDropdownEntries.isEmpty
                                    ? 'لا قياسات'
                                    : 'اختر اللزوجة'),
                          ),
                          isExpanded: true,
                          items: _oilViscosityDropdownEntries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.viscosity,
                                  child: Text(
                                    e.viscosity,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy ||
                                  _oilBrandDropdownValue == null ||
                                  _oilViscosityDropdownEntries.isEmpty
                              ? null
                              : _onOilViscosityDropdownChanged,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        onPressed: busy
                            ? null
                            : () => unawaited(_openOilCatalogManage()),
                        tooltip: 'إضافة زيت / لزوجة للكتالوج',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  _buildOilSourceSegment(cs, busy),
                  _buildWarehouseOilPickRow(cs, busy),
                  if (_showOilVolumeStepper) ...[
                    const SizedBox(height: 12),
                    MilliliterQuantityStepper(
                      controller: _oilSizeAmount,
                      enabled: !busy,
                      labelText: 'حجم الزيت المستعمل',
                      onChanged: () {
                        if (_usesWarehouseOilPicker || _usesShopOilFromStock) {
                          _syncStockLitersFromStepper();
                        }
                        setState(() {
                          _agreedTotalManual = false;
                          _recalculateOilTotal();
                        });
                      },
                    ),
                    if (_showCatalogOilFields &&
                        !_oilCustomerProvided &&
                        _oilBrandDropdownValue != null &&
                        _oilViscosityDropdownValue != null) ...[
                      const SizedBox(height: 8),
                      _buildOilLiterPriceHint(cs),
                    ],
                  ],
                  if (!widget.oilChangeMode) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedFilterType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الفلتر',
                        border: OutlineInputBorder(),
                      ),
                      items: _filterOptions
                          .map(
                            (o) => DropdownMenuItem(
                              value: o,
                              child: Text(o),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _selectedFilterType = v),
                    ),
                  ],
                ],
              ),

              if (widget.oilChangeMode) ...[
                _buildOilOptionalQuickBar(cs, busy),
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.products,
                  children: [
                    OilChangeProductsCard(
                      bare: true,
                      lines: _oilProductLines,
                      busy: busy || _oilBarcodeBusy,
                      onScanBarcode: () =>
                          unawaited(_openOilProductBarcodeCapture()),
                      onAddProduct: () => unawaited(_openOilProductPicker()),
                      onQuantityChanged: _onOilProductQuantityChanged,
                      onRemoveLine: _onOilProductLineRemoved,
                    ),
                  ],
                ),
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.filters,
                  children: [
                    if (_filterProductCatalogLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    for (var i = 0; i < OilChangeFilterKind.all.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildFilterKindRow(
                        context: context,
                        cs: cs,
                        busy: busy,
                        kind: OilChangeFilterKind.all[i],
                      ),
                    ],
                    if (_filterProductCatalog.isEmpty &&
                        !_filterProductCatalogLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'لا توجد فلاتر في الكتالوج. اضغط + بجانب كل فئة لإضافة اسم وسعر.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                  ],
                ),
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.hydraulicGear,
                  children: [
                    _buildHydraulicFluidCard(
                      context,
                      title: 'هيدروليك الكير',
                      slot: _gearHydraulic,
                      busy: busy,
                      cs: cs,
                      catalogNameLabel: 'اسم هيدروليك الكير',
                      volumeLabel: 'حجم هيدروليك الكير',
                      sourceTitle: 'مصدر هيدروليك الكير',
                      shopLabel: 'هيدروليك الكير (المحل)',
                      customerLabel: 'هيدروليك الكير (العميل)',
                      customerHint:
                          'لن يُخصم مخزون — العميل أحضر هيدروليك الكير.',
                      stockLabel: 'هيدروليك الكير من المخزون',
                      warehouseLabel: 'مستودع هيدروليك الكير',
                      wrapInSectionCard: false,
                    ),
                  ],
                ),
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.hydraulicPower,
                  children: [
                    _buildHydraulicFluidCard(
                      context,
                      title: 'هيدروليك الباور',
                      slot: _powerHydraulic,
                      busy: busy,
                      cs: cs,
                      catalogNameLabel: 'اسم هيدروليك الباور',
                      volumeLabel: 'حجم هيدروليك الباور',
                      sourceTitle: 'مصدر هيدروليك الباور',
                      shopLabel: 'هيدروليك الباور (المحل)',
                      customerLabel: 'هيدروليك الباور (العميل)',
                      customerHint:
                          'لن يُخصم مخزون — العميل أحضر هيدروليك الباور.',
                      stockLabel: 'هيدروليك الباور من المخزون',
                      warehouseLabel: 'مستودع هيدروليك الباور',
                      wrapInSectionCard: false,
                    ),
                  ],
                ),
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.services,
                  children: [
                    if (_basePriceFils > 0)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.opacity_rounded, color: cs.primary),
                        title: const Text('تبديل الزيت (السعر الأساسي)'),
                        trailing: Text(
                          _formatFilsLabel(_basePriceFils),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      )
                    else
                      Text(
                        'لم يُحدَّد سعر تبديل الزيت بعد — من «الخدمات وأسعارها» في القائمة الجانبية.',
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    const SizedBox(height: 8),
                    if (_oilCatalog.isEmpty)
                      Text(
                        'لا توجد خدمات إضافية. أضفها من «الخدمات وأسعارها».',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        textAlign: TextAlign.start,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _oilCatalog
                            .map((s) => _buildOilServiceCheckbox(s, cs, busy))
                            .toList(),
                      ),
                  ],
                ),
                if (!layout.isWideVariant) ...[
                  _buildOilTechnicianNotesSection(context, busy),
                  _buildOilCheckoutSectionCard(context, busy),
                ],
              ] else
                _buildSectionCard(
                  context,
                  title: 'الخدمات المطلوبة',
                  icon: Icons.checklist_rounded,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _serviceCheckboxes
                          .map((s) => _buildCheckboxItem(s, cs))
                          .toList(),
                    ),
                  ],
                ),

              if (!widget.oilChangeMode)
                _buildSectionCard(
                  context,
                  title: 'التفاصيل المالية والعملية',
                  icon: Icons.monetization_on_outlined,
                  children: [
                    Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: busy ? null : _openDurationWheel,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_filled_rounded, color: cs.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'المدة المتوقعة لإنجاز العمل',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _durationSummaryLabel(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('الخدمة الأساسية (الفنية)'),
                      subtitle: Text(
                        _serviceName?.trim().isNotEmpty == true
                            ? _serviceName!
                            : (_serviceId == null ? 'غير محددة (اختياري)' : 'محددة'),
                      ),
                      trailing: OutlinedButton.icon(
                        onPressed: busy ? null : _pickService,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('اختيار'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _estimated,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'سعر تقديري (الخدمة)',
                              border: OutlineInputBorder(),
                            ),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _agreed,
                            decoration: const InputDecoration(
                              labelText: 'السعر الإجمالي (د.ع)',
                              border: OutlineInputBorder(),
                              helperText: 'السعر النهائي المتفق عليه للعمل',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              final s = (v ?? '').trim().replaceAll(',', '');
                              if (s.isEmpty) return null;
                              final n = double.tryParse(s);
                              if (n == null || n < 0) return 'مبلغ غير صحيح';
                              return null;
                            },
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _advance,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المدفوع مسبقاً (العربون)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                        if (n == null || n < 0) return 'مبلغ غير صحيح';
                        return null;
                      },
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _technicianName,
                      decoration: const InputDecoration(
                        labelText: 'اسم الفني المسؤول',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.handyman_rounded),
                        hintText: 'مثال: أحمد علي',
                      ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _issue,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات وتفاصيل إضافية',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 5,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ),

              if (!widget.oilChangeMode) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: busy ? null : () => _submit(),
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                    _saving
                        ? 'جارٍ حفظ البطاقة…'
                        : (widget.isEdit
                            ? 'تعديل وحفظ البطاقة'
                            : (widget.oilChangeMode
                                ? 'حفظ بطاقة الغيار'
                                : 'إنشاء وحفظ بطاقة الصيانة')),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      if (_prefillBootstrapInProgress)
        Positioned.fill(
          child: ColoredBox(
            color: cs.surface.withValues(alpha: 0.72),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'جاري تجهيز البطاقة من السجل…',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
    );
  }
  String _oilAppBarTitle() {
    if (widget.isEdit) {
      if (_status == OilChangeOrderStatus.suspended) {
        return 'استكمال بطاقة معلّقة';
      }
      return 'تعديل بطاقة غيار زيت';
    }
    if (widget.prefillFromOrder != null) return 'زيارة غيار جديدة';
    return 'بطاقة غيار زيت جديدة';
  }

  /// لوحة جانبية ثابتة — للشاشات الواسعة فقط.
  Widget _buildOilCheckoutPanel(BuildContext context, bool busy) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: BorderDirectional(
          end: BorderSide(
            color: OilChangeRoyalCard.gold.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  color: OilChangeRoyalCard.gold,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'الفني والملاحظات',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._buildOilTechnicianAndNotesFields(
              context,
              busy,
              compact: false,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: OilChangeRoyalCard.gold,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'السعر والدفع',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._oilCheckoutFields(context, busy, compact: false),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _customerName.removeListener(_onCustomerNameTyped);
    if (!widget.isEdit) {
      _customerName.removeListener(_onCustomerNameChangedForVisitSync);
      _customerNameVisitSyncDebounce?.cancel();
    }
    _customerName.dispose();
    _customerFocus.dispose();
    _customerPhone.dispose();

    _deviceName.dispose();
    _carModel.dispose();
    _deviceSerial.dispose();
    _engineSize.dispose();

    _odometerCurrent.removeListener(_maybeSuggestNextOdometer);
    _agreed.removeListener(_onAgreedManualEdit);
    _advance.removeListener(_onAdvanceManualEdit);
    if (!widget.isEdit) {
      _deviceSerial.removeListener(_onPlateFieldChanged);
    }
    _plateVehicleSyncDebounce?.cancel();

    _odometerCurrent.dispose();
    _odometerNext.dispose();
    _oilType.dispose();
    _oilLitersStock.dispose();
    _gearHydraulic.dispose();
    _powerHydraulic.dispose();

    _estimated.dispose();
    _agreed.dispose();
    _advance.dispose();
    _issue.dispose();
    _technicianName.dispose();
    _oilSizeAmount.dispose();
    _barcodeBridge?.clearBarcodePriorityHandler(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.screenLayout;
    final pagePad = layout.pageHorizontalGap;

    if (_hydratingEdit && widget.isEdit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final busy =
        _hydratingEdit || _saving || _prefillBootstrapInProgress;

    final oilWidePanel = layout.isWideVariant;
    final oilCheckoutRailWidth = layout.isDesktopVariant ? 360.0 : 320.0;

    final scaffold = Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: _oilAppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: busy ? null : () => _submit(),
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildOilFormScrollStack(
              context,
              cs: cs,
              layout: layout,
              pagePad: pagePad,
              busy: busy,
              maxWidth: oilWidePanel ? 9999 : 720,
            ),
          ),
          if (oilWidePanel)
            SizedBox(
              width: oilCheckoutRailWidth,
              child: _buildOilCheckoutPanel(context, busy),
            ),
        ],
      ),
    );

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: scaffold,
    );
  }
}
