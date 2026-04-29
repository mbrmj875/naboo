import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../navigation/app_root_navigator_key.dart';
import '../../models/customer_record.dart';
import '../../models/installment_settings_data.dart';
import '../../models/invoice.dart';
import '../../models/sale_pos_settings_data.dart';
import '../../models/loyalty_settings_data.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loyalty_settings_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/print_settings_provider.dart';
import '../../providers/parked_sales_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sale_pos_settings_provider.dart';
import '../../providers/ui_feedback_settings_provider.dart';
import '../../providers/sale_draft_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../theme/sale_brand.dart';
import '../../utils/invoice_barcode.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/loyalty_math.dart';
import '../../utils/screen_layout.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/theme.dart';
import '../../navigation/content_navigation.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../../widgets/mac_style_settings_panel.dart';
import '../../widgets/wide_home_product_rail.dart';
import '../installments/add_installment_plan_screen.dart';
import '../inventory/add_product_screen.dart';
import '../customers/customer_form_screen.dart';
import 'process_return_screen.dart';

class _CartUndoOp {
  const _CartUndoOp({
    required this.lineId,
    required this.previousQty,
    required this.wasNewLine,
  });
  final int lineId;
  final double previousQty;
  final bool wasNewLine;
}

class AddInvoiceScreen extends StatefulWidget {
  final String? initialBarcode;

  /// من البحث السريع: يضيف سطرًا جاهزًا (اسم، سعر بيع، أدنى سعر).
  final Map<String, dynamic>? presetProductLine;

  /// استعادة فاتورة مُعلّقة من [parked_sales].
  final int? resumeParkedSaleId;

  const AddInvoiceScreen({
    super.key,
    this.initialBarcode,
    this.presetProductLine,
    this.resumeParkedSaleId,
  });

  @override
  State<AddInvoiceScreen> createState() => _AddInvoiceScreenState();
}

class _AddInvoiceScreenState extends State<AddInvoiceScreen> {
  bool _saleRouteRegistered = false;
  bool _saleDraftListenerAttached = false;
  bool _initialSaleDraftDrainScheduled = false;
  SaleDraftProvider? _saleDraftRef;

  // ── ماسح باركود/QR مدمج في واجهة البيع (قراءات متتالية بدون إغلاق) ─────────────
  bool _saleScannerOpen = false;
  MobileScannerController? _saleScannerController;
  bool _saleScannerBusy = false;
  String? _saleScannerLastCode;
  DateTime? _saleScannerLastAt;
  double _saleScannerHeight = 210;

  /// آخر إعدادات نقطة البيع المقروءة من [build] — تُستخدم في الحسابات خارج [build].
  SalePosSettingsData _salePos = SalePosSettingsData.defaults();
  bool _saleTypeGuardScheduled = false;

  /// أثناء سحب فاصل العرض العريض — يُدمج مع [SalePosSettingsData.wideSaleProductsFlex] حتى الحفظ.
  int? _wideFlexLive;

  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _deliveryAddressController = TextEditingController();
  final _discountPercentController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _advanceController = TextEditingController(text: '0');
  final List<_InvoiceLineState> _lines = [];
  final Map<int, List<Map<String, dynamic>>> _variantsByProductId = {};
  final Set<int> _variantsLoading = {};
  final Set<int> _expandedLineIds = {};
  int _lineIdSeq = 0;

  /// عند المتابعة من قائمة «معلّقة» أو بعد أول حفظ تعليق في نفس الجلسة.
  int? _activeParkedSaleId;

  /// يمنع دمج طابور البحث ([SaleDraftProvider]) مع الحمولة المستعادة قبل انتهاء [_loadParkedSale].
  bool _blockSaleDraftUntilResumeApplied = false;

  /// تنبيه داخل صفحة البيع فوق «تعليق الفاتورة» (بدل شريط SnackBar بعرض الشاشة).
  String? _saleInlineToast;
  Color? _saleInlineToastBg;
  Timer? _saleInlineToastTimer;

  final DatabaseHelper _parkDb = DatabaseHelper();

  Timer? _customerSearchDebounce;
  List<Map<String, dynamic>> _customerHits = [];

  /// عميل مرتبط من القائمة — مطلوب لاستخدام نقاط الولاء بدقة.
  int? _linkedCustomerId;
  int _customerLoyaltyBalance = 0;
  final _loyaltyRedeemController = TextEditingController(text: '0');

  /// مساعد عرض التقسيط: فائدة % على المبلغ بعد المقدّم، وعدد أشهر، والقسط الشهري المقترح.
  final _instInterestPct = TextEditingController(text: '0');
  final _instMonths = TextEditingController(text: '6');

  /// نسخة محلية من إعدادات التقسيط (إظهار البطاقة، الفائدة الافتراضية، عدد الأشهر الافتراضي…).
  InstallmentSettingsData _instSaleSettings =
      InstallmentSettingsData.defaults();

  /// تصفية عمود «المنتجات السريعة» على الشاشات العريضة فقط.
  final _saleQuickRailSearchController = TextEditingController();
  final FocusNode _saleQuickRailSearchFocus = FocusNode();
  bool _saleQuickRailSearchAutofocusDone = false;

  static const double _kSaleQuickRailMinW = 260;
  static const double _kSaleQuickRailMaxW = 380;
  static const String _kSaleQuickRailWidthPref =
      'sale_wide_quick_rail_width_v1';
  double _saleQuickRailWidth = 300;

  /// تنقّل لوحة المفاتيح في سلة البيع (السطور).
  final FocusNode _saleCartListFocus = FocusNode();
  int _saleCartKeyboardIndex = 0;

  /// تراجع بسيط آخر إضافة للسلة (Ctrl+Z).
  _CartUndoOp? _lastCartAddUndo;

  int _takeLineId() {
    _lineIdSeq += 1;
    return _lineIdSeq;
  }

  Future<void> _ensureVariantsLoadedForProduct(int productId) async {
    if (productId <= 0) return;
    if (_variantsByProductId.containsKey(productId)) return;
    if (_variantsLoading.contains(productId)) return;
    _variantsLoading.add(productId);
    try {
      final rows = await context
          .read<ProductProvider>()
          .listActiveUnitVariantsForProduct(productId);
      if (!mounted) return;
      setState(() => _variantsByProductId[productId] = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _variantsByProductId[productId] = const []);
    } finally {
      _variantsLoading.remove(productId);
    }
  }

  Future<
    ({
      int stockBaseKind,
      int? unitVariantId,
      String unitLabel,
      double unitFactor,
    })
  >
  _unitSelectionForCatalogProduct(Map<String, dynamic> p) async {
    final pid = (p['id'] as num?)?.toInt() ?? (p['productId'] as num?)?.toInt();
    final stockBaseKind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;

    final dvId = (p['defaultVariantId'] as num?)?.toInt();
    final dvFactor = (p['defaultUnitFactor'] as num?)?.toDouble();
    final dvLabel = (p['defaultUnitLabel'] as String?)?.trim();

    if (dvId != null && dvId > 0 && dvFactor != null && dvFactor > 0) {
      final label = (dvLabel == null || dvLabel.isEmpty) ? 'وحدة' : dvLabel;
      return (
        stockBaseKind: stockBaseKind,
        unitVariantId: dvId,
        unitLabel: label,
        unitFactor: dvFactor,
      );
    }

    if (pid == null) {
      return (
        stockBaseKind: stockBaseKind,
        unitVariantId: null,
        unitLabel: 'قطعة',
        unitFactor: 1.0,
      );
    }

    final rows = await context
        .read<ProductProvider>()
        .listActiveUnitVariantsForProduct(pid);
    if (!mounted || rows.isEmpty) {
      return (
        stockBaseKind: stockBaseKind,
        unitVariantId: null,
        unitLabel: 'قطعة',
        unitFactor: 1.0,
      );
    }
    final v = rows.first;
    final id = (v['id'] as num?)?.toInt();
    final f = (v['factorToBase'] as num?)?.toDouble() ?? 1.0;
    final name = (v['unitName'] ?? '').toString().trim();
    final sym = (v['unitSymbol'] ?? '').toString().trim();
    final label = sym.isEmpty
        ? (name.isEmpty ? 'قطعة' : name)
        : (name.isEmpty ? sym : '$name ($sym)');
    return (
      stockBaseKind: stockBaseKind,
      unitVariantId: id,
      unitLabel: label,
      unitFactor: f <= 0 ? 1.0 : f,
    );
  }

  String _variantChipLabel(Map<String, dynamic> v) {
    final name = (v['unitName'] ?? '').toString().trim();
    final sym = (v['unitSymbol'] ?? '').toString().trim();
    if (name.isEmpty) return 'وحدة';
    if (sym.isEmpty) return name;
    return '$name ($sym)';
  }

  /// سعر البيع وأدنى سعر للوحدة المختارة.
  ///
  /// القاعدة: أسعار بطاقة المنتج معرّفة للوحدة الأساسية (قطعة أو **كيلوغرام** عند بيع بالوزن).
  /// عند البيع بوحدة إضافية بعامل تحويل f، يُضرب السعر تلقائياً في f.
  /// إذا ملأ المستخدم «سعر بيع الوحدة» صراحة في الوحدة الإضافية، فذلك
  /// يتجاوز الحساب التلقائي (تجار الجملة يعطون خصم كرتون).
  ({double sell, double min}) _resolveVariantPricing({
    required double baseSell,
    required double baseMin,
    required double? variantSell,
    required double? variantMin,
    required double factor,
  }) {
    final f = factor <= 0 ? 1.0 : factor;
    final sell = variantSell ?? (baseSell * f);
    final min = variantMin ?? (baseMin * f);
    return (sell: sell, min: min);
  }

  void _touchProductVariants(int? productId) {
    final pid = productId;
    if (pid == null || pid <= 0) return;
    if (_variantsByProductId.containsKey(pid)) return;
    unawaited(_ensureVariantsLoadedForProduct(pid));
  }

  Future<void> _applyLineVariantSelection({
    required _InvoiceLineState line,
    required Map<String, dynamic> v,
  }) async {
    final vid = (v['id'] as num?)?.toInt();
    final f = (v['factorToBase'] as num?)?.toDouble() ?? 1.0;
    final factor = f <= 0 ? 1.0 : f;

    final vSell = (v['sellPrice'] as num?)?.toDouble();
    final vMin = (v['minSellPrice'] as num?)?.toDouble();
    double? baseSell;
    double? baseMin;
    if (line.productId != null) {
      final p = await context.read<ProductProvider>().getProductById(
        line.productId!,
      );
      if (!mounted) return;
      if (p != null) {
        baseSell = (p['sellPrice'] as num?)?.toDouble() ?? 0;
        baseMin = (p['minSellPrice'] as num?)?.toDouble() ?? baseSell;
      }
    }
    // عند غياب baseSell (سطر بلا productId)، اشتقّه من السعر الحالي: base = currentPrice / oldFactor.
    final prevFactorSafe = line.unitFactor <= 0 ? 1.0 : line.unitFactor;
    final baseSellResolved = baseSell ?? line.unitPrice / prevFactorSafe;
    final baseMinResolved = baseMin ?? line.minSellPrice / prevFactorSafe;
    // أسعار بطاقة المنتج للوحدة الأساسية؛ اضرب في factor عند غياب سعر صريح للوحدة.
    final pricing = _resolveVariantPricing(
      baseSell: baseSellResolved,
      baseMin: baseMinResolved,
      variantSell: vSell,
      variantMin: vMin,
      factor: factor,
    );
    final sell = pricing.sell;
    final minS = pricing.min;

    final un = (v['unitName'] ?? '').toString().trim();
    final us = (v['unitSymbol'] ?? '').toString().trim();
    final label = us.isEmpty
        ? (un.isEmpty ? 'وحدة' : un)
        : (un.isEmpty ? us : '$un ($us)');

    final oldVid = line.unitVariantId;
    final oldF = line.unitFactor <= 0 ? 1.0 : line.unitFactor;
    final oldLabel = line.unitLabel;
    final oldSell = line.unitPrice;
    final oldMin = line.minSellPrice;
    final entered = line.quantity;

    if (!mounted) return;
    setState(() {
      line.unitVariantId = vid;
      line.unitFactor = factor;
      line.unitLabel = label;
      line.unitPrice = sell;
      line.minSellPrice = minS;
      line.sellPrice = sell;
      // نُبقي «كمية العرض» كما هي ونُعيد قياس المخزون عبر factor الجديد.
      line.quantity = entered;
    });

    if (_lineIgnoresStock(line)) return;

    final maxBase = await _maxBaseQtyAllowedForLine(line);
    if (!mounted) return;
    if (maxBase == null) return;

    final newBase = entered * factor;
    if (newBase <= maxBase + 1e-9) return;

    // لا يكفي المخزون لهذا التحويل: نُرجع العامل السابق ونُبقي الكمية المعروضة، مع تعديل الكمية لتناسب المخزون إن أمكن.
    final maxEntered = maxBase / factor;
    if (maxEntered <= 0) {
      setState(() {
        line.unitVariantId = oldVid;
        line.unitFactor = oldF;
        line.unitLabel = oldLabel;
        line.unitPrice = oldSell;
        line.minSellPrice = oldMin;
        line.sellPrice = oldSell;
        line.quantity = entered;
      });
      _showSaleSnackBar(
        const SnackBar(content: Text('لا يتوفر مخزون كافٍ لهذه الوحدة.')),
      );
      return;
    }

    setState(() {
      line.unitVariantId = oldVid;
      line.unitFactor = oldF;
      line.unitLabel = oldLabel;
      line.unitPrice = oldSell;
      line.minSellPrice = oldMin;
      line.sellPrice = oldSell;
      line.quantity = maxEntered;
    });
    _showSaleSnackBar(
      SnackBar(
        content: Text(
          'تم ضبط الكمية إلى ${IraqiCurrencyFormat.formatDecimal2(maxEntered)} بسبب حد المخزون المتاح.',
        ),
      ),
    );
  }

  double _saleQtyStep(_InvoiceLineState l) {
    if (l.stockBaseKind == 1) {
      final q = l.quantity;
      if (q >= 10) return 1.0;
      if (q >= 2) return 0.5;
      return 0.25;
    }
    return 1;
  }

  String _formatSaleQty(_InvoiceLineState l) {
    final q = l.quantity;
    if (!q.isFinite) return '0';
    if (l.stockBaseKind != 1 && (q % 1).abs() < 1e-9) {
      return IraqiCurrencyFormat.formatInt(q);
    }
    return IraqiCurrencyFormat.formatDecimal2(q);
  }

  double _lineEnteredForMath(_InvoiceLineState l) => l.quantity;

  double _lineBaseForMath(_InvoiceLineState l) {
    final f = l.unitFactor <= 0 ? 1.0 : l.unitFactor;
    return _lineEnteredForMath(l) * f;
  }

  /// هامش سفلي لـ SnackBar فوق شريط «تعليق / الدفع» وليس تحته (مع لوحة المفاتيح إن وُجدت).
  double _saleSnackBarBottomMargin() {
    final mq = MediaQuery.of(context);
    final safe = mq.padding.bottom + mq.viewInsets.bottom;
    final sl = ScreenLayout.of(context);
    final actionStrip =
        (sl.showSaleBarcodeShortcut ? 52.0 : 50.0) +
        10 +
        (sl.showSaleBarcodeShortcut ? 54.0 : 50.0) +
        28;
    final fromLayout = safe + actionStrip + 48;
    final fromScreen = mq.size.height * 0.22;
    return math.max(220.0, math.max(fromLayout, fromScreen));
  }

  void _dismissSaleInlineToast() {
    _saleInlineToastTimer?.cancel();
    _saleInlineToastTimer = null;
    if (!mounted) {
      _saleInlineToast = null;
      _saleInlineToastBg = null;
      return;
    }
    if (_saleInlineToast != null) {
      setState(() {
        _saleInlineToast = null;
        _saleInlineToastBg = null;
      });
    }
  }

