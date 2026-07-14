import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'dart:math';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/new_product_extra_unit.dart';
import '../../providers/product_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/app_settings_repository.dart';
import '../../services/inventory_policy_settings.dart';
import '../../services/inventory_product_settings.dart';
import '../../services/product_repository.dart';
import '../../services/product_variants_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../services/business_setup_settings.dart';
import '../../verticals/_contract/vertical_manifest.dart';
import '../../verticals/_contract/vertical_registry.dart';
import '../../theme/app_corner_style.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_color_picker_dialog.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../../utils/app_logger.dart';
import '../../utils/debug_ndjson_logger.dart';
import '../../utils/barcode_prefill.dart';
import '../../utils/color_name_ar.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/iqd_money.dart';
import '../../utils/numeric_format.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/inputs/arabic_speech_mic_button.dart';
import '../../widgets/inputs/app_price_input.dart';
import '../../widgets/variants/variant_size_picker_sheet.dart';
import '../../navigation/app_route_observer.dart';

const Color _kGreen = Color(0xFF15803D);
const String _hintIqd = '0 د.ع';

class _ExtraUnitVariantDraft {
  _ExtraUnitVariantDraft()
    : unitName = TextEditingController(),
      unitSymbol = TextEditingController(),
      factor = TextEditingController(text: '1'),
      barcode = TextEditingController(),
      sell = TextEditingController(),
      minSell = TextEditingController();

  final TextEditingController unitName;
  final TextEditingController unitSymbol;
  final TextEditingController factor;
  final TextEditingController barcode;
  final TextEditingController sell;
  final TextEditingController minSell;

  void dispose() {
    unitName.dispose();
    unitSymbol.dispose();
    factor.dispose();
    barcode.dispose();
    sell.dispose();
    minSell.dispose();
  }
}

class _VariantSizeDraft {
  _VariantSizeDraft({
    String size = '',
    int qty = 0,
    String barcode = '',
  })  : sizeCtrl = TextEditingController(text: size),
        qtyCtrl = TextEditingController(text: '$qty'),
        barcodeCtrl = TextEditingController(text: barcode);

  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController barcodeCtrl;

  void dispose() {
    sizeCtrl.dispose();
    qtyCtrl.dispose();
    barcodeCtrl.dispose();
  }
}

class _VariantColorDraft {
  _VariantColorDraft({
    String name = '',
    String hex = '',
    List<_VariantSizeDraft>? sizes,
  })  : nameCtrl = TextEditingController(text: name),
        hexCtrl = TextEditingController(text: hex),
        sizes = sizes ?? <_VariantSizeDraft>[];

  final TextEditingController nameCtrl;
  final TextEditingController hexCtrl;
  final List<_VariantSizeDraft> sizes;

  bool nameManuallyEdited = false;

  void dispose() {
    nameCtrl.dispose();
    hexCtrl.dispose();
    for (final s in sizes) {
      s.dispose();
    }
  }
}

