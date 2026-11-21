import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../theme/design_tokens.dart';
import '../../models/customer_record.dart';
import '../../verticals/oil_change/models/oil_change_hydraulic_card_slot.dart';
import '../../verticals/oil_change/models/oil_change_filter_catalog_entry.dart';
import '../../verticals/oil_change/models/oil_change_filter_kind.dart';
import '../../verticals/oil_change/models/oil_change_hydraulic_catalog_entry.dart';
import '../../verticals/oil_change/models/oil_change_oil_catalog_entry.dart';
import '../../verticals/oil_change/models/oil_change_product_line.dart';
import '../../verticals/oil_change/models/oil_change_service_item.dart';
import '../../verticals/oil_change/services/oil_change_filter_catalog_repository.dart';
import '../../verticals/oil_change/services/oil_change_hydraulic_catalog_repository.dart';
import '../../verticals/oil_change/services/oil_change_oil_catalog_repository.dart';
import '../../screens/customers/customer_form_screen.dart';
import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';
import '../../services/product_repository.dart';
import '../../services/service_orders_repository.dart';
import '../../verticals/oil_change/services/oil_change_settings.dart';
import '../../verticals/oil_change/services/oil_change_services_repository.dart';
import '../../verticals/oil_change/services/oil_change_stock_service.dart';
import '../../services/oil_product_grades_repository.dart';
import '../../utils/app_logger.dart';
import '../../widgets/milliliter_quantity_stepper.dart';
import '../../verticals/oil_change/widgets/customer_open_debt_banner.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../../verticals/oil_change/widgets/oil_change_products_card.dart';
import '../../verticals/oil_change/widgets/oil_change_royal_card.dart';
import '../../verticals/oil_change/widgets/product_picker_dialog.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';
import '../../theme/sale_brand.dart';
import '../../verticals/oil_change/widgets/oil_change_filter_catalog_sheet.dart';
import '../../verticals/oil_change/widgets/oil_change_hydraulic_catalog_sheet.dart';
import '../../verticals/oil_change/widgets/oil_change_oil_catalog_sheet.dart';
import '../../verticals/oil_change/utils/oil_change_prefill_guard.dart';
import '../../verticals/oil_change/utils/oil_change_customer_debt.dart';
import '../../verticals/oil_change/utils/oil_change_filter_format.dart';
import '../../verticals/oil_change/utils/oil_change_log_format.dart';
import '../../utils/shift_actor_conflict_guard.dart';
import '../../services/service_order_kinds.dart';
import '../../services/print_settings_repository.dart';
import '../../models/invoice.dart';
import '../../providers/auth_provider.dart';
import '../../providers/global_barcode_route_bridge.dart';
import '../../providers/shift_provider.dart';
import '../../verticals/oil_change/services/oil_change_checkout_service.dart';
import '../../verticals/oil_change/services/oil_change_product_scan.dart';
import '../../utils/customer_phone_launch.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../verticals/oil_change/utils/oil_service_whatsapp_message.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/adaptive/adaptive_form_container.dart';
import '../../navigation/content_navigation.dart';
import '../../verticals/oil_change/utils/oil_change_order_status.dart';

enum _OilSubmitIntent { complete, suspend }

class ServiceOrderFormScreen extends StatefulWidget {
  const ServiceOrderFormScreen({
    super.key,
    this.editOrderId,
    this.editOrderGlobalId,
    this.prefillFromOrder,
  });

  final int? editOrderId;
  final String? editOrderGlobalId;
  final Map<String, dynamic>? prefillFromOrder;

  bool get isEdit => editOrderId != null && editOrderId! > 0;

  @override
  State<ServiceOrderFormScreen> createState() => _ServiceOrderFormScreenState();
}