  Color _toastOnSurface(Color bg) =>
      bg.computeLuminance() > 0.55 ? const Color(0xFF0F172A) : Colors.white;

  String? _plainTextFromSnackWidget(Widget? w) {
    if (w == null) return null;
    if (w is Text) {
      final d = w.data;
      if (d != null && d.trim().isNotEmpty) return d.trim();
      final span = w.textSpan;
      if (span != null) {
        final t = span.toPlainText().trim();
        if (t.isNotEmpty) return t;
      }
      return null;
    }
    if (w is Flex) {
      for (final c in w.children) {
        final t = _plainTextFromSnackWidget(c);
        if (t != null) return t;
      }
    }
    if (w is Padding) return _plainTextFromSnackWidget(w.child);
    if (w is Center) return _plainTextFromSnackWidget(w.child);
    if (w is Expanded) return _plainTextFromSnackWidget(w.child);
    if (w is SizedBox) return _plainTextFromSnackWidget(w.child);
    return null;
  }

  SnackBar _floatedSnackBar(SnackBar source, double bottomMargin) {
    return SnackBar(
      content: source.content,
      backgroundColor: source.backgroundColor,
      elevation: source.elevation,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(14, 0, 14, bottomMargin),
      duration: source.duration,
      action: source.action,
      dismissDirection: source.dismissDirection,
      shape: source.shape,
      showCloseIcon: source.showCloseIcon,
      closeIconColor: source.closeIconColor,
    );
  }