/// إضافة منتج جديد — تخطيط احترافي متجاوب، رمز منتج (SKU) تلقائي `N{tenantId}-…`، حقول مرتبطة بقاعدة البيانات.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({
    super.key,
    this.initialBarcode,
    this.autoFillFromScan = false,
  });

  final String? initialBarcode;

  /// عند `true` (مثلاً بعد مسح باركود غير موجود من البيع): يملأ اسمًا مقترحًا وملاحظات تواريخ ووزنًا إن وُجد في الباركود المدمج.
  final bool autoFillFromScan;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> with RouteAware {
  final _formKey = GlobalKey<FormState>();

  final ProductRepository _productRepo = ProductRepository();
  final ProductVariantsRepository _variantsRepo = ProductVariantsRepository.instance;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _supplierCodeCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();

  final _buyPriceCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _minSellPriceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _customTaxCtrl = TextEditingController();

  final _qtyCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController(text: '0');
  final _internalNotesCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _netWeightGramsCtrl = TextEditingController();
  final _mfgDateCtrl = TextEditingController();
  final _expDateCtrl = TextEditingController();
  final _expiryAlertDaysCtrl = TextEditingController(text: '14');

  String? _grade; // حقل الرتبة / درجة الجودة
  InventoryPolicySettingsData _policy = InventoryPolicySettingsData.defaults();

  int? _warehouseId;
  int _stockBaseKind = 0; // 0 قطعة | 1 كغم | 3 لتر
  int _stockTypeUi = 0; // 0 عدد | 1 وزن | 2 ملابس | 3 زيت مفرد | 4 هيدروليك عائلة | 5 زيت عائلة
  final List<Object> _hydraulicGradeDrafts = [];
  final List<Object> _oilFamilyGradeDrafts = [];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  VerticalFluidInventoryEditor? get _fluidInventoryEditor =>
      VerticalRegistry.instance
          .manifestFor(BusinessVertical.oilChange)
          ?.fluidInventoryEditor;

  VerticalPharmacyProductEditor? get _pharmacyEditor {
    try {
      return VerticalRegistry.instance.activeManifest.pharmacyProductEditor;
    } on StateError {
      return null;
    }
  }

  VerticalPharmacyProductEditorSession? _pharmacySession;
  RouteObserver<PageRoute<dynamic>>? _homeInnerRouteObserver;

  bool get _hasPharmacyExtension => _pharmacySession != null;

  bool get _isFluidFamilyUi => _stockTypeUi == 4 || _stockTypeUi == 5;

  List<Object> get _activeFluidGradeDrafts => _stockTypeUi == 5
      ? _oilFamilyGradeDrafts
      : _hydraulicGradeDrafts;
  String _discountType = '%';
  String _taxMode = 'معفى';

  bool _trackInventory = true;
  bool _multiVariantEnabled = false;
  final List<_VariantColorDraft> _colorDrafts = [];

  bool _saving = false;
  bool _loadingRefs = true;
  String _productCodeHint = 'N1-…';
  List<String> _categoryOptions = [];
  List<String> _brandOptions = [];
  List<Map<String, dynamic>> _warehouseRows = [];
  List<String> _supplierOptions = [];
  bool _enableWeightSales = true;
  bool _enableClothingVariants = false;

  final List<_ExtraUnitVariantDraft> _extraUnitVariants = [];

  final FocusNode _focusName = FocusNode();
  final FocusNode _focusDesc = FocusNode();
  final FocusNode _focusCategory = FocusNode();
  final FocusNode _focusBrand = FocusNode();
  final FocusNode _focusSupplier = FocusNode();
  final FocusNode _focusSupplierCode = FocusNode();
  final FocusNode _focusBarcodeField = FocusNode();
  final FocusNode _focusBuy = FocusNode();
  final FocusNode _focusSell = FocusNode();
  final FocusNode _focusCustomTax = FocusNode();
  final FocusNode _focusDiscount = FocusNode();
  final FocusNode _focusMin = FocusNode();
  final FocusNode _focusQty = FocusNode();

  bool _hasUnsavedChanges() {
    if (_saving) return false;

    bool dirtyText(TextEditingController c, {String? ignore}) {
      final t = c.text.trim();
      if (ignore != null && t == ignore) return false;
      return t.isNotEmpty;
    }

    if (dirtyText(_nameCtrl)) return true;
    if (dirtyText(_descCtrl)) return true;
    if (dirtyText(_barcodeCtrl)) return true;
    if (dirtyText(_supplierCodeCtrl)) return true;
    if (dirtyText(_categoryCtrl)) return true;
    if (dirtyText(_brandCtrl)) return true;
    if (dirtyText(_supplierCtrl)) return true;
    if (dirtyText(_buyPriceCtrl)) return true;
    if (dirtyText(_sellPriceCtrl)) return true;
    if (dirtyText(_minSellPriceCtrl)) return true;
    if (dirtyText(_discountCtrl)) return true;
    if (dirtyText(_customTaxCtrl)) return true;
    if (dirtyText(_qtyCtrl)) return true;
    if (dirtyText(_lowStockCtrl, ignore: '0')) return true;
    if (dirtyText(_internalNotesCtrl)) return true;
    if (dirtyText(_tagsCtrl)) return true;
    if (dirtyText(_netWeightGramsCtrl)) return true;
    if (dirtyText(_mfgDateCtrl)) return true;
    if (dirtyText(_expDateCtrl)) return true;
    if (dirtyText(_expiryAlertDaysCtrl, ignore: '14')) return true;

    if (_grade != null && _grade!.trim().isNotEmpty) return true;
    if (_warehouseId != null) return true;
    if (_stockBaseKind != 0) return true;
    if (_isFluidFamilyUi) {
      if (_fluidInventoryEditor?.hasDirtyGradeDrafts(_activeFluidGradeDrafts) ==
          true) {
        return true;
      }
    }
    if (_stockTypeUi != 0) return true;
    if (_discountType != '%') return true;
    if (_taxMode != 'معفى') return true;
    if (!_trackInventory) return true;
    if (_multiVariantEnabled) return true;
    if (_colorDrafts.isNotEmpty) return true;
    if (_extraUnitVariants.isNotEmpty) return true;

    return false;
  }

  Future<void> _handleLeaveAttemptFromRouteChange() async {
    if (!mounted) return;
    if (_saving) return;
    if (!_hasUnsavedChanges()) return;

    // ظهر مسار آخر فوق هذه الشاشة (مثلاً من القائمة الجانبية).
    // نسأل المستخدم: حفظ/مغادرة/إلغاء. عند الإلغاء نرجع لهذه الشاشة فوراً.
    final action = await _confirmLeaveIfDirty();
    if (!mounted) return;
    if (action == 0) {
      final myRoute = ModalRoute.of(context);
      if (myRoute != null) {
        Navigator.of(context).popUntil((r) => r == myRoute);
      }
      return;
    }
    if (action == 2) {
      // حفظ بدون إغلاق (لأننا فعلياً انتقلنا لشاشة أخرى).
      await _submit(popAfter: false);
    }
  }

  Future<int> _confirmLeaveIfDirty() async {
    // 0 = cancel, 1 = discard, 2 = save
    if (!_hasUnsavedChanges()) return 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: cs.surface,
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.save_outlined, color: AppColors.accentGold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تغييرات غير محفوظة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'لم تقم بحفظ المنتج. هل تريد الحفظ قبل المغادرة؟',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              style: TextButton.styleFrom(foregroundColor: cs.onSurface),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 1),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('مغادرة بدون حفظ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 2),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGold,
                foregroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('حفظ المنتج', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return res ?? 0;
  }
  final FocusNode _focusLow = FocusNode();

  String? _imagePath;

  /// من إعدادات المخزون: `code128` | `ean13`
  String _barcodeStandard = 'code128';
  InventoryProductSettingsData _uiSettings =
      InventoryProductSettingsData.fromRaw(const <String, String?>{});

  double get _profitMarginPct {
    final b = IraqiCurrencyFormat.parseIqdInt(_buyPriceCtrl.text).toDouble();
    final s = IraqiCurrencyFormat.parseIqdInt(_sellPriceCtrl.text).toDouble();
    if (b <= 0) return 0;
    return (s - b) / b * 100;
  }

  /// سعر البيع أقل من تكلفة الشراء — للتحذير المرئي.
  bool get _sellBelowBuy {
    final b = IraqiCurrencyFormat.parseIqdInt(_buyPriceCtrl.text);
    final s = IraqiCurrencyFormat.parseIqdInt(_sellPriceCtrl.text);
    return b > 0 && s > 0 && s < b;
  }

  /// تقريبي: السعر الأساسي المُدخل × (1 + الضريبة).
  int get _sellAfterTaxApprox {
    final sell = IraqiCurrencyFormat.parseIqdInt(_sellPriceCtrl.text);
    final t = _effectiveTaxPercent;
    final m = (1.0 + t / 100.0).clamp(0.0, 999.99);
    return ((sell * m)).round();
  }

  /// عند تفعيل «التسعير المتقدم» في إعدادات المنتجات: ربط تلقائي بين تكلفة الشراء وأسعار البيع.
  bool _costDrivesSuggestedPrices = true;
  bool _applyingSuggestedPrices = false;
  Timer? _costSuggestDebounce;

  void _onBuyPriceChangedForCostSuggest() {
    if (!mounted) return;
    if (!_uiSettings.advancedPricing || !_costDrivesSuggestedPrices) {
      setState(() {});
      return;
    }
    _costSuggestDebounce?.cancel();
    _costSuggestDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _applySuggestedPricesFromCost();
      setState(() {});
    });
  }

  void _onSellOrMinManualEdit() {
    if (_applyingSuggestedPrices || !mounted) return;
    if (_costDrivesSuggestedPrices) {
      setState(() => _costDrivesSuggestedPrices = false);
      return;
    }
    setState(() {});
  }

  void _applySuggestedPricesFromCost() {
    if (!_uiSettings.advancedPricing || !_costDrivesSuggestedPrices) return;
    final buy = _parseIqdMoney(_buyPriceCtrl.text);
    if (buy <= 0) return;
    final marginPct = _uiSettings.suggestedMarginPercent;
    final sellD = buy * (1.0 + marginPct / 100.0);
    if (!sellD.isFinite || sellD <= 0) return;
    final sell = sellD.round();
    final minPct = _uiSettings.minSellPercentOfSell.clamp(1.0, 100.0);
    final minD = sell * (minPct / 100.0);
    final minS = minD.isFinite ? minD.round().clamp(0, sell) : sell;
    _applyingSuggestedPrices = true;
    _sellPriceCtrl.text = IraqiCurrencyFormat.formatInt(sell);
    _minSellPriceCtrl.text = IraqiCurrencyFormat.formatInt(minS);
    _applyingSuggestedPrices = false;
  }

  double _parseIqdMoney(String text) =>
      IraqiCurrencyFormat.parseIqdInt(text).toDouble();

  double _parseQuantity(String text) {
    final t = text.trim().replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  int _parseNonNegativeInt(String raw) {
    final t = raw.trim();
    final n = int.tryParse(t);
    return (n == null || n < 0) ? -1 : n;
  }

  int _totalQtyAllVariants() {
    var sum = 0;
    for (final c in _colorDrafts) {
      for (final s in c.sizes) {
        final q = _parseNonNegativeInt(s.qtyCtrl.text);
        if (q > 0) sum += q;
      }
    }
    return sum;
  }

  int _totalQtyForColor(_VariantColorDraft c) {
    var sum = 0;
    for (final s in c.sizes) {
      final q = _parseNonNegativeInt(s.qtyCtrl.text);
      if (q > 0) sum += q;
    }
    return sum;
  }

  String _variantsSummaryLine() {
    final colors = _colorDrafts.length;
    var sizes = 0;
    for (final c in _colorDrafts) {
      sizes += c.sizes.length;
    }
    return 'ألوان: $colors • مقاسات: $sizes • إجمالي: ${_totalQtyAllVariants()}';
  }

  Future<void> _openVariantsEditor() async {
    // #region agent log
    DebugNdjsonLogger.log(
      runId: 'pre-fix',
      hypothesisId: 'H3',
      location: 'add_product_screen.dart:_openVariantsEditor',
      message: 'opening variants editor bottom sheet',
      data: {'mounted': mounted},
    );
    // #endregion

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenH = MediaQuery.sizeOf(ctx).height;
              final targetH = (screenH * 0.92).clamp(420.0, 900.0);
              final maxH = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : targetH;
              final sheetH = targetH > maxH ? maxH : targetH;

              // #region agent log
              DebugNdjsonLogger.log(
                runId: 'pre-fix',
                hypothesisId: 'H2',
                location:
                    'add_product_screen.dart:_openVariantsEditor:LayoutBuilder',
                message: 'variants editor sheet constraints + computed height',
                data: {
                  'constraints.maxHeight': constraints.maxHeight,
                  'constraints.hasBoundedHeight': constraints.hasBoundedHeight,
                  'screenH': screenH,
                  'targetH': targetH,
                  'sheetH': sheetH,
                },
              );
              // #endregion

              return SizedBox(
                height: sheetH,
                child: StatefulBuilder(
                  builder: (context, sheetSetState) {
                    return Material(
                      color: cs.surface,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              16,
                              8,
                              16,
                              8,
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'الألوان والمقاسات',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('إغلاق'),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              child: _buildVariantsSection(
                                ctx,
                                setStateOverride: sheetSetState,
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                16,
                                10,
                                16,
                                16,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('تم'),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() {}); // تحديث الملخص بعد الإغلاق
  }

  double _parseDiscountValue() {
    if (!_uiSettings.addShowAdvancedPricing ||
        !_uiSettings.addShowDiscountFields) {
      return 0;
    }
    if (_discountType == '%') {
      return double.tryParse(_discountCtrl.text.trim().replaceAll(',', '.')) ??
          0;
    }
    return _parseIqdMoney(_discountCtrl.text);
  }

  void _goAfterSupplierCode() {
    if (_uiSettings.addShowBarcodeField) {
      _focusBarcodeField.requestFocus();
    } else {
      _focusBuy.requestFocus();
    }
  }

  void _goAfterSell() {
    if (_uiSettings.addShowAdvancedPricing &&
        _uiSettings.addShowTaxField &&
        _taxMode == 'مخصص') {
      _focusCustomTax.requestFocus();
    } else {
      _goAfterTaxTowardDiscountThenMin();
    }
  }

  void _goAfterTaxTowardDiscountThenMin() {
    if (_uiSettings.addShowAdvancedPricing &&
        _uiSettings.addShowDiscountFields) {
      _focusDiscount.requestFocus();
    } else {
      _focusMin.requestFocus();
    }
  }

  void _goAfterCustomTax() => _goAfterTaxTowardDiscountThenMin();

  void _goAfterDiscount() => _focusMin.requestFocus();

  void _goAfterMin() {
    if (_trackInventory) {
      _focusQty.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _relinkSuggestedPricesToCost() {
    if (!_uiSettings.advancedPricing) return;
    setState(() {
      _costDrivesSuggestedPrices = true;
      _applySuggestedPricesFromCost();
    });
  }

  String _marginPercentUiLabel() {
    final m = _uiSettings.suggestedMarginPercent;
    return (m - m.round()).abs() < 1e-6 ? '${m.round()}' : m.toStringAsFixed(1);
  }

  String _minSellPercentUiLabel() {
    final m = _uiSettings.minSellPercentOfSell;
    return (m - m.round()).abs() < 1e-6 ? '${m.round()}' : m.toStringAsFixed(1);
  }

  double get _effectiveTaxPercent {
    switch (_taxMode) {
      case '5':
        return 5;
      case '10':
        return 10;
      case '15':
        return 15;
      case 'مخصص':
        return double.tryParse(_customTaxCtrl.text.replaceAll(',', '.')) ?? 0;
      default:
        return 0;
    }
  }

  void _reconcilePharmacySession() {
    final pharmacyEditor = _pharmacyEditor;
    if (pharmacyEditor == null) {
      _pharmacySession?.dispose();
      _pharmacySession = null;
      return;
    }
    if (_pharmacySession != null) return;
    _pharmacySession = pharmacyEditor.createSession(
      tenantId: TenantContextService.instance.activeTenantId,
    );
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBarcode?.trim();
    if (initial != null && initial.isNotEmpty) {
      _barcodeCtrl.text = initial;
    }
    _buyPriceCtrl.addListener(_onBuyPriceChangedForCostSuggest);
    _sellPriceCtrl.addListener(_onSellOrMinManualEdit);
    _minSellPriceCtrl.addListener(_onSellOrMinManualEdit);
    _reconcilePharmacySession();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    setState(() => _loadingRefs = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaultAlertDays =
          (prefs.getInt(NotificationPrefs.defaultExpiryAlertDays) ?? 14).clamp(
            1,
            365,
          );
      if (mounted) {
        _expiryAlertDaysCtrl.text = '$defaultAlertDays';
      }
      final data = await context
          .read<ProductProvider>()
          .loadAddProductFormData();
      final uiSettings = await InventoryProductSettingsData.load(
        AppSettingsRepository.instance,
      );
      final bcSettings = await BarcodeSettingsData.load(
        AppSettingsRepository.instance,
      );
      final policySettings = await InventoryPolicySettingsData.load(
        AppSettingsRepository.instance,
      );
      final bizSettings = await BusinessSetupSettingsData.load(
        AppSettingsRepository.instance,
      );
      VerticalRegistry.instance.syncActiveVertical(bizSettings);
      if (!mounted) return;
      setState(() {
        _productCodeHint = data.productCodeHint;
        _categoryOptions = data.categories;
        _brandOptions = data.brands;
        _warehouseRows = data.warehouses;
        _supplierOptions = data.suppliers;
        _uiSettings = uiSettings;
        _policy = policySettings;
        _enableWeightSales = bizSettings.enableWeightSales;
        _enableClothingVariants = bizSettings.enableClothingVariants;
        _barcodeStandard = bcSettings.standard;
        _warehouseId = null;
        _trackInventory = uiSettings.addDefaultTrackInventory;
        _costDrivesSuggestedPrices = uiSettings.advancedPricing;
        _applyBarcodeScanPrefill(bcSettings);
        _reconcilePharmacySession();
      });
      final defWhStr = await AppSettingsRepository.instance.get(
        InventoryProductSettingsKeys.defWarehouseId,
      );
      final defWid = int.tryParse(defWhStr ?? '');
      final defTax = await AppSettingsRepository.instance.get(
        InventoryProductSettingsKeys.defTax1,
      );
      if (!mounted) return;
      setState(() {
        if (defWid != null) {
          for (final w in _warehouseRows) {
            final id = (w['id'] as num).toInt();
            if (id == defWid) {
              _warehouseId = defWid;
              break;
            }
          }
        }
        if (_warehouseId == null && _warehouseRows.isNotEmpty) {
          final id = _warehouseRows.first['id'];
          _warehouseId = id is int ? id : (id as num).toInt();
        }
        if (defTax != null &&
            defTax.isNotEmpty &&
            {'معفى', '5', '10', '15', 'مخصص'}.contains(defTax)) {
          _taxMode = defTax;
        }
      });
    } catch (e, st) {
      AppLogger.error('Product', 'فشل تحميل بيانات نموذج المنتج', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تحميل بيانات النموذج. سيعمل الحقل بالوضع اليدوي.\n$e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRefs = false);
    }
  }

  void _applyBarcodeScanPrefill(BarcodeSettingsData bcSettings) {
    if (!widget.autoFillFromScan) return;
    final scan = widget.initialBarcode?.trim();
    if (scan == null || scan.isEmpty) return;
    final prefill = BarcodePrefill.fromScan(scan, bcSettings);
    _nameCtrl.text = prefill.suggestedName;
    if (prefill.suggestedQty != null && prefill.suggestedQty! > 0) {
      _qtyCtrl.text = BarcodePrefill.formatSuggestedQty(prefill.suggestedQty!);
    }
    _internalNotesCtrl.text = prefill.internalNotes;
    if (prefill.suggestedNetWeightGrams != null &&
        prefill.suggestedNetWeightGrams! > 0) {
      _netWeightGramsCtrl.text = BarcodePrefill.formatSuggestedQty(
        prefill.suggestedNetWeightGrams!,
      );
    }
    if (prefill.suggestedManufacturingDateIso != null) {
      _mfgDateCtrl.text = _displayDateFromIso(
        prefill.suggestedManufacturingDateIso,
      );
    }
    if (prefill.suggestedExpiryDateIso != null) {
      _expDateCtrl.text = _displayDateFromIso(prefill.suggestedExpiryDateIso);
    }
  }

  static final DateFormat _dateDisplay = DateFormat('dd/MM/yyyy');

  String _displayDateFromIso(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final p = iso.split('T').first.split('-');
    if (p.length != 3) return iso;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return iso;
    try {
      return _dateDisplay.format(DateTime(y, m, d));
    } catch (_) {
      return iso;
    }
  }

  DateTime? _parseDateField(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    for (final pattern in <String>[
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd/MM/yy',
      'd/M/yy',
    ]) {
      try {
        return DateFormat(pattern).parse(t);
      } catch (_) {}
    }
    final p = t.split(RegExp(r'[/\-\.]'));
    if (p.length == 3) {
      final d = int.tryParse(p[0].trim());
      final m = int.tryParse(p[1].trim());
      final y = int.tryParse(p[2].trim());
      if (d != null && m != null && y != null) {
        var yy = y;
        if (y < 100) yy = y >= 70 ? 1900 + y : 2000 + y;
        try {
          return DateTime(yy, m, d);
        } catch (_) {}
      }
    }
    return null;
  }

  String? _isoFromDateField(String text) {
    final d = _parseDateField(text);
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickProductDate(TextEditingController ctrl) async {
    final initial = _parseDateField(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => ctrl.text = _dateDisplay.format(picked));
  }

  @override
  void dispose() {
    _homeInnerRouteObserver?.unsubscribe(this);
    _pharmacySession?.dispose();
    _buyPriceCtrl.removeListener(_onBuyPriceChangedForCostSuggest);
    _sellPriceCtrl.removeListener(_onSellOrMinManualEdit);
    _minSellPriceCtrl.removeListener(_onSellOrMinManualEdit);
    _costSuggestDebounce?.cancel();
    _focusName.dispose();
    _focusDesc.dispose();
    _focusCategory.dispose();
    _focusBrand.dispose();
    _focusSupplier.dispose();
    _focusSupplierCode.dispose();
    _focusBarcodeField.dispose();
    _focusBuy.dispose();
    _focusSell.dispose();
    _focusCustomTax.dispose();
    _focusDiscount.dispose();
    _focusMin.dispose();
    _focusQty.dispose();
    _focusLow.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _barcodeCtrl.dispose();
    _supplierCodeCtrl.dispose();
    _categoryCtrl.dispose();
    _brandCtrl.dispose();
    _supplierCtrl.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _minSellPriceCtrl.dispose();
    _discountCtrl.dispose();
    _customTaxCtrl.dispose();
    _qtyCtrl.dispose();
    _lowStockCtrl.dispose();
    _internalNotesCtrl.dispose();
    _tagsCtrl.dispose();
    _netWeightGramsCtrl.dispose();
    _mfgDateCtrl.dispose();
    _expDateCtrl.dispose();
    _expiryAlertDaysCtrl.dispose();
    for (final v in _extraUnitVariants) {
      v.dispose();
    }
    for (final c in _colorDrafts) {
      c.dispose();
    }
    for (final g in _hydraulicGradeDrafts) {
      _fluidInventoryEditor?.disposeGradeDraft(g);
    }
    for (final g in _oilFamilyGradeDrafts) {
      _fluidInventoryEditor?.disposeGradeDraft(g);
    }
    super.dispose();
    // _grade is a String? — no dispose needed
  }

  void _regenerateBarcode() {
    final rnd = Random();
    final buf = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buf.write(rnd.nextInt(10));
    }
    setState(() => _barcodeCtrl.text = buf.toString());
  }

  Future<void> _pickImage() async {
    try {
      ImageSource source = ImageSource.gallery;
      
      final pfm = Theme.of(context).platform;
      if (!kIsWeb && (pfm == TargetPlatform.android || pfm == TargetPlatform.iOS)) {
        final choice = await showModalBottomSheet<ImageSource>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt_outlined, color: AppColors.accentGold),
                    title: const Text('التقاط صورة (الكاميرا)'),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: AppColors.accentGold),
                    title: const Text('اختيار من المعرض'),
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ),
        );
        if (choice == null) return;
        source = choice;
      }

      final x = ImagePicker();
      final file = await x.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 72,
      );
      if (file == null) return;
      if (kIsWeb) {
        setState(() => _imagePath = file.path);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final name =
          'product_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      final dest = p.join(dir.path, name);
      await File(file.path).copy(dest);
      if (!mounted) return;
      setState(() => _imagePath = dest);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر اختيار أو التقاط الصورة: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submit({required bool popAfter}) async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_uiSettings.addShowAdvancedPricing &&
        _uiSettings.addShowDiscountFields &&
        _discountType == '%') {
      final raw = _discountCtrl.text.trim();
      if (raw.isNotEmpty) {
        final p = double.tryParse(raw.replaceAll(',', '.'));
        if (p != null && p > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('خصم النسبة المئوية لا يمكن أن يتعدّى 100٪.'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
    }

    var buy = _parseIqdMoney(_buyPriceCtrl.text);
    var sell = _parseIqdMoney(_sellPriceCtrl.text);
    final minSellRaw = _minSellPriceCtrl.text.trim();
    final double? minSell =
        minSellRaw.isEmpty ? null : _parseIqdMoney(_minSellPriceCtrl.text);

    var qty = 0.0;
    double low = 0;
    if (_trackInventory) {
      qty = _parseQuantity(_qtyCtrl.text);
      low = _parseQuantity(_lowStockCtrl.text);
    }

    final barcode = _barcodeCtrl.text.trim();
    final category = _categoryCtrl.text.trim();
    final brand = _brandCtrl.text.trim();
    final supplier = _supplierCtrl.text.trim();
    final disc =
        _uiSettings.addShowAdvancedPricing && _uiSettings.addShowDiscountFields
            ? _parseDiscountValue()
            : 0.0;

    if (_uiSettings.addShowBarcodeField &&
        _uiSettings.addRequireBarcode &&
        barcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('حقل الباركود إلزامي حسب الإعدادات.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_uiSettings.addRequireSupplier && supplier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('حقل المورد إلزامي حسب الإعدادات.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_uiSettings.addRequireWarehouse && _warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('اختيار المخزن إلزامي حسب الإعدادات.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_uiSettings.addShowImageField &&
        _uiSettings.addRequireImage &&
        (_imagePath == null || _imagePath!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('صورة المنتج إلزامية حسب الإعدادات.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final mfgD = _parseDateField(_mfgDateCtrl.text);
    final expD = _parseDateField(_expDateCtrl.text);
    if (_uiSettings.addShowExtraFields) {
      if (_mfgDateCtrl.text.trim().isNotEmpty && mfgD == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'صيغة تاريخ الإنتاج غير صحيحة. استخدم يوم/شهر/سنة (مثال 15/01/2026).',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (_expDateCtrl.text.trim().isNotEmpty && expD == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'صيغة تاريخ الانتهاء غير صحيحة. استخدم يوم/شهر/سنة (مثال 15/01/2026).',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (mfgD != null && expD != null && expD.isBefore(mfgD)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'تاريخ الانتهاء يجب أن يكون بعد أو يساوي تاريخ الإنتاج.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final nwText = _netWeightGramsCtrl.text.trim();
    final netWeightGrams = nwText.isEmpty
        ? null
        : double.tryParse(nwText.replaceAll(',', '.'));

    int? expiryAlertDaysBefore;
    if (_uiSettings.addShowExtraFields && expD != null) {
      final parsed = int.tryParse(_expiryAlertDaysCtrl.text.trim());
      if (parsed != null && parsed >= 1 && parsed <= 365) {
        expiryAlertDaysBefore = parsed;
      } else {
        final p = await SharedPreferences.getInstance();
        expiryAlertDaysBefore =
            (p.getInt(NotificationPrefs.defaultExpiryAlertDays) ?? 14).clamp(
              1,
              365,
            );
      }
    }

    for (final row in _extraUnitVariants) {
      final unit = row.unitName.text.trim();
      if (unit.isEmpty) continue;
      final f =
          double.tryParse(row.factor.text.trim().replaceAll(',', '.')) ?? 0;
      if (!(f > 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'عامل التحويل يجب أن يكون أكبر من 0 لكل وحدة إضافية.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    String? validateVariantDrafts() {
      if (!_multiVariantEnabled) return null;
      if (_colorDrafts.isEmpty) {
        return 'أضف لوناً واحداً على الأقل.';
      }

      final seenBarcodes = <String>{};
      for (final c in _colorDrafts) {
        final colorName = c.nameCtrl.text.trim();
        if (colorName.isEmpty) return 'اسم اللون مطلوب.';
        if (c.sizes.isEmpty) return 'أضف مقاساً واحداً على الأقل لكل لون.';

        final seenSizesInColor = <String>{};
        for (final s in c.sizes) {
          final size = s.sizeCtrl.text.trim();
          if (size.isEmpty) return 'حقل المقاس مطلوب.';
          final key = size.toLowerCase();
          if (!seenSizesInColor.add(key)) {
            return 'المقاس "$size" مكرر داخل اللون "$colorName".';
          }

          final q = _parseNonNegativeInt(s.qtyCtrl.text);
          if (q < 0) return 'الكمية يجب أن تكون رقماً صحيحاً أكبر أو يساوي 0.';

          final bc = s.barcodeCtrl.text.trim().toUpperCase();
          if (bc.isNotEmpty) {
            if (!seenBarcodes.add(bc)) return 'يوجد باركود مكرر داخل المتغيرات.';
          }
        }
      }
      return null;
    }

    final variantErr = validateVariantDrafts();
    if (variantErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(variantErr),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isFluidFamilyUi) {
      final editor = _fluidInventoryEditor;
      if (editor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('محرّر عائلات السوائل غير متاح.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final validationErr = editor.validateFluidFamilyDrafts(
        isOilFamily: _stockTypeUi == 5,
        familyName: _nameCtrl.text.trim(),
        gradeDrafts: _activeFluidGradeDrafts,
      );
      if (validationErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationErr),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (_pharmacySession != null) {
      final resolveErr = await _pharmacySession!.resolveReferenceBeforeSave();
      if (resolveErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resolveErr),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final pharmacyErr = _pharmacySession!.validateForSave();
      if (pharmacyErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pharmacyErr),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final suggestedQty = _pharmacySession!.suggestedQty();
      if (suggestedQty != null) {
        qty = suggestedQty;
      }
      final suggestedCostFils = _pharmacySession!.suggestedCostFils();
      if (suggestedCostFils != null) {
        buy = IqdMoney.fromFils(suggestedCostFils);
        if (sell <= 0) {
          sell = buy;
        }
      }
      final suggestedName = _pharmacySession!.suggestedProductName();
      if (_nameCtrl.text.trim().isEmpty && suggestedName != null) {
        _nameCtrl.text = suggestedName;
      }
      final suggestedExpiry = _pharmacySession!.suggestedExpiryIso();
      if (_expDateCtrl.text.trim().isEmpty && suggestedExpiry != null) {
        _expDateCtrl.text = _displayDateFromIso(suggestedExpiry);
      }
    }

    final extraUnits = <NewProductExtraUnit>[];
    for (final row in _extraUnitVariants) {
      final unit = row.unitName.text.trim();
      if (unit.isEmpty) continue;
      final f =
          double.tryParse(row.factor.text.trim().replaceAll(',', '.')) ?? 0;
      final bc = row.barcode.text.trim();
      final s = row.sell.text.trim();
      final ms = row.minSell.text.trim();
      final sellV =
          s.isEmpty ? null : IraqiCurrencyFormat.parseIqdInt(s).toDouble();
      final minSellV =
          ms.isEmpty ? null : IraqiCurrencyFormat.parseIqdInt(ms).toDouble();
      extraUnits.add(
        NewProductExtraUnit(
          unitName: unit,
          unitSymbol: row.unitSymbol.text.trim().isEmpty
              ? null
              : row.unitSymbol.text.trim(),
          factorToBase: f,
          barcode: bc.isEmpty ? null : bc,
          sellPrice: sellV,
          minSellPrice: minSellV,
        ),
      );
    }

    setState(() => _saving = true);
    String? err;
    int? createdProductId;
    try {
      if (_isFluidFamilyUi) {
        int? categoryId;
        int? brandId;
        if (category.isNotEmpty) {
          categoryId = await _productRepo.getOrCreateCategoryId(category);
        }
        if (brand.isNotEmpty) {
          brandId = await _productRepo.getOrCreateBrandId(brand);
        }
        final editor = _fluidInventoryEditor;
        if (editor == null) {
          throw StateError('fluid_inventory_editor_unavailable');
        }
        createdProductId = await editor.createFluidFamily(
          isOilFamily: _stockTypeUi == 5,
          familyName: _nameCtrl.text.trim(),
          gradeDrafts: _activeFluidGradeDrafts,
          categoryId: categoryId,
          brandId: brandId,
          warehouseId: _warehouseId,
          lowStockThreshold: low,
        );
      } else if (_multiVariantEnabled) {
        for (final c in _colorDrafts) {
          for (final s in c.sizes) {
            final bc = s.barcodeCtrl.text.trim().toUpperCase();
            if (bc.isEmpty) continue;
            if (await _productRepo.isBarcodeTakenAnywhere(bc)) {
              throw StateError('variant_barcode_taken');
            }
            final existing = await _variantsRepo.findVariantByBarcode(bc);
            if (existing != null) throw StateError('variant_barcode_taken');
          }
        }

        int? categoryId;
        int? brandId;
        if (category.isNotEmpty) {
          categoryId = await _productRepo.getOrCreateCategoryId(category);
        }
        if (brand.isNotEmpty) {
          brandId = await _productRepo.getOrCreateBrandId(brand);
        }

        final ti = _trackInventory ? 1 : 0;
        createdProductId = await _productRepo.insertProductComplete(
          name: _nameCtrl.text.trim(),
          barcode: (_uiSettings.addShowBarcodeField && barcode.isNotEmpty)
              ? barcode
              : null,
          categoryId: categoryId,
          brandId: brandId,
          tenantId: TenantContextService.instance.activeTenantId,
          buyPrice: buy,
          sellPrice: sell,
          minSellPrice: minSell,
          qty: 0.0,
          lowStockThreshold: 0.0,
          warehouseId: _warehouseId,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
          imagePath: _uiSettings.addShowImageField ? _imagePath : null,
          internalNotes:
              _uiSettings.addShowExtraFields &&
                      _internalNotesCtrl.text.trim().isNotEmpty
                  ? _internalNotesCtrl.text
                  : null,
          tags: _uiSettings.addShowExtraFields && _tagsCtrl.text.trim().isNotEmpty
              ? _tagsCtrl.text
              : null,
          taxPercent:
              (_uiSettings.addShowAdvancedPricing && _uiSettings.addShowTaxField)
                  ? _effectiveTaxPercent
                  : 0,
          discountPercent: (_uiSettings.addShowAdvancedPricing &&
                  _uiSettings.addShowDiscountFields &&
                  _discountType == '%')
              ? disc
              : 0,
          discountAmount: (_uiSettings.addShowAdvancedPricing &&
                  _uiSettings.addShowDiscountFields &&
                  _discountType != '%')
              ? disc
              : 0,
          trackInventory: ti,
          allowNegativeStock: 0,
          supplierItemCode: _supplierCodeCtrl.text.trim().isEmpty
              ? null
              : _supplierCodeCtrl.text.trim(),
          stockBaseKind: _stockBaseKind,
          supplierName: supplier.isEmpty ? null : supplier,
          netWeightGrams: _uiSettings.addShowExtraFields ? netWeightGrams : null,
          manufacturingDate: _uiSettings.addShowExtraFields
              ? _isoFromDateField(_mfgDateCtrl.text)
              : null,
          expiryDate: _uiSettings.addShowExtraFields
              ? _isoFromDateField(_expDateCtrl.text)
              : null,
          grade: _policy.enableProductGrade ? _grade : null,
          expiryAlertDaysBefore: expiryAlertDaysBefore,
          extraUnits: extraUnits,
        );

        for (var colorIndex = 0; colorIndex < _colorDrafts.length; colorIndex++) {
          final c = _colorDrafts[colorIndex];
          final colorId = await _variantsRepo.addColor(
            productId: createdProductId,
            name: c.nameCtrl.text.trim(),
            hexCode: c.hexCtrl.text.trim().isEmpty ? null : c.hexCtrl.text.trim(),
            sortOrder: colorIndex,
          );
          for (final s in c.sizes) {
            final size = s.sizeCtrl.text.trim();
            final q = _parseNonNegativeInt(s.qtyCtrl.text);
            final bc = s.barcodeCtrl.text.trim().toUpperCase();
            await _variantsRepo.addVariant(
              productId: createdProductId,
              colorId: colorId,
              colorIndex: colorIndex,
              size: size,
              quantity: q,
              barcode: bc.isEmpty ? null : bc,
              sku: null,
            );
          }
        }
      } else if (_pharmacySession != null) {
        int? categoryId;
        int? brandId;
        if (category.isNotEmpty) {
          categoryId = await _productRepo.getOrCreateCategoryId(category);
        }
        if (brand.isNotEmpty) {
          brandId = await _productRepo.getOrCreateBrandId(brand);
        }
        final ti = _trackInventory ? 1 : 0;
        createdProductId = await _productRepo.insertProductComplete(
          name: _nameCtrl.text.trim(),
          barcode: (_uiSettings.addShowBarcodeField && barcode.isNotEmpty)
              ? barcode
              : null,
          categoryId: categoryId,
          brandId: brandId,
          tenantId: TenantContextService.instance.activeTenantId,
          buyPrice: buy,
          sellPrice: sell,
          minSellPrice: minSell,
          qty: qty,
          lowStockThreshold: low,
          warehouseId: _warehouseId,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
          imagePath: _uiSettings.addShowImageField ? _imagePath : null,
          internalNotes:
              _uiSettings.addShowExtraFields &&
                      _internalNotesCtrl.text.trim().isNotEmpty
                  ? _internalNotesCtrl.text
                  : null,
          tags: _uiSettings.addShowExtraFields && _tagsCtrl.text.trim().isNotEmpty
              ? _tagsCtrl.text
              : null,
          taxPercent:
              (_uiSettings.addShowAdvancedPricing && _uiSettings.addShowTaxField)
                  ? _effectiveTaxPercent
                  : 0,
          discountPercent: (_uiSettings.addShowAdvancedPricing &&
                  _uiSettings.addShowDiscountFields &&
                  _discountType == '%')
              ? disc
              : 0,
          discountAmount: (_uiSettings.addShowAdvancedPricing &&
                  _uiSettings.addShowDiscountFields &&
                  _discountType != '%')
              ? disc
              : 0,
          trackInventory: ti,
          allowNegativeStock: 0,
          supplierItemCode: _supplierCodeCtrl.text.trim().isEmpty
              ? null
              : _supplierCodeCtrl.text.trim(),
          stockBaseKind: _stockBaseKind,
          supplierName: supplier.isEmpty ? null : supplier,
          netWeightGrams: _uiSettings.addShowExtraFields ? netWeightGrams : null,
          manufacturingDate: _uiSettings.addShowExtraFields
              ? _isoFromDateField(_mfgDateCtrl.text)
              : null,
          expiryDate: _pharmacySession!.suggestedExpiryIso() ??
              (_uiSettings.addShowExtraFields
                  ? _isoFromDateField(_expDateCtrl.text)
                  : null),
          grade: _policy.enableProductGrade ? _grade : null,
          expiryAlertDaysBefore: expiryAlertDaysBefore,
          extraUnits: extraUnits,
        );
      } else {
        err = await context.read<ProductProvider>().addProduct(
          name: _nameCtrl.text.trim(),
          barcode: (_uiSettings.addShowBarcodeField && barcode.isNotEmpty)
              ? barcode
              : null,
          categoryName: category.isEmpty ? null : category,
          brandName: brand.isEmpty ? null : brand,
          buyPrice: buy,
          sellPrice: sell,
          minSellPrice: minSell,
          qty: qty,
          lowStockThreshold: low,
          warehouseId: _warehouseId,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
          imagePath: _uiSettings.addShowImageField ? _imagePath : null,
          internalNotes:
              _uiSettings.addShowExtraFields &&
                      _internalNotesCtrl.text.trim().isNotEmpty
                  ? _internalNotesCtrl.text
                  : null,
          tags: _uiSettings.addShowExtraFields && _tagsCtrl.text.trim().isNotEmpty
              ? _tagsCtrl.text
              : null,
          taxPercent:
              (_uiSettings.addShowAdvancedPricing && _uiSettings.addShowTaxField)
                  ? _effectiveTaxPercent
                  : 0,
          discountType:
              (_uiSettings.addShowAdvancedPricing &&
                      _uiSettings.addShowDiscountFields)
                  ? _discountType
                  : '%',
          discountValue: disc,
          trackInventory: _trackInventory,
          supplierItemCode: _supplierCodeCtrl.text.trim().isEmpty
              ? null
              : _supplierCodeCtrl.text.trim(),
          stockBaseKind: _stockBaseKind,
          supplierName: supplier.isEmpty ? null : supplier,
          netWeightGrams: _uiSettings.addShowExtraFields ? netWeightGrams : null,
          manufacturingDate: _uiSettings.addShowExtraFields
              ? _isoFromDateField(_mfgDateCtrl.text)
              : null,
          expiryDate: _uiSettings.addShowExtraFields
              ? _isoFromDateField(_expDateCtrl.text)
              : null,
          grade: _policy.enableProductGrade ? _grade : null,
          expiryAlertDaysBefore: expiryAlertDaysBefore,
          extraUnits: extraUnits,
        );
      }

      if (err == null &&
          _pharmacySession != null &&
          createdProductId != null) {
        try {
          await _pharmacySession!.save(
            tenantId: TenantContextService.instance.activeTenantId,
            productId: createdProductId,
          );
        } catch (e) {
          err = 'تم حفظ المنتج لكن فشل ربط بيانات الصيدلية';
        }
      }
    } on StateError catch (e) {
      if (e.message == 'duplicate_barcode') {
        err = 'هذا الباركود مستخدم لمنتج آخر.';
      } else if (e.message == 'variant_barcode_taken') {
        err = 'باركود المتغير مستخدم مسبقاً.';
      } else if (e.message == 'color_name_required') {
        err = 'اسم اللون مطلوب.';
      } else if (e.message == 'size_required') {
        err = 'حقل المقاس مطلوب.';
      } else if (e.message == 'duplicate_size') {
        err = 'المقاس مكرر داخل نفس اللون.';
      } else if (e.message == 'bad_quantity') {
        err = 'الكمية يجب أن تكون أكبر أو تساوي 0.';
      } else if (e.message == 'duplicate_barcode') {
        err = 'الباركود مستخدم مسبقاً.';
      } else if (e.message == 'family_name_required') {
        err = 'اسم العائلة مطلوب.';
      } else if (e.message == 'oil_grade_required') {
        err = 'أضف لزوجة أو درجة واحدة على الأقل.';
      } else if (e.message == 'viscosity_required') {
        err = 'اسم اللزوجة/الدرجة مطلوب لكل صف.';
      } else {
        err = e.message;
      }
    } catch (e) {
      err = 'تعذر حفظ المنتج: $e';
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
      return;
    }

    if (_multiVariantEnabled || _isFluidFamilyUi || _hasPharmacyExtension) {
      unawaited(context.read<ProductProvider>().loadProducts());
    }

    unawaited(context.read<NotificationProvider>().refresh());

    if (popAfter) {
      Navigator.of(context).pop(true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ المنتج. يمكنك إدخال منتج جديد.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _kGreen,
        ),
      );
      await _resetFormForNewProduct();
    }
  }

  Future<void> _resetFormForNewProduct() async {
    _nameCtrl.clear();
    _descCtrl.clear();
    _supplierCodeCtrl.clear();
    _categoryCtrl.clear();
    _brandCtrl.clear();
    _supplierCtrl.clear();
    _buyPriceCtrl.clear();
    _sellPriceCtrl.clear();
    _minSellPriceCtrl.clear();
    _discountCtrl.clear();
    _customTaxCtrl.clear();
    _qtyCtrl.clear();
    _lowStockCtrl.text = '0';
    _internalNotesCtrl.clear();
    _tagsCtrl.clear();
    _netWeightGramsCtrl.clear();
    _mfgDateCtrl.clear();
    _expDateCtrl.clear();
    final prefs = await SharedPreferences.getInstance();
    _expiryAlertDaysCtrl.text =
        '${(prefs.getInt(NotificationPrefs.defaultExpiryAlertDays) ?? 14).clamp(1, 365)}';
    _grade = null;
    _imagePath = null;
    for (final v in _extraUnitVariants) {
      v.dispose();
    }
    _extraUnitVariants.clear();
    _stockBaseKind = 0;
    _stockTypeUi = 0;
    for (final g in _hydraulicGradeDrafts) {
      _fluidInventoryEditor?.disposeGradeDraft(g);
    }
    _hydraulicGradeDrafts.clear();
    for (final g in _oilFamilyGradeDrafts) {
      _fluidInventoryEditor?.disposeGradeDraft(g);
    }
    _oilFamilyGradeDrafts.clear();
    _taxMode = 'معفى';
    _discountType = '%';
    _trackInventory = _uiSettings.addDefaultTrackInventory;
    _multiVariantEnabled = false;
    for (final c in _colorDrafts) {
      c.dispose();
    }
    _colorDrafts.clear();
    if (_warehouseRows.isNotEmpty) {
      final id = _warehouseRows.first['id'];
      _warehouseId = id is int ? id : (id as num).toInt();
    } else {
      _warehouseId = null;
    }
    _regenerateBarcode();
    _pharmacySession?.resetForm();
    setState(() => _loadingRefs = true);
    try {
      final data = await context
          .read<ProductProvider>()
          .loadAddProductFormData();
      final uiSettings = await InventoryProductSettingsData.load(
        AppSettingsRepository.instance,
      );
      final bcSettings = await BarcodeSettingsData.load(
        AppSettingsRepository.instance,
      );
      if (!mounted) return;
      setState(() {
        _productCodeHint = data.productCodeHint;
        _categoryOptions = data.categories;
        _brandOptions = data.brands;
        _warehouseRows = data.warehouses;
        _supplierOptions = data.suppliers;
        _uiSettings = uiSettings;
        _barcodeStandard = bcSettings.standard;
        _warehouseId = null;
        _trackInventory = uiSettings.addDefaultTrackInventory;
        _costDrivesSuggestedPrices = uiSettings.advancedPricing;
      });
      final defWhStr2 = await AppSettingsRepository.instance.get(
        InventoryProductSettingsKeys.defWarehouseId,
      );
      final defWid2 = int.tryParse(defWhStr2 ?? '');
      final defTax2 = await AppSettingsRepository.instance.get(
        InventoryProductSettingsKeys.defTax1,
      );
      if (!mounted) return;
      setState(() {
        if (defWid2 != null) {
          for (final w in _warehouseRows) {
            final id = (w['id'] as num).toInt();
            if (id == defWid2) {
              _warehouseId = defWid2;
              break;
            }
          }
        }
        if (_warehouseId == null && _warehouseRows.isNotEmpty) {
          final id = _warehouseRows.first['id'];
          _warehouseId = id is int ? id : (id as num).toInt();
        }
        if (defTax2 != null &&
            defTax2.isNotEmpty &&
            {'معفى', '5', '10', '15', 'مخصص'}.contains(defTax2)) {
          _taxMode = defTax2;
        }
      });
    } catch (_) {
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _loadingRefs = false);
    }
  }

  Widget _buildVariantsSection(
    BuildContext context, {
    void Function(void Function())? setStateOverride,
  }) {
    void ss(void Function() fn) {
      final s = setStateOverride ?? setState;
      s(fn);
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Future<void> pickColorFor(_VariantColorDraft c) async {
      final current = parseFlexibleHexColor(c.hexCtrl.text) ?? cs.primary;
      // #region agent log
      DebugNdjsonLogger.log(
        runId: 'pre-fix',
        hypothesisId: 'H3',
        location: 'add_product_screen.dart:_buildVariantsSection:pickColorFor',
        message: 'opening color picker',
        data: {
          'hasHex': c.hexCtrl.text.trim().isNotEmpty,
          'parsedOk': parseFlexibleHexColor(c.hexCtrl.text) != null,
        },
      );
      // #endregion
      final chosen = await showAppColorPickerDialog(
        context: context,
        initialColor: current,
        title: 'اختيار لون',
        subtitle: 'اختر لوناً يمثّل هذا الخيار (اختياري).',
      );
      if (chosen == null || !mounted) return;
      final hex =
          '#${(chosen.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      ss(() {
        c.hexCtrl.text = hex;
        if (!c.nameManuallyEdited) {
          c.nameCtrl.text = arabicColorNameFor(chosen);
        }
      });

      // #region agent log
      DebugNdjsonLogger.log(
        runId: 'pre-fix',
        hypothesisId: 'H3',
        location: 'add_product_screen.dart:_buildVariantsSection:pickColorFor',
        message: 'color picker returned and applied',
        data: {'appliedHex': hex},
      );
      // #endregion
    }

    Future<void> pickSizeFor(_VariantSizeDraft s) async {
      final chosen = await showVariantSizePickerSheet(
        context,
        current: s.sizeCtrl.text.trim(),
      );
      if (chosen == null) return;
      ss(() {
        s.sizeCtrl.text = chosen;
      });
    }

    Future<void> applyUniformQty() async {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تطبيق كمية موحدة'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'أدخل كمية (0 أو أكثر)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final q = _parseNonNegativeInt(ctrl.text);
      if (q < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'الكمية يجب أن تكون رقماً صحيحاً أكبر أو يساوي 0.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      ss(() {
        for (final c in _colorDrafts) {
          for (final s in c.sizes) {
            s.qtyCtrl.text = '$q';
          }
        }
      });
    }

    Widget colorCard(_VariantColorDraft c) {
      final hexColor = parseFlexibleHexColor(c.hexCtrl.text);
      final preview = hexColor ?? cs.surfaceContainerHighest;

      Widget sizeRow(_VariantSizeDraft s, int sizeIndex) {
        return Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: s.sizeCtrl,
                  readOnly: true,
                  canRequestFocus: false,
                  onTap: () => pickSizeFor(s),
                  decoration: InputDecoration(
                    labelText: 'المقاس',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.expand_more, color: cs.primary),
                  ),
                  textAlign: TextAlign.start,
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'اختيار مقاس',
                onPressed: () => pickSizeFor(s),
                icon: Icon(Icons.view_module_outlined, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: s.qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: s.barcodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الباركود (اختياري)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'حذف',
                onPressed: () {
                  ss(() {
                    final removed = c.sizes.removeAt(sizeIndex);
                    removed.dispose();
                  });
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
        );
      }

      return Card(
        elevation: 0,
        margin: const EdgeInsetsDirectional.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: c.nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم اللون',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        c.nameManuallyEdited = true;
                        ss(() {});
                      },
                      textAlign: TextAlign.start,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'اختيار لون (HEX)',
                    child: InkWell(
                      onTap: () => pickColorFor(c),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: preview,
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: hexColor == null
                            ? Icon(
                                Icons.color_lens_outlined,
                                color: cs.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'حذف اللون',
                    onPressed: () {
                      ss(() {
                        final idx = _colorDrafts.indexOf(c);
                        if (idx >= 0) {
                          final removed = _colorDrafts.removeAt(idx);
                          removed.dispose();
                        }
                      });
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'المقاسات والكميات',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (c.sizes.isEmpty)
                      Text(
                        'لا توجد مقاسات بعد. أضف مقاساً واحداً على الأقل.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      )
                    else
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          final list = Column(
                            children: [
                              for (var i = 0; i < c.sizes.length; i++)
                                sizeRow(c.sizes[i], i),
                            ],
                          );
                          if (wide) return list;
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(width: 760, child: list),
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ss(() => c.sizes.add(_VariantSizeDraft()));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('إضافة مقاس'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'إجمالي اللون: ${_totalQtyForColor(c)}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الألوان والمقاسات',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ),
                Text(
                  'الإجمالي: ${_totalQtyAllVariants()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                onPressed: () => ss(() {
                    final c = _VariantColorDraft();
                    c.sizes.add(_VariantSizeDraft());
                    _colorDrafts.add(c);
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة لون جديد'),
                ),
                OutlinedButton.icon(
                  onPressed: _colorDrafts.isEmpty ? null : applyUniformQty,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('تطبيق كمية موحدة على كل المقاسات'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_colorDrafts.isEmpty)
              Text(
                'لا توجد ألوان بعد. أضف لوناً للبدء.',
                style: TextStyle(color: cs.onSurfaceVariant),
                textAlign: TextAlign.end,
              )
            else
              Column(
                children: [for (final c in _colorDrafts) colorCard(c)],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeInnerRouteObserver ??= HomeInnerRouteObserverScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (route is PageRoute && _homeInnerRouteObserver != null) {
      _homeInnerRouteObserver!.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // تم فتح شاشة جديدة فوق شاشة إضافة المنتج.
    // نؤجل الحوار لآخر frame حتى يكون الـ Navigator مستقراً.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleLeaveAttemptFromRouteChange());
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.screenLayout;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final canPopNow = !_saving && !_hasUnsavedChanges();
    return PopScope(
      canPop: canPopNow,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_saving) return;
        final action = await _confirmLeaveIfDirty();
        if (!mounted) return;
        if (action == 0) return;
        if (action == 1) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          return;
        }
        if (action == 2) {
          await _submit(popAfter: true);
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _isDark ? AppColors.primaryDark : const Color(0xFFF1F5F9),
          appBar: AppBar(
            backgroundColor: _isDark ? AppColors.primaryDark : const Color(0xFFF1F5F9),
            foregroundColor: _isDark ? Colors.white : AppColors.primaryDark,
            elevation: 0,
            iconTheme: IconThemeData(color: _isDark ? Colors.white : AppColors.primaryDark),
            title: Text(
              'إضافة منتج جديد',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _isDark ? Colors.white : AppColors.primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: _saving ? null : () => Navigator.maybePop(context),
            ),
          ),
          body: _loadingRefs
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final boundedH =
                        constraints.hasBoundedHeight &&
                        constraints.maxHeight.isFinite;

                    Widget mainFields() {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.pageHorizontalGap,
                          vertical: 16,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: LayoutBuilder(
                              builder: (_, c) {
                                return _buildProductFormLayout(
                                  context,
                                  maxWidth: c.maxWidth,
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    }

                    return Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: boundedH
                          ? Column(
                              children: [
                                _buildToolbar(context),
                                Divider(height: 1, color: theme.dividerColor),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: mainFields(),
                                  ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildToolbar(context),
                                  Divider(height: 1, color: theme.dividerColor),
                                  mainFields(),
                                ],
                              ),
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final layout = context.screenLayout;
    if (layout.isHandsetForLayout) {
      return _buildHandsetToolbar(context);
    }
    return _buildWideToolbar(context);
  }

  /// شريط أزرار مضغوط — صف واحد على الهاتف لتقليل الارتفاع.
  Widget _buildHandsetToolbar(BuildContext context) {
    final layout = context.screenLayout;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.primary : Colors.white;
    final narrow = layout.isNarrowWidth;
    final saveLabel = _saving ? 'جاري…' : (narrow ? 'حفظ' : 'حفظ المنتج');
    final saveNewLabel = narrow ? 'حفظ+' : 'حفظ وجديد';

    final compactShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final compactPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 6);
    final compactText = const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

    return Material(
      color: surfaceColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.pageHorizontalGap,
          6,
          layout.pageHorizontalGap,
          6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'رمز المنتج: $_productCodeHint',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accentGold, width: 1.2),
                      foregroundColor: AppColors.accentGold,
                      padding: compactPadding,
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: compactShape,
                      textStyle: compactText,
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _submit(popAfter: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: compactPadding,
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: compactShape,
                      textStyle: compactText,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(saveLabel),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _submit(popAfter: false),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? AppColors.primaryDark : AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: compactPadding,
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: compactShape,
                      textStyle: compactText,
                    ),
                    child: Text(saveNewLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideToolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.primary : Colors.white;
    return Material(
      color: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'رمز المنتج: $_productCodeHint',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accentGold, width: 1.5),
                    foregroundColor: AppColors.accentGold,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _submit(popAfter: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(_saving ? 'جاري الحفظ…' : 'حفظ المنتج'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : () => _submit(popAfter: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppColors.primaryDark : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Colors.white),
                  label: const Text('حفظ وإضافة جديد', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── البطاقات ───────────────────────────────────────────────────────────

  /// تخطيط النموذج: على الشاشات العريضة تُوضَع «إدارة المخزون» تحت التسعير
  /// في العمود الجانبي (المساحة الفارغة يساراً في RTL) بدل أسفل الصفحة كاملة.
  Widget _buildProductFormLayout(BuildContext context, {required double maxWidth}) {
    if (maxWidth >= 720) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 11,
            child: _buildIdentityCard(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPricingCard(context),
                const SizedBox(height: 16),
                _buildInventoryCard(context),
                if (_hasPharmacyExtension) ...[
                  const SizedBox(height: 16),
                  _buildPharmacyExtensionCard(context),
                ],
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIdentityCard(context),
        const SizedBox(height: 16),
        _buildPricingCard(context),
        const SizedBox(height: 16),
        _buildInventoryCard(context),
        if (_hasPharmacyExtension) ...[
          const SizedBox(height: 16),
          _buildPharmacyExtensionCard(context),
        ],
      ],
    );
  }

  Widget _buildPharmacyExtensionCard(BuildContext context) {
    final session = _pharmacySession;
    if (session == null) return const SizedBox.shrink();
    return _sectionCard(
      context,
      title: 'بيانات الدواء',
      child: session.buildAddProductSection(
        context: context,
        onChanged: () => setState(() {}),
        onDrugReferenceSelected: (reference) {
          if (_nameCtrl.text.trim().isEmpty) {
            _nameCtrl.text = reference.nameAr.isNotEmpty
                ? reference.nameAr
                : reference.nameEn;
          }
          setState(() {});
        },
        onBatchDraftChanged: (batch) {
          _qtyCtrl.text = batch.qty % 1 == 0
              ? batch.qty.toInt().toString()
              : batch.qty.toString();
          _buyPriceCtrl.text =
              IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(batch.costFils));
          if (_sellPriceCtrl.text.trim().isEmpty) {
            _sellPriceCtrl.text = _buyPriceCtrl.text;
          }
          _expDateCtrl.text = _displayDateFromIso(
            DateTime(
              batch.expiryDate.year,
              batch.expiryDate.month,
              batch.expiryDate.day,
            ).toIso8601String(),
          );
          setState(() {});
        },
      ),
    );
  }

  Widget _buildIdentityCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'بيانات المنتج',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppInput(
                  label: 'اسم المنتج',
                  isRequired: true,
                  controller: _nameCtrl,
                  focusNode: _focusName,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusDesc.requestFocus(),
                  textAlign: TextAlign.right,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                child: _labeledField(
                  context,
                  label: 'SKU',
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                    child: Text(
                      _productCodeHint,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'الوصف',
            controller: _descCtrl,
            focusNode: _focusDesc,
            textAlign: TextAlign.right,
            minLines: 2,
            maxLines: 4,
            suffixIcon: ArabicSpeechMicButton(
              controller: _descCtrl,
              onTextUpdated: () => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          if (_uiSettings.addShowImageField) ...[
            _labeledField(
              context,
              label: 'صورة المنتج',
              requiredField: _uiSettings.addRequireImage,
              child: _imageTile(context),
            ),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (_, c) {
              final pairRow =
                  context.screenLayout.isHandsetForLayout || c.maxWidth >= 520;
              final gap = context.screenLayout.isHandsetForLayout ? 8.0 : 12.0;
              final cat = _comboField(
                context,
                label: 'التصنيف',
                controller: _categoryCtrl,
                options: _categoryOptions,
                hint: 'اكتب أو اختر من القائمة',
                focusNode: _focusCategory,
                onFieldSubmitted: (_) => _focusBrand.requestFocus(),
              );
              final br = _comboField(
                context,
                label: 'الماركة',
                controller: _brandCtrl,
                options: _brandOptions,
                hint: 'اكتب أو اختر من القائمة',
                focusNode: _focusBrand,
                onFieldSubmitted: (_) => _focusSupplier.requestFocus(),
              );
              if (pairRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cat),
                    SizedBox(width: gap),
                    Expanded(child: br),
                  ],
                );
              }
              return Column(children: [cat, const SizedBox(height: 14), br]);
            },
          ),
          // ── حقل الرتبة / درجة الجودة ─────────────────────────────────────
          if (_policy.enableProductGrade) ...[
            const SizedBox(height: 14),
            _labeledField(
              context,
              label: 'الرتبة / درجة الجودة',
              child: DropdownButtonFormField<String?>(
                value: _grade,
                isExpanded: true,
                decoration: _inputDecOf(context, hint: 'اختر الدرجة (اختياري)'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('— بدون تصنيف —')),
                  DropdownMenuItem(value: 'A', child: Text('درجة A — ممتاز')),
                  DropdownMenuItem(
                    value: 'B',
                    child: Text('درجة B — جيد جداً'),
                  ),
                  DropdownMenuItem(value: 'C', child: Text('درجة C — جيد')),
                  DropdownMenuItem(
                    value: 'درجة أولى',
                    child: Text('درجة أولى'),
                  ),
                  DropdownMenuItem(
                    value: 'درجة ثانية',
                    child: Text('درجة ثانية'),
                  ),
                  DropdownMenuItem(
                    value: 'درجة ثالثة',
                    child: Text('درجة ثالثة'),
                  ),
                  DropdownMenuItem(value: 'تجاري', child: Text('صنف تجاري')),
                  DropdownMenuItem(
                    value: 'اقتصادي',
                    child: Text('صنف اقتصادي'),
                  ),
                ],
                onChanged: (v) => setState(() => _grade = v),
              ),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (_, c) {
              final pairRow =
                  context.screenLayout.isHandsetForLayout || c.maxWidth >= 520;
              final gap = context.screenLayout.isHandsetForLayout ? 8.0 : 12.0;
              final warehouse = _labeledField(
                context,
                label: 'المخزن',
                requiredField: _uiSettings.addRequireWarehouse,
                child: DropdownButtonFormField<int?>(
                  value: _warehouseId,
                  isExpanded: true,
                  decoration: _inputDecOf(context, hint: ''),
                  hint: Text(
                    _warehouseRows.isEmpty
                        ? 'لا توجد مستودعات في قاعدة البيانات'
                        : 'اختر المخزن',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text(
                        '— بدون ربط بمخزن —',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    ..._warehouseRows.map(
                      (w) => DropdownMenuItem<int?>(
                        value: (w['id'] as num).toInt(),
                        child: Text(
                          w['name'] as String,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  onChanged: _warehouseRows.isEmpty
                      ? null
                      : (v) => setState(() => _warehouseId = v),
                ),
              );
              final stockType = _labeledField(
                context,
                label: 'نوع المخزون الأساسي',
                child: DropdownButtonFormField<int>(
                  value: _stockTypeUi,
                  isExpanded: true,
                  decoration: _inputDecOf(context, hint: ''),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('عدد (قطعة كأساس)'),
                    ),
                    if (_enableWeightSales)
                      const DropdownMenuItem(
                        value: 1,
                        child: Text('وزن (كيلوغرام كأساس)'),
                      ),
                    if (_enableClothingVariants)
                      const DropdownMenuItem(
                        value: 2,
                        child: Text('ملابس (ألوان ومقاسات)'),
                      ),
                    const DropdownMenuItem(
                      value: 3,
                      child: Text('حجم (لتر كأساس — زيت مفرد)'),
                    ),
                    if (_fluidInventoryEditor != null) ...[
                      const DropdownMenuItem(
                        value: 4,
                        child: Text('هيدروليك — عائلة (ماركة + درجات وعبوات)'),
                      ),
                      const DropdownMenuItem(
                        value: 5,
                        child: Text('زيت — عائلة (ماركة + لزوجات وعبوات)'),
                      ),
                    ],
                  ],
                  onChanged: (v) {
                    final next = v ?? 0;
                    setState(() {
                      _stockTypeUi = next;
                      if (next == 2) {
                        _multiVariantEnabled = true;
                        _trackInventory = true;
                        _stockBaseKind = 0;
                        if (_colorDrafts.isEmpty) {
                          final c = _VariantColorDraft();
                          c.sizes.add(_VariantSizeDraft());
                          _colorDrafts.add(c);
                        }
                      } else if (next == 4) {
                        _multiVariantEnabled = false;
                        _trackInventory = true;
                        _stockBaseKind = 3;
                        if (_hydraulicGradeDrafts.isEmpty) {
                          final draft = _fluidInventoryEditor?.newGradeDraft();
                          if (draft != null) _hydraulicGradeDrafts.add(draft);
                        }
                      } else if (next == 5) {
                        _multiVariantEnabled = false;
                        _trackInventory = true;
                        _stockBaseKind = 3;
                        if (_oilFamilyGradeDrafts.isEmpty) {
                          final draft = _fluidInventoryEditor?.newGradeDraft();
                          if (draft != null) _oilFamilyGradeDrafts.add(draft);
                        }
                      } else {
                        _multiVariantEnabled = false;
                        _stockBaseKind = next == 3 ? 3 : next;
                      }
                    });
                  },
                ),
              );
              if (pairRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: warehouse),
                    SizedBox(width: gap),
                    Expanded(child: stockType),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  warehouse,
                  const SizedBox(height: 14),
                  stockType,
                ],
              );
            },
          ),
          if (_stockTypeUi == 2) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الألوان والمقاسات',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _variantsSummaryLine(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: _openVariantsEditor,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('تعديل الألوان والمقاسات'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_isFluidFamilyUi && _fluidInventoryEditor != null) ...[
            const SizedBox(height: 10),
            _fluidInventoryEditor!.buildGradesEditor(
              context: context,
              isOilFamily: _stockTypeUi == 5,
              grades: _activeFluidGradeDrafts,
              onChanged: () => setState(() {}),
            ),
          ],
          if (_stockTypeUi != 2 &&
              _stockTypeUi != 3 &&
              !_isFluidFamilyUi)
            _saleExtraUnitsEditor(context),
          if (_stockTypeUi == 3) ...[
            const SizedBox(height: 8),
            Text(
              'أضف وحدات البيع من «وحدات إضافية»: أساسي لتر (معامل 1) وعلبة (مثال: معامل 5). '
              'مناسب لزيت مفرد — سعر اللتر وسعر العلبة لكل وحدة.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 8),
            _saleExtraUnitsEditor(context),
          ],
          const SizedBox(height: 14),
          Text(
            'معلومات المورد',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, c) {
              final pairRow =
                  context.screenLayout.isHandsetForLayout || c.maxWidth >= 520;
              final gap = context.screenLayout.isHandsetForLayout ? 8.0 : 12.0;
              final supplier = _comboField(
                context,
                label: 'المورد',
                controller: _supplierCtrl,
                options: _supplierOptions,
                hint: 'اكتب أو اختر من السجل',
                requiredField: _uiSettings.addRequireSupplier,
                focusNode: _focusSupplier,
                onFieldSubmitted: (_) => _focusSupplierCode.requestFocus(),
              );
              final supplierCode = _labeledField(
                context,
                label: 'كود المورد (اختياري)',
                child: AppInput(
                  label: '',
                  showLabel: false,
                  controller: _supplierCodeCtrl,
                  focusNode: _focusSupplierCode,
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _goAfterSupplierCode(),
                ),
              );
              if (pairRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: supplier),
                    SizedBox(width: gap),
                    Expanded(child: supplierCode),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  supplier,
                  const SizedBox(height: 14),
                  supplierCode,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (_uiSettings.addShowBarcodeField) _barcodeBlock(context),
        ],
      ),
    );
  }

  Widget _saleExtraUnitsEditor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.accentGold.withValues(alpha: 0.35) : AppColors.accentGold.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'وحدات بيع إضافية (اختياري)',
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'مثال: كرتون، طبقة، كيلوغرام… لكل وحدة باركود اختياري وعامل تحويل إلى أساس المخزون.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: () => setState(
                () => _extraUnitVariants.add(_ExtraUnitVariantDraft()),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accentGold, width: 1.5),
                foregroundColor: AppColors.accentGold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة وحدة'),
            ),
          ),
          if (_extraUnitVariants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'لا توجد وحدات إضافية بعد.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _extraUnitVariants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final row = _extraUnitVariants[i];
                return Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: ac.sm,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'وحدة ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => setState(() {
                                final r = _extraUnitVariants.removeAt(i);
                                r.dispose();
                              }),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: AppInput(
                                label: '',
                                showLabel: false,
                                controller: row.unitName,
                                textAlign: TextAlign.right,
                                hint: 'اسم الوحدة',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: AppInput(
                                label: '',
                                showLabel: false,
                                controller: row.unitSymbol,
                                textAlign: TextAlign.right,
                                hint: 'رمز',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: AppInput(
                                label: '',
                                showLabel: false,
                                controller: row.factor,
                                textAlign: TextAlign.right,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                hint: 'عامل التحويل إلى الأساس',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppInput(
                                label: '',
                                showLabel: false,
                                controller: row.barcode,
                                textAlign: TextAlign.right,
                                hint: 'باركود (اختياري)',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: AppPriceInput(
                                label: '',
                                paddingZeroOverride: true,
                                hint: 'اختياري — $_hintIqd',
                                controller: row.sell,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppPriceInput(
                                label: '',
                                paddingZeroOverride: true,
                                hint: 'أدنى سعر بيع — $_hintIqd',
                                controller: row.minSell,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _barcodeBlock(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final raw = _barcodeCtrl.text.trim();
    final isEan = _barcodeStandard == 'ean13';
    final bc = isEan ? Barcode.ean13() : Barcode.code128();

    String barcodeData;
    if (isEan) {
      final d = raw.isEmpty
          ? '000000000000'
          : raw.replaceAll(RegExp(r'\D'), '');
      barcodeData = d.padLeft(12, '0');
      if (barcodeData.length > 12) {
        barcodeData = barcodeData.substring(barcodeData.length - 12);
      }
    } else {
      barcodeData = raw.isEmpty ? '0000000' : raw;
      if (barcodeData.length > 48) {
        barcodeData = barcodeData.substring(0, 48);
      }
    }

    final barColor = cs.onSurface;
    final bgBarcode = cs.surfaceContainerHighest.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                isEan ? 'الباركود (EAN-13)' : 'الباركود (Code 128)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, c) {
            final w = (c.maxWidth - 24).clamp(120.0, 360.0);
            return Center(
              child: Container(
                width: w,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: bgBarcode,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: BarcodeWidget(
                  barcode: bc,
                  data: barcodeData,
                  drawText: true,
                  color: barColor,
                  backgroundColor: Colors.transparent,
                  width: w - 16,
                  height: 56,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppInput(
                label: '',
                showLabel: false,
                controller: _barcodeCtrl,
                focusNode: _focusBarcodeField,
                textAlign: TextAlign.right,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _focusBuy.requestFocus(),
                keyboardType:
                    isEan ? TextInputType.number : TextInputType.text,
                inputFormatters: isEan
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(13),
                      ]
                    : [LengthLimitingTextInputFormatter(48)],
                hint: 'قيمة الباركود',
                prefixIcon: Icon(
                  Icons.barcode_reader,
                  color: cs.onSurfaceVariant,
                  size: 22,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: BarcodeInputLauncher.useCamera(context)
                  ? 'التقاط من الكاميرا'
                  : 'قراءة من جهاز قارئ الباركود',
              child: Material(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    final code = await BarcodeInputLauncher.captureBarcode(
                      context,
                      title: 'قراءة باركود المنتج',
                    );
                    if (!mounted || code == null || code.trim().isEmpty) return;
                    setState(() => _barcodeCtrl.text = code.trim());
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      BarcodeInputLauncher.useCamera(context)
                          ? Icons.camera_alt_rounded
                          : Icons.keyboard_alt_rounded,
                      color: cs.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'توليد باركود رقمي جديد',
              child: Material(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _regenerateBarcode,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.refresh_rounded,
                      color: cs.primary,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pricingFieldsRow(
    BuildContext context, {
    required List<Widget> fields,
    List<int>? flex,
    double gap = 8,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            flex: flex != null && i < flex.length ? flex[i] : 1,
            child: fields[i],
          ),
        ],
      ],
    );
  }

  Widget _buildTaxDropdown(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _taxMode,
      isExpanded: true,
      decoration: _inputDecOf(context, hint: ''),
      items: const [
        DropdownMenuItem(value: 'معفى', child: Text('معفى')),
        DropdownMenuItem(value: '5', child: Text('5٪')),
        DropdownMenuItem(value: '10', child: Text('10٪')),
        DropdownMenuItem(value: '15', child: Text('15٪')),
        DropdownMenuItem(value: 'مخصص', child: Text('مخصص')),
      ],
      onChanged: (v) {
        setState(() => _taxMode = v ?? 'معفى');
      },
    );
  }

  Widget _buildDiscountTypeDropdown(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'نوع الخصم',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _discountType,
          isExpanded: true,
          decoration: _inputDecOf(context, hint: ''),
          selectedItemBuilder: (context) => const [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'نسبة (٪)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'مبلغ (د.ع)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          items: const [
            DropdownMenuItem(
              value: '%',
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'نسبة مئوية (٪)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'د.ع',
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'عمولة / مبلغ (د.ع)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() {
              final next = v ?? '%';
              if (next != _discountType) {
                _discountCtrl.clear();
              }
              _discountType = next;
            });
          },
        ),
      ],
    );
  }

  Widget _buildProfitMarginReadout(BuildContext context) {
    final buyN = NumericFormat.parseNumber(_buyPriceCtrl.text);
    final cs2 = Theme.of(context).colorScheme;
    Color tone;
    if (buyN <= 0) {
      tone = cs2.onSurfaceVariant;
    } else if (_profitMarginPct < 0) {
      tone = Colors.red.shade700;
    } else if (_profitMarginPct < 5) {
      tone = const Color(0xFFF59E0B);
    } else {
      tone = _kGreen;
    }
    return Container(
      height: 42,
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs2.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs2.outlineVariant),
      ),
      child: Text(
        buyN > 0 ? '${_profitMarginPct.toStringAsFixed(1)}٪' : '—',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: tone,
        ),
      ),
    );
  }

  /// تخطيط التسعير المضغوط للهاتف — صفوف أفقية لتوفير المساحة.
  Widget _buildHandsetPricingLayout(
    BuildContext context, {
    required String? perKgHint,
  }) {
    final cs = Theme.of(context).colorScheme;
    final showTax =
        _uiSettings.addShowAdvancedPricing && _uiSettings.addShowTaxField;
    final showDiscount =
        _uiSettings.addShowAdvancedPricing && _uiSettings.addShowDiscountFields;

    final buyPrice = _labeledField(
      context,
      label: 'سعر الشراء',
      subtitle: perKgHint,
      child: AppPriceInput(
        label: '',
        paddingZeroOverride: true,
        hint: _hintIqd,
        controller: _buyPriceCtrl,
        focusNode: _focusBuy,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _focusSell.requestFocus(),
        onParsedChanged: (_) => setState(() {}),
      ),
    );
    final sellPrice = _labeledField(
      context,
      label: 'سعر البيع',
      subtitle: perKgHint,
      child: AppPriceInput(
        label: '',
        paddingZeroOverride: true,
        hint: _hintIqd,
        controller: _sellPriceCtrl,
        focusNode: _focusSell,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _goAfterSell(),
        warningText: _sellBelowBuy
            ? 'تحذير: سعر البيع أقل من سعر الشراء (يمكن الإكمال).'
            : null,
        onParsedChanged: (_) => setState(() {}),
      ),
    );
    final taxField = _labeledField(
      context,
      label: 'الضريبة',
      child: _buildTaxDropdown(context),
    );
    final discountType = _buildDiscountTypeDropdown(context, cs);
    final discountValue = _labeledField(
      context,
      label: 'قيمة الخصم',
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _discountCtrl,
        focusNode: _focusDiscount,
        textAlign: TextAlign.end,
        textDirection: TextDirection.ltr,
        textInputAction: TextInputAction.next,
        selectAllOnFocus: true,
        onFieldSubmitted: (_) => _goAfterDiscount(),
        keyboardType: _discountType == '%'
            ? const TextInputType.numberWithOptions(decimal: true)
            : const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: _discountType == '%'
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : [IraqiCurrencyFormat.moneyInputFormatter()],
        hint: _discountType == '%' ? 'مثال: 15' : _hintIqd,
        suffixText: _discountType == '%' ? '٪' : 'د.ع',
      ),
    );
    final minSell = _labeledField(
      context,
      label: 'أقل سعر بيع',
      subtitle: perKgHint,
      child: AppPriceInput(
        label: '',
        paddingZeroOverride: true,
        hint: 'اختياري',
        controller: _minSellPriceCtrl,
        focusNode: _focusMin,
        isOptional: true,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _goAfterMin(),
        onParsedChanged: (_) => setState(() {}),
      ),
    );
    final profitMargin = _labeledField(
      context,
      label: 'هامش الربح',
      child: _buildProfitMarginReadout(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uiSettings.advancedPricing) ...[
          Material(
            color: cs.primaryContainer.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _costDrivesSuggestedPrices
                          ? 'هامش ${_marginPercentUiLabel()}٪ على التكلفة'
                          : 'التعديل اليدوي نشط',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_costDrivesSuggestedPrices) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _relinkSuggestedPricesToCost,
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('إعادة الربط بتكلفة الشراء'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        _pricingFieldsRow(context, fields: [buyPrice, sellPrice]),
        if (showTax || showDiscount) ...[
          const SizedBox(height: 12),
          if (showTax && showDiscount)
            _pricingFieldsRow(
              context,
              flex: const [2, 2, 2],
              fields: [taxField, discountType, discountValue],
            )
          else if (showTax)
            taxField
          else
            _pricingFieldsRow(
              context,
              fields: [discountType, discountValue],
            ),
          if (showTax && _taxMode == 'مخصص') ...[
            const SizedBox(height: 8),
            AppInput(
              label: '',
              showLabel: false,
              controller: _customTaxCtrl,
              focusNode: _focusCustomTax,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _goAfterCustomTax(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              hint: 'نسبة الضريبة %',
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (showTax && _effectiveTaxPercent > 0) ...[
            const SizedBox(height: 6),
            Text(
              'شاملاً الضريبة: ${IraqiCurrencyFormat.formatIqd(_sellAfterTaxApprox)}',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        if (_uiSettings.addShowAdvancedPricing)
          _pricingFieldsRow(context, fields: [minSell, profitMargin])
        else
          minSell,
      ],
    );
  }

  Widget _buildPricingCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_isFluidFamilyUi) {
      final labels = _fluidInventoryEditor?.labels(
        isOilFamily: _stockTypeUi == 5,
      );
      return _sectionCard(
        context,
        title: 'التسعير',
        child: Text(
          labels?.pricingHint ??
              'سعر الشراء والبيع يُحدَّد في جدول اللزوجات/الدرجات أعلاه.',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          textAlign: TextAlign.start,
        ),
      );
    }
    final perKgHint = _stockBaseKind == 1
        ? 'يُحسب لكل كيلوغرام واحد (أساس المخزون بالوزن).'
        : null;
    final isHandset = context.screenLayout.isHandsetForLayout;
    if (isHandset) {
      return _sectionCard(
        context,
        title: 'التسعير',
        child: _buildHandsetPricingLayout(context, perKgHint: perKgHint),
      );
    }
    return _sectionCard(
      context,
      title: 'التسعير',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labeledField(
            context,
            label: 'سعر الشراء',
            subtitle: perKgHint,
            child: AppPriceInput(
              label: '',
              paddingZeroOverride: true,
              hint: _hintIqd,
              controller: _buyPriceCtrl,
              focusNode: _focusBuy,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusSell.requestFocus(),
              onParsedChanged: (_) => setState(() {}),
            ),
          ),
          if (_uiSettings.advancedPricing) ...[
            const SizedBox(height: 10),
            Material(
              color: cs.primaryContainer.withValues(alpha: 0.28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 22,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'اقتراح من سعر الشراء',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _costDrivesSuggestedPrices
                                    ? 'هامش ${_marginPercentUiLabel()}٪ على التكلفة؛ أقل سعر = ${_minSellPercentUiLabel()}٪ من سعر البيع. تعديل سعر البيع أو أقل سعر يوقف التحديث التلقائي.'
                                    : 'التعديل اليدوي نشط — لن يُحدَّث سعر البيع تلقائياً عند تغيير التكلفة.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!_costDrivesSuggestedPrices) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _relinkSuggestedPricesToCost,
                          icon: const Icon(Icons.link_rounded, size: 18),
                          label: const Text('إعادة الربط بتكلفة الشراء'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _labeledField(
            context,
            label: 'سعر البيع',
            subtitle: perKgHint,
            child: AppPriceInput(
              label: '',
              paddingZeroOverride: true,
              hint: _hintIqd,
              controller: _sellPriceCtrl,
              focusNode: _focusSell,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _goAfterSell(),
              warningText: _sellBelowBuy
                  ? 'تحذير: سعر البيع أقل من سعر الشراء (يمكن الإكمال).'
                  : null,
              onParsedChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          if (_uiSettings.addShowAdvancedPricing &&
              _uiSettings.addShowTaxField) ...[
            _labeledField(
              context,
              label: 'الضريبة',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (_, c) {
                      if (c.maxWidth >= 520) {
                        return SegmentedButton<String>(
                          style: SegmentedButton.styleFrom(
                            side: BorderSide(
                              color: _isDark ? AppColors.accentGold.withValues(alpha: 0.35) : AppColors.accentGold.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          segments: const [
                            ButtonSegment(value: 'معفى', label: Text('معفى')),
                            ButtonSegment(value: '5', label: Text('5٪')),
                            ButtonSegment(value: '10', label: Text('10٪')),
                            ButtonSegment(value: '15', label: Text('15٪')),
                            ButtonSegment(value: 'مخصص', label: Text('مخصص')),
                          ],
                          selected: {_taxMode},
                          onSelectionChanged: (s) {
                            setState(() => _taxMode = s.first);
                          },
                        );
                      }
                      return DropdownButtonFormField<String>(
                        value: _taxMode,
                        isExpanded: true,
                        decoration: _inputDecOf(context, hint: ''),
                        items: const [
                          DropdownMenuItem(
                            value: 'معفى',
                            child: Text('معفى من الضريبة'),
                          ),
                          DropdownMenuItem(value: '5', child: Text('ضريبة 5٪')),
                          DropdownMenuItem(
                            value: '10',
                            child: Text('ضريبة 10٪'),
                          ),
                          DropdownMenuItem(
                            value: '15',
                            child: Text('ضريبة 15٪'),
                          ),
                          DropdownMenuItem(
                            value: 'مخصص',
                            child: Text('نسبة مخصصة'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _taxMode = v ?? 'معفى');
                        },
                      );
                    },
                  ),
                  if (_taxMode == 'مخصص') ...[
                    const SizedBox(height: 10),
                    AppInput(
                      label: '',
                      showLabel: false,
                      controller: _customTaxCtrl,
                      focusNode: _focusCustomTax,
                      textAlign: TextAlign.end,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _goAfterCustomTax(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      hint: 'نسبة الضريبة %',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  if (_effectiveTaxPercent > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      'البيع شاملاً الضريبة (تقريبي): ${IraqiCurrencyFormat.formatIqd(_sellAfterTaxApprox)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (_, c) {
              final row = c.maxWidth >= 480;
              final discType = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'نوع الخصم',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _discountType,
                    isExpanded: true,
                    decoration: _inputDecOf(context, hint: ''),
                    selectedItemBuilder: (context) => const [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'نسبة مئوية (٪)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'عمولة / مبلغ (د.ع)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    items: const [
                      DropdownMenuItem(
                        value: '%',
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'نسبة مئوية (٪)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'د.ع',
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'عمولة / مبلغ (د.ع)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        final next = v ?? '%';
                        if (next != _discountType) {
                          _discountCtrl.clear();
                        }
                        _discountType = next;
                      });
                    },
                  ),
                ],
              );
              final discVal = _labeledField(
                context,
                label: 'قيمة الخصم',
                child: AppInput(
                  label: '',
                  showLabel: false,
                  controller: _discountCtrl,
                  focusNode: _focusDiscount,
                  textAlign: TextAlign.end,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  selectAllOnFocus: true,
                  onFieldSubmitted: (_) => _goAfterDiscount(),
                  keyboardType: _discountType == '%'
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: _discountType == '%'
                      ? [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ]
                      : [IraqiCurrencyFormat.moneyInputFormatter()],
                  hint: _discountType == '%' ? 'مثال: 15' : _hintIqd,
                  suffixText: _discountType == '%' ? '٪' : 'د.ع',
                ),
              );
              final minP = _labeledField(
                context,
                label: 'أقل سعر بيع',
                subtitle: perKgHint,
                child: AppPriceInput(
                  label: '',
                  paddingZeroOverride: true,
                  hint: 'اختياري',
                  controller: _minSellPriceCtrl,
                  focusNode: _focusMin,
                  isOptional: true,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _goAfterMin(),
                  onParsedChanged: (_) => setState(() {}),
                ),
              );
              if (!_uiSettings.addShowAdvancedPricing ||
                  !_uiSettings.addShowDiscountFields) {
                return minP;
              }
              if (row) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: discType),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: discVal),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: minP),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  discType,
                  const SizedBox(height: 12),
                  discVal,
                  const SizedBox(height: 12),
                  minP,
                ],
              );
            },
          ),
          if (_uiSettings.addShowAdvancedPricing) ...[
            const SizedBox(height: 14),
            _labeledField(
              context,
              label: 'هامش الربح (سعر البيع مقابل الشراء)',
              child: Builder(
                builder: (context) {
                  final buyN = NumericFormat.parseNumber(_buyPriceCtrl.text);
                  final cs2 = Theme.of(context).colorScheme;
                  Color tone;
                  if (buyN <= 0) {
                    tone = cs2.onSurfaceVariant;
                  } else if (_profitMarginPct < 0) {
                    tone = Colors.red.shade700;
                  } else if (_profitMarginPct < 5) {
                    tone = const Color(0xFFF59E0B);
                  } else {
                    tone = _kGreen;
                  }
                  return Container(
                    height: 42,
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: cs2.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs2.outlineVariant),
                    ),
                    child: Text(
                      buyN > 0 ? '${_profitMarginPct.toStringAsFixed(1)}٪' : '—',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: tone,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHandsetInventorySixFieldGrid(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qtyHint = _stockBaseKind == 1 ? 'كغ' : null;
    final lowHint = _stockBaseKind == 1 ? 'كغ' : null;

    final qty = _labeledField(
      context,
      label: 'الكمية',
      subtitle: qtyHint,
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _qtyCtrl,
        focusNode: _focusQty,
        textAlign: TextAlign.end,
        textDirection: TextDirection.ltr,
        textInputAction: TextInputAction.next,
        selectAllOnFocus: true,
        onFieldSubmitted: (_) => _focusLow.requestFocus(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        hint: '0',
      ),
    );
    final low = _labeledField(
      context,
      label: 'تنبيه المخزون',
      subtitle: lowHint,
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _lowStockCtrl,
        focusNode: _focusLow,
        textAlign: TextAlign.end,
        textDirection: TextDirection.ltr,
        selectAllOnFocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        hint: '0',
      ),
    );
    final weight = _labeledField(
      context,
      label: 'الوزن (غ)',
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _netWeightGramsCtrl,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        hint: 'اختياري',
      ),
    );
    final mfg = _labeledField(
      context,
      label: 'تاريخ الإنتاج',
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _mfgDateCtrl,
        textAlign: TextAlign.right,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          onPressed: () => _pickProductDate(_mfgDateCtrl),
          tooltip: 'اختر من التقويم',
          visualDensity: VisualDensity.compact,
        ),
        hint: 'يوم/شهر/سنة',
      ),
    );
    final exp = _labeledField(
      context,
      label: 'تاريخ الانتهاء',
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _expDateCtrl,
        textAlign: TextAlign.right,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          onPressed: () => _pickProductDate(_expDateCtrl),
          tooltip: 'اختر من التقويم',
          visualDensity: VisualDensity.compact,
        ),
        hint: 'يوم/شهر/سنة',
      ),
    );
    final expiryAlert = _labeledField(
      context,
      label: 'تنبيه الصلاحية',
      child: AppInput(
        label: '',
        showLabel: false,
        controller: _expiryAlertDaysCtrl,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        hint: '14',
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pricingFieldsRow(
          context,
          flex: const [1, 1, 1],
          fields: [qty, low, weight],
        ),
        const SizedBox(height: 12),
        _pricingFieldsRow(
          context,
          flex: const [1, 1, 1],
          fields: [mfg, exp, expiryAlert],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            'يُستخدم مع «تاريخ الانتهاء» فقط؛ يظهر التنبيه في لوحة الإشعارات خلال هذه المدة قبل التاريخ.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHandset = context.screenLayout.isHandsetForLayout;
    final showQtyLow =
        _trackInventory && !_multiVariantEnabled && !_isFluidFamilyUi;
    final showExtra = _uiSettings.addShowExtraFields;
    final handsetSixGrid = isHandset && showQtyLow && showExtra;
    return _sectionCard(
      context,
      title: 'إدارة المخزون',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تتبع المخزون',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              'عند الإيقاف لا تُسجَّل كميات لهذا المنتج',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            value: _trackInventory,
            activeThumbColor: cs.primary,
            onChanged:
                _multiVariantEnabled ? null : (v) => setState(() => _trackInventory = v),
          ),
          if (showQtyLow && !handsetSixGrid) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (_, c) {
                final row =
                    context.screenLayout.isHandsetForLayout || c.maxWidth >= 480;
                final qtyHint = _stockBaseKind == 1
                    ? 'بالكيلوغرام — يدعم الكسور (0.25، 0.5، 1.5…)'
                    : null;
                final lowHint = _stockBaseKind == 1
                    ? 'بالكيلوغرام (مثال: 1 = تنبيه عند أقل من 1 كغ)'
                    : null;
                final q = _labeledField(
                  context,
                  label: 'الكمية في المخزون',
                  child: AppInput(
                    label: '',
                    showLabel: false,
                    controller: _qtyCtrl,
                    focusNode: _focusQty,
                    textAlign: TextAlign.end,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    selectAllOnFocus: true,
                    onFieldSubmitted: (_) => _focusLow.requestFocus(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    hint: '0',
                  ),
                  subtitle: qtyHint,
                );
                final low = _labeledField(
                  context,
                  label: 'تنبيه عند أقل من',
                  child: AppInput(
                    label: '',
                    showLabel: false,
                    controller: _lowStockCtrl,
                    focusNode: _focusLow,
                    textAlign: TextAlign.end,
                    textDirection: TextDirection.ltr,
                    selectAllOnFocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    hint: '0',
                  ),
                  subtitle: lowHint,
                );
                if (row) {
                  return Row(
                    children: [
                      Expanded(child: q),
                      SizedBox(
                        width: context.screenLayout.isHandsetForLayout ? 8 : 12,
                      ),
                      Expanded(child: low),
                    ],
                  );
                }
                return Column(children: [q, const SizedBox(height: 12), low]);
              },
            ),
          ],
          if (handsetSixGrid) ...[
            const SizedBox(height: 8),
            _buildHandsetInventorySixFieldGrid(context),
          ],
          if (_trackInventory && _multiVariantEnabled) ...[
            const SizedBox(height: 8),
            Text(
              'المخزون يُدار عبر الألوان والمقاسات. الإجمالي الحالي: ${_totalQtyAllVariants()}',
              textAlign: TextAlign.end,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          if (showExtra) ...[
            if (!handsetSixGrid) ...[
              const SizedBox(height: 12),
              _labeledField(
                context,
                label: 'الوزن الصافي (غرام) — اختياري',
                child: AppInput(
                  label: '',
                  showLabel: false,
                  controller: _netWeightGramsCtrl,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  hint: 'يُملأ تلقائياً من باركود GS1 أو الوزن المدمج',
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (_, c) {
                  final row =
                      context.screenLayout.isHandsetForLayout ||
                      c.maxWidth >= 480;
                  Widget mfgField() => _labeledField(
                    context,
                    label: 'تاريخ الإنتاج — اختياري',
                    child: AppInput(
                      label: '',
                      showLabel: false,
                      controller: _mfgDateCtrl,
                      textAlign: TextAlign.right,
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                        ),
                        onPressed: () => _pickProductDate(_mfgDateCtrl),
                        tooltip: 'اختر من التقويم',
                      ),
                      hint: 'يوم/شهر/سنة',
                    ),
                  );
                  Widget expField() => _labeledField(
                    context,
                    label: 'تاريخ الانتهاء — اختياري',
                    child: AppInput(
                      label: '',
                      showLabel: false,
                      controller: _expDateCtrl,
                      textAlign: TextAlign.right,
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                        ),
                        onPressed: () => _pickProductDate(_expDateCtrl),
                        tooltip: 'اختر من التقويم',
                      ),
                      hint: 'يوم/شهر/سنة',
                    ),
                  );
                  if (row) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: mfgField()),
                        SizedBox(
                          width:
                              context.screenLayout.isHandsetForLayout ? 8 : 12,
                        ),
                        Expanded(child: expField()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      mfgField(),
                      const SizedBox(height: 12),
                      expField(),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _labeledField(
                context,
                label: 'تنبيه قبل انتهاء الصلاحية (عدد الأيام)',
                child: AppInput(
                  label: '',
                  showLabel: false,
                  controller: _expiryAlertDaysCtrl,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  hint:
                      'عند تسجيل تاريخ انتهاء: 1–365 (فارغ = الافتراضي من الإعدادات)',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'يُستخدم مع «تاريخ الانتهاء» فقط؛ يظهر التنبيه في لوحة الإشعارات خلال هذه المدة قبل التاريخ.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
            if (handsetSixGrid) const SizedBox(height: 8),
            _labeledField(
              context,
              label: 'ملاحظات داخلية',
              child: AppInput(
                label: '',
                showLabel: false,
                controller: _internalNotesCtrl,
                textAlign: TextAlign.right,
                minLines: 2,
                maxLines: 4,
                hint: 'لا تظهر للعميل — للفريق فقط',
                suffixIcon: ArabicSpeechMicButton(
                  controller: _internalNotesCtrl,
                  onTextUpdated: () => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _labeledField(
              context,
              label: 'وسوم',
              child: AppInput(
                label: '',
                showLabel: false,
                controller: _tagsCtrl,
                textAlign: TextAlign.right,
                hint: 'مفصولة بفواصل أو مسافات — للبحث والتصفية',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.primary : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.accentGold.withValues(alpha: 0.45) : AppColors.accentGold.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 40,
              color: AppColors.accentGold,
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _labeledField(
    BuildContext context, {
    required String label,
    required Widget child,
    bool requiredField = false,
    String? subtitle,
  }) {
    final onSurf = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: onSurf,
              ),
            ),
            if (requiredField) ...[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, height: 1.25, color: muted),
          ),
        ],
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _comboField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required String hint,
    bool requiredField = false,
    FocusNode? focusNode,
    void Function(String)? onFieldSubmitted,
  }) {
    final cs = Theme.of(context).colorScheme;
    return AppInput(
      label: label,
      isRequired: requiredField,
      hint: hint,
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.right,
      textInputAction: onFieldSubmitted != null
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: onFieldSubmitted,
      suffixIcon: options.isEmpty
          ? null
          : PopupMenuButton<String>(
              icon: Icon(
                Icons.arrow_drop_down_circle_outlined,
                color: cs.onSurfaceVariant,
              ),
              tooltip: 'اختر من القائمة',
              itemBuilder: (ctx) =>
                  options.map((e) => PopupMenuItem(value: e, child: Text(e))).toList(),
              onSelected: (v) {
                controller.text = v;
                setState(() {});
              },
            ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _imageTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.accentGold.withValues(alpha: 0.35) : AppColors.accentGold.withValues(alpha: 0.5);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _pickImage,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child:
              _imagePath != null &&
                  ((kIsWeb) || (!kIsWeb && File(_imagePath!).existsSync()))
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: kIsWeb
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'تم اختيار صورة (معاينة على الويب غير متاحة)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : Image.file(
                          File(_imagePath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 120,
                        ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: AppColors.accentGold,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'اضغط لإضافة صورة أو التقاطها بالكاميرا',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  InputDecoration _inputDecOf(BuildContext context, {required String hint}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.accentGold.withValues(alpha: 0.35) : AppColors.accentGold.withValues(alpha: 0.5);
    const r = BorderRadius.all(Radius.circular(12));
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant.withValues(alpha: 0.75),
        fontSize: 13,
      ),
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      isDense: true,
      contentPadding:
          const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
      ),
    );
  }
}