class _ServiceOrderFormScreenState extends State<ServiceOrderFormScreen> {
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
  /// يمنع مسح الهاتف بعد اختيار العميل من القائمة (سباق RawAutocomplete على التابلت/الحاسوب).
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
  final List<OilChangeProductLine> _oilProductLines = [];
  String? _orderGlobalId;
  GlobalBarcodeRouteBridge? _barcodeBridge;
  bool _oilBarcodeBusy = false;
  bool _isProductPickerOpen = false;
  int _customerOpenDebtFils = 0;
  bool _customerOpenDebtLoading = false;
  int _priorOpenDebtFilsAtCheckout = 0;
  Timer? _plateVehicleSyncDebounce;
  Timer? _customerNameVisitSyncDebounce;
  bool _vehicleSyncInFlight = false;
  /// آخر لوحة جُلب لها سجل تلقائياً — يمنع حلقة إعادة المزامنة عند تعيين نفس اللوحة.
  String? _lastAutoSyncedPlate;
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
    _customerName.addListener(_onCustomerNameTyped);
    if (widget.isEdit) {
      _hydratingEdit = true;
      unawaited(_load());
    }
  }

  void _assignControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
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

void _onPlateFieldChanged() {} // moved: OilChangeOrderFormScreen

  /// يملأ حقول السيارة/الزيت من سجل سابق — [replaceAll] للتعبئة من صف السجل، وإلا الحقول الفارغة فقط.
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
    textCtrl(_deviceSerial, 'deviceSerial');
    textCtrl(_engineSize, 'engineSize');
    textCtrl(_odometerCurrent, 'odometerCurrent');
    final nextOdo = (r['odometerNext'] ?? '').toString();
    if (replaceAll || _odometerNext.text.trim().isEmpty) {
      _odometerNext.text = nextOdo;
      if (nextOdo.trim().isNotEmpty) _odometerNextTouched = true;
    }
    if (!skipOilAndHydraulic) {
      textCtrl(_oilType, 'oilType');
      if (replaceAll || _selectedViscosity == null) {
        final vis = r['oilViscosity']?.toString();
        _selectedViscosity =
            vis == null || vis.isEmpty ? null : vis;
      }
      if (replaceAll || _oilSizeAmount.text.trim().isEmpty) {
        _parseOilSize(r['oilSize']?.toString());
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
      _estimated.text = IraqiCurrencyFormat.formatDecimal2(
        IqdMoney.fromFils((r['estimatedPriceFils'] as num?)?.toInt() ?? 0),
      );
      final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
      _agreed.text = agreedF == null
          ? ''
          : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF));
      _advance.text = IraqiCurrencyFormat.formatDecimal2(
        IqdMoney.fromFils((r['advancePaymentFils'] as num?)?.toInt() ?? 0),
      );
      _serviceId = (r['serviceId'] as num?)?.toInt();
      final req = parseOilRequestedServices(r['requestedServices']?.toString());
      _selectedServices.clear();
      if (req.isNotEmpty) {
        _selectedServices.addAll(req);
      }
    } else {
      if (_agreed.text.trim().isEmpty) {
        final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
        if (agreedF != null) {
          _agreed.text =
              IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF));
        }
      }
      if (_selectedServices.isEmpty) {
        final req = parseOilRequestedServices(r['requestedServices']?.toString());
        if (req.isNotEmpty) {
          _selectedServices.addAll(req);
        }
      }
    }

    if (_customerId != null && _customerId! > 0) {
      _linkedCustomerName = _customerName.text.trim();
    }
    } finally {
      _applyingVehicleRecord = false;
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
      _customerPhone.clear();
    });
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
      _customerName.text = name;
      if (phone.isNotEmpty) {
        _customerPhone.text = phone;
      }
      _customerName.selection = TextSelection.collapsed(offset: name.length);
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _suspendCustomerIdClear = false;
  }

  @override
  void dispose() {
    _customerName.removeListener(_onCustomerNameTyped);
    _customerName.dispose();
    _customerFocus.dispose();
    _customerPhone.dispose();

    _deviceName.dispose();
    _carModel.dispose();
    _deviceSerial.dispose();
    _engineSize.dispose();

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
    super.dispose();
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
        r = await ServiceOrdersRepository.instance.getServiceOrderByGlobalId(gid);
      } else if (widget.editOrderId != null && widget.editOrderId! > 0) {
        r = await ServiceOrdersRepository.instance.getServiceOrderById(
          widget.editOrderId!,
        );
      }
      if (!mounted) return;
      if (r == null) throw StateError('not_found');
      final row = r;

      final svcId = (row['serviceId'] as num?)?.toInt();
      String? svcName;
      if (svcId != null && svcId > 0) {
        final row = await ProductRepository().getProductById(svcId);
        svcName = row == null ? null : (row['name'] ?? '').toString().trim();
      }
      final edm = (r['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
      final h = edm > 0 ? edm ~/ 60 : 0;
      final m = edm > 0 ? edm % 60 : 0;

      setState(() {
        _customerId = (row['customerId'] as num?)?.toInt();
        _customerName.text = (row['customerNameSnapshot'] ?? '').toString();
        _customerPhone.text = (row['customerPhone'] ?? '').toString();
        
        _deviceName.text = (row['deviceName'] ?? '').toString();
        _carModel.text = (row['carModel'] ?? '').toString();
        _deviceSerial.text = (row['deviceSerial'] ?? '').toString();
        _engineSize.text = (row['engineSize'] ?? '').toString();
        
        _odometerCurrent.text = (row['odometerCurrent'] ?? '').toString();
        _odometerNext.text = (row['odometerNext'] ?? '').toString();
        _oilType.text = (row['oilType'] ?? '').toString();
        _selectedViscosity = row['oilViscosity']?.toString().isEmpty == true
            ? null
            : row['oilViscosity']?.toString();
        final catSell = (row['oilSellPerLiterFils'] as num?)?.toInt();
        _catalogSellPerLiterFils =
            catSell != null && catSell > 0 ? catSell : null;
        _parseOilSize(row['oilSize']?.toString());
        _selectedFilterType = row['filterType']?.toString().isEmpty == true
            ? null
            : row['filterType']?.toString();

        _status = (row['status'] ?? 'pending').toString();
        _serviceId = svcId;
        _serviceName = svcName;
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((row['estimatedPriceFils'] as num?)?.toInt() ?? 0),
        );
        final agreedF = (row['agreedPriceFils'] as num?)?.toInt();
        _agreed.text = agreedF == null
            ? ''
            : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF));
        _advance.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((row['advancePaymentFils'] as num?)?.toInt() ?? 0),
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

        _selectedServices.clear();
        final req = parseOilRequestedServices(
          row['requestedServices']?.toString(),
        );
        if (req.isNotEmpty) {
          _selectedServices.addAll(req);
        }

        _hydratingEdit = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _hydratingEdit = false;
      });
    }
  }
  String _friendlyError(Object e) {
    final raw = e.toString();
    if (_isTenantScopeError(raw)) {
      return 'تعذر تحديد بيانات المستأجر. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (raw.contains('no such table') || raw.contains('no such column')) {
      return 'قاعدة البيانات تحتاج تهيئة/تحديث. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (raw.contains('الرصيد غير كافٍ') || raw.contains('رصيد غير كاف')) {
      return raw.replaceFirst('StateError: ', '').trim();
    }
    if (raw.contains('تعذّر صرف الزيت')) {
      return 'تعذّر صرف الزيت من المخزون. تحقق من الرصيد والمستودع.';
    }
    if (raw.contains('CHECK constraint failed') &&
        raw.toLowerCase().contains('status')) {
      return 'تعذّر حفظ حالة «معلّقة». أغلق التطبيق وافتحه من جديد لتحديث قاعدة البيانات.';
    }
    return 'حدث خطأ غير متوقع أثناء الحفظ.';
  }

  bool _isTenantScopeError(String raw) {
    return raw.contains('TenantContextService') ||
        raw.contains('TenantContext غير') ||
        raw.contains('لا يوجد مستأجر نشط') ||
        raw.contains('معرّف المستأجر النشط');
  }

  int _parseFils(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '');
    final v = double.tryParse(raw) ?? 0;
    return IqdMoney.toFils(v);
  }

  String? _filterTypeSummaryForSave() => _selectedFilterType;

  String? _hydraulicSizeValueForSaveFor(OilChangeHydraulicCardSlot slot) =>
      slot.sizeValueForSave(
        usesWarehousePicker: false,
        effectiveCustomerProvided: slot.customerProvided,
      );

  String? _oilSizeValueForSave() {
    if (_selectedSizeUnit == 'Q') return 'Q';
    final stored = oilSizeDisplayToStored(_oilSizeAmount.text);
    if (stored.isEmpty) return null;
    return stored;
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

  Future<void> _openDurationWheel() async {
    if (_hydratingEdit || _saving) return;
    var h = _etaHours.clamp(0, 72);
    var m = _etaMinutes.clamp(0, 59);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
                    child: Text(
                      'المدة المتوقعة لإنجاز العمل',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ساعات',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'دقائق',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: h,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (i) {
                                h = i;
                                setModal(() {});
                              },
                              children: [
                                for (var i = 0; i <= 72; i++)
                                  Center(child: Text('$i')),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: m,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (i) {
                                m = i;
                                setModal(() {});
                              },
                              children: [
                                for (var i = 0; i < 60; i++)
                                  Center(child: Text('$i')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _etaHours = h;
                              _etaMinutes = m;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('تم'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
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
      _agreed.clear();
    });
  }

  Future<void> _pickService() async {
    final repo = ProductRepository();
    final rows = await repo.getProducts();
    if (!mounted) return;
    final services = rows
        .where((e) => ((e['isService'] as num?)?.toInt() ?? 0) == 1)
        .toList(growable: false);

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final search = TextEditingController();
        return StatefulBuilder(builder: (ctx, setModal) {
          final q = search.text.trim().toLowerCase();
          final filtered = services.where((s) {
            if (q.isEmpty) return true;
            final n = (s['name'] ?? '').toString().toLowerCase();
            final bc = (s['barcode'] ?? '').toString().toLowerCase();
            return n.contains(q) || bc.contains(q);
          }).toList(growable: false);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
                  child: TextField(
                     controller: search,
                    onChanged: (_) => setModal(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'بحث في الخدمات…',
                      isDense: true,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final s = filtered[i];
                      final name = (s['name'] ?? '').toString();
                      final id = (s['id'] as num?)?.toInt();
                      final sell = (s['sell'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        title: Text(name.isEmpty ? 'خدمة' : name),
                        subtitle: Text(
                          IraqiCurrencyFormat.formatIqd(sell),
                          textDirection: TextDirection.ltr,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: id == null ? null : () => Navigator.pop(ctx, s),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        });
      },
    );

    if (picked == null) return;
    final pid = (picked['id'] as num?)?.toInt();
    setState(() {
      _serviceId = pid;
      _serviceName = (picked['name'] ?? '').toString().trim();
    });
    await _applyServicePricing(pid);
  }
  Future<void> _afterOilChangeSaved({
    required Map<String, dynamic>? savedOrder,
    required int? orderId,
    required bool openInvoice,
    bool skipPostSaveActions = false,
  }) async {}

  Future<void> _submit({
    bool openInvoice = false,
    _OilSubmitIntent intent = _OilSubmitIntent.complete,
  }) async {
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

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    var serialOut = _deviceSerial.text.trim();
    if (serialOut.isEmpty) {
      serialOut =
          'REF-${DateTime.now().millisecondsSinceEpoch % 100000000}';
      _deviceSerial.text = serialOut;
    }

    final customerNameOut = _customerName.text.trim();
    final deviceNameOut = _deviceName.text.trim();

    final sizeVal = _oilSizeValueForSave();
    final hydSizeVal = _hydraulicSizeValueForSaveFor(_gearHydraulic);
    final powerHydSizeVal = _hydraulicSizeValueForSaveFor(_powerHydraulic);

    final estF = _parseFils(_estimated);
    final agreedRaw = _agreed.text.trim().replaceAll(',', '');
    final agreedD = agreedRaw.isEmpty ? null : double.tryParse(agreedRaw);
    final agreedF = agreedD == null ? null : IqdMoney.toFils(agreedD);
    final advF = _parseFils(_advance);

    final etaMins = _etaTotalMinutes();
    String? promIso;
    if (_workStartedAtUtc != null && etaMins != null && etaMins > 0) {
      promIso = _workStartedAtUtc!
          .add(Duration(minutes: etaMins))
          .toIso8601String();
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      int? savedId;

      if (widget.isEdit) {
        await ServiceOrdersRepository.instance.updateServiceOrderById(
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
          carModel: _carModel.text.trim(),
          engineSize: _engineSize.text.trim(),
          odometerCurrent: _odometerCurrent.text.trim(),
          odometerNext: _odometerNext.text.trim(),
          oilType: _oilType.text.trim(),
          oilViscosity: _selectedViscosity,
          oilSize: sizeVal,
          filterType: _filterTypeSummaryForSave(),
          engineFilterName:
              _engineFilter.hasSelection ? _engineFilter.name : null,
          engineFilterPriceFils:
              _engineFilter.hasSelection ? _engineFilter.priceFils : null,
          airFilterName: _airFilter.hasSelection ? _airFilter.name : null,
          airFilterPriceFils:
              _airFilter.hasSelection ? _airFilter.priceFils : null,
          gearFilterName: _gearFilter.hasSelection ? _gearFilter.name : null,
          gearFilterPriceFils:
              _gearFilter.hasSelection ? _gearFilter.priceFils : null,
          requestedServices: _selectedServices.join(','),
          customerPhone: _customerPhone.text.trim(),
          technicianName: _technicianName.text.trim(),
          patchOilStockFields: false,
          patchHydraulicStockFields: false,
          patchPowerHydraulicStockFields: false,
        );
        savedId = widget.editOrderId;
      } else {
        savedId = await ServiceOrdersRepository.instance.createServiceOrder(
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
          carModel: _carModel.text.trim(),
          engineSize: _engineSize.text.trim(),
          odometerCurrent: _odometerCurrent.text.trim(),
          odometerNext: _odometerNext.text.trim(),
          oilType: _oilType.text.trim(),
          oilViscosity: _selectedViscosity,
          oilSize: sizeVal,
          filterType: _filterTypeSummaryForSave(),
          engineFilterName:
              _engineFilter.hasSelection ? _engineFilter.name : null,
          engineFilterPriceFils:
              _engineFilter.hasSelection ? _engineFilter.priceFils : null,
          airFilterName: _airFilter.hasSelection ? _airFilter.name : null,
          airFilterPriceFils:
              _airFilter.hasSelection ? _airFilter.priceFils : null,
          gearFilterName: _gearFilter.hasSelection ? _gearFilter.name : null,
          gearFilterPriceFils:
              _gearFilter.hasSelection ? _gearFilter.priceFils : null,
          requestedServices: _selectedServices.join(','),
          customerPhone: _customerPhone.text.trim(),
          technicianName: _technicianName.text.trim(),
          orderKind: ServiceOrderKinds.repair,
        );
      }
      if (!mounted) return;

      await _afterOilChangeSaved(
        savedOrder: null,
        orderId: savedId,
        openInvoice: openInvoice,
      );
      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _saving = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ServiceOrderFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // لا إعادة تعبئة من prefill عند إعادة بناء الودجت — يحافظ على تعديلات المستخدم.
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_hydratingEdit && widget.isEdit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final busy = _hydratingEdit || _saving;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEdit ? 'تعديل تذكرة صيانة' : 'بطاقة صيانة جديدة',
        ),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: busy ? null : _submit,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: AdaptiveFormContainer(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 22),
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
              _buildScheduleBanner(cs),
              if (_etaTotalMinutes() != null ||
                  _promisedDeliveryStoredIso != null)
                const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RawAutocomplete<CustomerRecord>(
                      textEditingController: _customerName,
                      focusNode: _customerFocus,
                      displayStringForOption: (c) => c.name,
                      optionsBuilder: (tv) async {
                        final q = tv.text.trim();
                        if (q.isEmpty) {
                          return const Iterable<CustomerRecord>.empty();
                        }
                        await Future<void>.delayed(
                          const Duration(milliseconds: 240),
                        );
                        if (!mounted || _customerName.text.trim() != q) {
                          return const Iterable<CustomerRecord>.empty();
                        }
                        final rows = await _customersDb.queryCustomersPage(
                          query: q,
                          statusArabic: 'الكل',
                          sortKey: 'name_asc',
                          limit: 20,
                          offset: 0,
                        );
                        return rows.map(CustomerRecord.fromMap);
                      },
                      onSelected: (c) => unawaited(_applyCustomerSelection(c)),
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmit) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'اسم العميل',
                            border: const OutlineInputBorder(),
                            hintText: 'ابدأ الكتابة للبحث في العملاء',
                            suffixIcon: _customerId != null
                                ? Icon(Icons.link_rounded, color: cs.primary)
                                : null,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'اسم العميل مطلوب'
                              : null,
                          textAlign: TextAlign.start,
                          onFieldSubmitted: (_) => onSubmit(),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final list = options.toList();
                        return Align(
                          alignment: AlignmentDirectional.topStart,
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 220),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: list.length,
                                itemBuilder: (ctx, i) {
                                  final c = list[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      c.name.trim().isEmpty ? 'عميل' : c.name,
                                      textAlign: TextAlign.start,
                                    ),
                                    subtitle: c.phone == null ||
                                            c.phone!.trim().isEmpty
                                        ? null
                                        : Text(
                                            c.phone!,
                                            textDirection: TextDirection.ltr,
                                            textAlign: TextAlign.start,
                                          ),
                                    onTap: () => onSelected(c),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'عميل جديد',
                    onPressed: busy ? null : _openNewCustomer,
                    icon: const Icon(Icons.person_add_alt_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _deviceName,
                decoration: const InputDecoration(
                  labelText: 'اسم الجهاز / السيارة',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'اسم الجهاز مطلوب'
                    : null,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _deviceSerial,
                decoration: const InputDecoration(
                  labelText: 'رقم تسلسلي / لوحة (اختياري)',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
                child: Text(
                  'إن تُرك فارغاً يُولَّد تلقائياً رقم مرجعي داخلي للتذكرة (وليس سيريال الجهاز).',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : _openDurationWheel,
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_filled_rounded,
                            color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'المدة المتوقعة',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                                textAlign: TextAlign.start,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _durationSummaryLabel(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_left_rounded,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الخدمة'),
                subtitle: Text(
                  _serviceName?.trim().isNotEmpty == true
                      ? _serviceName!
                      : (_serviceId == null
                          ? 'غير محددة (اختياري)'
                          : 'محددة'),
                ),
                trailing: OutlinedButton.icon(
                  onPressed: busy ? null : _pickService,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('اختيار'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _estimated,
                      readOnly: true,
                      enableInteractiveSelection: true,
                      decoration: const InputDecoration(
                        labelText: 'سعر تقديري (من الخدمة)',
                        border: OutlineInputBorder(),
                        helperText: 'يُملأ تلقائياً من سعر الخدمة',
                      ),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _agreed,
                      decoration: const InputDecoration(
                        labelText: 'السعر المتفق عليه (د.ع)',
                        border: OutlineInputBorder(),
                        helperText: 'المكان الوحيد لتعديل السعر',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim().replaceAll(',', '');
                        if (s.isEmpty) return null;
                        final n = double.tryParse(s);
                        if (n == null || n < 0) return 'أدخل مبلغاً صحيحاً';
                        return null;
                      },
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _advance,
                decoration: const InputDecoration(
                  labelText: 'عربون/دفعة مقدمة (د.ع)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n =
                      double.tryParse((v ?? '').trim().replaceAll(',', ''));
                  if (n == null || n < 0) return 'أدخل مبلغاً صحيحاً';
                  return null;
                },
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _issue,
                decoration: const InputDecoration(
                  labelText: 'وصف المشكلة (اختياري)',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 5,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ التذكرة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