  void _showSaleSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final compact = context
        .read<UiFeedbackSettingsProvider>()
        .useCompactSnackNotifications;
    final plain = _plainTextFromSnackWidget(snackBar.content);
    if (compact && plain != null && plain.isNotEmpty) {
      final pal = SalePalette.fromSettings(_salePos, Theme.of(context));
      final bg = snackBar.backgroundColor ?? pal.navy.withValues(alpha: 0.96);
      _saleInlineToastTimer?.cancel();
      setState(() {
        _saleInlineToast = plain;
        _saleInlineToastBg = bg;
      });
      _saleInlineToastTimer = Timer(snackBar.duration, _dismissSaleInlineToast);
      return;
    }
    if (!compact) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: snackBar.content,
          backgroundColor: snackBar.backgroundColor,
          elevation: snackBar.elevation,
          behavior: SnackBarBehavior.fixed,
          duration: snackBar.duration,
          action: snackBar.action,
          dismissDirection: snackBar.dismissDirection,
          shape: snackBar.shape,
          showCloseIcon: snackBar.showCloseIcon,
          closeIconColor: snackBar.closeIconColor,
        ),
      );
      return;
    }
    final floated = _floatedSnackBar(snackBar, _saleSnackBarBottomMargin());
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(floated);
  }

  /// بعد [Navigator.pop] من البيع — هامش أقل لكن فوق شريط التنقل إن وُجد.
  /// [useCompactSnackOverride] عند الإغلاق من نافذة mac عائمة: لا نستخدم [context] بعد [pop].
  void _showSnackBarViaMessenger(
    ScaffoldMessengerState messenger,
    SnackBar snackBar, {
    double bottomMargin = 88,
    bool? useCompactSnackOverride,
  }) {
    final compact =
        useCompactSnackOverride ??
        context.read<UiFeedbackSettingsProvider>().useCompactSnackNotifications;
    if (!compact) {
      messenger.showSnackBar(
        SnackBar(
          content: snackBar.content,
          backgroundColor: snackBar.backgroundColor,
          elevation: snackBar.elevation,
          behavior: SnackBarBehavior.fixed,
          duration: snackBar.duration,
          action: snackBar.action,
          dismissDirection: snackBar.dismissDirection,
          shape: snackBar.shape,
          showCloseIcon: snackBar.showCloseIcon,
          closeIconColor: snackBar.closeIconColor,
        ),
      );
      return;
    }
    messenger.showSnackBar(_floatedSnackBar(snackBar, bottomMargin));
  }

  /// إغلاق شاشة البيع: [Navigator.pop] للمسار الداخلي، أو إغلاق نافذة mac عائمة عندما لا يوجد سوى مسار واحد.
  void _leaveSaleScreen() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      closeMacFloatingPanelByRouteId(AppContentRoutes.addInvoice);
    }
  }

  /// بعد إتمام الدفع مع البقاء على شاشة البيع — سلة جديدة دون إغلاق الصفحة.
  void _resetSaleForNextInvoice() {
    if (!mounted) return;
    _customerSearchDebounce?.cancel();
    setState(() {
      _lines.clear();
      _variantsByProductId.clear();
      _variantsLoading.clear();
      _expandedLineIds.clear();
      _lineIdSeq = 0;
      _customerController.clear();
      _deliveryAddressController.clear();
      _discountPercentController.text = '0';
      _taxController.text = '0';
      _advanceController.text = '0';
      _loyaltyRedeemController.text = '0';
      _instInterestPct.text = '0';
      _instMonths.text = '6';
      _linkedCustomerId = null;
      _customerLoyaltyBalance = 0;
      _customerHits = [];
      type = InvoiceType.cash;
      _activeParkedSaleId = null;
    });
    _dismissSaleInlineToast();
    _formKey.currentState?.reset();
    _saleQuickRailSearchAutofocusDone = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _saleQuickRailSearchFocus.requestFocus();
      _syncCashAdvanceToTotalIfCash(
        Provider.of<LoyaltySettingsProvider>(context, listen: false).data,
      );
    });
  }

  InvoiceType type = InvoiceType.cash;

  double get subtotal => _lines.fold(
    0,
    (sum, line) => sum + (_lineEnteredForMath(line) * line.unitPrice),
  );
  double get _tax {
    if (!_salePos.enableTaxOnSale) return 0;
    return double.tryParse(_taxController.text.trim()) ?? 0;
  }

  double get _advancePayment =>
      double.tryParse(_advanceController.text.trim()) ?? 0;
  double get _discountPercent {
    final raw = double.tryParse(_discountPercentController.text.trim()) ?? 0;
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.clamp(0, 100);
  }

  double get _maxAllowedDiscountPercent {
    if (_lines.isEmpty || subtotal <= 0) return 100;
    var maxDiscountValue = 0.0;
    for (final l in _lines) {
      final diff = (l.unitPrice - l.minSellPrice).clamp(0, l.unitPrice);
      maxDiscountValue += diff * _lineEnteredForMath(l);
    }
    return ((maxDiscountValue / subtotal) * 100).clamp(0, 100);
  }

  double get discountValue {
    if (!_salePos.enableInvoiceDiscount) return 0;
    final effectivePct = _discountPercent.clamp(0, _maxAllowedDiscountPercent);
    return subtotal * (effectivePct / 100.0);
  }

  /// صافٍ قبل خصم نقاط الولاء.
  double get _netBeforeLoyaltySale => subtotal - discountValue + _tax;

  int _clampedRedeemPoints(LoyaltySettingsData s) {
    if (type == InvoiceType.installment) return 0;
    if (!s.enabled || _linkedCustomerId == null) return 0;
    final raw = int.tryParse(_loyaltyRedeemController.text.trim()) ?? 0;
    return LoyaltyMath.clampRedeemInput(
      requested: raw,
      balance: _customerLoyaltyBalance,
      netBeforeLoyalty: _netBeforeLoyaltySale,
      s: s,
    );
  }

  double _loyaltyDiscountAmount(LoyaltySettingsData s) {
    final pts = _clampedRedeemPoints(s);
    return LoyaltyMath.discountFromPoints(pts, s);
  }

  double saleTotal(LoyaltySettingsData s) {
    final v = _netBeforeLoyaltySale - _loyaltyDiscountAmount(s);
    return v < 0 ? 0 : v;
  }

  bool get _needsCustomerNameFor {
    if (type == InvoiceType.credit || type == InvoiceType.installment) {
      return true;
    }
    if (type == InvoiceType.delivery) {
      return true;
    }
    return false;
  }

  Future<void> _refreshLoyaltyBalance() async {
    final id = _linkedCustomerId;
    if (id == null) {
      if (mounted) setState(() => _customerLoyaltyBalance = 0);
      return;
    }
    final row = await _parkDb.getCustomerById(id);
    if (!mounted) return;
    setState(() {
      _customerLoyaltyBalance = (row?['loyaltyPoints'] as num?)?.toInt() ?? 0;
    });
  }

  /// إضافة عميل جديد من شاشة البيع: تفتح صفحة النموذج ثم تربط العميل بالفاتورة عند الرجوع.
  Future<void> _openQuickAddCustomerDialog() async {
    final saved = await Navigator.of(context).push<CustomerRecord?>(
      MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _customerController.text = saved.name;
      _linkedCustomerId = saved.id;
      _customerHits = [];
    });
    CloudSyncService.instance.scheduleSyncSoon();
    await _refreshLoyaltyBalance();
  }

  void _onCustomerInputChanged() {
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(
      const Duration(milliseconds: 120),
      () async {
        final q = _customerController.text.trim();
        if (q.isEmpty) {
          if (mounted) setState(() => _customerHits = []);
          return;
        }
        final rows = await _parkDb.searchCustomers(q, limit: 15);
        if (!mounted) return;
        setState(() => _customerHits = rows);
      },
    );
  }

  /// مجموع البنود بعد خصم الفاتورة وقبل الضريبة.
  double get _subtotalAfterDiscount => subtotal - discountValue;

  double _lineGross(_InvoiceLineState l) =>
      _lineEnteredForMath(l) * l.unitPrice;

  /// حصة خصم الفاتورة (النسبة على الإجمالي) الموزّعة على هذا السطر.
  double _lineBasketDiscountShare(_InvoiceLineState l) {
    if (subtotal <= 0) return 0;
    return (_lineGross(l) / subtotal) * discountValue;
  }

  double _lineNetAfterBasketDiscount(_InvoiceLineState l) =>
      _lineGross(l) - _lineBasketDiscountShare(l);

  bool _lineIgnoresStock(_InvoiceLineState l) {
    if (l.productId == null) return true;
    if (!l.trackInventory) return true;
    if (l.allowNegativeStock) return true;
    if (!_salePos.enforceAvailableQtyAtSale) return true;
    return false;
  }

  /// مجموع الكميات لنفس المنتج، مع استثناء سطر (للتحقق من الحد).
  double _totalQtyForProduct(int? productId, {int? excludeLineId}) {
    if (productId == null) return 0.0;
    return _lines
        .where(
          (x) =>
              x.productId == productId &&
              (excludeLineId == null || x.lineId != excludeLineId),
        )
        .fold<double>(0.0, (s, x) => s + _lineBaseForMath(x));
  }

  Future<double?> _maxBaseQtyAllowedForLine(_InvoiceLineState line) async {
    if (_lineIgnoresStock(line)) return null;
    final m = await context.read<ProductProvider>().getProductById(
      line.productId!,
    );
    if (!mounted || m == null) return null;
    final stock = (m['qty'] as num?)?.toDouble() ?? 0;
    final other = _totalQtyForProduct(
      line.productId,
      excludeLineId: line.lineId,
    );
    final raw = stock - other;
    if (raw < 0) return 0;
    return raw;
  }

  Future<bool> _trySetLineQuantity(
    _InvoiceLineState line,
    double newQty,
  ) async {
    if (!newQty.isFinite || newQty <= 0) return false;
    if (_lineIgnoresStock(line)) {
      setState(() => line.quantity = newQty);
      return true;
    }
    final maxBase = await _maxBaseQtyAllowedForLine(line);
    if (!mounted) return false;
    if (maxBase == null) {
      setState(() => line.quantity = newQty);
      return true;
    }
    final newBase = newQty * (line.unitFactor <= 0 ? 1.0 : line.unitFactor);
    if (newBase <= maxBase + 1e-9) {
      setState(() => line.quantity = newQty);
      return true;
    }
    _showSaleSnackBar(
      SnackBar(
        content: Text(
          'الكمية غير متوفرة في المخزون. المتاح للبيع (أساس المخزون): ${IraqiCurrencyFormat.formatDecimal2(maxBase)} فقط (بعد احتساب الكميات في الأسطر الأخرى لنفس المنتج).',
        ),
      ),
    );
    return false;
  }

  Future<bool> _canAppendProductLine({
    required int? productId,
    required bool trackInventory,
    required bool allowNegativeStock,
    required double baseQtyToAdd,
    double? knownOnHandQty,
  }) async {
    if (productId == null) return true;
    if (!trackInventory || allowNegativeStock) return true;
    if (!context
        .read<SalePosSettingsProvider>()
        .data
        .enforceAvailableQtyAtSale) {
      return true;
    }
    double stock;
    if (knownOnHandQty != null) {
      stock = knownOnHandQty;
    } else {
      final m = await context.read<ProductProvider>().getProductById(productId);
      if (!mounted || m == null) return true;
      stock = (m['qty'] as num?)?.toDouble() ?? 0;
    }
    final already = _totalQtyForProduct(productId, excludeLineId: null);
    if (already + baseQtyToAdd <= stock + 1e-9) return true;
    final maxAdd = stock - already;
    _showSaleSnackBar(
      SnackBar(
        content: Text(
          maxAdd <= 0
              ? 'لا توجد كمية متوفرة في المخزون لهذا المنتج.'
              : 'الكمية غير متوفرة. المتاح للبيع (أساس المخزون): ${IraqiCurrencyFormat.formatDecimal2(maxAdd)} فقط.',
        ),
      ),
    );
    return false;
  }

  bool _sameCatalogLinePrices(
    _InvoiceLineState line,
    double unitPrice,
    double minSell,
  ) {
    return (line.unitPrice - unitPrice).abs() < 0.01 &&
        (line.minSellPrice - minSell).abs() < 0.01;
  }

  _InvoiceLineState? _findMergeTargetForProduct(
    int productId,
    double unitPrice,
    double minSell, {
    required int? unitVariantId,
    required double unitFactor,
  }) {
    for (final l in _lines) {
      if (l.productId == productId &&
          l.unitVariantId == unitVariantId &&
          (l.unitFactor - unitFactor).abs() < 1e-9 &&
          _sameCatalogLinePrices(l, unitPrice, minSell)) {
        return l;
      }
    }
    return null;
  }

  /// يدمج مع سطر قائم إن وُجد نفس المنتج وبنفس سعر البيع والأدنى (مثلاً من البحث ثم من الباركود).
  Future<void> _addOrMergeCatalogProductLine({
    required String productName,
    required int? productId,
    required double sellPrice,
    required double minSellPrice,
    required bool trackInventory,
    required bool allowNegativeStock,
    String? newItemSnackText,
    double? knownOnHandQty,
    int stockBaseKind = 0,
    int? unitVariantId,
    String? unitLabel,
    double unitFactor = 1.0,
    double addQuantity = 1.0,
    bool suppressLineSnacks = false,
  }) async {
    if (!mounted) return;
    final f = unitFactor <= 0 ? 1.0 : unitFactor;
    final dq = addQuantity.isFinite && addQuantity > 0 ? addQuantity : 1.0;

    if (productId != null) {
      final existing = _findMergeTargetForProduct(
        productId,
        sellPrice,
        minSellPrice,
        unitVariantId: unitVariantId,
        unitFactor: f,
      );
      if (existing != null) {
        final prevQty = existing.quantity;
        final ok = await _trySetLineQuantity(existing, existing.quantity + dq);
        if (!ok || !mounted) return;
        if (!suppressLineSnacks) {
          _showSaleSnackBar(
            SnackBar(content: Text('تمت زيادة الكمية: $productName')),
          );
        }
        _lastCartAddUndo = _CartUndoOp(
          lineId: existing.lineId,
          previousQty: prevQty,
          wasNewLine: false,
        );
        return;
      }
    }

    final ok = await _canAppendProductLine(
      productId: productId,
      trackInventory: trackInventory,
      allowNegativeStock: allowNegativeStock,
      baseQtyToAdd: f * dq,
      knownOnHandQty: knownOnHandQty,
    );
    if (!ok || !mounted) return;

    int newLineId = -1;
    setState(() {
      final lid = _takeLineId();
      newLineId = lid;
      _lines.add(
        _InvoiceLineState(
          lineId: lid,
          productName: productName,
          quantity: dq,
          unitPrice: sellPrice,
          sellPrice: sellPrice,
          minSellPrice: minSellPrice,
          productId: productId,
          trackInventory: trackInventory,
          allowNegativeStock: allowNegativeStock,
          stockBaseKind: stockBaseKind,
          unitVariantId: unitVariantId,
          unitLabel: unitLabel,
          unitFactor: f,
        ),
      );
      _saleCartKeyboardIndex = _lines.length - 1;
      if (productId != null) {
        unawaited(_ensureVariantsLoadedForProduct(productId));
      }
    });
    if (!mounted) return;

    _lastCartAddUndo = _CartUndoOp(
      lineId: newLineId,
      previousQty: 0,
      wasNewLine: true,
    );

    if (!suppressLineSnacks) {
      _showSaleSnackBar(
        SnackBar(
          content: Text(newItemSnackText ?? 'تمت إضافة سطر جديد: $productName'),
        ),
      );
    }
  }

  bool _parseTrackInvMap(Map<String, dynamic> m) {
    final v = m['trackInventory'];
    if (v == null) return true;
    return (v as num) != 0;
  }

  bool _parseAllowNegMap(Map<String, dynamic> m) {
    final v = m['allowNegativeStock'];
    if (v == null) return false;
    return (v as num) != 0;
  }

  bool _tiFromProductRow(Map<String, dynamic> m) {
    final v = m['trackInventory'];
    if (v == null) return true;
    return (v as num) != 0;
  }

  bool _anFromProductRow(Map<String, dynamic> m) {
    final v = m['allowNegativeStock'];
    if (v == null) return false;
    return (v as num) != 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saleDraftRef ??= context.read<SaleDraftProvider>();
    if (!_saleDraftListenerAttached) {
      _saleDraftListenerAttached = true;
      _saleDraftRef!.addListener(_onSaleDraftChanged);
    }
    if (!_saleRouteRegistered) {
      _saleRouteRegistered = true;
      _saleDraftRef!.registerSaleScreenOpen();
    }
    if (!_initialSaleDraftDrainScheduled) {
      _initialSaleDraftDrainScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_blockSaleDraftUntilResumeApplied) return;
        final d = context.read<SaleDraftProvider>();
        if (d.pendingProductLinesCount == 0) return;
        final pending = d.takePendingProductLines();
        if (pending.isEmpty) return;
        unawaited(_consumeDraftLines(pending));
      });
    }
  }

  void _onSaleDraftChanged() {
    if (!mounted || _saleDraftRef == null) return;
    if (_blockSaleDraftUntilResumeApplied) return;
    final pending = _saleDraftRef!.takePendingProductLines();
    if (pending.isEmpty) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_consumeDraftLines(pending));
    });
  }

  @override
  void initState() {
    super.initState();
    _loyaltyRedeemController.addListener(() {
      if (mounted) setState(() {});
    });
    _instInterestPct.addListener(() {
      if (mounted) setState(() {});
    });
    _instMonths.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.resumeParkedSaleId != null) {
      _blockSaleDraftUntilResumeApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadParkedSale());
    } else if (widget.presetProductLine != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final p = widget.presetProductLine!;
        final name = (p['name'] ?? '').toString().trim();
        final sell = (p['sell'] as num?)?.toDouble() ?? 0;
        final minS = (p['minSell'] as num?)?.toDouble() ?? sell;
        final pid = (p['productId'] as num?)?.toInt();
        final trackInv = (p['trackInventory'] as bool?) ?? true;
        final allowNeg = (p['allowNegativeStock'] as bool?) ?? false;
        final baseKind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;
        setState(() {
          _lines.add(
            _InvoiceLineState(
              lineId: _takeLineId(),
              productName: name.isEmpty ? 'منتج' : name,
              quantity: 1.0,
              unitPrice: sell,
              sellPrice: sell,
              minSellPrice: minS,
              productId: (pid != null && pid > 0) ? pid : null,
              trackInventory: trackInv,
              allowNegativeStock: allowNeg,
              stockBaseKind: baseKind,
              unitVariantId: null,
              unitLabel: 'قطعة',
              unitFactor: 1.0,
            ),
          );
        });
        if (pid != null && pid > 0) {
          _touchProductVariants(pid);
        }
      });
    } else {
      final barcode = widget.initialBarcode?.trim();
      if (barcode != null && barcode.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_handleBarcode(barcode));
        });
      }
    }
    unawaited(_refreshInstSaleSettingsFromDb());
    unawaited(_restoreSaleQuickRailWidth());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<ParkedSalesProvider>().refresh());
    });
  }

  Future<void> _restoreSaleQuickRailWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_kSaleQuickRailWidthPref);
    if (!mounted || v == null || !v.isFinite) return;
    setState(() {
      _saleQuickRailWidth = v.clamp(_kSaleQuickRailMinW, _kSaleQuickRailMaxW);
    });
  }

  Future<void> _persistSaleQuickRailWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSaleQuickRailWidthPref, _saleQuickRailWidth);
  }

  Future<void> _refreshInstSaleSettingsFromDb() async {
    try {
      final st = await _parkDb.getInstallmentSettings();
      if (!mounted) return;
      setState(() => _instSaleSettings = st);
    } catch (_) {}
  }

  @override
  void dispose() {
    _saleInlineToastTimer?.cancel();
    _customerSearchDebounce?.cancel();
    if (_saleDraftListenerAttached) {
      _saleDraftRef?.removeListener(_onSaleDraftChanged);
      _saleDraftListenerAttached = false;
    }
    _saleDraftRef?.registerSaleScreenClosed();
    _customerController.dispose();
    _deliveryAddressController.dispose();
    _discountPercentController.dispose();
    _taxController.dispose();
    _advanceController.dispose();
    _loyaltyRedeemController.dispose();
    _instInterestPct.dispose();
    _instMonths.dispose();
    _saleQuickRailSearchController.dispose();
    _saleQuickRailSearchFocus.dispose();
    _saleCartListFocus.dispose();
    _saleScannerController?.dispose();
    super.dispose();
  }

  bool _canUseEmbeddedScanner(BuildContext context) {
    // الكاميرا للمحمول فقط (Android/iOS) — على سطح المكتب نستخدم قارئ لوحة المفاتيح.
    return ScreenLayout.of(context).isHandsetForLayout &&
        BarcodeInputLauncher.useCamera(context);
  }

  void _toggleSaleScanner() {
    if (!_canUseEmbeddedScanner(context)) {
      unawaited(_openSaleBarcodeCapture()); // fallback: نفس التدفق القديم
      return;
    }
    setState(() {
      _saleScannerOpen = !_saleScannerOpen;
    });
    if (_saleScannerOpen) {
      _saleScannerController ??= MobileScannerController();
    }
  }

  void _closeSaleScanner() {
    if (!_saleScannerOpen) return;
    setState(() => _saleScannerOpen = false);
    // لا نُتلف الكاميرا إلا عند مغادرة الشاشة (dispose) كي تكون العودة سريعة.
  }

  void _onSaleScannerDetect(BarcodeCapture capture) {
    if (_saleScannerBusy) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();
    final lastAt = _saleScannerLastAt;
    final lastCode = _saleScannerLastCode;

    // منع التكرار السريع (الكاميرا قد ترسل نفس الكود عدة مرات في الثانية).
    if (lastAt != null &&
        lastCode == code &&
        now.difference(lastAt).inMilliseconds < 900) {
      return;
    }

    _saleScannerLastAt = now;
    _saleScannerLastCode = code;
    _saleScannerBusy = true;

    unawaited(
      _handleBarcode(code).whenComplete(() {
        if (!mounted) return;
        _saleScannerBusy = false;
      }),
    );
  }

  Future<void> _prefillInstallmentAssistFields() async {
    try {
      final st = await _parkDb.getInstallmentSettings();
      if (!mounted) return;
      setState(() {
        _instSaleSettings = st;
        _instMonths.text = '${st.defaultInstallmentCount.clamp(1, 120)}';
        _instInterestPct.text = st.saleDefaultInterestPercent % 1 == 0
            ? '${st.saleDefaultInterestPercent.toInt()}'
            : st.saleDefaultInterestPercent.toStringAsFixed(2);
      });
    } catch (_) {}
  }

  /// المبلغ المتبقي للتقسيط بعد المقدّم (على أساس إجمالي الفاتورة الحالي).
  double _installmentFinancedAmount(LoyaltySettingsData loyalty) {
    final pay = saleTotal(loyalty);
    final adv = _advancePayment;
    return (pay - adv).clamp(0.0, double.infinity);
  }

  ({
    double financed,
    double interestPct,
    double interestAmt,
    double totalWithInterest,
    int months,
    double monthly,
  })
  _installmentCalcFromInputs(
    LoyaltySettingsData loyalty, {
    required double interestPct,
    required int months,
  }) {
    final financed = _installmentFinancedAmount(loyalty);
    final interestPctClamped = interestPct.clamp(0.0, 100.0);
    final monthsClamped = months.clamp(1, 120);
    final interestAmt = financed * (interestPctClamped / 100.0);
    final totalWithInterest = financed + interestAmt;
    final monthly = monthsClamped > 0
        ? totalWithInterest / monthsClamped
        : totalWithInterest;
    return (
      financed: financed,
      interestPct: interestPctClamped,
      interestAmt: interestAmt,
      totalWithInterest: totalWithInterest,
      months: monthsClamped,
      monthly: monthly,
    );
  }

  ({
    double financed,
    double interestPct,
    double interestAmt,
    double totalWithInterest,
    int months,
    double monthly,
  })
  _installmentCalc(LoyaltySettingsData loyalty) {
    final interestPct =
        (double.tryParse(_instInterestPct.text.replaceAll(',', '').trim()) ?? 0)
            .clamp(0.0, 100.0);
    final months = (int.tryParse(_instMonths.text.trim()) ?? 1).clamp(1, 120);
    return _installmentCalcFromInputs(
      loyalty,
      interestPct: interestPct,
      months: months,
    );
  }

  Widget _buildInstallmentAssistCard(
    LoyaltySettingsData loyaltyCfg,
    SalePosSettingsData pos,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final c = _installmentCalc(loyaltyCfg);
    final boxRadius = pos.panelCornerStyle == SalePanelCornerStyle.sharp
        ? BorderRadius.zero
        : BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.22),
          borderRadius: boxRadius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    color: scheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'مخطط التقسيط',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'يُحسب على «الإجمالي بعد المقدّم». للمراجعة مع العميل — لا يُضاف للفاتورة إلا إذا رفعت الأسعار يدوياً.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _advanceController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'المقدّم / الدفعة الأولى (د.ع)',
                  helperText: 'يُخصم من الإجمالي قبل حساب الفائدة والقسط',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _instInterestPct,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'فائدة على المبلغ المراد تقسيطه',
                        suffixText: '%',
                        helperText: 'نسبة من المبلغ بعد المقدّم',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _instMonths,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'عدد الأشهر',
                        suffixText: 'شهراً',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _instSumRow(
                'المبلغ بعد المقدّم (أساس التقسيط)',
                IraqiCurrencyFormat.formatIqd(c.financed),
                scheme,
              ),
              _instSumRow(
                'قيمة الفائدة (${c.interestPct.toStringAsFixed(1)}٪)',
                IraqiCurrencyFormat.formatIqd(c.interestAmt),
                scheme,
              ),
              const Divider(height: 18),
              _instSumRow(
                'الإجمالي مع الفائدة',
                IraqiCurrencyFormat.formatIqd(c.totalWithInterest),
                scheme,
                strong: true,
              ),
              const SizedBox(height: 6),
              _instSumRow(
                'القسط الشهري المقترح (${c.months} شهراً)',
                IraqiCurrencyFormat.formatIqd(c.monthly),
                scheme,
                strong: true,
                accent: scheme.primary,
              ),
              if (c.financed < 1e-6) ...[
                const SizedBox(height: 8),
                Text(
                  'المقدّم يساوي الإجمالي — لا يوجد مبلغ للتقسيط. خفّض المقدّم لرؤية الفائدة والقسط.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _instSumRow(
    String k,
    String v,
    ColorScheme scheme, {
    bool strong = false,
    Color? accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: strong ? 13.5 : 12.5,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: FontWeight.w800,
              color: accent ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salePos = context.watch<SalePosSettingsProvider>().data;
    _salePos = salePos;
    if (!salePos.allowsPayment(type) && !_saleTypeGuardScheduled) {
      _saleTypeGuardScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saleTypeGuardScheduled = false;
        if (!mounted) return;
        final p = context.read<SalePosSettingsProvider>().data;
        if (!p.allowsPayment(type)) {
          setState(() => type = InvoiceType.cash);
        }
      });
    }
    final palette = SalePalette.fromSettings(salePos, Theme.of(context));
    final printProv = context.watch<PrintSettingsProvider>();
    final buyerAddressQrEnabled =
        printProv.isReady && printProv.data.receiptShowBuyerAddressQr;
    final loyaltyCfg = context.watch<LoyaltySettingsProvider>().data;
    final compactSnack = context
        .watch<UiFeedbackSettingsProvider>()
        .useCompactSnackNotifications;
    if (!compactSnack && _saleInlineToast != null) {
      Future.microtask(() {
        if (mounted) _dismissSaleInlineToast();
      });
    }
    final payableTotal = saleTotal(loyaltyCfg);
    final saleLightBg = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFFCFAF7)
        : null;
    final sl = ScreenLayout.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: saleLightBg,
        appBar: AppBar(
          title: const Text('البيع'),
          backgroundColor: palette.navy,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.pause_circle_outline_rounded),
              color: palette.gold,
              tooltip: 'تعليق الفاتورة',
              onPressed: _parkInvoice,
            ),
          ],
        ),
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f1):
                _focusSaleQuickRailSearch,
            const SingleActivator(LogicalKeyboardKey.f4): () =>
                unawaited(_parkInvoice()),
            const SingleActivator(LogicalKeyboardKey.f12): () =>
                unawaited(_saveInvoiceIfEligible()),
            const SingleActivator(LogicalKeyboardKey.escape):
                _handleSaleEscapeKey,
            const SingleActivator(LogicalKeyboardKey.f2): _cartKbEditQtyKey,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _undoLastCartMutation,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                _undoLastCartMutation,
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _cartKbMoveHighlight(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _cartKbMoveHighlight(1),
            const SingleActivator(LogicalKeyboardKey.equal): () =>
                _cartKbBumpQty(1),
            const SingleActivator(LogicalKeyboardKey.add): () =>
                _cartKbBumpQty(1),
            const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
                _cartKbBumpQty(1),
            const SingleActivator(LogicalKeyboardKey.minus): () =>
                _cartKbBumpQty(-1),
            const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
                _cartKbBumpQty(-1),
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                _cartKbRemoveHighlighted(),
          },
          child: Form(
            key: _formKey,
            child: sl.isHandsetForLayout
                ? _buildSaleMainBodyWithOptionalQuickRail(
                    context,
                    sl: sl,
                    salePos: salePos,
                    palette: palette,
                    loyaltyCfg: loyaltyCfg,
                    payableTotal: payableTotal,
                    buyerAddressQrEnabled: buyerAddressQrEnabled,
                    compactSnack: compactSnack,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _buildSaleMainBodyWithOptionalQuickRail(
                          context,
                          sl: sl,
                          salePos: salePos,
                          palette: palette,
                          loyaltyCfg: loyaltyCfg,
                          payableTotal: payableTotal,
                          buyerAddressQrEnabled: buyerAddressQrEnabled,
                          compactSnack: compactSnack,
                        ),
                      ),
                      _buildSaleCheckoutActionsFixedBar(
                        context,
                        sl: sl,
                        palette: palette,
                        loyaltyCfg: loyaltyCfg,
                        payableTotal: payableTotal,
                        compactSnack: compactSnack,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _setInvoicePaymentType(InvoiceType t) {
    final pos = context.read<SalePosSettingsProvider>().data;
    if (!pos.allowsPayment(t)) return;
    final prev = type;
    setState(() {
      type = t;
      if (t == InvoiceType.delivery) {
        _advanceController.text = '0';
      }
    });
    if (t == InvoiceType.installment && prev != InvoiceType.installment) {
      unawaited(_prefillInstallmentAssistFields());
    }
    if (t == InvoiceType.cash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncCashAdvanceToTotalIfCash(
          context.read<LoyaltySettingsProvider>().data,
        );
      });
    }
  }

  Color _salePanelPrimaryText(BuildContext context, SalePalette palette) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE8E4DC)
      : palette.navy;

  Color _salePanelMutedText(BuildContext context, SalePalette palette) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : palette.navy.withValues(alpha: 0.58);

  /// مسافة بعد كل كتلة رئيسية في تدفق البيع — أوسع قليلاً على الشاشات الكبيرة.
  double _saleFlowBlockGap(BuildContext context) =>
      ScreenLayout.of(context).showSaleBarcodeShortcut ? 18 : 26;

  EdgeInsets _saleOuterScrollPadding(ScreenLayout sl) => EdgeInsets.fromLTRB(
    sl.pageHorizontalGap,
    16,
    sl.pageHorizontalGap,
    sl.showSaleBarcodeShortcut ? 10 : 14,
  );

  static const double _kWideQuickProductRailMinWidth = 800;

  bool _showWideQuickProductRail(ScreenLayout sl) =>
      !sl.isHandsetForLayout && sl.size.width >= _kWideQuickProductRailMinWidth;

  Future<void> _onWideSaleRailProductPick(
    Map<String, dynamic> p, {
    double addQuantity = 1.0,
  }) async {
    final name = (p['name'] ?? '').toString().trim();
    final baseSell = (p['sell'] as num?)?.toDouble() ?? 0;
    final baseMin = (p['minSell'] as num?)?.toDouble() ?? baseSell;
    final pid = (p['id'] as num?)?.toInt();
    final display = name.isEmpty ? 'منتج' : name;
    final knownQty = (p['qty'] as num?)?.toDouble();
    final u = await _unitSelectionForCatalogProduct(p);
    if (!mounted) return;
    // سعر بطاقة المنتج للوحدة الأساسية؛ يُضرب في factor الوحدة الافتراضية المعروضة.
    final pricing = _resolveVariantPricing(
      baseSell: baseSell,
      baseMin: baseMin,
      variantSell: null,
      variantMin: null,
      factor: u.unitFactor,
    );
    await _addOrMergeCatalogProductLine(
      productName: display,
      productId: pid,
      sellPrice: pricing.sell,
      minSellPrice: pricing.min,
      trackInventory: _tiFromProductRow(p),
      allowNegativeStock: _anFromProductRow(p),
      knownOnHandQty: knownQty,
      stockBaseKind: u.stockBaseKind,
      unitVariantId: u.unitVariantId,
      unitLabel: u.unitLabel,
      unitFactor: u.unitFactor,
      addQuantity: addQuantity,
      suppressLineSnacks: true,
    );
    if (!mounted || type != InvoiceType.cash) return;
    _syncCashAdvanceToTotalIfCash(
      Provider.of<LoyaltySettingsProvider>(context, listen: false).data,
    );
  }

  /// أزرار تعليق/دفع — داخل التمرير على الهاتف، شريط ثابت على التابلت.
  Widget _buildSaleCheckoutActionsContent(
    BuildContext context, {
    required ScreenLayout sl,
    required SalePalette palette,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool compactSnack,
  }) {
    final parkedCount = context.watch<ParkedSalesProvider>().count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compactSnack && _saleInlineToast != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    440,
                    sl.size.width - sl.pageHorizontalGap * 2,
                  ),
                ),
                child: Material(
                  color:
                      _saleInlineToastBg ??
                      palette.navy.withValues(alpha: 0.96),
                  elevation: 3,
                  shadowColor: palette.navy.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: palette.gold.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: _dismissSaleInlineToast,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 20,
                            color: palette.gold,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saleInlineToast!,
                              style: TextStyle(
                                color: _toastOnSurface(
                                  _saleInlineToastBg ?? palette.navy,
                                ),
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        SizedBox(
          height: sl.showSaleBarcodeShortcut ? 48 : 46,
          child: OutlinedButton.icon(
            onPressed: _parkInvoice,
            icon: Icon(
              Icons.pause_circle_outline_rounded,
              size: 22,
              color: SaleAccessibleButtonColors.outlinedAccentIcon(
                palette.gold,
              ),
            ),
            label: Text(
              parkedCount > 0
                  ? 'تعليق الفاتورة — تعليق ($parkedCount)'
                  : 'تعليق الفاتورة — خدمة عميل آخر',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: sl.showSaleBarcodeShortcut ? 13.5 : 14,
                color: SaleAccessibleButtonColors.outlinedOnAppSurfaceText(
                  palette.navy,
                  Theme.of(context).brightness,
                ),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  SaleAccessibleButtonColors.outlinedOnAppSurfaceText(
                    palette.navy,
                    Theme.of(context).brightness,
                  ),
              iconColor: SaleAccessibleButtonColors.outlinedAccentIcon(
                palette.gold,
              ),
              side: BorderSide(color: palette.gold, width: 1.4),
            ),
          ),
        ),
        SizedBox(height: sl.showSaleBarcodeShortcut ? 10 : 8),
        SizedBox(
          height: sl.showSaleBarcodeShortcut ? 52 : 48,
          child: FilledButton.icon(
            onPressed: !_canCompleteSalePayment(loyaltyCfg)
                ? null
                : () => unawaited(_saveInvoice()),
            style: FilledButton.styleFrom(
              backgroundColor: palette.navy,
              foregroundColor: SaleAccessibleButtonColors.filledOnNavyLabel(),
              iconColor: SaleAccessibleButtonColors.filledOnNavyIcon(
                palette.gold,
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.payments_rounded),
            label: Text(
              'الدفع — ${IraqiCurrencyFormat.formatIqd(payableTotal)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: sl.showSaleBarcodeShortcut ? 16 : 15,
                color: SaleAccessibleButtonColors.filledOnNavyLabel(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaleCheckoutActionsFixedBar(
    BuildContext context, {
    required ScreenLayout sl,
    required SalePalette palette,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool compactSnack,
  }) {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: sl.showSaleBarcodeShortcut ? 10 : 4,
        shadowColor: palette.navy.withValues(alpha: 0.2),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: palette.gold.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sl.pageHorizontalGap,
              12,
              sl.pageHorizontalGap,
              12,
            ),
            child: _buildSaleCheckoutActionsContent(
              context,
              sl: sl,
              palette: palette,
              loyaltyCfg: loyaltyCfg,
              payableTotal: payableTotal,
              compactSnack: compactSnack,
            ),
          ),
        ),
      ),
    );
  }

  /// نهاية عمود التمرير على الهاتف — نفس الأزرار مع فاصل وحاشية سفلية آمنة.
  Widget _buildSaleHandsetCheckoutScrollFooter(
    BuildContext context, {
    required ScreenLayout sl,
    required SalePalette palette,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool compactSnack,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(top: 18, bottom: bottomInset + 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            height: 1,
            thickness: 1.5,
            color: palette.gold.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          _buildSaleCheckoutActionsContent(
            context,
            sl: sl,
            palette: palette,
            loyaltyCfg: loyaltyCfg,
            payableTotal: payableTotal,
            compactSnack: compactSnack,
          ),
        ],
      ),
    );
  }

  /// تدفق البيع مع عمود «المنتجات السريعة» على الشاشات العريضة فقط.
  Widget _buildSaleMainBodyWithOptionalQuickRail(
    BuildContext context, {
    required ScreenLayout sl,
    required SalePosSettingsData salePos,
    required SalePalette palette,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool buyerAddressQrEnabled,
    required bool compactSnack,
  }) {
    final main = _buildSaleMainScrollArea(
      context,
      sl: sl,
      salePos: salePos,
      palette: palette,
      loyaltyCfg: loyaltyCfg,
      payableTotal: payableTotal,
      buyerAddressQrEnabled: buyerAddressQrEnabled,
      compactSnack: compactSnack,
    );
    if (!_showWideQuickProductRail(sl)) return main;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saleQuickRailSearchAutofocusDone) return;
      _saleQuickRailSearchAutofocusDone = true;
      _saleQuickRailSearchFocus.requestFocus();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final railBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final text1 = isDark ? Colors.white : const Color(0xFF0F172A);
    final text2 = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      textDirection: TextDirection.rtl,
      children: [
        Expanded(child: main),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) {
              setState(() {
                _saleQuickRailWidth = (_saleQuickRailWidth + d.delta.dx).clamp(
                  _kSaleQuickRailMinW,
                  _kSaleQuickRailMaxW,
                );
              });
            },
            onHorizontalDragEnd: (_) => unawaited(_persistSaleQuickRailWidth()),
            child: Tooltip(
              message: 'اسحب لتغيير عرض القائمة الجانبية',
              child: Container(
                width: 7,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: _saleQuickRailWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: railBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: TextField(
                    controller: _saleQuickRailSearchController,
                    focusNode: _saleQuickRailSearchFocus,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontSize: 13, color: text1),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'تصفية القائمة…',
                      hintStyle: TextStyle(color: text2, fontSize: 12.5),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF334155).withValues(alpha: 0.35)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      suffixIcon: _saleQuickRailSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح',
                              onPressed: () {
                                setState(_saleQuickRailSearchController.clear);
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: text2,
                              ),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: WideHomeProductRail(
                  searchQuery: _saleQuickRailSearchController.text,
                  isDark: isDark,
                  onProductPick: (m, {required addQuantity}) => unawaited(
                    _onWideSaleRailProductPick(m, addQuantity: addQuantity),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// عمود المنتجات + فاصل سحب + عمود الملخص والعميل (عرض ≥ 700dp ومع تفعيل التقسيم في الإعدادات)، أو عمود واحد.
  Widget _buildSaleMainScrollArea(
    BuildContext context, {
    required ScreenLayout sl,
    required SalePosSettingsData salePos,
    required SalePalette palette,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool buyerAddressQrEnabled,
    required bool compactSnack,
  }) {
    final useWideTwoColumns =
        sl.useWideSaleTwoColumnLayout && salePos.enableWideSalePartition;
    if (!useWideTwoColumns) {
      final embedCheckoutInScroll = sl.isHandsetForLayout;
      return SingleChildScrollView(
        padding: _saleOuterScrollPadding(sl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSaleFlowStepProducts(context, palette, salePos),
            _buildSaleFlowStepBasketSummary(context, palette, salePos),
            _buildSaleFlowStepPriceDetails(
              context,
              loyaltyCfg,
              palette,
              salePos,
            ),
            _buildSaleFlowStepCustomerPayment(
              context,
              palette: palette,
              salePos: salePos,
              loyaltyCfg: loyaltyCfg,
              payableTotal: payableTotal,
              buyerAddressQrEnabled: buyerAddressQrEnabled,
            ),
            if (embedCheckoutInScroll)
              _buildSaleHandsetCheckoutScrollFooter(
                context,
                sl: sl,
                palette: palette,
                loyaltyCfg: loyaltyCfg,
                payableTotal: payableTotal,
                compactSnack: compactSnack,
              ),
          ],
        ),
      );
    }

    final productsFlex = _wideFlexLive ?? salePos.wideSaleProductsFlex;
    final sideFlex = 100 - productsFlex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowW = constraints.maxWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: productsFlex,
              child: SingleChildScrollView(
                padding: _saleOuterScrollPadding(sl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSaleFlowStepProducts(context, palette, salePos),
                  ],
                ),
              ),
            ),
            _wideSaleDividerBetweenColumns(
              palette: palette,
              rowWidth: rowW,
              salePos: salePos,
            ),
            Expanded(
              flex: sideFlex,
              child: SingleChildScrollView(
                padding: _saleOuterScrollPadding(sl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSaleFlowStepBasketSummary(context, palette, salePos),
                    _buildSaleFlowStepPriceDetails(
                      context,
                      loyaltyCfg,
                      palette,
                      salePos,
                    ),
                    _buildSaleFlowStepCustomerPayment(
                      context,
                      palette: palette,
                      salePos: salePos,
                      loyaltyCfg: loyaltyCfg,
                      payableTotal: payableTotal,
                      buyerAddressQrEnabled: buyerAddressQrEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _wideSaleDividerBetweenColumns({
    required SalePalette palette,
    required double rowWidth,
    required SalePosSettingsData salePos,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: SizedBox(
        width: 12,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            setState(() {
              _wideFlexLive = _wideFlexLive ?? salePos.wideSaleProductsFlex;
            });
          },
          onHorizontalDragUpdate: (details) {
            if (rowWidth < 80) return;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final dx = rtl ? -details.delta.dx : details.delta.dx;
            setState(() {
              final cur = _wideFlexLive ?? salePos.wideSaleProductsFlex;
              final delta = (dx / rowWidth * 100).round();
              _wideFlexLive = SaleWideLayoutFlexBounds.clampProducts(
                cur + delta,
              );
            });
          },
          onHorizontalDragEnd: (_) => unawaited(_persistWideSaleFlex()),
          onHorizontalDragCancel: () => unawaited(_persistWideSaleFlex()),
          child: ColoredBox(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: 3,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: palette.gold.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _persistWideSaleFlex() async {
    final live = _wideFlexLive;
    if (live == null || !mounted) return;
    final prov = context.read<SalePosSettingsProvider>();
    if (prov.data.wideSaleProductsFlex == live) {
      setState(() => _wideFlexLive = null);
      return;
    }
    await prov.save(prov.data.copyWith(wideSaleProductsFlex: live));
    if (mounted) setState(() => _wideFlexLive = null);
  }

  Widget _saleFlowSectionTitle(
    BuildContext context,
    SalePalette palette, {
    required String title,
    String? caption,
    Widget? trailing,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFF1EDE6) : palette.navy;
    final capColor = dark
        ? const Color(0xFFCBD5E1)
        : palette.navy.withValues(alpha: 0.62);

    final wide = !ScreenLayout.of(context).showSaleBarcodeShortcut;
    return Padding(
      padding: EdgeInsets.only(bottom: wide ? 12 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: wide ? 4 : 3,
            height: wide ? 46 : 42,
            decoration: BoxDecoration(
              color: palette.gold,
              boxShadow: [
                BoxShadow(
                  color: palette.gold.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          SizedBox(width: wide ? 14 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: wide ? 17 : 16,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    letterSpacing: -0.2,
                    height: 1.25,
                  ),
                ),
                if (caption != null && caption.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: wide ? 11.5 : 11,
                      height: 1.45,
                      color: capColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _saleFlowPanel(
    BuildContext context,
    SalePalette palette,
    SalePosSettingsData pos, {
    required Widget child,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = !ScreenLayout.of(context).showSaleBarcodeShortcut;
    final bg = dark ? palette.ivoryDark : palette.ivory;
    final edge = dark
        ? palette.gold.withValues(alpha: 0.4)
        : palette.navy.withValues(alpha: 0.2);
    final r = pos.saleFlowBorderRadius;
    // لا تضع borderRadius على BoxDecoration مع حدود غير متساوية (اليمين أعرض) —
    // على الويب قد لا يُرسم المحتوى. القصّ بـ ClipRRect يعطي الزوايا الدائرية بأمان.
    final panel = Container(
      width: double.infinity,
      padding: EdgeInsets.all(wide ? 16 : 13),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: edge),
          bottom: BorderSide(color: edge),
          left: BorderSide(color: edge),
          right: BorderSide(color: palette.gold, width: wide ? 3 : 2.5),
        ),
      ),
      child: child,
    );
    if (pos.panelCornerStyle == SalePanelCornerStyle.sharp) {
      return panel;
    }
    return ClipRRect(
      borderRadius: r,
      clipBehavior: Clip.antiAlias,
      child: panel,
    );
  }

  Widget _paymentTypeChip(
    BuildContext context,
    SalePalette palette,
    SalePosSettingsData pos,
    InvoiceType value,
    String label,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected = type == value;
    final phone = ScreenLayout.of(context).showSaleBarcodeShortcut;
    final chipRadius = pos.saleChipBorderRadius;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => _setInvoicePaymentType(value),
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
      backgroundColor: dark ? const Color(0xFF243047) : Colors.white,
      selectedColor: palette.navy,
      labelPadding: EdgeInsets.symmetric(
        horizontal: phone ? 12 : 14,
        vertical: phone ? 9 : 8,
      ),
      side: BorderSide(
        color: selected ? palette.gold : palette.navy.withValues(alpha: 0.28),
        width: selected ? 1.8 : 1,
      ),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: phone ? 13.5 : 13,
        color: selected
            ? SaleAccessibleButtonColors.choiceChipSelectedLabel()
            : SaleAccessibleButtonColors.choiceChipUnselectedLabel(
                palette.navy,
                palette.gold,
                dark ? Brightness.dark : Brightness.light,
              ),
      ),
      visualDensity: VisualDensity.standard,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildSaleFlowStepProducts(
    BuildContext context,
    SalePalette palette,
    SalePosSettingsData pos,
  ) {
    final showScan = ScreenLayout.of(context).showSaleBarcodeShortcut;
    final productsCaption = (!pos.enableInvoiceDiscount && !pos.enableTaxOnSale)
        ? 'أسطر الفاتورة والكميات والأسعار — ثم راجع تفاصيل السعر وطريقة الدفع.'
        : 'أسطر الفاتورة والكميات والأسعار — ثم انتقل لخصم الفاتورة والضريبة.';
    return Padding(
      padding: EdgeInsets.only(bottom: _saleFlowBlockGap(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _saleFlowSectionTitle(
            context,
            palette,
            title: 'المنتجات',
            caption: productsCaption,
            trailing: showScan
                ? Tooltip(
                    message:
                        'إضافة صنف بالباركود، أو فتح مرتجع بمسح رقم الفاتورة (INV-)',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: palette.navy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: palette.gold.withValues(alpha: 0.22),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: _saleScannerOpen ? 10 : 6,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _toggleSaleScanner,
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _saleScannerOpen
                                    ? Icons.close_rounded
                                    : Icons.qr_code_scanner_rounded,
                                size: 24,
                                color: palette.gold,
                              ),
                              if (_saleScannerOpen) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'الماسح',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          if (_saleScannerOpen && _canUseEmbeddedScanner(context)) ...[
            _SaleInlineScannerCard(
              palette: palette,
              controller: _saleScannerController!,
              height: _saleScannerHeight,
              onClose: _closeSaleScanner,
              onDetect: _onSaleScannerDetect,
              onHeightChange: (h) => setState(() {
                _saleScannerHeight = h.clamp(160.0, 360.0);
              }),
            ),
            const SizedBox(height: 10),
          ],
          if (_lines.isEmpty)
            _saleFlowPanel(
              context,
              palette,
              pos,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: palette.gold.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      showScan
                          ? 'لا توجد أصناف بعد.\nامسح الباركود أعلاه أو أضف من البحث في الشاشة الرئيسية.\nابحث عن منتج أو امسح الباركود للإضافة.'
                          : 'لا توجد أصناف بعد.\nأضف منتجات من البحث في الشاشة الرئيسية.\nابحث عن منتج أو امسح الباركود للإضافة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF94A3B8)
                            : palette.navy.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._lines.asMap().entries.map((entry) {
              return _buildSaleLineCard(entry.key, entry.value, palette, pos);
            }),
        ],
      ),
    );
  }

  Widget _buildSaleFlowStepBasketSummary(
    BuildContext context,
    SalePalette palette,
    SalePosSettingsData pos,
  ) {
    if (!pos.enableInvoiceDiscount && !pos.enableTaxOnSale) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: _saleFlowBlockGap(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _saleFlowSectionTitle(
            context,
            palette,
            title: 'ملخص البيع',
            caption:
                'الخصم والضريبة يُطبَّقان على إجمالي الفاتورة (وليس لكل صنف على حدة).',
          ),
          const SizedBox(height: 6),
          _saleFlowPanel(
            context,
            palette,
            pos,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pos.enableInvoiceDiscount) ...[
                  Text(
                    'خصم الفاتورة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _salePanelPrimaryText(context, palette),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _discountPercentController,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'نسبة الخصم على إجمالي البيع %',
                      helperText:
                          'الحد الأقصى المسموح حالياً: ${_maxAllowedDiscountPercent.toStringAsFixed(1)}٪ — يُحسب من أدنى سعر لكل صنف.',
                      helperMaxLines: 3,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (pos.enableInvoiceDiscount && pos.enableTaxOnSale)
                  const SizedBox(height: 14),
                if (pos.enableTaxOnSale) ...[
                  Text(
                    'الضريبة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _salePanelPrimaryText(context, palette),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أدخل مبلغ الضريبة بالدينار إن وُجد؛ يُضاف إلى المجموع بعد خصم الفاتورة.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: _salePanelMutedText(context, palette),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _taxController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'مبلغ الضريبة (د.ع)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleFlowStepPriceDetails(
    BuildContext context,
    LoyaltySettingsData loyaltyCfg,
    SalePalette palette,
    SalePosSettingsData pos,
  ) {
    final payableTotal = saleTotal(loyaltyCfg);
    final priceCaption = (!pos.enableInvoiceDiscount && !pos.enableTaxOnSale)
        ? 'نتيجة الأرقام والدفعة الأولى إن وُجدت، قبل الانتقال لبيانات العميل.'
        : 'نتيجة الأرقام بعد الخصم والضريبة، والدفعة الأولى إن وُجدت، قبل الانتقال لبيانات العميل.';
    return Padding(
      padding: EdgeInsets.only(bottom: _saleFlowBlockGap(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _saleFlowSectionTitle(
            context,
            palette,
            title: 'تفاصيل السعر',
            caption: priceCaption,
          ),
          const SizedBox(height: 6),
          _saleFlowPanel(
            context,
            palette,
            pos,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تفصيل المبالغ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _salePanelPrimaryText(context, palette),
                  ),
                ),
                const SizedBox(height: 8),
                _sumRow(
                  'المبلغ الأصلي (مجموع البنود)',
                  IraqiCurrencyFormat.formatIqd(subtotal),
                ),
                if (pos.enableInvoiceDiscount) ...[
                  const SizedBox(height: 6),
                  _sumRow(
                    'قيمة خصم الفاتورة',
                    IraqiCurrencyFormat.formatIqd(discountValue),
                  ),
                  const SizedBox(height: 4),
                  _sumRow(
                    'المجموع بعد الخصم (قبل الضريبة)',
                    IraqiCurrencyFormat.formatIqd(_subtotalAfterDiscount),
                  ),
                ],
                if (pos.enableTaxOnSale) ...[
                  const SizedBox(height: 6),
                  _sumRow('الضريبة', IraqiCurrencyFormat.formatIqd(_tax)),
                ],
                if (type != InvoiceType.cash &&
                    type != InvoiceType.credit &&
                    type != InvoiceType.delivery &&
                    !(type == InvoiceType.installment &&
                        _instSaleSettings.showInstallmentCalculatorOnSale)) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _advanceController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'المقدم (د.ع)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (loyaltyCfg.enabled &&
                    type != InvoiceType.installment &&
                    _loyaltyDiscountAmount(loyaltyCfg) > 0) ...[
                  const SizedBox(height: 8),
                  _sumRow(
                    'خصم ولاء (نقاط)',
                    '-${IraqiCurrencyFormat.formatInt(_loyaltyDiscountAmount(loyaltyCfg))} د.ع',
                  ),
                ],
                Divider(
                  height: 22,
                  color: palette.navy.withValues(alpha: 0.12),
                ),
                _sumRow(
                  'الإجمالي النهائي',
                  IraqiCurrencyFormat.formatIqd(payableTotal),
                  strong: true,
                  labelColor: _salePanelPrimaryText(context, palette),
                  valueColor: palette.gold,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleFlowStepCustomerPayment(
    BuildContext context, {
    required SalePalette palette,
    required SalePosSettingsData salePos,
    required LoyaltySettingsData loyaltyCfg,
    required double payableTotal,
    required bool buyerAddressQrEnabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final paymentOptions = <String>[
      'نقدي',
      if (salePos.allowCredit) 'دين',
      if (salePos.allowInstallment) 'تقسيط',
      if (salePos.allowDelivery) 'توصيل',
    ];
    final customerCaption =
        'اختر ${paymentOptions.join(' أو ')}، ثم أكمل بيانات العميل والحقول المرتبطة بنوع الدفع.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _saleFlowSectionTitle(
            context,
            palette,
            title: 'العميل وطريقة الدفع',
            caption: customerCaption,
          ),
          const SizedBox(height: 6),
          _saleFlowPanel(
            context,
            palette,
            salePos,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'طريقة الدفع',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _salePanelPrimaryText(context, palette),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.start,
                  children: [
                    _paymentTypeChip(
                      context,
                      palette,
                      salePos,
                      InvoiceType.cash,
                      'نقدي',
                    ),
                    if (salePos.allowCredit)
                      _paymentTypeChip(
                        context,
                        palette,
                        salePos,
                        InvoiceType.credit,
                        'دين',
                      ),
                    if (salePos.allowInstallment)
                      _paymentTypeChip(
                        context,
                        palette,
                        salePos,
                        InvoiceType.installment,
                        'تقسيط',
                      ),
                    if (salePos.allowDelivery)
                      _paymentTypeChip(
                        context,
                        palette,
                        salePos,
                        InvoiceType.delivery,
                        'توصيل',
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _customerController,
                        decoration: const InputDecoration(
                          labelText: 'اسم العميل',
                          isDense: true,
                          hintText: 'ابحث من أول حرف…',
                        ),
                        onChanged: (_) {
                          setState(() => _linkedCustomerId = null);
                          _onCustomerInputChanged();
                        },
                        validator: (v) {
                          if (_needsCustomerNameFor &&
                              (v == null || v.trim().isEmpty)) {
                            return type == InvoiceType.delivery
                                ? 'اسم العميل مطلوب للتوصيل'
                                : 'مطلوب للدين/التقسيط';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Tooltip(
                        message: 'إضافة عميل جديد دون مغادرة البيع',
                        child: Material(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.95,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.none,
                          ),
                          child: InkWell(
                            onTap: _openQuickAddCustomerDialog,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.person_add_alt_1_outlined,
                                size: 22,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (type == InvoiceType.credit) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _advanceController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'المبلغ الواصل (د.ع)',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_customerHits.isNotEmpty &&
                    _customerController.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Material(
                      elevation: 3,
                      color: Theme.of(context).cardColor,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _customerHits.length,
                          itemBuilder: (ctx, i) {
                            final c = _customerHits[i];
                            final phone = c['phone']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              title: Text(c['name']?.toString() ?? ''),
                              subtitle: phone.isNotEmpty ? Text(phone) : null,
                              onTap: () {
                                _customerController.text =
                                    c['name']?.toString() ?? '';
                                setState(() {
                                  _linkedCustomerId = c['id'] as int?;
                                  _customerHits = [];
                                });
                                FocusScope.of(context).unfocus();
                                unawaited(_refreshLoyaltyBalance());
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (type == InvoiceType.installment &&
                    _instSaleSettings.showInstallmentCalculatorOnSale)
                  _buildInstallmentAssistCard(loyaltyCfg, salePos),
                if (type == InvoiceType.delivery ||
                    (buyerAddressQrEnabled &&
                        (type != InvoiceType.cash ||
                            salePos.showBuyerAddressOnCash)))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextFormField(
                      controller: _deliveryAddressController,
                      decoration: InputDecoration(
                        labelText:
                            type == InvoiceType.delivery &&
                                buyerAddressQrEnabled
                            ? 'عنوان التوصيل والموقع (QR خرائط)'
                            : type == InvoiceType.delivery
                            ? 'عنوان التوصيل'
                            : 'عنوان المشتري (QR للخرائط على الإيصال)',
                        helperText:
                            buyerAddressQrEnabled &&
                                type != InvoiceType.delivery
                            ? 'اختياري — وصف أو عنوان يظهر في Google Maps عند مسح الرمز'
                            : (buyerAddressQrEnabled
                                  ? (type == InvoiceType.delivery
                                        ? 'مطلوب — يُطبَع QR للخرائط عند وجود نص؛ اكتب عنوان التوصيل بوضوح'
                                        : 'يُطبَع QR يفتح الخرائط عند المسح')
                                  : null),
                        isDense: true,
                      ),
                      maxLines: buyerAddressQrEnabled ? 3 : 2,
                      validator: (v) {
                        if (type == InvoiceType.delivery &&
                            (v == null || v.trim().isEmpty)) {
                          return 'عنوان التوصيل مطلوب';
                        }
                        return null;
                      },
                    ),
                  ),
                if (loyaltyCfg.enabled && type != InvoiceType.installment) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _linkedCustomerId == null
                          ? 'لاستخدام النقاط: اختر عميلاً مسجّلاً من القائمة المقترحة.'
                          : 'رصيد نقاط العميل: $_customerLoyaltyBalance',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_linkedCustomerId != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _loyaltyRedeemController,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText:
                                  'نقاط للاستبدال (حد أقصى ${LoyaltyMath.maxRedeemablePoints(balance: _customerLoyaltyBalance, netBeforeLoyalty: _netBeforeLoyaltySale, s: loyaltyCfg)})',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OutlinedButton(
                            onPressed: () {
                              final m = LoyaltyMath.maxRedeemablePoints(
                                balance: _customerLoyaltyBalance,
                                netBeforeLoyalty: _netBeforeLoyaltySale,
                                s: loyaltyCfg,
                              );
                              setState(() {
                                _loyaltyRedeemController.text = m.toString();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  SaleAccessibleButtonColors.outlinedOnSalePanelText(
                                    palette.navy,
                                    Theme.of(context).brightness,
                                  ),
                              side: BorderSide(color: palette.gold, width: 1.1),
                            ),
                            child: const Text('الأقصى'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                if (_needsCustomerNameFor)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      type == InvoiceType.delivery
                          ? 'للتوصيل: أدخل اسم العميل وعنوان التوصيل (كلاهما مطلوب). يظهر اقتراح للاسم من قاعدة العملاء أثناء الكتابة.'
                          : 'مهم: للدين والتقسيط اضغط على اسم العميل من القائمة المقترحة لربط البيع ببطاقته (لا يكفي كتابة الاسم يدوياً إن لم يُطابق سجلاً واحداً بالضبط).',
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(
    String k,
    String v, {
    bool strong = false,
    Color? labelColor,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                fontSize: strong ? 15 : 13,
                height: 1.3,
                color: labelColor,
              ),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            v,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: strong ? 16 : 13,
              height: 1.25,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleLineCard(
    int idx,
    _InvoiceLineState item,
    SalePalette palette,
    SalePosSettingsData pos,
  ) {
    _touchProductVariants(item.productId);
    final expanded = _expandedLineIds.contains(item.lineId);
    final gross = _lineGross(item);
    final share = _lineBasketDiscountShare(item);
    final net = _lineNetAfterBasketDiscount(item);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lineBorder = dark
        ? scheme.outlineVariant
        : palette.navy.withValues(alpha: 0.14);
    final cardRadius = pos.saleFlowBorderRadius;
    final variants = item.productId == null
        ? const <Map<String, dynamic>>[]
        : (_variantsByProductId[item.productId!] ??
              const <Map<String, dynamic>>[]);
    final showVariantChips = item.productId != null && variants.length > 1;
    final qtyStep = _saleQtyStep(item);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: lineBorder),
            borderRadius: cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 22,
                      ),
                      tooltip: expanded
                          ? 'إخفاء التفاصيل'
                          : 'تفاصيل السعر والخصم',
                      onPressed: () {
                        setState(() {
                          if (expanded) {
                            _expandedLineIds.remove(item.lineId);
                          } else {
                            _expandedLineIds.add(item.lineId);
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (showVariantChips) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final v in variants)
                                  ChoiceChip(
                                    label: Text(
                                      _variantChipLabel(v),
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    selected: () {
                                      final vid = (v['id'] as num?)?.toInt();
                                      if (item.unitVariantId != null) {
                                        return item.unitVariantId == vid;
                                      }
                                      return ((v['isDefault'] as num?)
                                                  ?.toInt() ??
                                              0) ==
                                          1;
                                    }(),
                                    onSelected: (_) => unawaited(
                                      _applyLineVariantSelection(
                                        line: item,
                                        v: v,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (item.stockBaseKind == 1) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  label: const Text('+¼ كغ'),
                                  onPressed: () => unawaited(
                                    _trySetLineQuantity(
                                      item,
                                      item.quantity + 0.25,
                                    ),
                                  ),
                                ),
                                ActionChip(
                                  label: const Text('+½ كغ'),
                                  onPressed: () => unawaited(
                                    _trySetLineQuantity(
                                      item,
                                      item.quantity + 0.5,
                                    ),
                                  ),
                                ),
                                ActionChip(
                                  label: const Text('+1 كغ'),
                                  onPressed: () => unawaited(
                                    _trySetLineQuantity(
                                      item,
                                      item.quantity + 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            'سعر ${IraqiCurrencyFormat.formatInt(item.unitPrice)} · أدنى ${IraqiCurrencyFormat.formatInt(item.minSellPrice)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (!expanded) ...[
                            const SizedBox(height: 2),
                            Text(
                              'الإجمالي: ${IraqiCurrencyFormat.formatIqd(gross)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            setState(() {
                              final next = item.quantity - qtyStep;
                              final minQ = item.stockBaseKind == 1 ? 1e-6 : 1.0;
                              if (next + 1e-12 >= minQ) {
                                item.quantity = next;
                              }
                            });
                          },
                        ),
                        Material(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: InkWell(
                            onTap: () => _promptEditQuantity(item),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                _formatSaleQty(item),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () async {
                            await _trySetLineQuantity(
                              item,
                              item.quantity + qtyStep,
                            );
                          },
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => setState(() {
                            _expandedLineIds.remove(item.lineId);
                            _lines.removeAt(idx);
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (expanded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _lineDetailRow(
                        'سعر البيع (للوحدة)',
                        IraqiCurrencyFormat.formatIqd(item.unitPrice),
                      ),
                      _lineDetailRow(
                        'إجمالي السطر قبل خصم الفاتورة',
                        IraqiCurrencyFormat.formatIqd(gross),
                      ),
                      _lineDetailRow(
                        'حصة خصم الفاتورة لهذا السطر',
                        IraqiCurrencyFormat.formatIqd(share),
                        emphasize: share > 0,
                      ),
                      _lineDetailRow(
                        'الإجمالي بعد خصم الفاتورة (لهذا السطر)',
                        IraqiCurrencyFormat.formatIqd(net),
                        strong: true,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يُوزَّع خصم النسبة على الأسطر بحسب مساهمة كل سطر في إجمالي البنود.',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.25,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineDetailRow(
    String label,
    String value, {
    bool strong = false,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppTheme.primaryColor : null,
            ),
          ),
        ],
      ),
    );
  }

  void _promptEditQuantity(_InvoiceLineState item) {
    final ctrl = TextEditingController(text: _formatSaleQty(item));
    final isWeight = item.stockBaseKind == 1;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('الكمية'),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: false,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            autofocus: true,
            decoration: InputDecoration(
              labelText: isWeight ? 'الكمية (كيلوغرام)' : 'الكمية',
              hintText: isWeight ? 'مثال: 0.25 أو 1.5 أو 3' : 'مثال: 2',
            ),
            onSubmitted: (_) async {
              await _applyQuantityFromDialog(ctx, item, ctrl.text);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await _applyQuantityFromDialog(ctx, item, ctrl.text);
              },
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyQuantityFromDialog(
    BuildContext dialogContext,
    _InvoiceLineState item,
    String raw,
  ) async {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    final minQ = item.stockBaseKind == 1 ? 1e-6 : 1.0;
    if (v == null || v < minQ) {
      _showSaleSnackBar(
        SnackBar(
          content: Text(
            item.stockBaseKind == 1
                ? 'أدخل كمية أكبر من 0 (يمكن كسور للوزن).'
                : 'أدخل عدداً صحيحاً 1 فما فوق',
          ),
        ),
      );
      return;
    }
    final ok = await _trySetLineQuantity(item, v);
    if (ok && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }

  Map<String, dynamic> _serializeParkedPayload() {
    return {
      'v': 1,
      'customer': _customerController.text,
      'linkedCustomerId': _linkedCustomerId,
      'loyaltyRedeem': _loyaltyRedeemController.text,
      'deliveryAddress': _deliveryAddressController.text,
      'discountPercent': _discountPercentController.text,
      'tax': _taxController.text,
      'advance': _advanceController.text,
      'instInterestPct': _instInterestPct.text,
      'instMonths': _instMonths.text,
      'type': type.index,
      'lineIdSeq': _lineIdSeq,
      'lines': _lines
          .map(
            (l) => {
              'lineId': l.lineId,
              'productName': l.productName,
              'quantity': l.quantity,
              'unitPrice': l.unitPrice,
              'sellPrice': l.sellPrice,
              'minSellPrice': l.minSellPrice,
              'productId': l.productId,
              'trackInventory': l.trackInventory,
              'allowNegativeStock': l.allowNegativeStock,
              'stockBaseKind': l.stockBaseKind,
              'unitVariantId': l.unitVariantId,
              'unitLabel': l.unitLabel,
              'unitFactor': l.unitFactor,
            },
          )
          .toList(),
    };
  }

  void _applyParkedPayloadMap(Map<String, dynamic> m) {
    _customerController.text = m['customer']?.toString() ?? '';
    _linkedCustomerId = (m['linkedCustomerId'] as num?)?.toInt();
    _loyaltyRedeemController.text = m['loyaltyRedeem']?.toString() ?? '0';
    _deliveryAddressController.text = m['deliveryAddress']?.toString() ?? '';
    _discountPercentController.text = m['discountPercent']?.toString() ?? '0';
    _taxController.text = m['tax']?.toString() ?? '0';
    _advanceController.text = m['advance']?.toString() ?? '0';
    _instInterestPct.text = m['instInterestPct']?.toString() ?? '0';
    _instMonths.text = m['instMonths']?.toString() ?? '6';
    type = invoiceTypeFromDb(m['type']);
    if (type == InvoiceType.delivery) {
      _advanceController.text = '0';
    }
    _variantsByProductId.clear();
    _variantsLoading.clear();
    _lines.clear();
    final rawLines = m['lines'] as List<dynamic>? ?? [];
    var maxLineId = _lineIdSeq;
    for (final raw in rawLines) {
      final e = raw as Map<String, dynamic>;
      final lid = (e['lineId'] as num?)?.toInt() ?? (_lineIdSeq + 1);
      if (lid > maxLineId) maxLineId = lid;
      _lines.add(
        _InvoiceLineState(
          lineId: lid,
          productName: e['productName']?.toString() ?? 'صنف',
          quantity: (e['quantity'] as num?)?.toDouble() ?? 1.0,
          unitPrice: (e['unitPrice'] as num?)?.toDouble() ?? 0,
          sellPrice:
              (e['sellPrice'] as num?)?.toDouble() ??
              (e['unitPrice'] as num?)?.toDouble() ??
              0,
          minSellPrice:
              (e['minSellPrice'] as num?)?.toDouble() ??
              (e['unitPrice'] as num?)?.toDouble() ??
              0,
          productId: (e['productId'] as num?)?.toInt(),
          trackInventory: e['trackInventory'] == false ? false : true,
          allowNegativeStock: e['allowNegativeStock'] == true,
          stockBaseKind: (e['stockBaseKind'] as num?)?.toInt() ?? 0,
          unitVariantId: (e['unitVariantId'] as num?)?.toInt(),
          unitLabel: e['unitLabel']?.toString(),
          unitFactor: (e['unitFactor'] as num?)?.toDouble() ?? 1.0,
        ),
      );
      final pid = (e['productId'] as num?)?.toInt();
      if (pid != null) {
        unawaited(_ensureVariantsLoadedForProduct(pid));
      }
    }
    _lineIdSeq = maxLineId;
  }

  Future<void> _loadParkedSale() async {
    final id = widget.resumeParkedSaleId;
    if (id == null || !mounted) return;
    final row = await _parkDb.getParkedSaleById(id);
    if (!mounted) return;
    if (row == null) {
      if (mounted) {
        setState(() => _blockSaleDraftUntilResumeApplied = false);
      }
      _showSaleSnackBar(
        const SnackBar(content: Text('تعذر العثور على الفاتورة المعلّقة')),
      );
      return;
    }
    try {
      final map = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      if ((map['v'] as num?)?.toInt() != 1) {
        throw FormatException('bad version');
      }
      setState(() {
        _applyParkedPayloadMap(map);
        _activeParkedSaleId = id;
        _blockSaleDraftUntilResumeApplied = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshLoyaltyBalance());
        unawaited(_refreshInstSaleSettingsFromDb());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _blockSaleDraftUntilResumeApplied = false);
      _showSaleSnackBar(
        const SnackBar(
          content: Text('ملف الفاتورة المعلّقة تالف أو غير متوافق'),
        ),
      );
    }
  }

  Future<void> _parkInvoice() async {
    if (_lines.isEmpty) {
      _showSaleSnackBar(
        const SnackBar(
          content: Text('أضف صنفاً واحداً على الأقل لتعليق الفاتورة'),
        ),
      );
      return;
    }
    final defaultTitle = _customerController.text.trim().isEmpty
        ? 'فاتورة (${_lines.length} صنف)'
        : _customerController.text.trim();
    final theme = Theme.of(context);
    final salePos = context.read<SalePosSettingsProvider>().data;
    final palette = SalePalette.fromSettings(salePos, theme);
    final isDark = theme.brightness == Brightness.dark;
    final title = await showDialog<String>(
      context: context,
      // داخل نفس مسار البيع (نافذة mac / المحتوى) — لا يُعرض فوق كامل الشاشة بعيداً عن لوحة البيع.
      useRootNavigator: false,
      barrierDismissible: true,
      barrierColor: palette.navy.withValues(alpha: 0.52),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: _SaleParkInvoiceDialog(
          palette: palette,
          isDark: isDark,
          initialTitle: defaultTitle,
        ),
      ),
    );
    if (!mounted || title == null) return;
    final t = title.trim();
    final effectiveTitle = t.isEmpty ? defaultTitle : t;
    await _performParkSave(effectiveTitle);
  }

  Future<void> _performParkSave(String title) async {
    final jsonStr = jsonEncode(_serializeParkedPayload());
    try {
      if (_activeParkedSaleId != null) {
        await _parkDb.updateParkedSale(
          id: _activeParkedSaleId!,
          title: title,
          payloadJson: jsonStr,
        );
      } else {
        await _parkDb.insertParkedSale(title: title, payloadJson: jsonStr);
      }
      CloudSyncService.instance.scheduleSyncSoon();
      if (!mounted) return;
      final parkedMessenger = ScaffoldMessenger.of(context);
      final snackCompact = context
          .read<UiFeedbackSettingsProvider>()
          .useCompactSnackNotifications;
      await context.read<ParkedSalesProvider>().refresh();
      if (!mounted) return;
      _leaveSaleScreen();
      _showSnackBarViaMessenger(
        parkedMessenger,
        SnackBar(
          content: Text(
            _activeParkedSaleId != null
                ? 'تم تحديث الفاتورة المعلّقة'
                : 'تم تعليق الفاتورة — يمكنك استئنافها من قائمة الفواتير',
          ),
        ),
        useCompactSnackOverride: snackCompact,
      );
    } catch (_) {
      if (!mounted) return;
      _showSaleSnackBar(
        const SnackBar(content: Text('تعذر حفظ الفاتورة المعلّقة')),
      );
    }
  }

  Future<void> _clearParkedIfAny() async {
    final id = _activeParkedSaleId;
    if (id == null) return;
    await _parkDb.deleteParkedSale(id);
    CloudSyncService.instance.scheduleSyncSoon();
    if (mounted) {
      await context.read<ParkedSalesProvider>().refresh();
    }
  }

  Future<void> _safePrintReceipt(
    BuildContext navigatorContext,
    Invoice invoice,
    double subtotalBefore,
  ) async {
    try {
      await SaleReceiptPdf.presentReceipt(
        navigatorContext,
        invoice: invoice,
        subtotalBeforeDiscount: subtotalBefore,
      );
    } catch (e, st) {
      debugPrint('presentReceipt failed: $e\n$st');
    }
  }

  List<Map<String, dynamic>> _saleLineMapsForNotification(
    List<InvoiceItem> items,
  ) {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final it in items) {
      if (i++ >= 25) break;
      out.add({
        'name': it.productName.trim().isEmpty ? 'صنف' : it.productName.trim(),
        'qty': it.enteredQty,
        'lineTotal': it.total,
        if (it.productId != null) 'productId': it.productId,
      });
    }
    return out;
  }

  Future<void> _emitFinancedSaleNotif({
    required int invoiceId,
    required bool isInstallment,
    required String customerName,
    required String staffName,
    required double total,
    required double advance,
    required DateTime at,
    required List<InvoiceItem> items,
    int? planId,
    bool planCreationFailed = false,
    ({
      double financed,
      double interestPct,
      double interestAmt,
      double totalWithInterest,
      int months,
      double monthly,
    })?
    installmentCalc,
  }) async {
    if (!mounted || !context.mounted) return;
    final c = installmentCalc;
    await context.read<NotificationProvider>().recordFinancedSale(
      invoiceId: invoiceId,
      isInstallment: isInstallment,
      customerName: customerName,
      staffName: staffName,
      total: total,
      advance: advance,
      at: at,
      lines: _saleLineMapsForNotification(items),
      planId: planId,
      plannedMonths: c?.months,
      suggestedMonthly: c?.monthly,
      financedAtSale: c?.financed,
      totalWithInterest: c?.totalWithInterest,
      planCreationFailed: planCreationFailed,
    );
  }

  Future<void> _saveInvoice() async {
    if (_lines.isEmpty) {
      _showSaleSnackBar(
        const SnackBar(
          content: Text('أضف صنفاً واحداً على الأقل لإتمام البيع'),
        ),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSaleSnackBar(
        const SnackBar(
          content: Text(
            'أكمل الحقول المطلوبة: للدين أو التقسيط أدخل اسم العميل، وللتوصيل أدخل اسم العميل وعنوان التوصيل. راجع الحقول المظللة بالأحمر.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    final posSave = context.read<SalePosSettingsProvider>().data;
    if (!posSave.allowsPayment(type)) {
      _showSaleSnackBar(
        const SnackBar(
          content: Text(
            'طريقة الدفع الحالية غير مسموحة — راجع «الفواتير → إعدادات نقطة البيع» أو اختر نقدي.',
          ),
        ),
      );
      return;
    }

    if (posSave.enableInvoiceDiscount &&
        _discountPercent > _maxAllowedDiscountPercent) {
      _showSaleSnackBar(
        SnackBar(
          content: Text(
            'نسبة الخصم أعلى من المسموح. الحد الأقصى ${_maxAllowedDiscountPercent.toStringAsFixed(2)}%',
          ),
        ),
      );
      return;
    }

    final customerName = _customerController.text.trim();
    final loyaltyCfg = Provider.of<LoyaltySettingsProvider>(
      context,
      listen: false,
    ).data;
    final invoiceProvider = Provider.of<InvoiceProvider>(
      context,
      listen: false,
    );
    final staffName = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).username.trim();

    final customerId =
        _linkedCustomerId ??
        await _parkDb.tryResolveCustomerIdByExactName(customerName);
    if (!mounted) return;

    if ((type == InvoiceType.credit || type == InvoiceType.installment) &&
        customerId == null) {
      if (mounted) {
        _showSaleSnackBar(
          const SnackBar(
            content: Text(
              'للمبيع بالدين أو التقسيط: اختر عميلاً مسجّلاً من القائمة المقترحة أسفل حقل الاسم '
              '(أو أضفه من «العملاء» أولاً) حتى تُربط الفاتورة ببطاقة العميل وتظهر لاحقاً في الديون والأقساط.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    final redeemPts = _clampedRedeemPoints(loyaltyCfg);
    final rawRedeem = int.tryParse(_loyaltyRedeemController.text.trim()) ?? 0;
    if (loyaltyCfg.enabled && rawRedeem > 0 && customerId == null) {
      if (mounted) {
        _showSaleSnackBar(
          const SnackBar(
            content: Text(
              'لاستبدال النقاط اختر العميل من القائمة أو أدخل اسماً يطابق سجلاً واحداً في العملاء.',
            ),
          ),
        );
      }
      return;
    }
    final items = _lines.map((l) {
      final entered = _lineEnteredForMath(l);
      final base = _lineBaseForMath(l);
      return InvoiceItem(
        productName: l.productName,
        quantity: base,
        price: l.unitPrice,
        total: entered * l.unitPrice,
        productId: l.productId,
        unitVariantId: l.unitVariantId,
        unitLabel: l.unitLabel,
        unitFactor: l.unitFactor <= 0 ? 1.0 : l.unitFactor,
        enteredQty: entered,
        baseQty: base,
      );
    }).toList();
    final discount = discountValue;
    final tax = _tax;
    final advancePayment = type == InvoiceType.delivery ? 0.0 : _advancePayment;
    final deliveryAddress = _deliveryAddressController.text.trim().isEmpty
        ? null
        : _deliveryAddressController.text.trim();

    final dp = posSave.enableInvoiceDiscount
        ? _discountPercent.clamp(0, _maxAllowedDiscountPercent).toDouble()
        : 0.0;
    final now = DateTime.now();

    final payTotal = saleTotal(loyaltyCfg);
    final loyaltyDisc = _loyaltyDiscountAmount(loyaltyCfg);

    InstallmentSettingsData? instSettingsForSave;
    if (type == InvoiceType.installment) {
      instSettingsForSave = await _parkDb.getInstallmentSettings();
      if (instSettingsForSave.requireDownPaymentForInstallmentSale &&
          payTotal > 1e-6) {
        final minAdv =
            payTotal * (instSettingsForSave.minDownPaymentPercent / 100.0);
        if (advancePayment + 1e-6 < minAdv) {
          if (mounted) {
            _showSaleSnackBar(
              SnackBar(
                content: Text(
                  'بيع التقسيط: المقدّم يجب ألا يقل عن ${instSettingsForSave.minDownPaymentPercent}% من إجمالي الفاتورة (يُقارب ${IraqiCurrencyFormat.formatIqd(minAdv)}). عدّل حقل المقدّم أو راجع «الأقساط → إعدادات تقسيط».',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        }
      }
    }

    if (type == InvoiceType.credit) {
      final debtSet = await _parkDb.getDebtSettings();
      final remRaw = payTotal - advancePayment;
      final rem = remRaw.isFinite ? remRaw.clamp(0.0, 1e15) : 0.0;

      if (debtSet.enforceSingleInvoiceCapAtSale &&
          debtSet.maxOpenRemainingPerInvoice > 0 &&
          rem > debtSet.maxOpenRemainingPerInvoice + 1e-6) {
        if (mounted) {
          final cap = debtSet.maxOpenRemainingPerInvoice;
          _showSaleSnackBar(
            SnackBar(
              content: Text(
                'حد الدين للفاتورة: المتبقي (${IraqiCurrencyFormat.formatIqd(rem)}) يتجاوز السقف '
                '${IraqiCurrencyFormat.formatIqd(cap)}. عدّل الإجمالي أو المبلغ الواصل أو «الديون → إعدادات الدين».',
              ),
              duration: const Duration(seconds: 7),
            ),
          );
        }
        return;
      }

      if (debtSet.enforceCustomerCapAtSale &&
          debtSet.maxTotalOpenDebtPerCustomer > 0) {
        var existing = 0.0;
        if (customerId != null) {
          existing = await _parkDb.sumOpenCreditDebtForCustomer(customerId);
        } else if (customerName.trim().isNotEmpty) {
          existing = await _parkDb.sumOpenCreditDebtForUnlinkedCustomerName(
            customerName,
          );
        }
        if (existing + rem > debtSet.maxTotalOpenDebtPerCustomer + 1e-6) {
          if (mounted) {
            final cap = debtSet.maxTotalOpenDebtPerCustomer;
            _showSaleSnackBar(
              SnackBar(
                content: Text(
                  'حد الدين للعميل: مجموع المتبقي الحالي ≈ ${IraqiCurrencyFormat.formatIqd(existing)}، '
                  'والفاتورة تضيف ${IraqiCurrencyFormat.formatIqd(rem)} (يتجاوز ${IraqiCurrencyFormat.formatIqd(cap)}). '
                  'اربط العميل من القائمة، أو خفّض المبلغ، أو راجع إعدادات الديون.',
                ),
                duration: const Duration(seconds: 8),
              ),
            );
          }
          return;
        }
      }
    }

    final instCalc =
        type == InvoiceType.installment && instSettingsForSave != null
        ? (instSettingsForSave.showInstallmentCalculatorOnSale
              ? _installmentCalc(loyaltyCfg)
              : _installmentCalcFromInputs(
                  loyaltyCfg,
                  interestPct: instSettingsForSave.saleDefaultInterestPercent,
                  months: instSettingsForSave.defaultInstallmentCount,
                ))
        : null;

    final invoice = Invoice(
      customerName: customerName,
      date: now,
      type: type,
      items: items,
      discount: discount,
      tax: tax,
      advancePayment: advancePayment,
      total: payTotal,
      isReturned: false,
      originalInvoiceId: null,
      deliveryAddress: deliveryAddress,
      createdByUserName: staffName.isEmpty ? null : staffName,
      discountPercent: dp,
      customerId: customerId,
      loyaltyDiscount: loyaltyDisc,
      loyaltyPointsRedeemed: redeemPts,
      loyaltyPointsEarned: 0,
      installmentInterestPct: instCalc?.interestPct ?? 0,
      installmentPlannedMonths: instCalc?.months ?? 0,
      installmentFinancedAmount: instCalc?.financed ?? 0,
      installmentInterestAmount: instCalc?.interestAmt ?? 0,
      installmentTotalWithInterest: instCalc?.totalWithInterest ?? 0,
      installmentSuggestedMonthly: instCalc?.monthly ?? 0,
    );

    final int invoiceId;
    try {
      invoiceId = await invoiceProvider.addInvoice(invoice);
    } catch (e) {
      if (mounted) {
        _showSaleSnackBar(SnackBar(content: Text('تعذر حفظ الفاتورة: $e')));
      }
      return;
    }
    if (!mounted || !context.mounted) return;

    if (type == InvoiceType.credit) {
      await _emitFinancedSaleNotif(
        invoiceId: invoiceId,
        isInstallment: false,
        customerName: customerName,
        staffName: staffName,
        total: payTotal,
        advance: advancePayment,
        at: now,
        items: items,
      );
    }

    await _clearParkedIfAny();
    if (!mounted || !context.mounted) return;

    final agg = <int, double>{};
    for (final it in items) {
      if (it.productId == null) continue;
      agg[it.productId!] = (agg[it.productId!] ?? 0) + it.quantity;
    }
    final negLines = <Map<String, dynamic>>[];
    final prodProv = context.read<ProductProvider>();
    for (final e in agg.entries) {
      final m = await prodProv.getProductById(e.key);
      if (!mounted || m == null) continue;
      final track = (m['trackInventory'] as int?) != 0;
      if (!track) continue;
      final after = (m['qty'] as num?)?.toDouble() ?? 0;
      if (after >= -1e-9) continue;
      final before = after + e.value;
      final nm = (m['name'] as String?)?.trim() ?? 'منتج';
      negLines.add({
        'name': nm,
        'productId': e.key,
        'qtySold': e.value,
        'before': before,
        'after': after,
      });
    }
    if (negLines.isNotEmpty && mounted) {
      await context.read<NotificationProvider>().recordNegativeStockSale(
        invoiceId: invoiceId,
        staffName: staffName,
        customerName: customerName,
        at: now,
        lines: negLines,
      );
    }
    if (!mounted || !context.mounted) return;

    final forPrint = Invoice(
      id: invoiceId,
      customerName: customerName,
      date: now,
      type: type,
      items: items,
      discount: discount,
      tax: tax,
      advancePayment: advancePayment,
      total: payTotal,
      isReturned: false,
      originalInvoiceId: null,
      deliveryAddress: deliveryAddress,
      createdByUserName: staffName.isEmpty ? null : staffName,
      discountPercent: dp,
      customerId: customerId,
      loyaltyDiscount: loyaltyDisc,
      loyaltyPointsRedeemed: redeemPts,
      loyaltyPointsEarned: 0,
      installmentInterestPct: instCalc?.interestPct ?? 0,
      installmentPlannedMonths: instCalc?.months ?? 0,
      installmentFinancedAmount: instCalc?.financed ?? 0,
      installmentInterestAmount: instCalc?.interestAmt ?? 0,
      installmentTotalWithInterest: instCalc?.totalWithInterest ?? 0,
      installmentSuggestedMonthly: instCalc?.monthly ?? 0,
    );

    /// يُحسب قبل إعادة تهيئة السلة — وإلا يصبح [subtotal] صفراً بعد [_resetSaleForNextInvoice].
    final receiptSubtotalBefore = subtotal;

    /// [ScaffoldMessenger] يُلتقط قبل إعادة تهيئة السلة عند البقاء على شاشة البيع.
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final productProvForBg = context.read<ProductProvider>();
    final notifProvForBg = context.read<NotificationProvider>();

    /// بعد الدفع: إيصال الطباعة فوق شاشة البيع. عند [pushReplacement] لخطة التقسيط يُستخدم جذر التطبيق لأن سياق البيع يُستبدل.
    void scheduleReceiptPrint({bool saleContextDisposedAfter = false}) {
      final inv = forPrint;
      final subtot = receiptSubtotalBefore;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (saleContextDisposedAfter) {
            final rootNav = appRootNavigatorKey.currentState;
            final ctx = rootNav?.context ?? appRootNavigatorKey.currentContext;
            if (ctx == null || !ctx.mounted) return;
            unawaited(_safePrintReceipt(ctx, inv, subtot));
            return;
          }
          final ctx = context;
          if (!ctx.mounted) return;
          unawaited(_safePrintReceipt(ctx, inv, subtot));
        });
      });
    }

    void scheduleBackgroundRefresh() {
      unawaited(productProvForBg.loadProducts());
      unawaited(notifProvForBg.refresh());
    }

    final hasFinanceBalance = advancePayment < payTotal - 1e-6;

    /// خطة أقساط تُنشأ لبيع «تقسيط» فقط — التوصيل دون مقدّم ولا يُفتَح محرر خطة هنا.
    final needsInstallmentPlanRow = type == InvoiceType.installment;
    final openPlanEditor = hasFinanceBalance && type == InvoiceType.installment;

    if (needsInstallmentPlanRow) {
      int planId;
      try {
        final existing = await _parkDb.getInstallmentPlanByInvoiceId(invoiceId);
        planId =
            existing?.id ??
            await _parkDb.insertDefaultInstallmentPlanForInvoice(
              invoiceId: invoiceId,
              customerName: customerName,
              customerId: customerId,
              totalAmount: payTotal,
              paidAmount: advancePayment,
              invoiceDate: now,
              interestPct: instCalc?.interestPct ?? 0,
              interestAmount: instCalc?.interestAmt ?? 0,
              financedAtSale: instCalc?.financed ?? 0,
              totalWithInterest: instCalc?.totalWithInterest ?? 0,
              plannedMonths: instCalc?.months ?? 0,
              suggestedMonthly: instCalc?.monthly ?? 0,
            );
      } catch (e) {
        if (mounted) {
          _showSnackBarViaMessenger(
            messenger,
            SnackBar(
              content: Text('تم حفظ الفاتورة لكن تعذّر إنشاء خطة التقسيط: $e'),
            ),
          );
        }
        _resetSaleForNextInvoice();
        scheduleReceiptPrint();
        scheduleBackgroundRefresh();
        await _emitFinancedSaleNotif(
          invoiceId: invoiceId,
          isInstallment: true,
          customerName: customerName,
          staffName: staffName,
          total: payTotal,
          advance: advancePayment,
          at: now,
          items: items,
          planCreationFailed: true,
          installmentCalc: instCalc,
        );
        return;
      }
      if (openPlanEditor) {
        _showSnackBarViaMessenger(
          messenger,
          const SnackBar(
            content: Text(
              'تم حفظ الفاتورة وإنشاء خطة التقسيط — يمكنك ضبط الجدول أو الرجوع',
            ),
          ),
        );
        await _emitFinancedSaleNotif(
          invoiceId: invoiceId,
          isInstallment: true,
          customerName: customerName,
          staffName: staffName,
          total: payTotal,
          advance: advancePayment,
          at: now,
          items: items,
          planId: planId,
          installmentCalc: instCalc,
        );
        nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AddInstallmentPlanScreen(
              planId: planId,
              invoiceId: invoiceId,
              customerName: customerName,
              totalAmount: payTotal,
              paidAmount: advancePayment,
              invoiceDate: now,
            ),
          ),
        );
        scheduleReceiptPrint(saleContextDisposedAfter: true);
        scheduleBackgroundRefresh();
        return;
      }

      _resetSaleForNextInvoice();
      _showSnackBarViaMessenger(
        messenger,
        const SnackBar(
          content: Text(
            'تم حفظ فاتورة التقسيط وربطها بخطة (لا أقساط متبقية لأن المبلغ محصّل بالكامل).',
          ),
        ),
      );
      await _emitFinancedSaleNotif(
        invoiceId: invoiceId,
        isInstallment: true,
        customerName: customerName,
        staffName: staffName,
        total: payTotal,
        advance: advancePayment,
        at: now,
        items: items,
        planId: planId,
        installmentCalc: instCalc,
      );
      scheduleReceiptPrint();
      scheduleBackgroundRefresh();
      return;
    }

    _resetSaleForNextInvoice();
    _showSnackBarViaMessenger(
      messenger,
      const SnackBar(
        content: Text('تم تسجيل الفاتورة وتحديث المخزون والصندوق'),
      ),
    );

    scheduleReceiptPrint();
    scheduleBackgroundRefresh();
  }

  Future<void> _consumeDraftLines(List<Map<String, dynamic>> pending) async {
    for (final m in pending) {
      if (!mounted) return;
      await _applyPendingProductDraft(m);
    }
  }

  Future<void> _applyPendingProductDraft(Map<String, dynamic> m) async {
    final bc = m['barcode']?.toString().trim();
    if (bc != null && bc.isNotEmpty) {
      await _handleBarcode(bc);
      return;
    }
    final name = (m['name'] ?? '').toString().trim();
    final baseSell = (m['sell'] as num?)?.toDouble() ?? 0;
    final baseMin = (m['minSell'] as num?)?.toDouble() ?? baseSell;
    final pid = (m['productId'] as num?)?.toInt();
    final ti = _parseTrackInvMap(m);
    final an = _parseAllowNegMap(m);
    if (!mounted) return;
    final display = name.isEmpty ? 'منتج' : name;
    final knownQty = (m['qty'] as num?)?.toDouble();
    final u = await _unitSelectionForCatalogProduct(m);
    if (!mounted) return;
    // سعر بطاقة المنتج للوحدة الأساسية؛ يُضرب في factor الوحدة الافتراضية المعروضة.
    final pricing = _resolveVariantPricing(
      baseSell: baseSell,
      baseMin: baseMin,
      variantSell: null,
      variantMin: null,
      factor: u.unitFactor,
    );
    await _addOrMergeCatalogProductLine(
      productName: display,
      productId: pid,
      sellPrice: pricing.sell,
      minSellPrice: pricing.min,
      trackInventory: ti,
      allowNegativeStock: an,
      knownOnHandQty: knownQty,
      stockBaseKind: u.stockBaseKind,
      unitVariantId: u.unitVariantId,
      unitLabel: u.unitLabel,
      unitFactor: u.unitFactor,
    );
  }

  Future<void> _openSaleBarcodeCapture() async {
    final raw = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'باركود صنف أو فاتورة للمرتجع',
      preferCompactHandsetOverlay: true,
    );
    if (!mounted) return;
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return;
    await _handleBarcode(t);
  }

  Future<void> _handleBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    final invId = tryParseInvoiceIdFromBarcode(barcode);
    if (invId != null) {
      final inv = await _parkDb.getInvoiceById(invId);
      if (!mounted) return;
      if (inv == null) {
        _showSaleSnackBar(
          SnackBar(content: Text('لا توجد فاتورة برقم $invId')),
        );
        return;
      }
      if (inv.isReturned) {
        _showSaleSnackBar(
          const SnackBar(content: Text('هذه الفاتورة مرتجع مسبقاً')),
        );
        return;
      }
      final open =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('فاتورة #${inv.id}'),
              content: Text(
                'فتح شاشة المرتجع (منتجات فقط)؟\n'
                'الإجمالي الأصلي: ${IraqiCurrencyFormat.formatIqd(inv.total)}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('مرتجع'),
                ),
              ],
            ),
          ) ??
          false;
      if (!open || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProcessReturnScreen(originalInvoice: inv),
        ),
      );
      return;
    }
    final resolved = await context
        .read<ProductProvider>()
        .resolveProductByAnyBarcode(barcode);
    if (!mounted) return;
    final product = resolved?['product'] as Map<String, dynamic>?;
    final variant = resolved?['variant'] as Map<String, dynamic>?;
    if (product != null) {
      final name = (product['name']?.toString() ?? '').trim();
      final pid = (product['id'] as num?)?.toInt();
      final ti = _tiFromProductRow(product);
      final an = _anFromProductRow(product);
      final display = name.isEmpty ? 'منتج غير مسمى' : name;

      final baseSell = (product['sellPrice'] as num?)?.toDouble() ?? 0;
      final baseMin = (product['minSellPrice'] as num?)?.toDouble() ?? baseSell;
      final vSell = (variant?['sellPrice'] as num?)?.toDouble();
      final vMin = (variant?['minSellPrice'] as num?)?.toDouble();

      final stockBaseKind = (product['stockBaseKind'] as num?)?.toInt() ?? 0;
      late final int? unitVariantId;
      late final String unitLabel;
      late final double unitFactor;
      if (variant != null) {
        unitVariantId = (variant['id'] as num?)?.toInt();
        unitFactor = (variant['factorToBase'] as num?)?.toDouble() ?? 1.0;
        final un = (variant['unitName'] ?? '').toString().trim();
        final us = (variant['unitSymbol'] ?? '').toString().trim();
        unitLabel = us.isEmpty
            ? (un.isEmpty ? 'وحدة' : un)
            : (un.isEmpty ? us : '$un ($us)');
      } else {
        final u = await _unitSelectionForCatalogProduct(product);
        unitVariantId = u.unitVariantId;
        unitLabel = u.unitLabel;
        unitFactor = u.unitFactor;
      }
      if (!mounted) return;

      // السعر للوحدة المختارة: إذا وُجد variant sellPrice يُستخدم كما هو،
      // وإلا يُضرب سعر بطاقة المنتج (للوحدة الأساسية) في factor.
      final pricing = _resolveVariantPricing(
        baseSell: baseSell,
        baseMin: baseMin,
        variantSell: vSell,
        variantMin: vMin,
        factor: unitFactor,
      );

      await _addOrMergeCatalogProductLine(
        productName: display,
        productId: pid,
        sellPrice: pricing.sell,
        minSellPrice: pricing.min,
        trackInventory: ti,
        allowNegativeStock: an,
        stockBaseKind: stockBaseKind,
        unitVariantId: unitVariantId,
        unitLabel: unitLabel,
        unitFactor: unitFactor,
        newItemSnackText: 'تمت إضافة المنتج: ${name.isEmpty ? barcode : name}',
      );
      return;
    }

    final goToAdd =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('المنتج غير موجود'),
            content: const Text(
              'هذا الباركود غير موجود في المنتجات. هل تريد فتح شاشة إضافة منتج جديد؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إضافة منتج'),
              ),
            ],
          ),
        ) ??
        false;

    if (!goToAdd || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddProductScreen(initialBarcode: barcode, autoFillFromScan: true),
      ),
    );
    if (!mounted) return;
    final afterAdd = await context.read<ProductProvider>().findProductByBarcode(
      barcode,
    );
    if (afterAdd != null && mounted) {
      final name = (afterAdd['name']?.toString() ?? '').trim();
      final baseSell = (afterAdd['sellPrice'] as num?)?.toDouble() ?? 0;
      final baseMin =
          (afterAdd['minSellPrice'] as num?)?.toDouble() ?? baseSell;
      final pid = (afterAdd['id'] as num?)?.toInt();
      final ti = _tiFromProductRow(afterAdd);
      final an = _anFromProductRow(afterAdd);
      final display = name.isEmpty ? 'منتج جديد' : name;
      final u = await _unitSelectionForCatalogProduct(afterAdd);
      if (!mounted) return;
      // السعر للوحدة الافتراضية المختارة = سعر الأساس × factor (لا variantSell هنا).
      final pricing = _resolveVariantPricing(
        baseSell: baseSell,
        baseMin: baseMin,
        variantSell: null,
        variantMin: null,
        factor: u.unitFactor,
      );
      await _addOrMergeCatalogProductLine(
        productName: display,
        productId: pid,
        sellPrice: pricing.sell,
        minSellPrice: pricing.min,
        trackInventory: ti,
        allowNegativeStock: an,
        stockBaseKind: u.stockBaseKind,
        unitVariantId: u.unitVariantId,
        unitLabel: u.unitLabel,
        unitFactor: u.unitFactor,
        newItemSnackText: 'تمت إضافة المنتج: ${name.isEmpty ? barcode : name}',
      );
    }
  }

  void _undoLastCartMutation() {
    final u = _lastCartAddUndo;
    if (u == null || _lines.isEmpty) return;
    setState(() {
      if (u.wasNewLine) {
        _lines.removeWhere((l) => l.lineId == u.lineId);
        _expandedLineIds.remove(u.lineId);
      } else {
        for (final l in _lines) {
          if (l.lineId == u.lineId) {
            l.quantity = u.previousQty;
            break;
          }
        }
      }
      _lastCartAddUndo = null;
    });
  }

  bool _canCompleteSalePayment(LoyaltySettingsData loyalty) {
    if (_lines.isEmpty) return false;
    final pay = saleTotal(loyalty);
    if (type == InvoiceType.cash) {
      if (_advancePayment + 0.5 < pay) return false;
    }
    if (type == InvoiceType.credit || type == InvoiceType.installment) {
      if (_linkedCustomerId == null) return false;
    }
    if (type == InvoiceType.delivery) {
      if (_customerController.text.trim().isEmpty) return false;
      if (_deliveryAddressController.text.trim().isEmpty) return false;
    }
    return true;
  }

  void _focusSaleQuickRailSearch() {
    _saleQuickRailSearchFocus.requestFocus();
  }

  void _handleSaleEscapeKey() {
    if (_saleQuickRailSearchController.text.isNotEmpty) {
      setState(() => _saleQuickRailSearchController.clear());
      return;
    }
    if (_lines.isEmpty) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إفراغ السلة؟'),
          content: const Text('سيتم إزالة جميع الأصناف من الفاتورة الحالية.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _lines.clear();
                  _expandedLineIds.clear();
                  _lastCartAddUndo = null;
                });
              },
              child: const Text('إفراغ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveInvoiceIfEligible() async {
    final loyaltyCfg = Provider.of<LoyaltySettingsProvider>(
      context,
      listen: false,
    ).data;
    if (!_canCompleteSalePayment(loyaltyCfg)) {
      return;
    }
    await _saveInvoice();
  }

  void _cartKbMoveHighlight(int delta) {
    if (_lines.isEmpty) return;
    setState(() {
      final hi = _saleCartKeyboardIndex.clamp(0, _lines.length - 1).toInt();
      final next = hi + delta;
      _saleCartKeyboardIndex = next.clamp(0, _lines.length - 1);
    });
    _saleCartListFocus.requestFocus();
  }

  void _cartKbBumpQty(int delta) {
    if (_lines.isEmpty) return;
    final hi = _saleCartKeyboardIndex.clamp(0, _lines.length - 1).toInt();
    final item = _lines[hi];
    final step = _saleQtyStep(item);
    final next = item.quantity + delta * step;
    final minQ = item.stockBaseKind == 1 ? 1e-6 : 1.0;
    setState(() {
      if (next + 1e-12 >= minQ) {
        item.quantity = next;
      }
    });
  }

  void _cartKbRemoveHighlighted() {
    if (_lines.isEmpty) return;
    final hi = _saleCartKeyboardIndex.clamp(0, _lines.length - 1).toInt();
    setState(() {
      final id = _lines[hi].lineId;
      _expandedLineIds.remove(id);
      _lines.removeAt(hi);
      if (_lines.isEmpty) {
        _saleCartKeyboardIndex = 0;
      } else {
        _saleCartKeyboardIndex = hi.clamp(0, _lines.length - 1);
      }
    });
  }

  void _cartKbEditQtyKey() {
    if (_lines.isEmpty) return;
    final hi = _saleCartKeyboardIndex.clamp(0, _lines.length - 1).toInt();
    _promptEditQuantity(_lines[hi]);
  }

  void _syncCashAdvanceToTotalIfCash(LoyaltySettingsData loyalty) {
    if (type != InvoiceType.cash) return;
    final pay = saleTotal(loyalty);
    final t = pay.round().clamp(0, 2000000000).toString();
    _advanceController.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// حوار تعليق الفاتورة — ألوان وحدود مطابقة لشاشة البيع ([SalePalette]).
class _SaleParkInvoiceDialog extends StatefulWidget {
  const _SaleParkInvoiceDialog({
    required this.palette,
    required this.isDark,
    required this.initialTitle,
  });

  final SalePalette palette;
  final bool isDark;
  final String initialTitle;

  @override
  State<_SaleParkInvoiceDialog> createState() => _SaleParkInvoiceDialogState();
}

class _SaleParkInvoiceDialogState extends State<_SaleParkInvoiceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final isDark = widget.isDark;
    final primary = isDark ? const Color(0xFFE8E4DC) : palette.navy;
    final muted = isDark
        ? const Color(0xFF94A3B8)
        : palette.navy.withValues(alpha: 0.58);
    final fieldFill = isDark
        ? palette.navy.withValues(alpha: 0.28)
        : Colors.white;
    final borderGold = palette.gold.withValues(alpha: 0.45);
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: Material(
          color: isDark ? palette.ivoryDark : palette.ivory,
          elevation: 10,
          shadowColor: palette.navy.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: AppShape.none,
            side: BorderSide(color: borderGold, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.navy,
                  border: Border(
                    bottom: BorderSide(
                      color: palette.gold.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pause_circle_outline_rounded,
                      color: palette.gold,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'تعليق الفاتورة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          fontFamily: AppFontFamilies.tajawal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: ScreenLayout.of(context).pageHorizontalGap,
                          end: ScreenLayout.of(context).pageHorizontalGap,
                          top: 14,
                          bottom: 8,
                        ),
                        child: Text(
                          'يُحفظ محلياً على هذا الجهاز. يمكنك استئناف البيع لاحقاً من «الفواتير ← معلّقة مؤقتاً».',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.38,
                            color: muted,
                            fontFamily: AppFontFamilies.tajawal,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ScreenLayout.of(
                            context,
                          ).pageHorizontalGap,
                        ),
                        child: TextField(
                          controller: _controller,
                          style: TextStyle(
                            color: primary,
                            fontFamily: AppFontFamilies.tajawal,
                          ),
                          decoration: InputDecoration(
                            labelText: 'اسم للتعريف (يظهر في القائمة)',
                            labelStyle: TextStyle(
                              color: muted,
                              fontFamily: AppFontFamilies.tajawal,
                            ),
                            filled: true,
                            fillColor: fieldFill,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: AppShape.none,
                              borderSide: BorderSide(color: borderGold),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: AppShape.none,
                              borderSide: BorderSide(
                                color: palette.gold,
                                width: 1.6,
                              ),
                            ),
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              SaleAccessibleButtonColors.outlinedOnSalePanelText(
                                palette.navy,
                                isDark ? Brightness.dark : Brightness.light,
                              ),
                          side: BorderSide(
                            color: palette.gold.withValues(alpha: 0.75),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.none,
                          ),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.none,
                          ),
                        ),
                        child: const Text(
                          'حفظ التعليق',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleScanOverlayPainter extends CustomPainter {
  _SaleScanOverlayPainter({required this.scanRect});

  final Rect scanRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final borderPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final layerRect = Offset.zero & size;
    canvas.saveLayer(layerRect, Paint());
    canvas.drawRect(layerRect, overlayPaint);
    canvas.drawRect(scanRect, clearPaint);
    canvas.drawRect(scanRect, borderPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SaleScanOverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}

class _InvoiceLineState {
  _InvoiceLineState({
    required this.lineId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.sellPrice,
    required this.minSellPrice,
    this.productId,
    this.trackInventory = true,
    this.allowNegativeStock = false,
    this.stockBaseKind = 0,
    this.unitVariantId,
    String? unitLabel,
    this.unitFactor = 1.0,
  }) : unitLabel = (unitLabel == null || unitLabel.trim().isEmpty)
           ? 'قطعة'
           : unitLabel.trim();

  final int lineId;
  final int? productId;
  final bool trackInventory;
  final bool allowNegativeStock;
  final String productName;
  double quantity;
  double unitPrice;
  double sellPrice;
  double minSellPrice;

  /// 0 = مخزون بعدد (قطعة أساساً) | 1 = مخزون بالوزن (**كيلوغرام** أساساً).
  final int stockBaseKind;

  int? unitVariantId;
  String unitLabel;
  double unitFactor;
}

class _SaleInlineScannerCard extends StatelessWidget {
  const _SaleInlineScannerCard({
    required this.palette,
    required this.controller,
    required this.height,
    required this.onClose,
    required this.onDetect,
    required this.onHeightChange,
  });

  final SalePalette palette;
  final MobileScannerController controller;
  final double height;
  final VoidCallback onClose;
  final void Function(BarcodeCapture capture) onDetect;
  final ValueChanged<double> onHeightChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline = cs.outlineVariant.withValues(alpha: 0.8);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
                Expanded(
                  child: Text(
                    'ماسح الباركود',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'فلاش',
                  onPressed: () => controller.toggleTorch(),
                  icon: Icon(Icons.flash_on_rounded, color: palette.gold),
                ),
                IconButton(
                  tooltip: 'تبديل الكاميرا',
                  onPressed: () => controller.switchCamera(),
                  icon: Icon(Icons.cameraswitch_rounded, color: palette.gold),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          GestureDetector(
            onVerticalDragUpdate: (d) => onHeightChange(height - d.delta.dy),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: height,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final pad = 10.0;
                    final rect = Rect.fromLTWH(
                      pad,
                      pad,
                      (c.maxWidth - 2 * pad).clamp(1.0, c.maxWidth),
                      (c.maxHeight - 2 * pad).clamp(1.0, c.maxHeight),
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: controller,
                          scanWindow: rect,
                          onDetect: onDetect,
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _SaleScanOverlayPainter(scanRect: rect),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'امسح — سيتم الإضافة تلقائيًا',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
