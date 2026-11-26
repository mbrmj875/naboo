import '../../../assistant/exec/assistant_prefill.dart';
import 'dart:convert';
import '../../../printing/receipt_printer.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../guides/guide_anchor.dart';
import '../../../guides/guide_controller.dart';
import '../../../theme/design_tokens.dart';
import '../../../models/customer_record.dart';
import '../models/oil_card_required_fields.dart';
import '../models/oil_change_hydraulic_card_slot.dart';
import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';
import '../models/oil_change_hydraulic_catalog_entry.dart';
import '../models/oil_change_oil_catalog_entry.dart';
import '../models/oil_change_product_line.dart';
import '../models/oil_change_service_item.dart';
import '../services/oil_change_filter_catalog_repository.dart';
import '../services/oil_change_filter_kinds_repository.dart';
import '../services/oil_filter_stock_catalog.dart';
import '../services/oil_card_stock_check.dart';
import '../services/oil_card_draft_store.dart';
import '../widgets/oil_change_owner_pin_confirm_dialog.dart';
import '../../../owner/services/business_audit_log_service.dart';
import '../services/oil_change_hydraulic_catalog_repository.dart';
import '../services/oil_change_oil_catalog_repository.dart';
import '../../../screens/customers/customer_form_screen.dart';
import '../../../services/customer_search_index.dart';
import '../../../services/database_helper.dart';
import '../../../services/shared_db_transaction.dart';
import '../../../services/tenant_context_service.dart';
import '../../../services/product_repository.dart';
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
import '../widgets/iraq_plate_field.dart';
import '../widgets/oil_change_products_card.dart';
import '../widgets/oil_change_royal_card.dart';
import '../widgets/oil_change_save_success_overlay.dart';
import '../widgets/oil_change_technician_field.dart';
import '../widgets/product_picker_dialog.dart';
import '../widgets/oil_change_form_theme.dart';
import '../../../theme/sale_brand.dart';
import '../widgets/oil_change_filter_catalog_sheet.dart';
import '../widgets/oil_change_hydraulic_catalog_sheet.dart';
import '../widgets/oil_change_oil_catalog_sheet.dart';
import '../utils/oil_card_account.dart';
import '../../../models/customer_debt_models.dart';
import '../utils/oil_change_advance_autofill.dart';
import '../utils/oil_change_agreed_total.dart';
import '../utils/oil_change_amend_whatsapp.dart';
import '../utils/oil_field_select_all.dart';
import '../utils/oil_change_finance.dart';
import '../utils/oil_change_layout.dart';
import '../utils/oil_change_lookup_normalize.dart';
import '../utils/oil_change_prefill_guard.dart';
import '../utils/oil_change_customer_debt.dart';
import '../../../services/sale_debt_caps_validator.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_change_log_format.dart';
import '../services/oil_notes_money_ai_client.dart';
import '../utils/oil_notes_money_parser.dart';
import '../widgets/oil_notes_money_preview_bar.dart';
import '../../../utils/shift_actor_conflict_guard.dart';
import '../../../services/effective_store_branding.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/business_features_provider.dart';
import '../../../providers/customers_provider.dart';
import '../../../providers/global_barcode_route_bridge.dart';
import '../../../providers/shift_provider.dart';
import '../services/oil_change_checkout_service.dart';
import '../services/oil_change_post_sale_service.dart';
import '../services/oil_change_whatsapp_notify_service.dart';
import '../services/wa_oil_followup_scheduler.dart';
import '../widgets/wa_reminder_consent_tile.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import '../services/oil_change_product_scan.dart';
import '../../../utils/customer_phone_launch.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_service_whatsapp_message.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/adaptive_form_container.dart';
import '../../../widgets/raw_keyboard_inset.dart';
import '../../../navigation/app_root_navigator_key.dart';
import '../../../models/print_settings_data.dart';
import '../../../navigation/content_navigation.dart';
import '../utils/oil_change_order_status.dart';
import '../utils/oil_order_has_oil.dart';
import '../utils/oil_odometer_unit.dart';
import '../utils/oil_card_labor.dart';
import 'oil_change_form_screen.dart';
import '../../../utils/arabic_count.dart';
import '../../../assistant/ui/assistant_context_scope.dart';

part 'oil_change_order_form/oil_form_types.dart';
part 'oil_change_order_form/oil_form_sections.dart';
part 'oil_change_order_form/oil_form_save.dart';

class OilChangeOrderFormScreen extends StatefulWidget {
  const OilChangeOrderFormScreen({
    super.key,
    this.editOrderId,
    this.editOrderGlobalId,
    this.prefillFromOrder,
    this.amendInvoicedOrder = false,
    this.assistantPrefill,
  }) : assert(!amendInvoicedOrder || editOrderId != null, 'تصحيح الفاتورة يتطلب بطاقة موجودة');

  /// بطاقة جديدة عبّأها المساعد (م4-1). تُراجع وتُحفظ بزر البطاقة نفسه.
  final AssistantPrefill? assistantPrefill;

  final int? editOrderId;
  final String? editOrderGlobalId;

  /// لقطة صف محلية لرسم النموذج فوراً عند التعديل/التصحيح بدون انتظار.
  final Map<String, dynamic>? prefillFromOrder;

  /// تعديل بطاقة مكتملة مربوطة بفاتورة — يحدّث نفس الفاتورة والصندوق.
  final bool amendInvoicedOrder;

  bool get isEdit => editOrderId != null && editOrderId! > 0;
  bool get isNewCard => !isEdit;
  bool get isOilNewCard => isNewCard;

  @override
  State<OilChangeOrderFormScreen> createState() => _OilChangeOrderFormScreenState();
}

class _OilChangeOrderFormScreenState extends State<OilChangeOrderFormScreen> {
  /// setState للأجزاء المنقولة إلى ملفات أخرى (الامتدادات لا تستدعيه مباشرة).
  void _rebuild(VoidCallback fn) => setState(fn);

  bool _oilCatalogGuideOpen = false;
  bool _filterCatalogGuideOpen = false;
  bool _hydraulicCatalogGuideOpen = false;

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _customerName = TextEditingController();
  final _customerFocus = FocusNode();
  final _customerPhone = TextEditingController(text: '07');

  final _deviceName = TextEditingController(); // اسم السيارة
  final _carModel = TextEditingController(); // موديل السيارة
  final _deviceSerial = TextEditingController(); // رقم اللوحة
  final _engineSize = TextEditingController(); // حجم المحرك

  final _odometerCurrent = TextEditingController(); // القراءة الحالية
  final _odometerNext = TextEditingController(); // القراءة اللاحقة
  final _oilType = TextEditingController(); // نوع الزيت

  final _estimated = TextEditingController(text: '0');
  final _agreed = TextEditingController();
  final _advance = TextEditingController(text: '0');
  final _issue = TextEditingController(); // الملاحظات
  final _technicianName = TextEditingController(); // اسم الفني

  /// مبالغ مؤكَّدة من الملاحظات (فلس) — تُضاف للمجموع بعد زر «إضافة للمجموع».
  int _notesExtrasFils = 0;
  bool _notesExtrasConfirmed = false;
  String? _notesExtrasDismissedKey;
  OilNotesMoneyParseResult _notesMoneyPreview = OilNotesMoneyParseResult.empty;
  Timer? _notesMoneyDebounce;

  /// يجمع ضربات الحجم/المبالغ حتى لا يُعاد بناء النموذج كاملاً كل إطار.
  Timer? _checkoutUiDebounce;
  bool _notesMoneyAiLoading = false;
  final _notesMoneyAi = OilNotesMoneyAiClient();

  /// نتيجة محلية أخيرة — تُمرَّر كتلميح للتحليل الذكي.
  OilNotesMoneyParseResult _notesMoneyLocalHint = OilNotesMoneyParseResult.empty;

  /// نص الملاحظات الذي بُني عليه آخر تحليل AI.
  String? _notesMoneyAiForText;

  // Dropdowns Selection
  String? _selectedViscosity;
  final _oilSizeAmount = TextEditingController();

  final Set<int> _selectedOilServiceIds = {};
  List<OilChangeServiceItem> _oilCatalog = [];
  int _basePriceFils = 0;
  bool _agreedTotalManual = false;
  bool _advanceManuallyEdited = false;
  bool _syncingAgreed = false;
  int? _lastAutoSyncedTotalFils;
  String? _openDebtRequestKey;
  ThemeData? _formTheme;

  /// إطار أول خفيف: AppBar فوراً ثم الجسم بعد إطار واحد.
  bool _formBodyReady = false;

  List<OilChangeOilCatalogEntry>? _oilBrandItemsSource;
  List<String> _oilBrandItemsCache = const [];
  List<OilChangeOilCatalogEntry>? _oilViscosityEntriesSource;
  String? _oilViscosityEntriesBrand;
  List<OilChangeOilCatalogEntry> _oilViscosityEntriesCache = const [];
  List<OilChangeHydraulicCatalogEntry>? _hydraulicBrandItemsSource;
  List<String> _hydraulicBrandItemsCache = const [];
  final Map<OilChangeHydraulicCardSlot, _HydraulicGradeCache> _hydraulicGradeEntriesCache = {};

  /// الكتابة الجارية في حقل المبلغ مصدرها الحساب التلقائي لا المستخدم.
  bool _syncingAdvance = false;

  bool _oilCustomerProvided = false;

  /// إعداد المحل: ربط بطاقة الغيار بأصناف المخزون (زيت المحل).
  bool _stockFromWarehouseEnabled = true;

  /// إعداد المحل: إظهار كل قسم من «إضافات عند الحاجة» على حدة.
  final Map<_OilFormOptionalSection, bool> _optionalExtraVisible = {
    for (final s in _OilFormOptionalSection.values) s: true,
  };
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

  /// أي قسم هيدروليك مرتبط بالمخزون (لتحميل أصنافه).
  bool _hydraulicStockFromWarehouseEnabled = true;
  bool _gearHydraulicStockEnabled = true;
  bool _powerHydraulicStockEnabled = true;

  /// مصدر قسم هيدروليك بعينه: المخزون أو أسماء وأسعار فقط.
  bool _hydraulicStockEnabledFor(OilChangeHydraulicCardSlot slot) =>
      identical(slot, _powerHydraulic) ? _powerHydraulicStockEnabled : _gearHydraulicStockEnabled;
  final _gearHydraulic = OilChangeHydraulicCardSlot.gear();
  final _powerHydraulic = OilChangeHydraulicCardSlot.power();
  List<OilChangeFilterCatalogEntry> _filterProductCatalog = const [];
  bool _filterProductCatalogLoading = false;
  List<OilChangeFilterKind> _filterKinds = List<OilChangeFilterKind>.from(OilChangeFilterKind.builtins);
  final Map<String, OilChangeFilterSlot> _filterSlotsByCode = {};

  /// مصدر الفلاتر: أصناف المخزون حسب «الصنف»، أو كتالوج الأسماء والأسعار.
  bool _filtersStockEnabled = false;

  /// كمية الفلتر قابلة للتعديل، وإلا قطعة واحدة.
  bool _filterQtyEditable = false;

  /// تغيّر مصدر الفلاتر بعد تحميل قائمتها — يُعاد تحميلها.
  bool _filterSourceChanged = false;

  /// المالك وافق برمزه على البيع رغم نقص الرصيد (لهذا الحفظ فقط).
  bool _stockOverrideApproved = false;

  /// حفظ مسودة البطاقة الجديدة محلياً كل بضع ثوانٍ.
  Timer? _draftTimer;

  /// البطاقة حُفظت/عُلّقت: لا مسودة لها بعد ذلك حتى تُمسح الحقول.
  bool _draftDone = false;
  List<OilStockShortage> _stockOverrideShortages = const [];

  /// فلاتر البطاقة كما حُفظت عند فتح التعديل — لمزامنة صرف المخزون.
  List<OilFilterLineData> _editFilterLines = const [];
  List<OilPickLine> _hydraulicStockPickLines = const [];
  bool _hydraulicStockPickLinesLoading = false;

  /// لقطة مخزون عند فتح التعديل — لمزامنة الصرف.
  int? _editStockVoucherId;
  double _editOilLitersUsed = 0;
  int? _editOilProductId;
  int? _editOilWarehouseId;
  bool _editOilCustomerProvided = false;
  int _editInvoiceId = 0;

  /// هاتف البطاقة عند فتح التصحيح (مقفول بعد التحميل) — لكشف تغيّر الرقم فقط.
  String? _baselineCustomerPhoneDigits;
  bool _baselineCustomerPhoneLocked = false;

  bool _hydratingEdit = false;
  bool _saving = false;

  /// بعد حفظ ناجح أو موافقة المستخدم على المغادرة.
  bool _leaveGateAllowPop = false;

  /// بصمة الحقول بعد التحميل/الفتح — للمقارنة عند الرجوع.
  String? _leaveGateCleanFingerprint;
  Object? _error;
  String? _errorText;

  int? _customerId;
  bool _suspendCustomerIdClear = false;

  /// يمنع مسح الهاتف بعد اختيار العميل من القائمة (سباق تحديث الحقل على التابلت/الحاسوب).
  String? _linkedCustomerName;

  DateTime? _workStartedAtUtc;

  int _etaHours = 0;
  int _etaMinutes = 0;

  int? _serviceId;
  String _status = 'pending';

  /// البطاقة المفتوحة للتعديل مرتبطة بفاتورة.
  bool _editHasInvoice = false;
  final Set<_OilFormOptionalSection> _expandedOptional = {};

  /// يمنع جدولة مزامنة الدليل في كل إطار — فقط عند تغيّر الخطوة.
  String? _lastGuideSyncKey;

  /// يُبطِل ردود DeepSeek المتأخرة بعد مغادرة/تعديل النص.
  int _notesMoneyAiGeneration = 0;
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
  bool? _waAskRatingAfterSave;
  bool _waReminderConsent = true;
  WaRecipientConsentStatus _waReminderPrior = WaRecipientConsentStatus.none;
  String _waReminderCheckedPhone = '';
  Timer? _plateVehicleSyncDebounce;
  bool _vehicleSyncInFlight = false;
  bool _vehicleSyncQueued = false;

  /// آخر لوحة جُلب لها سجل تلقائياً بنجاح — يمنع إعادة المزامنة لنفس اللوحة.
  String? _lastAutoSyncedPlate;

  /// محافظة المحل للوحات الجديدة (إعداد بطاقة الغيار).
  String? _defaultPlateProvince;

  /// الموظف أكّد أن اللوحة الكاملة لسيارة قديمة لوحتها ناقصة: تأخذها
  /// السيارة عند الحفظ فتبقى زياراتها في مكان واحد.
  String? _adoptVehicleGid;
  String? _adoptPlateKey;

  /// لوحات أجاب الموظف عنها «سيارة أخرى» — لا يُسأل عنها ثانية في البطاقة.
  final Set<String> _declinedLegacyPlates = {};

  /// سيارات العميل المختار (اثنتان أو أكثر = أزرار اختيار فوق بيانات السيارة).
  List<Map<String, dynamic>> _customerVehicles = const [];
  int? _customerVehiclesFor;
  String? _lastAutoSyncedCustomerKey;
  bool _applyingVehicleRecord = false;

  /// الهاتف يُكتب برمجياً (فتح بطاقة، مسودة، اختيار عميل): لا ربط فوري.
  bool _settingPhoneProgrammatically = false;

  /// آخر رقم كامل فُحص للربط الفوري.
  String? _phoneLinkCheckedKey;

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

  /// قراءة العداد في الزيارة السابقة: تُعرض تلميحاً تحت القراءة الحالية.
  String? _previousVisitOdometer;

  /// وحدة القراءة السابقة؛ لا مقارنة «أقل من السابقة» بين وحدتين مختلفتين.
  String _previousOdometerUnit = OilOdometerUnit.km;

  /// وحدة عداد هذه السيارة ('km' أو 'mi')؛ تُنسخ من آخر زيارة لها.
  String _odometerUnit = OilOdometerUnit.km;

  /// تاريخ القراءة السابقة (من سجل السيارة)، يُعرض بجانبها.
  String? _previousOdometerAt;
  Timer? _previousOdometerDebounce;
  bool _odometerLowerThanPrevious = false;

  /// الحقول الإلزامية من إعدادات المحل (الافتراضي يطابق السلوك القديم).
  OilCardRequiredFields _requiredFields = OilCardRequiredFields.defaults;
  bool _isFieldRequired(OilCardField f) => _requiredFields.isRequired(f);

  /// أجور اليد من الإعدادات، وما عدّله الموظف لهذه البطاقة.
  OilCustomerLaborSettings _customerLabor = const OilCustomerLaborSettings();
  int? _oilLaborCardFils;

  /// أجرة التبديل الفعلية (الأساسية، أو أجرة زيت العميل، أو ما كُتب هنا).
  int _oilLaborFils() => effectiveOilLaborFils(
    customerOil: _oilCustomerProvided,
    baseFils: _basePriceFils,
    customerOilSettingFils: _customerLabor.oilFils,
    cardFils: _oilLaborCardFils,
  );

  int _hydraulicLaborFilsFor(OilChangeHydraulicCardSlot slot) => effectiveCustomerItemLaborFils(
    customerProvided: slot.customerProvided,
    settingFils: identical(slot, _powerHydraulic)
        ? _customerLabor.hydraulicPowerFils
        : _customerLabor.hydraulicGearFils,
    cardFils: slot.laborCardFils,
  );

  int _filterLaborFilsFor(OilChangeFilterSlot slot) => effectiveCustomerItemLaborFils(
    customerProvided: slot.customerProvided,
    settingFils: _customerLabor.filterFils,
    cardFils: slot.laborCardFils,
  );

  final DatabaseHelper _customersDb = DatabaseHelper();

  // Static Lists

  @override
  void initState() {
    super.initState();
    // ق67: «هذا/هنا» في المساعد تعني عنصر هذه الشاشة.
    AssistantScreenContext.push(AssistantContextItem(kind: 'oil_card', id: widget.editOrderId ?? 0, label: 'البطاقة التي تعدّلها'));
    if (!widget.isEdit) {
      _status = 'pending';
      // الافتراضي: الزيت إلزامي فقسمه مفتوح من أول إطار.
      _expandedOptional.add(_OilFormOptionalSection.oil);
      // البطاقة الجديدة لا تنتظر شيئاً لتُرسم؛ لا دائرة تحميل في الإطار الأول.
      _formBodyReady = true;
    }
    _customerName.addListener(_onCustomerNameTyped);
    // مسار العداد: القراءة السابقة من سجل السيارة، والتنبيه إن قلّت.
    _deviceSerial.addListener(_schedulePreviousOdometer);
    _odometerCurrent.addListener(_onOdometerCurrentChanged);
    _customerPhone.addListener(_onCustomerPhoneForReminder);
    _customerPhone.addListener(_onCustomerPhoneForLink);
    unawaited(WaOilFollowupScheduler.instance.flushPending());
    // لا مزامنة زيارة تلقائية عند الكتابة في الاسم — التعبئة فقط باختيار من قائمة الاقتراحات.
    _odometerNext.addListener(_onOdometerNextTyped);
    _agreed.addListener(_onAgreedManualEdit);
    _advance.addListener(_onAdvanceManualEdit);
    _issue.addListener(_onIssueNotesChanged);
    if (!widget.isEdit) {
      _deviceSerial.addListener(_onPlateFieldChanged);
      unawaited(_loadDefaultPlateProvince());
    }
    if (widget.isEdit) {
      final warm = _warmEditPrefillRow();
      if (warm != null) {
        // فتح فوري من صف السجل المحلي — بلا سبنر وبلا إنترنت.
        _hydrateEditFieldsFromRow(warm);
        _hydratingEdit = false;
        _formBodyReady = true;
        _seedPhoneBaselineFromRow(warm);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _markLeaveGateClean();
          _attachOilBarcodeHandler();
        });
        unawaited(_loadEditSupportingData(warm));
      } else {
        _hydratingEdit = true;
        unawaited(_load());
      }
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
      // إطار أول خفيف: لا تحميل كتالوج/مخزون قبل رسم الصفحة.
      // لا نستدعِ ArabicSpeechMicButton.warmUp هنا — على macOS يقتل التطبيق (TCC).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_loadOilCatalog());
        unawaited(_loadOilProductCatalog());
        unawaited(_loadFluidStockSettings());
        // بطاقة عبّأها المساعد لا تعرض استرجاع مسودة قديمة فوقها.
        if (widget.assistantPrefill == null) unawaited(_offerDraftRestore());
      });
      final ap = widget.assistantPrefill;
      if (ap != null) {
        // بعد أول إطار: مستمعو الحقول يستدعون setState.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _applyAssistantPrefill(ap));
        });
      }
    }
    if (!widget.isEdit) {
      _draftTimer = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_autosaveDraft()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachOilBarcodeHandler();
    });
    if (!widget.isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markLeaveGateClean();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_warmPostSaveSettings());
    });
    // فهرس العملاء بعد سكون الواجهة — لا ينافس فتح الصفحة ولا الكيبورد.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        unawaited(CustomerSearchIndex.instance.ensureFresh());
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // بناء الثيم يخصّص ThemeData وستة حدود إدخال؛ لا داعي لتكراره كل إطار.
    _formTheme = OilChangeFormTheme.wrap(context, Theme.of(context));
    final guide = context.read<GuideController>();
    if (!identical(_guideListenable, guide)) {
      _guideListenable?.removeListener(_onGuideControllerChanged);
      _guideListenable = guide;
      _guideListenable!.addListener(_onGuideControllerChanged);
    }
  }

  GuideController? _guideListenable;

  void _onGuideControllerChanged() {
    final guide = _guideListenable;
    if (guide == null || !mounted) return;
    final step = guide.currentStep;
    final syncKey = guide.isRunning ? '${step?.anchorId}|${step?.action}|${step?.title}' : 'off';
    if (_lastGuideSyncKey == syncKey) return;
    _lastGuideSyncKey = syncKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncGuideCatalogActions(guide);
    });
  }

  Future<PrintSettingsData> _loadStoreBrandingForCustomer() {
    final auth = context.read<AuthProvider>();
    return EffectiveStoreBranding.resolve(
      isOwner: auth.isOwner,
      userGlobalId: auth.userGlobalId,
      userId: auth.userId,
      fallbackToWorkspace: true,
    );
  }

  /// المرحلة 4 — ربط العميل بالهاتف: عند اكتمال رقم يكتبه الموظف لعميل
  /// مسجّل تُربط البطاقة به فوراً ويُملأ الاسم ويظهر دينه. إن كان الاسم
  /// المكتوب مختلفاً يُسأل الموظف: الربط بالمسجّل، أو تعديل الرقم.
  void _onCustomerPhoneForLink() {
    final raw = _customerPhone.text.trim();
    if (CustomerValidation.iraqiMobilePhone(raw) != null) {
      _phoneLinkCheckedKey = null;
      return;
    }
    final e164 = CustomerValidation.toE164IraqMobile(raw);
    final key = CustomerValidation.phoneMatchKey(e164);
    if (e164 == null || key == null || key.isEmpty) return;
    if (key == _phoneLinkCheckedKey) return;
    _phoneLinkCheckedKey = key;
    if (_settingPhoneProgrammatically ||
        _suspendCustomerIdClear ||
        _applyingVehicleRecord ||
        _hydratingEdit ||
        _saving ||
        widget.amendInvoicedOrder) {
      return;
    }
    unawaited(_linkCustomerByPhone(e164, key));
  }

  Future<void> _linkCustomerByPhone(String e164, String key) async {
    int? cid;
    Map<String, dynamic>? row;
    try {
      cid = await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(e164);
      if (cid != null && cid > 0) row = await _customersDb.getCustomerById(cid);
    } catch (e, st) {
      AppLogger.error('OilChangeForm', 'phone link lookup failed', e, st);
      return;
    }
    if (!mounted || cid == null || cid <= 0 || row == null) return;
    if (cid == _customerId) return;
    // كتب الموظف رقماً آخر أثناء البحث.
    if (_phoneLinkCheckedKey != key) return;
    final regName = (row['name'] ?? '').toString().trim();
    if (regName.isEmpty) return;
    final typed = _customerName.text.trim();
    final sameName =
        typed.isEmpty ||
        OilChangeLookupNormalize.normalizeNameKey(typed) == OilChangeLookupNormalize.normalizeNameKey(regName);
    if (!sameName) {
      final link = await _askLinkPhoneToRegistered(registeredName: regName, typedName: typed);
      if (!mounted || _phoneLinkCheckedKey != key) return;
      if (link != true) {
        // الرقم لعميل آخر: يُعدَّل الرقم، فلا يُحفظ باسم غير صاحبه.
        _customerPhone.selection = TextSelection(baseOffset: 0, extentOffset: _customerPhone.text.length);
        _phoneLinkCheckedKey = null;
        return;
      }
    }
    await _applyCustomerSelection(
      CustomerRecord(
        id: cid,
        name: regName,
        phone: (row['phone'] ?? '').toString(),
        balance: (row['balance'] as num?)?.toDouble() ?? 0,
        loyaltyPoints: (row['loyaltyPoints'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<bool?> _askLinkPhoneToRegistered({required String registeredName, required String typedName}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('الرقم مسجّل لعميل آخر'),
        content: Text(
          'هذا الرقم مسجّل باسم «$registeredName»، والاسم المكتوب «$typedName».\n'
          'العميل يُعرف برقمه: اربط البطاقة به، أو عدّل الرقم.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تعديل الرقم')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('ربط بـ $registeredName')),
        ],
      ),
    );
  }

  /// زبون سبق أن رفض لا يعود مشتركًا لأن الخيار مفعّل تلقائيًا.
  Future<void> _onCustomerPhoneForReminder() async {
    final phone = _customerPhone.text.trim();
    if (phone.length != 11 || phone == _waReminderCheckedPhone) return;
    _waReminderCheckedPhone = phone;
    final prior = await WaOilFollowupScheduler.instance.recipientConsentStatus(phone);
    if (!mounted || _customerPhone.text.trim() != phone) return;
    setState(() {
      _waReminderPrior = prior;
      _waReminderConsent = prior == WaRecipientConsentStatus.none;
    });
  }

  Future<void> _warmPostSaveSettings() async {
    if (_cachedPrintSettings != null &&
        _waAutoAfterSave != null &&
        _waManualAfterSave != null &&
        _waAskRatingAfterSave != null) {
      return;
    }
    final results = await Future.wait([_loadStoreBrandingForCustomer(), OilChangeSettings.loadCardSettings()]);
    if (!mounted) return;
    final card = results[1] as OilChangeCardSettings;
    _cachedPrintSettings = results[0] as PrintSettingsData;
    _waAutoAfterSave = card.whatsappAutoAfterSave;
    _waManualAfterSave = card.whatsappManualAfterSave;
    _waAskRatingAfterSave = card.whatsappAskRatingAfterSave;
  }

  Future<void> _loadFluidStockSettings({bool awaitStockLoads = false}) async {
    final card = await OilChangeSettings.loadCardSettings();
    final oilOn = card.stockFromWarehouse;
    final hydOn = card.anyHydraulicStockFromWarehouse;
    final extras = card.optionalExtras;
    if (!mounted) return;
    setState(() {
      _requiredFields = card.requiredFields;
      _customerLabor = card.customerLabor;
      _stockFromWarehouseEnabled = oilOn;
      _hydraulicStockFromWarehouseEnabled = hydOn;
      _gearHydraulicStockEnabled = card.hydraulicGearStockFromWarehouse;
      _powerHydraulicStockEnabled = card.hydraulicPowerStockFromWarehouse;
      _filterQtyEditable = card.filterQuantityEditable;
      if (_filtersStockEnabled != card.filtersStockFromWarehouse) {
        _filtersStockEnabled = card.filtersStockFromWarehouse;
        _filterSourceChanged = true;
      }
      for (final section in _OilFormOptionalSection.values) {
        _optionalExtraVisible[section] = extras[_toOptionalExtraKind(section)] ?? true;
      }
      _expandedOptional.removeWhere((s) {
        if (s == _OilFormOptionalSection.oil) {
          // بطاقة جديدة: الزيت مفتوح ما دام إلزامياً، ومطوي إن صار اختيارياً.
          return !widget.isEdit && !_isFieldRequired(OilCardField.oil) && !_oilSectionHasData();
        }
        if (_optionalExtraVisible[s] ?? true) return false;
        return !_optionalSectionHasData(s);
      });
      if (!oilOn) {
        _oilStockProductId = null;
        _oilWarehouseId = null;
        _oilLitersStock.clear();
      }
      for (final slot in [_gearHydraulic, _powerHydraulic]) {
        if (!_hydraulicStockEnabledFor(slot)) {
          slot.stockProductId = null;
          slot.warehouseId = null;
          slot.litersStock.clear();
        }
      }
    });
    if (_filterSourceChanged) unawaited(_loadFilterProductCatalog());
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

  OilOptionalExtraKind _toOptionalExtraKind(_OilFormOptionalSection section) {
    return switch (section) {
      // لا مفتاح إعداد للزيت؛ [_isOptionalSectionEnabled] يعيده دائماً.
      _OilFormOptionalSection.oil || _OilFormOptionalSection.products => OilOptionalExtraKind.products,
      _OilFormOptionalSection.filters => OilOptionalExtraKind.filters,
      _OilFormOptionalSection.hydraulicGear => OilOptionalExtraKind.hydraulicGear,
      _OilFormOptionalSection.hydraulicPower => OilOptionalExtraKind.hydraulicPower,
      _OilFormOptionalSection.services => OilOptionalExtraKind.services,
    };
  }

  bool _isOptionalSectionEnabled(_OilFormOptionalSection section) {
    // الزيت متاح دائماً؛ إعدادات الإضافات لا تخفيه.
    if (section == _OilFormOptionalSection.oil) return true;
    return _optionalExtraVisible[section] ?? true;
  }

  /// في البطاقة زيت مُدخل (اسم أو حجم أو صنف مخزون أو زيت العميل).
  bool _oilSectionHasData() =>
      _oilCustomerProvided ||
      _oilType.text.trim().isNotEmpty ||
      (_selectedViscosity ?? '').isNotEmpty ||
      (_oilStockProductId ?? 0) > 0 ||
      _oilSizeAmount.text.trim().isNotEmpty ||
      _parseOilLitersStock() > 0;

  bool get _anyOptionalExtrasEnabled => _OilFormOptionalSection.values.any(_shouldRenderOptionalSection);

  bool _optionalSectionHasData(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.oil => _oilSectionHasData(),
      _OilFormOptionalSection.products => _oilProductLines.isNotEmpty,
      _OilFormOptionalSection.filters => _filterKinds.any((k) => _filterSlotFor(k).hasSelection),
      _OilFormOptionalSection.hydraulicGear => _hydraulicSlotHasData(_gearHydraulic),
      _OilFormOptionalSection.hydraulicPower => _hydraulicSlotHasData(_powerHydraulic),
      _OilFormOptionalSection.services => _selectedOilServiceIds.isNotEmpty,
    };
  }

  /// يظهر القسم إن كان مفعّلاً في الإعدادات، أو فيه بيانات محفوظة (تعديل بطاقة).
  bool _shouldRenderOptionalSection(_OilFormOptionalSection section) {
    return _isOptionalSectionEnabled(section) ||
        _optionalSectionHasData(section) ||
        _expandedOptional.contains(section);
  }

  // ── Shared with repair (108 methods, 21 stubbed) ──

  void _markOilFluidUserEdited() {
    _oilFluidUserEdited = true;
    _plateVehicleSyncDebounce?.cancel();
  }

  bool get _isPrefillFromLog => widget.prefillFromOrder != null;

  bool _shouldBlockFluidReconcileAfterPrefill() => shouldBlockFluidReconcileAfterPrefill(
    isPrefillFromLog: _isPrefillFromLog,
    prefillCatalogSyncedOnce: _prefillCatalogSyncedOnce,
  );

  bool _blocksAutoVisitLookup({bool force = false}) => shouldBlockAutoVisitLookup(
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
    // إعادة الحساب تكتب في الحقل، وعدّها تعديلاً يدوياً كانت تُجمّد الإجمالي.
    if (_syncingAgreed) return;
    _agreedTotalManual = true;
    if (!_advanceManuallyEdited) {
      _syncAdvanceFromTotal(_parseFils(_agreed));
    }
    _onOilCheckoutFieldsChanged();
  }

  void _onAdvanceManualEdit() {
    // التعبئة التلقائية تكتب في الحقل أيضاً، وعدّها تعديلاً يدوياً كان يجمّد
    // المبلغ على صفر فيتحوّل الإجمالي كله إلى دين على الزبون.
    if (_syncingAdvance) return;
    _advanceManuallyEdited = true;
    _clampAdvanceToCheckoutTotal();
    _onOilCheckoutFieldsChanged();
  }

  /// الدين السابق الذي يمكن تحصيله من هذه البطاقة: عميل مسجّل، بيع جديد
  /// أو إكمال معلّقة (لا في تصحيح فاتورة).
  int _collectibleOldDebtFils() {
    if (widget.amendInvoicedOrder) return 0;
    if (_customerId == null || _customerId! <= 0) return 0;
    return _customerOpenDebtFils > 0 ? _customerOpenDebtFils : 0;
  }

  /// أعلى مبلغ مستلم: الزيارة + الدين السابق. الزائد عن الزيارة يُسدَّد من
  /// الدين القديم عند البيع.
  int _maxReceivableFils() => _oilCheckoutTotalFils() + _collectibleOldDebtFils();

  /// المبلغ المستلم لا يتجاوز الزيارة + الدين السابق — قص فوري عند التعديل.
  void _clampAdvanceToCheckoutTotal() {
    final totalF = _oilCheckoutTotalFils();
    if (totalF <= 0) return;
    final maxF = _maxReceivableFils();
    final paidF = _parseFils(_advance);
    if (paidF <= maxF) return;
    _syncingAdvance = true;
    try {
      _assignControllerText(_advance, _formatAdvanceIqd(maxF));
    } finally {
      _syncingAdvance = false;
    }
  }

  /// عرض مبالغ البطاقة بدون كسور ومع فواصل آلاف (68,000 وليس 68000 أو 68,000.00).
  String _formatIqdWhole(int fils) {
    if (fils <= 0) return '0';
    return IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(fils).round());
  }

  /// توافق الاسم السابق — نفس [_formatIqdWhole].
  String _formatAdvanceIqd(int fils) => _formatIqdWhole(fils);

  void _syncAdvanceFromTotal(int totalFils) {
    final label = _formatAdvanceIqd(totalFils);
    _syncingAdvance = true;
    try {
      _assignControllerText(_advance, label);
    } finally {
      _syncingAdvance = false;
    }
  }

  void _onIssueNotesChanged() {
    if (_notesMoneyAiLoading) {
      _notesMoneyAiGeneration++;
      if (mounted) setState(() => _notesMoneyAiLoading = false);
    }
    _notesMoneyDebounce?.cancel();
    _notesMoneyDebounce = Timer(const Duration(milliseconds: 400), _refreshNotesMoneyPreview);
  }

  void _refreshNotesMoneyPreview() {
    if (!mounted) return;
    final text = _issue.text;
    final key = text.trim();
    if (_notesExtrasDismissedKey != null && _notesExtrasDismissedKey == key) {
      setState(() {
        _notesMoneyPreview = OilNotesMoneyParseResult.empty;
        _notesMoneyLocalHint = OilNotesMoneyParseResult.empty;
      });
      return;
    }
    if (_notesExtrasDismissedKey != null && _notesExtrasDismissedKey != key) {
      _notesExtrasDismissedKey = null;
    }

    final parsed = parseOilNotesMoney(text);
    _notesMoneyLocalHint = parsed;
    if (_notesExtrasConfirmed) {
      if (parsed.totalFils != _notesExtrasFils) {
        setState(() {
          _notesExtrasConfirmed = false;
          _notesExtrasFils = 0;
          _notesMoneyPreview = parsed;
          _notesMoneyAiForText = null;
          _agreedTotalManual = false;
        });
        _recalculateOilTotal();
      } else {
        setState(() => _notesMoneyPreview = OilNotesMoneyParseResult.empty);
      }
      return;
    }

    // إن تغيّر النص بعد التحليل الذكي — ارجع للاكتشاف المحلي.
    if (_notesMoneyPreview.isFromAi && _notesMoneyAiForText != key) {
      setState(() {
        _notesMoneyPreview = parsed;
        _notesMoneyAiForText = null;
      });
      return;
    }
    if (_notesMoneyPreview.isFromAi) return;

    setState(() => _notesMoneyPreview = parsed);
  }

  Future<void> _requestNotesMoneyAi() async {
    final text = _issue.text.trim();
    if (text.length < 3 || _notesMoneyAiLoading) return;
    final gen = ++_notesMoneyAiGeneration;
    setState(() => _notesMoneyAiLoading = true);
    final ai = await _notesMoneyAi.analyze(
      notes: text,
      localHint: _notesMoneyLocalHint.isNotEmpty ? _notesMoneyLocalHint : parseOilNotesMoney(text),
    );
    if (!mounted || gen != _notesMoneyAiGeneration) return;
    setState(() {
      _notesMoneyAiLoading = false;
      if (ai != null && ai.isNotEmpty) {
        _notesMoneyPreview = ai;
        _notesMoneyAiForText = text;
        _notesExtrasConfirmed = false;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر التحليل الذكي الآن — يمكنك الاعتماد على الاكتشاف المحلي أو إعادة المحاولة'),
          ),
        );
      }
    });
  }

  void _confirmNotesMoneyExtras(int fils) {
    if (fils <= 0) return;
    setState(() {
      _notesExtrasFils = fils;
      _notesExtrasConfirmed = true;
      _notesMoneyPreview = OilNotesMoneyParseResult.empty;
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _dismissNotesMoneyExtras() {
    _notesMoneyAiGeneration++;
    setState(() {
      _notesExtrasDismissedKey = _issue.text.trim();
      _notesMoneyPreview = OilNotesMoneyParseResult.empty;
      _notesMoneyAiLoading = false;
      _notesMoneyAiForText = null;
    });
  }

  void _resetOilCheckoutAutoAdvance() {
    _advanceManuallyEdited = false;
    final total = _oilCheckoutTotalFils();
    _lastAutoSyncedTotalFils = total;
    _syncAdvanceFromTotal(total);
  }

  /// مصدر الحقيقة الوحيد للمبلغ المستلم ما دام المستخدم لم يكتبه بنفسه.
  ///
  /// يُستدعى من مسارات إعادة الحساب / تغيّر حقول الدفع — وليس من داخل build.
  void _ensureAdvanceMatchesTotal(int totalFils) {
    if (!OilChangeAdvanceAutofill.shouldSync(
      manuallyEdited: _advanceManuallyEdited,
      currentAdvanceFils: _parseFils(_advance),
      totalFils: totalFils,
      lastSyncedTotalFils: _lastAutoSyncedTotalFils,
    )) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final total = _oilCheckoutTotalFils();
      if (!OilChangeAdvanceAutofill.shouldSync(
        manuallyEdited: _advanceManuallyEdited,
        currentAdvanceFils: _parseFils(_advance),
        totalFils: total,
        lastSyncedTotalFils: _lastAutoSyncedTotalFils,
      )) {
        return;
      }
      _lastAutoSyncedTotalFils = total;
      setState(() => _syncAdvanceFromTotal(total));
    });
  }

  void _onOdometerNextTyped() {
    if (_odometerDigits(_odometerNext.text).isNotEmpty) {}
  }

  void _onOilCheckoutFieldsChanged() {
    if (!mounted) return;
    _ensureAdvanceMatchesTotal(_oilCheckoutTotalFils());
    _scheduleCheckoutUiRefresh();
  }

  /// تحديث واجهة الدفع/الإجمالي بدون عاصفة setState أثناء الكتابة أو الضغط المطوّل.
  void _scheduleCheckoutUiRefresh({Duration delay = const Duration(milliseconds: 90)}) {
    _checkoutUiDebounce?.cancel();
    _checkoutUiDebounce = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  void _onOilOrHydraulicVolumeChanged({required void Function() syncStockLiters}) {
    syncStockLiters();
    _agreedTotalManual = false;
    _recalculateOilTotal();
    _scheduleCheckoutUiRefresh();
  }

  void _assignControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  static final _carModelDigitFormatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]'))];

  /// حجم المحرك: أرقام + فاصلة عشرية واحدة (مثل 1.8).
  static final _engineSizeInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.]')),
    TextInputFormatter.withFunction((oldValue, newValue) {
      final t = newValue.text;
      if ('.'.allMatches(t).length <= 1) return newValue;
      return oldValue;
    }),
  ];

  String get _carModelForSave => OilChangeLookupNormalize.toWesternDigits(_carModel.text.trim());

  static final _odometerInputFormatters = [IraqiCurrencyFormat.moneyInputFormatter()];

  static final _iraqiMobilePhoneFormatters = CustomerValidation.iraqiMobileInputFormatters();

  void _resetCustomerPhonePrefix() {
    _setCustomerPhoneField(null);
  }

  void _setCustomerPhoneField(String? raw) {
    final t = (raw ?? '').trim();
    final next = t.isEmpty ? '07' : CustomerValidation.coerceIraqiMobileDigits(t);
    _settingPhoneProgrammatically = true;
    try {
      _assignControllerText(_customerPhone, next);
    } finally {
      _settingPhoneProgrammatically = false;
    }
    final sel = next == '07' ? 2 : next.length;
    _customerPhone.selection = TextSelection.collapsed(offset: sel);
  }

  bool get _customerPhoneIsBlank {
    final t = _customerPhone.text.trim();
    return t.isEmpty || t == '07';
  }

  String _odometerDigits(String display) => display.replaceAll(',', '').trim();

  String _formatOdometerDisplay(String? raw) {
    final digits = OilChangeLookupNormalize.toWesternDigits(raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
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

  int? get _previousOdometerKm => int.tryParse(OilChangeLookupNormalize.toWesternDigits(_previousVisitOdometer ?? ''));

  int? get _currentOdometerKm => int.tryParse(OilChangeLookupNormalize.toWesternDigits(_odometerCurrentForSave));

  /// القراءة المكتوبة أقل من آخر قراءة للسيارة؟ (غالباً خطأ كتابة 58 بدل 85.)
  bool _computeOdometerLower() {
    final prev = _previousOdometerKm;
    final cur = _currentOdometerKm;
    if (_previousOdometerUnit != _odometerUnit) return false;
    return prev != null && prev > 0 && cur != null && cur > 0 && cur < prev;
  }

  void _onOdometerCurrentChanged() {
    final lower = _computeOdometerLower();
    if (lower != _odometerLowerThanPrevious && mounted) {
      setState(() => _odometerLowerThanPrevious = lower);
    }
  }

  void _schedulePreviousOdometer() {
    _previousOdometerDebounce?.cancel();
    _previousOdometerDebounce = Timer(const Duration(milliseconds: 400), () => unawaited(_refreshPreviousOdometer()));
  }

  /// آخر قراءة للسيارة من سجلها، قبل هذه البطاقة إن كانت تُعدَّل. سيارة غير
  /// معروفة بعد: يبقى ما جاء من الزيارة السابقة (إن وُجد).
  Future<void> _refreshPreviousOdometer() async {
    final plate = _deviceSerial.text.trim();
    if (plate.length < 3) return;
    try {
      final r = await OilChangeOrdersRepository.instance.previousOdometerReading(
        plate,
        excludeOrderId: widget.editOrderId,
      );
      if (!mounted || _deviceSerial.text.trim() != plate || r == null) return;
      setState(() {
        _previousVisitOdometer = r.km?.toString();
        _previousOdometerAt = r.at;
        _previousOdometerUnit = r.unit;
        _odometerLowerThanPrevious = _computeOdometerLower();
      });
    } catch (_) {}
  }

  /// نص التلميح تحت القراءة الحالية: «السابقة: 85,000 كم · 12/03/2026».
  String? get _previousOdometerHelper {
    final prevUnit = OilOdometerUnit.label(_previousOdometerUnit);
    final prev = _previousOdometerKm;
    if (prev == null || prev <= 0) {
      final raw = (_previousVisitOdometer ?? '').trim();
      return raw.isEmpty ? null : 'السابقة: $raw $prevUnit';
    }
    final km = IraqiCurrencyFormat.formatInt(prev);
    if (_odometerLowerThanPrevious) {
      return 'أقل من السابقة ($km $prevUnit) — تأكّد من القراءة';
    }
    final at = DateTime.tryParse(_previousOdometerAt ?? '');
    final day = at == null
        ? ''
        : ' · ${at.day.toString().padLeft(2, '0')}/'
              '${at.month.toString().padLeft(2, '0')}/${at.year}';
    return 'السابقة: $km $prevUnit$day';
  }

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
    // زيت العميل: لا سعر كتالوج؛ اسمه حر يكتبه الموظف.
    if (_oilCustomerProvided) return;
    final brand = _selectedOilBrand;
    final vis = _selectedViscosity;
    if (brand == null || brand.isEmpty || vis == null || vis.isEmpty || _oilProductCatalog.isEmpty) {
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

  void _syncHydraulicCatalogPricingFromSelectionFor(OilChangeHydraulicCardSlot slot) {
    final brand = slot.selectedBrand;
    final grade = slot.selectedGrade;
    if (brand == null || brand.isEmpty || grade == null || grade.isEmpty || _hydraulicProductCatalog.isEmpty) {
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
    return OilChangeAgreedTotal.checkoutTotalFils(
      agreedFils: _parseFils(_agreed),
      cardGrandFils: _cardGrandTotalFils(),
      manuallyEdited: _agreedTotalManual,
    );
  }

  /// بعد تحميل البنود: إن كان المتفق عليه ناقصاً (فلتر بلا إجمالي) أعد الحساب.
  void _reconcileAgreedAfterHydrate() {
    final card = _cardGrandTotalFils();
    final agreed = _parseFils(_agreed);
    _agreedTotalManual = OilChangeAgreedTotal.isManualOnHydration(
      agreedFils: agreed > 0 ? agreed : null,
      cardGrandFils: card,
    );
    if (!_agreedTotalManual) {
      _recalculateOilTotal();
    }
  }

  int _oilCheckoutPaidFils() {
    final paid = _parseFils(_advance);
    final total = _oilCheckoutTotalFils();
    if (total > 0 && paid > total) return total;
    if (paid < 0) return 0;
    return paid;
  }

  bool get _usesWarehouseOilPicker => _stockFromWarehouseEnabled && !_oilCustomerProvided;

  bool get _showCatalogOilFields => !_oilCustomerProvided && !_usesWarehouseOilPicker;

  static int _oilFamilyKey(OilPickLine line) => line.parentProductId ?? -line.linkedProductId;

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
    return _oilStockPickLines.where((l) => _oilFamilyKey(l) == key).toList()
      ..sort((a, b) => a.viscosity.toLowerCase().compareTo(b.viscosity.toLowerCase()));
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
    if (_oilStockPickLines.isEmpty) return;
    final pid = _oilStockProductId;
    if (pid != null && pid > 0) {
      for (final line in _oilStockPickLines) {
        if (line.linkedProductId == pid) {
          _selectedOilFamilyKey = _oilFamilyKey(line);
          _oilType.text = line.parentName;
          _selectedViscosity = line.viscosity.isEmpty ? null : line.viscosity;
          _oilPickSellPerLiter = line.sellPerLiterIqd;
          return;
        }
      }
    }
    // جلب اللوحة: البطاقة السابقة بلا رقم صنف (أو دُمجت دون استبدال) —
    // نطابق بالاسم واللزوجة حتى تُختار عائلة الزيت تلقائياً.
    if (_oilCustomerProvided) return;
    final line = matchOilPickLineByName(_oilStockPickLines, name: _oilType.text, viscosity: _selectedViscosity);
    if (line == null) return;
    _selectedOilFamilyKey = _oilFamilyKey(line);
    final sameViscosity = line.viscosity.trim().toLowerCase() == (_selectedViscosity ?? '').trim().toLowerCase();
    if (sameViscosity) {
      _oilStockProductId = line.linkedProductId;
      _oilPickSellPerLiter = line.sellPerLiterIqd;
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
      AppLogger.error('ServiceOrderForm', 'loadOilStockMeta failed', e, st);
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
    if (pid == null || pid <= 0) {
      if (mounted) setState(() => _oilAvailableLiters = 0);
      return;
    }
    try {
      final q = await OilChangeStockService.instance.availableLiters(productId: pid, warehouseId: wid ?? 0);
      if (mounted) setState(() => _oilAvailableLiters = q);
    } catch (_) {}
  }

  bool _effectiveHydraulicCustomerProvidedFor(OilChangeHydraulicCardSlot slot) =>
      !_hydraulicStockEnabledFor(slot) || slot.customerProvided;

  bool _usesWarehouseHydraulicPickerFor(OilChangeHydraulicCardSlot slot) =>
      _hydraulicStockEnabledFor(slot) && !slot.customerProvided;

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
    if (_hydraulicFluidUserEditedFor(slot) || _shouldBlockFluidReconcileAfterPrefill()) {
      return;
    }
    final pid = slot.stockProductId;
    if (pid == null || pid <= 0 || _hydraulicStockPickLines.isEmpty) return;
    for (final line in _hydraulicStockPickLines) {
      if (line.linkedProductId == pid) {
        slot.selectedFamilyKey = _oilFamilyKey(line);
        slot.type.text = line.parentName;
        slot.selectedGrade = line.viscosity.isEmpty ? null : line.viscosity;
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
      final lines = await OilChangeStockService.instance.listHydraulicPickLines();
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
      if (_powerHydraulic.stockProductId != null && _powerHydraulic.warehouseId != null) {
        await _refreshHydraulicAvailableLitersFor(_powerHydraulic);
      }
    } catch (e, st) {
      AppLogger.error('ServiceOrderForm', 'loadHydraulicStockMeta failed', e, st);
      if (mounted) {
        setState(() {
          _hydraulicStockPickLinesLoading = false;
          _hydraulicStockPickLines = const [];
        });
      }
    }
  }

  Future<void> _refreshHydraulicAvailableLitersFor(OilChangeHydraulicCardSlot slot) async {
    final pid = slot.stockProductId;
    final wid = slot.warehouseId;
    if (pid == null || pid <= 0) {
      if (mounted) setState(() => slot.availableLiters = 0);
      return;
    }
    try {
      final q = await OilChangeStockService.instance.availableLiters(productId: pid, warehouseId: wid ?? 0);
      if (mounted) setState(() => slot.availableLiters = q);
    } catch (_) {}
  }

  Future<void> _loadOilCatalog() async {
    try {
      final results = await Future.wait([
        OilChangeSettings.loadCardSettings(),
        OilChangeServicesRepository.instance.listActive(),
      ]);
      final base = (results[0] as OilChangeCardSettings).baseOilChangePriceFils;
      final list = results[1] as List<OilChangeServiceItem>;
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
      final list = await OilChangeOilCatalogRepository.instance.listActive();
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

  /// اشتقاق القوائم يفرز الكتالوج ويزيل المكرر؛ كان يتكرّر ~15 مرة في كل
  /// إعادة بناء. الكتالوجات تُستبدل بقائمة جديدة عند التحميل، فالمقارنة
  /// بالهوية كافية لإبطال المخزون المؤقت.
  List<String> get _oilBrandDropdownItems {
    if (!identical(_oilBrandItemsSource, _oilProductCatalog)) {
      _oilBrandItemsSource = _oilProductCatalog;
      _oilBrandItemsCache = OilChangeOilCatalogRepository.brandNamesFrom(_oilProductCatalog);
    }
    return _oilBrandItemsCache;
  }

  List<OilChangeOilCatalogEntry> get _oilViscosityDropdownEntries {
    final brand = _selectedOilBrand;
    if (brand == null || brand.isEmpty) return const [];
    if (!identical(_oilViscosityEntriesSource, _oilProductCatalog) || _oilViscosityEntriesBrand != brand) {
      _oilViscosityEntriesSource = _oilProductCatalog;
      _oilViscosityEntriesBrand = brand;
      _oilViscosityEntriesCache = OilChangeOilCatalogRepository.entriesForBrand(_oilProductCatalog, brand);
    }
    return _oilViscosityEntriesCache;
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
    final entries = OilChangeOilCatalogRepository.entriesForBrand(_oilProductCatalog, brand);
    return entries.length == 1 ? entries.first : null;
  }

  void _applyCatalogOilEntryFromReconcile(OilChangeOilCatalogEntry entry) {
    _selectedOilBrand = entry.brandName;
    _assignControllerText(_oilType, entry.brandName);
    _selectedViscosity = entry.viscosity;
    _catalogSellPerLiterFils = entry.sellPerLiterFils;
  }

  void _reconcileOilCatalogSelection() {
    if (_oilCustomerProvided) return;
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
          _oilSizeAmount.text = formatOilVolumeDisplay((liters * 1000).round());
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
      final entries = OilChangeOilCatalogRepository.entriesForBrand(_oilProductCatalog, brand);
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
    if (_agreedTotalManual) return;
    final total = _cardGrandTotalFils();
    _syncingAgreed = true;
    try {
      _agreed.text = _formatIqdWhole(total);
    } finally {
      _syncingAgreed = false;
    }
    if (!_advanceManuallyEdited) {
      _lastAutoSyncedTotalFils = total;
      _syncAdvanceFromTotal(total);
    }
  }

  Future<void> _loadHydraulicProductCatalog() async {
    final firstLoad = _hydraulicProductCatalog.isEmpty;
    if (firstLoad && mounted) {
      setState(() => _hydraulicProductCatalogLoading = true);
    }
    try {
      final list = await OilChangeHydraulicCatalogRepository.instance.listActive();
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
    return _filterSlotsByCode.putIfAbsent(kind.code, OilChangeFilterSlot.new);
  }

  Future<void> _loadFilterProductCatalog() async {
    if (mounted) setState(() => _filterProductCatalogLoading = true);
    try {
      final loaded = await OilChangeFilterKindsRepository.instance.listActive();
      final kinds = loaded.isEmpty ? List<OilChangeFilterKind>.from(OilChangeFilterKind.builtins) : loaded;
      _filterSourceChanged = false;
      final List<OilChangeFilterCatalogEntry> resolved;
      if (_filtersStockEnabled) {
        resolved = await OilFilterStockCatalog.load(kinds);
      } else {
        final list = await OilChangeFilterCatalogRepository.instance.listActive();
        resolved = [for (final e in list) e.withResolvedKind(kinds)];
      }
      if (!mounted) return;
      setState(() {
        _filterKinds = kinds;
        _filterProductCatalog = resolved;
        _filterProductCatalogLoading = false;
        _reconcileAllFilterSelections();
      });
    } catch (_) {
      if (mounted) setState(() => _filterProductCatalogLoading = false);
    }
  }

  void _reconcileFilterSelectionFor(OilChangeFilterKind kind) {
    final slot = _filterSlotFor(kind);
    if (slot.customerProvided) return;
    if (_filtersStockEnabled) {
      // مصدر المخزون: يُطابَق بالصنف فقط. فلتر محفوظ بالاسم (معلّقة قديمة)
      // يبقى تلميحاً ويُطلب اختياره من المخزون قبل البيع.
      final pid = slot.productId;
      slot.catalogEntryId = null;
      if (pid == null || pid <= 0) return;
      for (final e in OilChangeFilterCatalogRepository.entriesForKind(_filterProductCatalog, kind)) {
        if (e.productId == pid) {
          slot.catalogEntryId = e.id;
          return;
        }
      }
      return;
    }
    final id = slot.catalogEntryId;
    if (id != null && id > 0) {
      final entry = OilChangeFilterCatalogRepository.entryById(_filterProductCatalog, id);
      if (entry == null || entry.kind.code != kind.code) {
        slot.catalogEntryId = null;
      } else {
        slot.applyEntry(entry);
        return;
      }
    }
    final name = (slot.name ?? '').trim();
    if (name.isEmpty) return;
    for (final e in OilChangeFilterCatalogRepository.entriesForKind(_filterProductCatalog, kind)) {
      if (e.name.toLowerCase() == name.toLowerCase()) {
        slot.applyEntry(e);
        return;
      }
    }
  }

  void _reconcileAllFilterSelections() {
    for (final kind in _filterKinds) {
      _reconcileFilterSelectionFor(kind);
    }
  }

  int _filtersTotalFils() {
    var total = 0;
    for (final kind in _filterKinds) {
      final slot = _filterSlotFor(kind);
      if (!slot.hasSelection) continue;
      total += slot.customerProvided ? _filterLaborFilsFor(slot) : slot.priceFils;
    }
    return total;
  }

  String? _filterTypeSummaryForSave() {
    final parts = <String>[];
    for (final kind in _filterKinds) {
      final slot = _filterSlotFor(kind);
      if (!slot.hasSelection) continue;
      final line = oilFilterLineLabel(kindLabel: kind.label, name: slot.name ?? '', priceFils: slot.priceFils);
      if (line != null) parts.add(line);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<OilFilterLineData> _oilFilterLinesForSave() {
    final out = <OilFilterLineData>[];
    for (final kind in _filterKinds) {
      final slot = _filterSlotFor(kind);
      if (!slot.hasSelection) continue;
      out.add(
        OilFilterLineData(
          code: kind.code,
          name: (slot.name ?? '').trim(),
          priceFils: slot.priceFils,
          catalogEntryId: slot.catalogEntryId,
          label: kind.label,
          customerProvided: slot.customerProvided,
          laborFils: slot.customerProvided ? _filterLaborFilsFor(slot) : 0,
          productId: slot.customerProvided ? null : slot.productId,
          qty: slot.customerProvided ? 1 : slot.qty,
          stockVoucherId: slot.customerProvided ? null : slot.stockVoucherId,
        ),
      );
    }
    return out;
  }

  String? _oilFiltersJsonForSave() {
    final lines = _oilFilterLinesForSave();
    if (lines.isEmpty) return null;
    return encodeOilFiltersJson(lines);
  }

  void _loadFiltersFromRow(Map<String, dynamic> row) {
    for (final slot in _filterSlotsByCode.values) {
      slot.clear();
    }
    final lines = oilFilterLinesDataFromRow(row);
    if (lines.isNotEmpty) {
      for (final line in lines) {
        final slot = _filterSlotsByCode.putIfAbsent(line.code, OilChangeFilterSlot.new);
        slot.catalogEntryId = line.catalogEntryId;
        slot.name = line.name.isEmpty ? null : line.name;
        slot.priceFils = line.priceFils;
        slot.customerProvided = line.customerProvided;
        slot.laborCardFils = line.customerProvided ? line.laborFils : null;
        slot.productId = line.productId;
        slot.qty = line.qty < 1 ? 1 : line.qty;
        slot.unitPriceFils = line.priceFils ~/ slot.qty;
        slot.stockVoucherId = line.stockVoucherId;
      }
    } else {
      for (final kind in OilChangeFilterKind.builtins) {
        _filterSlotFor(kind).loadFromRow(row, nameKey: kind.nameColumnKey, priceKey: kind.priceColumnKey);
      }
    }
    final hasAny = _filterSlotsByCode.values.any((s) => s.hasSelection);
    if (!hasAny) {
      final legacy = (row['filterType'] ?? '').toString().trim();
      if (legacy.isNotEmpty) {
        final slot = _filterSlotFor(OilChangeFilterKind.engine);
        slot.name = legacy;
        slot.priceFils = 0;
      }
    }
    _reconcileAllFilterSelections();
    _expandOptionalSectionsFromData();
  }

  List<String> get _hydraulicBrandDropdownItems {
    if (!identical(_hydraulicBrandItemsSource, _hydraulicProductCatalog)) {
      _hydraulicBrandItemsSource = _hydraulicProductCatalog;
      _hydraulicBrandItemsCache = OilChangeHydraulicCatalogRepository.brandNamesFrom(_hydraulicProductCatalog);
    }
    return _hydraulicBrandItemsCache;
  }

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

  bool _usesCatalogHydraulicPricingFor(OilChangeHydraulicCardSlot slot) => (slot.catalogSellPerLiterFils ?? 0) > 0;

  bool get _usesCatalogOilPricing => _catalogSellPerLiterFils != null && _catalogSellPerLiterFils! > 0;

  bool get _showOilVolumeStepper {
    if (_oilCustomerProvided) return true;
    if (_usesCatalogOilPricing) return true;
    if (_showCatalogOilFields && _oilBrandDropdownValue != null && _oilViscosityDropdownValue != null) {
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
    final ml = parseOilVolumeDisplay(slot.sizeAmount.text);
    if (ml <= 0) return 0;
    if (slot.customerProvided) return 0;
    if (_usesWarehouseHydraulicPickerFor(slot)) {
      if ((slot.stockProductId ?? 0) <= 0) return 0;
      final sell = _selectedHydraulicSellPerLiterIqdFor(slot);
      if (sell == null || sell <= 0) return 0;
      return sellFilsForVolumeMl(sellPerLiterFils: IqdMoney.toFils(sell), milliliters: ml);
    }
    if (_usesCatalogHydraulicPricingFor(slot)) {
      return sellFilsForVolumeMl(sellPerLiterFils: slot.catalogSellPerLiterFils!, milliliters: ml);
    }
    return 0;
  }

  int _cardGrandTotalFils() =>
      _oilServicesTotalFils() +
      _oilMaterialSellFilsEst() +
      _hydraulicMaterialSellFilsEstFor(_gearHydraulic) +
      _hydraulicMaterialSellFilsEstFor(_powerHydraulic) +
      _hydraulicLaborFilsFor(_gearHydraulic) +
      _hydraulicLaborFilsFor(_powerHydraulic) +
      _filtersTotalFils() +
      _oilProductLinesTotalFils() +
      _notesExtrasFils;

  String? _hydraulicSizeValueForSaveFor(OilChangeHydraulicCardSlot slot) => slot.sizeValueForSave(
    usesWarehousePicker: _usesWarehouseHydraulicPickerFor(slot),
    effectiveCustomerProvided: _effectiveHydraulicCustomerProvidedFor(slot),
  );

  /// كانت تقترح «الحالية + 5000» تلقائياً — أُوقفت بطلب المستخدم.
  void _parseOilSize(String? stored) {
    if (stored == null || stored.trim().isEmpty) {
      _oilSizeAmount.clear();
      return;
    }
    final raw = stored.trim();
    if (raw == 'Q') {
      // قيمة قديمة بلا رقم — تجاهل.
      _oilSizeAmount.clear();
      return;
    }
    final ml = oilSizeStoredToMilliliters(raw);
    if (ml > 0) {
      _oilSizeAmount.text = formatOilVolumeDisplay(ml);
      return;
    }
    _oilSizeAmount.clear();
  }

  void _applyVehicleRecord(
    Map<String, dynamic> r, {
    required bool replaceAll,
    bool skipOilAndHydraulic = false,
    bool skipHydraulicGear = false,
    bool skipHydraulicPower = false,
    // زيارة جديدة من سجل سابق: لا تُنسخ قراءات العداد والملاحظات والخدمات
    // والفني؛ تخص الزيارة السابقة لا هذه.
    bool newVisit = false,
    // من اللوحة: السيارة قد تُباع، فلا يُنسخ اسم صاحبها السابق ولا هاتفه.
    bool fillCustomer = true,
  }) {
    void textCtrl(TextEditingController c, String key) {
      final v = (r[key] ?? '').toString();
      if (replaceAll || c.text.trim().isEmpty) {
        _assignControllerText(c, v);
      }
    }

    // الزيارة تحفظ +964، والحقل يقبل 07 فقط. نحوّل قبل العرض حتى ينجح الحفظ.
    void assignStoredPhone() {
      final stored = (r['customerPhone'] ?? '').toString();
      if (!replaceAll && !_customerPhoneIsBlank) return;
      _setCustomerPhoneField(stored);
    }

    _applyingVehicleRecord = true;
    try {
      if (!fillCustomer) {
        // لا شيء: الزبون يُختار أو يُكتب، لا يُستنتج من اللوحة.
      } else if (replaceAll) {
        _customerId = (r['customerId'] as num?)?.toInt();
        textCtrl(_customerName, 'customerNameSnapshot');
        assignStoredPhone();
      } else {
        if (_customerId == null) {
          final cid = (r['customerId'] as num?)?.toInt();
          if (cid != null && cid > 0) _customerId = cid;
        }
        textCtrl(_customerName, 'customerNameSnapshot');
        assignStoredPhone();
      }

      textCtrl(_deviceName, 'deviceName');
      textCtrl(_carModel, 'carModel');
      _normalizeCarModelDisplay();
      // البحث باللوحة لا يغيّر اللوحة المكتوبة (قد تكون أكمل من القديمة).
      if (fillCustomer) textCtrl(_deviceSerial, 'deviceSerial');
      textCtrl(_engineSize, 'engineSize');
      // السيارة تتذكّر وحدة عدادها (كم أو ميل) من آخر زيارة.
      _odometerUnit = OilOdometerUnit.of(r);
      if (newVisit) {
        final prev = _odometerDigits((r['odometerCurrent'] ?? '').toString());
        _previousVisitOdometer = prev.isEmpty ? null : prev;
        _previousOdometerUnit = _odometerUnit;
        _previousOdometerAt = (r['createdAt'] ?? '').toString();
        _odometerLowerThanPrevious = _computeOdometerLower();
      } else if (!widget.isEdit) {
        if (replaceAll || _odometerDigits(_odometerCurrent.text).isEmpty) {
          _assignOdometerText(_odometerCurrent, (r['odometerCurrent'] ?? '').toString());
        }
        final nextOdo = (r['odometerNext'] ?? '').toString();
        if (replaceAll || _odometerDigits(_odometerNext.text).isEmpty) {
          _assignOdometerText(_odometerNext, nextOdo);
        }
      }
      if (!skipOilAndHydraulic) {
        textCtrl(_oilType, 'oilType');
        if (replaceAll) {
          _oilCustomerProvided = ((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
          if (!_stockFromWarehouseEnabled) {
            _oilStockProductId = null;
            _oilWarehouseId = null;
            _oilLitersStock.clear();
          } else {
            _oilStockProductId = (r['oilProductId'] as num?)?.toInt();
            _oilWarehouseId = (r['oilWarehouseId'] as num?)?.toInt();
            final liters = (r['oilLitersUsed'] as num?)?.toDouble();
            if (liters != null && liters > 0) {
              _oilLitersStock.text = liters % 1 == 0 ? liters.toInt().toString() : liters.toString();
            }
          }
        }
        if (replaceAll || _selectedViscosity == null) {
          final vis = r['oilViscosity']?.toString();
          _selectedViscosity = vis == null || vis.isEmpty ? null : vis;
        }
        if (replaceAll || _oilSizeAmount.text.trim().isEmpty) {
          _parseOilSize(r['oilSize']?.toString());
          if (_oilSizeAmount.text.trim().isEmpty) {
            final liters = (r['oilLitersUsed'] as num?)?.toDouble();
            if (liters != null && liters > 0) {
              _oilSizeAmount.text = formatOilVolumeDisplay((liters * 1000).round());
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
          _gearHydraulic.loadFromRow(r, stockEnabled: _gearHydraulicStockEnabled);
        }
        if (!skipHydraulicPower) {
          _powerHydraulic.loadFromRow(r, stockEnabled: _powerHydraulicStockEnabled);
        }
      }
      if (!newVisit) {
        textCtrl(_technicianName, 'technicianName');
        textCtrl(_issue, 'issueDescription');
      }
      if (replaceAll) {
        _loadFiltersFromRow(r);
      }

      if (replaceAll) {
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((r['estimatedPriceFils'] as num?)?.toInt() ?? 0),
        );
        final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
        _syncingAgreed = true;
        try {
          _agreed.text = agreedF == null ? '' : _formatIqdWhole(agreedF);
        } finally {
          _syncingAgreed = false;
        }
        _advance.text = _formatAdvanceIqd((r['advancePaymentFils'] as num?)?.toInt() ?? 0);
        _serviceId = (r['serviceId'] as num?)?.toInt();
        if (!newVisit) {
          final req = parseOilRequestedServices(r['requestedServices']?.toString());
          _selectedOilServiceIds.clear();
          _matchServiceNamesToIds(req);
        }
      } else {
        if (_agreed.text.trim().isEmpty) {
          final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
          if (agreedF != null) {
            _syncingAgreed = true;
            try {
              _agreed.text = _formatIqdWhole(agreedF);
            } finally {
              _syncingAgreed = false;
            }
          }
        }
        if (!newVisit && _selectedOilServiceIds.isEmpty) {
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
          if (_estimated.text.trim().isEmpty || _estimated.text.trim() == '0') {
            final sp = (row['sellPrice'] as num?)?.toDouble() ?? 0.0;
            _estimated.text = IraqiCurrencyFormat.formatDecimal2(sp);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDefaultPlateProvince() async {
    try {
      final p = await OilChangeSettings.getDefaultPlateProvince();
      if (mounted && p != null) setState(() => _defaultPlateProvince = p);
    } catch (_) {}
  }

  /// اللوحة الكاملة جديدة وفي السجل سيارة بالرقم نفسه بلا حرف ولا محافظة:
  /// يُسأل الموظف مرة. يرجع آخر زيارة للسيارة المختارة، أو null.
  Future<Map<String, dynamic>?> _askLegacyPlateMatch(String plate) async {
    final key = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (key.isEmpty || _declinedLegacyPlates.contains(key)) return null;
    if (_adoptPlateKey == key && _adoptVehicleGid != null) {
      return OilChangeOrdersRepository.instance.getLatestOilChangeForVehicle(_adoptVehicleGid!);
    }
    final candidates = await OilChangeOrdersRepository.instance.legacyVehicleCandidates(plate);
    if (candidates.isEmpty || !mounted) return null;
    final gid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('هل هي سيارة مسجّلة؟'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'في السجل سيارة بالرقم نفسه كُتبت لوحتها بلا حرف ولا محافظة. '
                'إن كانت هي، تُكمَّل لوحتها إلى «$plate» وتبقى زياراتها معاً.',
              ),
              const SizedBox(height: 8),
              for (final v in candidates)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    key: Key('legacyPlate_${v['global_id']}'),
                    title: Text(
                      [
                        (v['plate_display'] ?? '').toString(),
                        (v['name'] ?? '').toString(),
                      ].where((s) => s.trim().isNotEmpty).join(' · '),
                      textDirection: TextDirection.rtl,
                    ),
                    subtitle: Text(
                      [
                        (v['customer_name'] ?? '').toString(),
                        arabicVisitsCount((v['visits_count'] as num?)?.toInt() ?? 0),
                      ].where((s) => s.trim().isNotEmpty).join(' · '),
                    ),
                    trailing: const Text('هي'),
                    onTap: () => Navigator.pop(ctx, (v['global_id'] ?? '').toString()),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('legacyPlateOther'),
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('سيارة أخرى'),
          ),
        ],
      ),
    );
    if (gid == null) return null;
    if (gid.isEmpty) {
      _declinedLegacyPlates.add(key);
      return null;
    }
    _adoptVehicleGid = gid;
    _adoptPlateKey = key;
    return OilChangeOrdersRepository.instance.getLatestOilChangeForVehicle(gid);
  }

  Future<void> _syncVehicleFromPlate({
    bool showFeedback = false,
    bool overwriteExisting = false,
    bool force = false,
    // عند انتهاء كتابة الرقم فقط: لا يُفتح سؤال وسط الكتابة.
    bool askLegacy = false,
  }) async {
    if (widget.isEdit) return;
    final plate = _deviceSerial.text.trim();
    if (plate.length < 3) return;
    final plateKey = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (!force && plateKey.isNotEmpty && plateKey == _lastAutoSyncedPlate) {
      return;
    }
    await _applyLastVisitFromRepository(
      fetch: () async {
        final exact = await OilChangeOrdersRepository.instance.getLatestOilChangeByPlate(plate);
        if (exact != null || !askLegacy) return exact;
        return _askLegacyPlateMatch(plate);
      },
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

  Future<void> _syncVehicleFromCustomer(int customerId, {String? fallbackName}) async {
    if (widget.isEdit || customerId <= 0) return;
    if (_blocksAutoVisitLookup()) return;
    final customerKey = 'id:$customerId';
    if (customerKey == _lastAutoSyncedCustomerKey) return;

    // سيارات العميل من السجل: أكثر من واحدة = يختار الموظف (لا تعبئة)،
    // واحدة = آخر زيارة لها هي (لا لسيارة باعها).
    var vehicles = const <Map<String, dynamic>>[];
    try {
      vehicles = await OilChangeOrdersRepository.instance.vehiclesForCustomer(customerId);
    } catch (_) {}
    if (!mounted || _customerId != customerId) return;
    setState(() {
      _customerVehicles = vehicles.length >= 2 ? vehicles : const [];
      _customerVehiclesFor = customerId;
    });
    if (vehicles.length >= 2) {
      _lastAutoSyncedCustomerKey = customerKey;
      return;
    }

    await _applyLastVisitFromRepository(
      fetch: () async {
        if (vehicles.length == 1) {
          final own = await OilChangeOrdersRepository.instance.getLatestOilChangeForVehicle(
            (vehicles.single['global_id'] ?? '').toString(),
          );
          if (own != null) return own;
        }
        final byId = await OilChangeOrdersRepository.instance.getLatestOilChangeByCustomerId(customerId);
        if (byId != null) return byId;
        final name = (fallbackName ?? _customerName.text).trim();
        if (name.isEmpty) return null;
        return OilChangeOrdersRepository.instance.getLatestOilChangeByCustomerName(name);
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

  /// الموظف اختار سيارة من سيارات العميل: تُكتب لوحتها، والبحث باللوحة
  /// يجلب آخر زيارة لها كما لو كُتبت باليد.
  void _pickCustomerVehicle(Map<String, dynamic> v) {
    setState(() {
      _assignControllerText(_deviceName, (v['name'] ?? '').toString());
      _assignControllerText(_carModel, (v['model'] ?? '').toString());
      _assignControllerText(_engineSize, (v['engine_size'] ?? '').toString());
      _lastAutoSyncedPlate = null;
      _deviceSerial.text = (v['plate_display'] ?? '').toString();
    });
  }

  /// «سيارة جديدة»: العميل أحضر سيارة غير المسجّلة باسمه.
  void _pickNewCustomerVehicle() {
    setState(() {
      _deviceSerial.clear();
      _deviceName.clear();
      _carModel.clear();
      _engineSize.clear();
      _previousVisitOdometer = null;
      _previousOdometerAt = null;
      _odometerLowerThanPrevious = false;
      _odometerUnit = OilOdometerUnit.km;
      _previousOdometerUnit = OilOdometerUnit.km;
      _lastAutoSyncedPlate = null;
      // قائمة سيارات العميل تبقى ظاهرة: إخفاؤها كان يرفع كل الحقول تحتها
      // فيقع ما يُكتب في «القراءة اللاحقة» بدل اللوحة.
    });
  }

  void _applyLastVisitForNewCard(Map<String, dynamic> r, {bool fillCustomer = true}) {
    _applyVehicleRecord(r, replaceAll: true, newVisit: true, fillCustomer: fillCustomer);
    _reconcileOilFluidAfterVisitLoad(r);
    _advanceManuallyEdited = false;
    _agreedTotalManual = false;
    _recalculateOilTotal();
    if (_customerId != null && _customerId! > 0) {
      _linkedCustomerName = _customerName.text.trim();
    }
  }

  void _mergeLastVisitForNewCard(Map<String, dynamic> r, {bool fillCustomer = true}) {
    _applyVehicleRecord(
      r,
      replaceAll: false,
      fillCustomer: fillCustomer,
      skipOilAndHydraulic: _oilFluidUserEdited,
      skipHydraulicGear: _hydraulicGearUserEdited,
      skipHydraulicPower: _hydraulicPowerUserEdited,
      newVisit: true,
    );
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
    _vehicleSyncInFlight = true;
    try {
      final row = await fetch();
      if (!mounted) return;
      // بعد await: ألغِ التطبيق إن تغيّرت اللوحة/العميل (نتيجة متأخرة).
      if (onPlateApplied != null && onPlateApplied.trim().isNotEmpty) {
        final expected = onPlateApplied.trim();
        final currentKey = OilChangeLookupNormalize.normalizePlateKey(_deviceSerial.text.trim());
        if (currentKey != expected && _deviceSerial.text.trim() != expected) {
          return;
        }
      }
      if (onCustomerApplied != null && onCustomerApplied.trim().isNotEmpty) {
        final expected = onCustomerApplied.trim();
        if (expected.startsWith('id:')) {
          final id = int.tryParse(expected.substring(3));
          if (id != null && id > 0 && _customerId != id) return;
        } else {
          final nameKey = OilChangeLookupNormalize.normalizeNameKey(_customerName.text.trim());
          if (nameKey != expected && _customerName.text.trim() != expected) {
            return;
          }
        }
      }
      if (row == null) {
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notFoundMessage)));
        }
        return;
      }
      final catalogWasEmpty = _oilProductCatalog.isEmpty;
      // البحث باللوحة لا يملأ الزبون أبداً (قرار المرحلة 6).
      final fillCustomer = onPlateApplied == null;
      setState(() {
        if (widget.isOilNewCard) {
          if (overwriteExisting && !_oilFluidUserEdited) {
            _applyLastVisitForNewCard(row, fillCustomer: fillCustomer);
          } else {
            _mergeLastVisitForNewCard(row, fillCustomer: fillCustomer);
          }
        } else {
          final cid = (row['customerId'] as num?)?.toInt();
          final name = (row['customerNameSnapshot'] ?? '').toString().trim();
          _applyVehicleRecord(row, replaceAll: false, fillCustomer: fillCustomer);
          if (fillCustomer && cid != null && cid > 0 && _customerId == null) {
            _customerId = cid;
            if (name.isNotEmpty) {
              _customerName.text = name;
              _linkedCustomerName = name;
            }
          }
        }
      });
      if (widget.isOilNewCard && !_oilFluidUserEdited && catalogWasEmpty) {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(foundMessage)));
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
    }
    // لا تعبئة تلقائية بالاسم — الاختيار من قائمة الاقتراحات فقط.
  }

  bool get _oilEditCompletingSuspended => widget.isEdit && _status == OilChangeOrderStatus.suspended;

  /// بطاقة حُفظت مكتملة ولم يتم بيعها (تعذّر البيع عند الحفظ، كسقف الدين):
  /// تُباع من هنا كالمعلّقة.
  bool get _oilEditSellsUnbilled =>
      widget.isEdit && !widget.amendInvoicedOrder && _status == OilChangeOrderStatus.completed && !_editHasInvoice;

  /// زر الحفظ في التعديل يبيع أيضاً.
  bool get _oilEditOffersSale => _oilEditCompletingSuspended || _oilEditSellsUnbilled;

  bool get _oilCheckoutFinalized => !widget.amendInvoicedOrder && (_status == 'delivered' || _status == 'cancelled');

  void _onPlateFieldChanged() {
    if (widget.isEdit || _hydratingEdit || _applyingVehicleRecord) {
      return;
    }
    final plate = _deviceSerial.text.trim();
    if (plate.length < 3) {
      _lastAutoSyncedPlate = null;
      return;
    }
    if (widget.prefillFromOrder != null && _prefillPlateAtOpen != null && plate != _prefillPlateAtOpen) {
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
        // زيت + خدمات أولاً؛ فلاتر/هيدروليك تُحمَّل إن وُجدت بيانات أو عند التوسيع.
        await Future.wait([_loadOilCatalog(), _loadOilProductCatalog()]);
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
    // تعبئة سجل زيارة تكتب الاسم برمجياً؛ اعتبارها كتابة يدوية كان يفكّ ربط
    // العميل ويمسح هاتفه فور «جلب آخر زيارة».
    if (_applyingVehicleRecord) return;
    if (_customerId == null) return;
    final typed = _customerName.text.trim();
    if (_linkedCustomerName != null && typed == _linkedCustomerName) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _customerId = null;
      _linkedCustomerName = null;
      _resetCustomerPhonePrefix();
      _lastAutoSyncedCustomerKey = null;
    });
    unawaited(_refreshCustomerOpenDebt());
  }

  /// عند فتح بطاقة من السجل: ربط [customerId] تلقائياً من السجل أو الاسم أو الهاتف.
  Future<void> _resolveCustomerLinkFromPrefill(Map<String, dynamic> r) async {
    if (!widget.isOilNewCard || widget.isEdit) return;

    final snapshotName = (r['customerNameSnapshot'] ?? _customerName.text).toString().trim();
    final snapshotPhone = (r['customerPhone'] ?? _customerPhone.text).toString().trim();

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
          cid = await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(digits);
        }
      }

      if (cid == null && snapshotName.isNotEmpty) {
        cid = await _customersDb.tryResolveCustomerIdByExactName(snapshotName);
      }

      if (cid != null && cid > 0) {
        if (!mounted) return;
        final row = await _customersDb.getCustomerById(cid);
        final dbName = row != null ? (row['name'] ?? '').toString().trim() : snapshotName;
        setState(() {
          _customerId = cid;
          _linkedCustomerName = dbName.isNotEmpty ? dbName : snapshotName;
          if (dbName.isNotEmpty &&
              OilChangeLookupNormalize.normalizeNameKey(_customerName.text) !=
                  OilChangeLookupNormalize.normalizeNameKey(dbName)) {
            _assignControllerText(_customerName, dbName);
          }
          if (snapshotPhone.isNotEmpty && _customerPhoneIsBlank) {
            _setCustomerPhoneField(snapshotPhone);
          } else if (row != null) {
            final phone = (row['phone'] ?? '').toString().trim();
            if (phone.isNotEmpty && _customerPhoneIsBlank) {
              _setCustomerPhoneField(phone);
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
      // الفهرس نفسه الذي يغذّي الاقتراحات: كان هنا استعلام ثانٍ مطابق للاستعلام
      // الذي نفّذه حقل البحث قبل 310 مللي ثانية.
      await CustomerSearchIndex.instance.ensureFresh();
      final matches = CustomerSearchIndex.instance.searchRecords(q, limit: 24);
      CustomerRecord? exact;
      for (final c in matches) {
        if (OilChangeLookupNormalize.normalizeNameKey(c.name) == qKey) {
          exact = c;
          break;
        }
      }
      if (exact == null || !mounted) return false;
      final phone = exact.phone?.trim() ?? '';
      setState(() {
        _customerId = exact!.id;
        _linkedCustomerName = exact.name.trim();
        if (phone.isNotEmpty && _customerPhoneIsBlank) {
          _setCustomerPhoneField(phone);
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadOilProductLinesForOrder(String orderGlobalId) async {
    final og = orderGlobalId.trim();
    if (og.isEmpty) return;
    final rows = await OilChangeOrdersRepository.instance.getOilChangeItems(og);
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
  }

  /// لقطة السجل إن طابقت بطاقة التعديل — للفتح الفوري محلياً.
  Map<String, dynamic>? _warmEditPrefillRow() {
    if (!widget.isEdit) return null;
    final warm = widget.prefillFromOrder;
    if (warm == null) return null;
    final warmId = (warm['id'] as num?)?.toInt();
    if (warmId == null || warmId <= 0) return null;
    if (warmId != widget.editOrderId) return null;
    return Map<String, dynamic>.from(warm);
  }

  /// م4-1: ما قاله المستخدم للمساعد يملأ الحقول نفسها التي يكتبها بيده،
  /// فتعمل بعدها كل قواعد البطاقة (آخر زيارة باللوحة، تنبيه العدّاد، الزيت).
  void _applyAssistantPrefill(AssistantPrefill p) {
    final plate = p.str('plate');
    final customer = p.str('customer');
    final odo = p.number('odometer');
    final oil = p.str('oil');
    final liters = p.number('liters');
    final extras = p.list('extras');
    // ب7: طلب زيارة من واتساب يحمل رقم الزبون وسيارته كما كتبها.
    final phone = p.str('phone');
    final car = p.str('car');
    if (customer != null) _customerName.text = customer;
    if (phone != null) _setCustomerPhoneField(phone);
    if (car != null && _deviceName.text.trim().isEmpty) _deviceName.text = car;
    if (odo != null) _assignOdometerText(_odometerCurrent, '${odo.toInt()}');
    if (oil != null) {
      _oilType.text = oil;
      _markOilFluidUserEdited();
    }
    if (liters != null && liters > 0) _oilLitersStock.text = '$liters';
    if (extras.isNotEmpty) _issue.text = extras.join('، ');
    // اللوحة أخيراً: مستمعها يجلب آخر زيارة ويكمل الفارغ فقط.
    if (plate != null) _deviceSerial.text = plate;
  }

  void _seedPhoneBaselineFromRow(Map<String, dynamic> row) {
    if (_baselineCustomerPhoneLocked) return;
    _baselineCustomerPhoneDigits = _normalizedPhoneKey((row['customerPhone'] ?? _customerPhone.text).toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _baselineCustomerPhoneLocked) return;
      _baselineCustomerPhoneDigits = _normalizedPhoneKey(_customerPhone.text);
      _baselineCustomerPhoneLocked = true;
    });
  }

  /// يملأ حقول التعديل من صف محلي — بدون await.
  void _hydrateEditFieldsFromRow(Map<String, dynamic> row) {
    final svcId = (row['serviceId'] as num?)?.toInt();
    final edm = (row['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
    final h = edm > 0 ? edm ~/ 60 : 0;
    final m = edm > 0 ? edm % 60 : 0;

    _customerId = (row['customerId'] as num?)?.toInt();
    _customerName.text = (row['customerNameSnapshot'] ?? '').toString();
    _setCustomerPhoneField((row['customerPhone'] ?? '').toString());

    _deviceName.text = (row['deviceName'] ?? '').toString();
    _carModel.text = OilChangeLookupNormalize.toWesternDigits((row['carModel'] ?? '').toString());
    _deviceSerial.text = (row['deviceSerial'] ?? '').toString();
    _engineSize.text = (row['engineSize'] ?? '').toString();

    _odometerUnit = OilOdometerUnit.of(row);
    _assignOdometerText(_odometerCurrent, (row['odometerCurrent'] ?? '').toString());
    _assignOdometerText(_odometerNext, (row['odometerNext'] ?? '').toString());
    if (_odometerDigits(_odometerNext.text).isNotEmpty) {}
    _oilType.text = (row['oilType'] ?? '').toString();
    _selectedViscosity = row['oilViscosity']?.toString().isEmpty == true ? null : row['oilViscosity']?.toString();
    final catSell = (row['oilSellPerLiterFils'] as num?)?.toInt();
    _catalogSellPerLiterFils = catSell != null && catSell > 0 ? catSell : null;
    _reconcileOilCatalogSelection();
    _reconcileOilStockLineSelection();
    _parseOilSize(row['oilSize']?.toString());
    _loadFiltersFromRow(row);

    _status = (row['status'] ?? 'pending').toString();
    _editHasInvoice = ((row['invoiceId'] as num?)?.toInt() ?? 0) > 0;
    if (OilChangeOrderStatus.isSuspended(row)) {
      _allowAutoVisitLookup = false;
    }
    _serviceId = svcId;
    _estimated.text = IraqiCurrencyFormat.formatDecimal2(
      IqdMoney.fromFils((row['estimatedPriceFils'] as num?)?.toInt() ?? 0),
    );
    final agreedF = (row['agreedPriceFils'] as num?)?.toInt();
    _syncingAgreed = true;
    try {
      _agreed.text = agreedF == null ? '' : _formatIqdWhole(agreedF);
    } finally {
      _syncingAgreed = false;
    }
    final advF = (row['advancePaymentFils'] as num?)?.toInt() ?? 0;
    _advance.text = _formatAdvanceIqd(advF);
    _issue.text = (row['issueDescription'] ?? '').toString();
    _technicianName.text = (row['technicianName'] ?? '').toString();

    _workStartedAtUtc = DateTime.tryParse((row['workStartedAt'] ?? '').toString())?.toUtc();
    _etaHours = h;
    _etaMinutes = m;

    _matchServiceNamesToIds(parseOilRequestedServices(row['requestedServices']?.toString()));
    _advanceManuallyEdited = OilChangeAdvanceAutofill.isManualOnHydration(agreedFils: agreedF, advanceFils: advF);
    _oilCustomerProvided = ((row['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
    _oilStockProductId = (row['oilProductId'] as num?)?.toInt();
    _oilWarehouseId = (row['oilWarehouseId'] as num?)?.toInt();
    // null في البطاقات قبل الإصدار 51: الأجرة من الإعدادات.
    _oilLaborCardFils = (row['oilLaborFils'] as num?)?.toInt();
    final liters = (row['oilLitersUsed'] as num?)?.toDouble();
    if (liters != null && liters > 0) {
      _oilLitersStock.text = liters % 1 == 0 ? liters.toInt().toString() : liters.toString();
    }
    _editStockVoucherId = (row['stockVoucherId'] as num?)?.toInt();
    _editOilLitersUsed = liters ?? 0;
    _editOilProductId = _oilStockProductId;
    _editOilWarehouseId = _oilWarehouseId;
    _editOilCustomerProvided = _oilCustomerProvided;
    _editInvoiceId = (row['invoiceId'] as num?)?.toInt() ?? 0;
    _editFilterLines = oilFilterLinesDataFromRow(row);
    if (_stockFromWarehouseEnabled && _oilStockProductId != null && _oilWarehouseId != null) {
      unawaited(_refreshAvailableLiters());
    }
    if (_usesWarehouseOilPicker && _oilLitersStock.text.trim().isNotEmpty) {
      _syncOilSizeRecordFromStockLiters();
    }
    _gearHydraulic.loadFromRow(row, stockEnabled: _gearHydraulicStockEnabled);
    _powerHydraulic.loadFromRow(row, stockEnabled: _powerHydraulicStockEnabled);
    _reconcileHydraulicCatalogSelectionFor(_gearHydraulic);
    _reconcileHydraulicCatalogSelectionFor(_powerHydraulic);
    for (final slot in [_gearHydraulic, _powerHydraulic]) {
      if (!_hydraulicStockEnabledFor(slot)) continue;
      _reconcileHydraulicStockLineSelectionFor(slot);
      if (slot.stockProductId != null && slot.warehouseId != null) {
        unawaited(_refreshHydraulicAvailableLitersFor(slot));
      }
    }

    _applyOptionalExpansionFromData();
    if (_customerId != null && _customerId! > 0) {
      _linkedCustomerName = _customerName.text.trim();
    }
    _reconcileAgreedAfterHydrate();
  }

  /// كتالوجات ومخزون بعد ظهور النموذج — لا يحجب التعديل.
  Future<void> _loadEditSupportingData(Map<String, dynamic> row) async {
    try {
      await _loadFluidStockSettings(awaitStockLoads: false);
      await Future.wait([_loadOilCatalog(), _loadOilProductCatalog(), _loadFilterProductCatalog()]);
      if (!mounted) return;
      setState(() {
        _reconcileOilCatalogSelection();
        _reconcileOilStockLineSelection();
        _reconcileHydraulicCatalogSelectionFor(_gearHydraulic);
        _reconcileHydraulicCatalogSelectionFor(_powerHydraulic);
        for (final slot in [_gearHydraulic, _powerHydraulic]) {
          if (_hydraulicStockEnabledFor(slot)) {
            _reconcileHydraulicStockLineSelectionFor(slot);
          }
        }
        _applyOptionalExpansionFromData();
      });
      final svcId = (row['serviceId'] as num?)?.toInt();
      if (svcId != null && svcId > 0) {
        unawaited(_loadServiceProductIfNeeded());
      }
      final og = (row['global_id'] ?? row['globalId'] ?? '').toString().trim();
      if (og.isNotEmpty) {
        await _loadOilProductLinesForOrder(og);
      }
      if (!mounted) return;
      setState(_reconcileAgreedAfterHydrate);
    } catch (e, st) {
      AppLogger.error('OilChangeForm', 'edit supporting data', e, st);
    }
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
        r = await OilChangeOrdersRepository.instance.getOilChangeOrderById(widget.editOrderId!);
      }
      if (!mounted) return;
      if (r == null) throw StateError('not_found');
      final row = r;

      // أظهر النموذج فوراً من SQLite المحلي — الكتالوجات لاحقاً.
      setState(() {
        _hydrateEditFieldsFromRow(row);
        _hydratingEdit = false;
        _formBodyReady = true;
      });
      _seedPhoneBaselineFromRow(row);
      _markLeaveGateClean();
      _attachOilBarcodeHandler();
      unawaited(_loadEditSupportingData(row));
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
    final name = _customerName.text.trim();
    // تُستدعى من ستة مواضع، وقد تتزامن ثلاث مرات لاختيار عميل واحد.
    final requestKey = '${_customerId ?? 0}|$name';
    if (_openDebtRequestKey == requestKey && _customerOpenDebtLoading) return;
    _openDebtRequestKey = requestKey;
    if (mounted) setState(() => _customerOpenDebtLoading = true);
    try {
      final fils = await loadCustomerOpenDebtFils(customerId: _customerId, customerName: name);
      if (_openDebtRequestKey != requestKey) return; // سبقه طلب أحدث
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
        _setCustomerPhoneField(phone);
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
          style: success ? const TextStyle(color: SaleBrandColors.navy, fontWeight: FontWeight.w700) : null,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? SaleBrandColors.gold.withValues(alpha: 0.95) : Theme.of(context).colorScheme.error,
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
    if (orderId <= 0) return;
    var gid = (_orderGlobalId ?? '').trim();
    if (gid.isEmpty) {
      final row = await OilChangeOrdersRepository.instance.getOilChangeOrderById(orderId);
      gid = (row?['global_id'] ?? '').toString().trim();
    }
    if (gid.isEmpty) return;
    _orderGlobalId = gid;
    await OilChangeOrdersRepository.instance.replaceOilChangeItems(
      orderGlobalId: gid,
      lines: _oilProductLines
          .map(
            (l) => (productId: l.productId, productName: l.productName, quantity: l.quantity, priceFils: l.priceFils),
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
    if (raw.contains('الرصيد غير كافٍ') || raw.contains('رصيد غير كاف')) {
      return raw.replaceFirst('StateError: ', '').trim();
    }
    if (raw.contains('تعذّر صرف الزيت')) {
      return 'تعذّر صرف الزيت من المخزون. تحقق من الرصيد والمستودع.';
    }
    if (raw.contains('CHECK constraint failed') && raw.toLowerCase().contains('status')) {
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

  ({String customerName, String deviceName}) _oilSuspendSaveLabels(String plate) {
    final customer = _customerName.text.trim();
    final car = _deviceName.text.trim();
    return (customerName: customer.isEmpty ? '—' : customer, deviceName: car.isEmpty ? plate : car);
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
    final rec = await Navigator.of(
      context,
    ).push<CustomerRecord>(FastContentPageRoute(builder: (_) => const CustomerFormScreen()));
    if (!mounted || rec == null) return;
    CustomerSearchIndex.instance.invalidate();
    await _applyCustomerSelection(rec);
  }

  void _markLeaveGateClean() {
    _leaveGateCleanFingerprint = _leaveGateFingerprint();
  }

  Future<void> _confirmAndClearOilFormFields() async {
    if (_saving || _hydratingEdit || !widget.isNewCard) return;
    if (!_hasUnsavedOilDraft() &&
        _customerName.text.trim().isEmpty &&
        _deviceSerial.text.trim().isEmpty &&
        _odometerDigits(_odometerCurrent.text).isEmpty) {
      // لا شيء يُمسح — لا حوار بلا سبب.
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مسح الحقول'),
          content: const Text('هل تريد مسح كل حقول البطاقة؟ لا يمكن التراجع عن ذلك.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('مسح الكل')),
          ],
        ),
      ),
    );
    if (!mounted || ok != true) return;
    _clearAllOilFormFields();
  }

  void _clearAllOilFormFields() {
    _previousVisitOdometer = null;
    _previousOdometerAt = null;
    _odometerUnit = OilOdometerUnit.km;
    _previousOdometerUnit = OilOdometerUnit.km;
    _odometerLowerThanPrevious = false;
    _draftDone = false;
    unawaited(OilCardDraftStore.instance.clear());
    _plateVehicleSyncDebounce?.cancel();
    _notesMoneyDebounce?.cancel();
    _checkoutUiDebounce?.cancel();
    _notesMoneyAiGeneration++;

    _suspendCustomerIdClear = true;
    _applyingVehicleRecord = true;
    try {
      _customerName.clear();
      _resetCustomerPhonePrefix();
      _deviceName.clear();
      _carModel.clear();
      _deviceSerial.clear();
      _engineSize.clear();
      _odometerCurrent.clear();
      _odometerNext.clear();
      _oilType.clear();
      _oilSizeAmount.clear();
      _oilLitersStock.clear();
      _estimated.text = '0';
      _agreed.clear();
      _advance.text = '0';
      _issue.clear();
      _technicianName.clear();

      _customerId = null;
      _linkedCustomerName = null;
      _customerOpenDebtFils = 0;
      _customerOpenDebtLoading = false;
      _priorOpenDebtFilsAtCheckout = 0;

      _selectedViscosity = null;
      _selectedOilBrand = null;
      _selectedOilFamilyKey = null;
      _selectedOilServiceIds.clear();
      _oilProductLines.clear();
      _orderGlobalId = null;

      _oilLaborCardFils = null;
      _oilCustomerProvided = false;
      _oilStockProductId = null;
      _oilAvailableLiters = 0;
      _oilPickSellPerLiter = null;
      _catalogSellPerLiterFils = null;
      _basePriceFils = 0;

      _gearHydraulic.clear();
      _powerHydraulic.clear();
      for (final slot in _filterSlotsByCode.values) {
        slot.clear();
      }

      _notesExtrasFils = 0;
      _notesExtrasConfirmed = false;
      _notesExtrasDismissedKey = null;
      _notesMoneyPreview = OilNotesMoneyParseResult.empty;
      _notesMoneyLocalHint = OilNotesMoneyParseResult.empty;
      _notesMoneyAiLoading = false;
      _notesMoneyAiForText = null;

      _agreedTotalManual = false;
      _advanceManuallyEdited = false;
      _lastAutoSyncedTotalFils = null;
      _oilFluidUserEdited = false;
      _hydraulicGearUserEdited = false;
      _hydraulicPowerUserEdited = false;
      _expandedOptional
        ..clear()
        ..addAll([if (_isFieldRequired(OilCardField.oil)) _OilFormOptionalSection.oil]);

      _lastAutoSyncedPlate = null;
      _lastAutoSyncedCustomerKey = null;
      _prefillPlateAtOpen = null;
      _allowAutoVisitLookup = true;
      _vehicleSyncQueued = false;
      _error = null;
      _errorText = null;
      _status = 'pending';
    } finally {
      _suspendCustomerIdClear = false;
      _applyingVehicleRecord = false;
    }

    if (!mounted) return;
    setState(() {});
    _markLeaveGateClean();
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('تم مسح كل الحقول'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// المبلغ يُملأ تلقائياً بصفر — فليس تعديلاً من الموظف يستدعي تحذير المغادرة.
  String _agreedForLeaveGate() {
    final agreed = _agreed.text.trim();
    return RegExp(r'^[0.,]*$').hasMatch(agreed) ? '' : agreed;
  }

  String _leaveGateFingerprint() {
    final filterSig = _filterSlotsByCode.entries
        .where((e) => e.value.hasSelection)
        .map((e) => '${e.key}:${e.value.catalogEntryId ?? e.value.name}')
        .join(',');
    final productsSig = _oilProductLines.map((l) => '${l.productId}:${l.quantity}').join(',');
    return [
      _customerName.text.trim(),
      _customerPhone.text.trim(),
      _deviceName.text.trim(),
      _deviceSerial.text.trim(),
      _carModel.text.trim(),
      _engineSize.text.trim(),
      _odometerDigits(_odometerCurrent.text),
      _odometerDigits(_odometerNext.text),
      _odometerUnit,
      _oilType.text.trim(),
      _issue.text.trim(),
      _technicianName.text.trim(),
      _agreedForLeaveGate(),
      (_customerId ?? 0).toString(),
      filterSig,
      productsSig,
      _oilCustomerProvided ? '1' : '0',
      (_oilStockProductId ?? 0).toString(),
      _oilSizeAmount.text.trim(),
      _oilLitersStock.text.trim(),
      // الخدمات، اللزوجة، الهيدروليك، والمبلغ المستلم: تغييرها يستحق التحذير.
      (_selectedOilServiceIds.toList()..sort()).join(','),
      _selectedViscosity ?? '',
      _hydraulicLeaveSig(_gearHydraulic),
      _hydraulicLeaveSig(_powerHydraulic),
      _advanceForLeaveGate(),
    ].join('\u{1e}');
  }

  String _hydraulicLeaveSig(OilChangeHydraulicCardSlot slot) => [
    slot.type.text.trim(),
    slot.selectedGrade ?? '',
    slot.litersForPricing().toStringAsFixed(2),
    (slot.stockProductId ?? 0).toString(),
    slot.customerProvided ? '1' : '0',
  ].join('|');

  /// المستلم يبدأ بصفر تلقائياً — مثل [_agreedForLeaveGate].
  String _advanceForLeaveGate() {
    final adv = _advance.text.trim();
    return RegExp(r'^[0.,]*$').hasMatch(adv) ? '' : adv;
  }

  bool _hasUnsavedOilDraft() {
    if (_leaveGateAllowPop) return false;
    if (_hydratingEdit || !_formBodyReady) return false;
    final clean = _leaveGateCleanFingerprint;
    if (clean == null) {
      // بطاقة جديدة قبل تثبيت البصمة: أي إدخال جوهري = مسودة.
      return _customerName.text.trim().isNotEmpty ||
          !_customerPhoneIsBlank ||
          _deviceName.text.trim().isNotEmpty ||
          _deviceSerial.text.trim().isNotEmpty ||
          _carModel.text.trim().isNotEmpty ||
          _odometerDigits(_odometerCurrent.text).isNotEmpty ||
          _issue.text.trim().isNotEmpty ||
          _oilProductLines.isNotEmpty ||
          _filterSlotsByCode.values.any((s) => s.hasSelection);
    }
    return _leaveGateFingerprint() != clean;
  }

  Future<bool> _confirmLeaveOilFormIfDirty() async {
    if (!_hasUnsavedOilDraft()) return true;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('بيانات غير محفوظة'),
          content: Text(
            widget.isEdit
                ? 'عدّلت البطاقة ولم تُحفظ بعد. هل تريد المغادرة وفقدان التعديل؟'
                : 'البطاقة لم تُحفظ بعد. تبقى مسودة على هذا الجهاز وتُعرض عند '
                      'فتح بطاقة جديدة.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('البقاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مغادرة')),
          ],
        ),
      ),
    );
    return leave == true;
  }

  bool _hydraulicSlotHasData(OilChangeHydraulicCardSlot slot) {
    return slot.type.text.trim().isNotEmpty ||
        (slot.selectedGrade ?? '').trim().isNotEmpty ||
        slot.litersForPricing() > 1e-9 ||
        (slot.stockProductId ?? 0) > 0 ||
        slot.customerProvided;
  }

  void _applyOptionalExpansionFromData() {
    if (_oilSectionHasData()) {
      _expandedOptional.add(_OilFormOptionalSection.oil);
    }
    if (_oilProductLines.isNotEmpty) {
      _expandedOptional.add(_OilFormOptionalSection.products);
    }
    if (_filterKinds.any((k) => _filterSlotFor(k).hasSelection)) {
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
    _ensureDeferredCatalogsForExpanded();
  }

  /// تحميل فلاتر/هيدروليك فقط عند الحاجة (توسيع أو بيانات موجودة).
  void _ensureDeferredCatalogsForExpanded() {
    final needFilters = _expandedOptional.contains(_OilFormOptionalSection.filters);
    final needHydraulic =
        _expandedOptional.contains(_OilFormOptionalSection.hydraulicGear) ||
        _expandedOptional.contains(_OilFormOptionalSection.hydraulicPower);
    if (needFilters && _filterProductCatalog.isEmpty && !_filterProductCatalogLoading) {
      unawaited(_loadFilterProductCatalog());
    }
    if (needHydraulic && _hydraulicProductCatalog.isEmpty && !_hydraulicProductCatalogLoading) {
      unawaited(_loadHydraulicProductCatalog());
    }
  }

  void _expandOptionalSectionsFromData() {
    setState(_applyOptionalExpansionFromData);
  }

  @override
  void dispose() {
    AssistantScreenContext.pop(AssistantContextItem(kind: 'oil_card', id: widget.editOrderId ?? 0, label: 'البطاقة التي تعدّلها'));
    _draftTimer?.cancel();
    _guideListenable?.removeListener(_onGuideControllerChanged);
    _guideListenable = null;
    _customerName.removeListener(_onCustomerNameTyped);
    _customerPhone.removeListener(_onCustomerPhoneForReminder);
    _customerPhone.removeListener(_onCustomerPhoneForLink);
    _customerName.dispose();
    _customerFocus.dispose();
    _customerPhone.dispose();

    _deviceName.dispose();
    _carModel.dispose();
    _deviceSerial.dispose();
    _engineSize.dispose();

    _odometerNext.removeListener(_onOdometerNextTyped);
    _agreed.removeListener(_onAgreedManualEdit);
    _advance.removeListener(_onAdvanceManualEdit);
    _issue.removeListener(_onIssueNotesChanged);
    _notesMoneyDebounce?.cancel();
    _checkoutUiDebounce?.cancel();
    _notesMoneyAiGeneration++;
    if (!widget.isEdit) {
      _deviceSerial.removeListener(_onPlateFieldChanged);
    }
    _plateVehicleSyncDebounce?.cancel();
    _previousOdometerDebounce?.cancel();

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

    final busy = _hydratingEdit || _saving || _prefillBootstrapInProgress;

    final oilWidePanel = layout.isWideVariant;
    final oilCheckoutRailWidth = layout.isDesktopVariant ? 360.0 : 320.0;

    final formBody = !_formBodyReady
        ? const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : Row(
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
              if (oilWidePanel) SizedBox(width: oilCheckoutRailWidth, child: _buildOilCheckoutPanel(context, busy)),
            ],
          );

    return Theme(
      data: _formTheme ?? OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: ListenableBuilder(
        // بعض الحقول لا تعيد بناء الشاشة عند الكتابة، فتتابعها الحماية مباشرة.
        listenable: Listenable.merge([
          _customerName,
          _customerPhone,
          _deviceName,
          _deviceSerial,
          _carModel,
          _engineSize,
          _odometerCurrent,
          _odometerNext,
          _oilType,
          _issue,
          _technicianName,
          _agreed,
          _oilSizeAmount,
          _oilLitersStock,
        ]),
        builder: (context, child) => PopScope(
          canPop: !_hasUnsavedOilDraft(),
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_saving) return;
            final leave = await _confirmLeaveOilFormIfDirty();
            if (!mounted || !leave) return;
            _leaveGateAllowPop = true;
            Navigator.of(context).pop();
          },
          child: child!,
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: _oilAppBarTitle(),
            actions: [
              if (widget.isNewCard)
                IconButton(
                  tooltip: 'مسح الحقول',
                  onPressed: busy ? null : () => unawaited(_confirmAndClearOilFormFields()),
                  icon: const Icon(Icons.clear_all_rounded),
                ),
              // زر الحفظ العلوي أُزيل: كان يبيع البطاقة الجديدة مباشرة دون
              // تمييز عن «تعليق». أزرار الحفظ أسفل البطاقة هي المسار الوحيد.
            ],
          ),
          body: AssistantPrefillBanner.wrap(
            widget.assistantPrefill,
            only: const {'plate', 'customer', 'oil', 'liters', 'odometer', 'extras'},
            child: formBody,
          ),
        ),
      ),
    );
  }
}
