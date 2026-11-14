import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/customer_record.dart';
import '../../../models/invoice.dart';
import '../../../navigation/content_navigation.dart';
import '../../../providers/auth_provider.dart';
import '../../../screens/customers/customer_form_screen.dart';
import '../../../services/customer_search_index.dart';
import '../../../services/product_quick_pick_cache.dart';
import '../../../services/product_repository.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/barcode_input_launcher.dart';
import '../../../widgets/raw_keyboard_inset.dart';
import '../models/oil_change_product_line.dart';
import '../services/oil_change_direct_sale_service.dart';
import '../services/oil_change_product_scan.dart';
import '../widgets/oil_change_customer_name_field.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_log_stitch.dart';
import '../widgets/product_picker_dialog.dart';

/// بيع مباشر لمنتجات المخزون — بدون بطاقة غيار.
class OilChangeDirectSaleScreen extends StatefulWidget {
  const OilChangeDirectSaleScreen({super.key});

  @override
  State<OilChangeDirectSaleScreen> createState() =>
      _OilChangeDirectSaleScreenState();
}

class _OilChangeDirectSaleScreenState extends State<OilChangeDirectSaleScreen> {
  static const int _initialLimit = 240;
  static const int _searchLimit = 120;

  final ProductRepository _repo = ProductRepository();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _customerName = TextEditingController();
  final TextEditingController _advancePaid = TextEditingController(text: '0');
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _customerFocus = FocusNode();
  final FocusNode _advanceFocus = FocusNode();

  Timer? _debounce;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _banner;
  List<Map<String, dynamic>> _rows = const [];
  final List<OilChangeProductLine> _cart = [];
  final Map<int, List<_SaleUnit>> _saleUnits = {};
  bool _isCredit = false;
  int? _customerId;
  bool _customerLinked = false;
  int? _completedInvoiceId;

  @override
  void initState() {
    super.initState();
    final cached = ProductQuickPickCache.instance.snapshot;
    if (cached != null) {
      _rows = cached;
      _loading = false;
    }
    _search.addListener(_onSearchChanged);
    _advancePaid.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final layout = context.screenLayout;
      final twoColumn = !layout.isPhoneVariant && layout.size.width >= 700;
      if (twoColumn) _searchFocus.requestFocus();
    });
    unawaited(_loadProducts());
    unawaited(CustomerSearchIndex.instance.ensureFresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _customerName.dispose();
    _advancePaid.dispose();
    _searchFocus.dispose();
    _customerFocus.dispose();
    _advanceFocus.dispose();
    super.dispose();
  }

  int _parseAdvanceFils() {
    final dinars = IraqiCurrencyFormat.parseIqdInt(_advancePaid.text);
    return IqdMoney.toFils(dinars.toDouble());
  }

  void _onCreditModeChanged(bool credit) {
    setState(() {
      _isCredit = credit;
      if (!credit) {
        _advancePaid.text = '0';
      }
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_loadProducts());
    });
    setState(() {});
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    final q = _search.text.trim();
    if (_rows.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = q.isEmpty
          ? await ProductQuickPickCache.instance.refresh(limit: _initialLimit)
          : await _repo.searchSaleGridProducts(q, limit: _searchLimit);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _rows.isEmpty ? 'تعذّر تحميل المنتجات' : _error;
        _loading = false;
      });
    }
  }

  int get _cartTotalFils => _cart.fold<int>(0, (s, l) => s + l.totalFils);

  int _cartQtyFor(int productId) {
    var n = 0;
    for (final l in _cart) {
      if (l.productId == productId) n += l.quantity;
    }
    return n;
  }

  void _flash(String message) {
    setState(() => _banner = message);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_banner == message) setState(() => _banner = null);
    });
  }

  void _addProductRow(Map<String, dynamic> product) {
    final msg = OilChangeProductScan.addFromProductMap(
      lines: _cart,
      product: product,
    );
    setState(() {});
    _warmSaleUnits();
    if (msg != null) _flash(msg);
  }

  void _warmSaleUnits() {
    for (final line in _cart) {
      if (_saleUnits.containsKey(line.productId)) continue;
      unawaited(_loadSaleUnits(line.productId, line.literPriceFils));
    }
  }

  Future<void> _loadSaleUnits(int productId, int literPriceFils) async {
    if (productId <= 0 || _saleUnits.containsKey(productId)) return;
    _saleUnits[productId] = const [];
    try {
      final rows = await _repo.listActiveUnitVariantsForProduct(productId);
      final units = <_SaleUnit>[
        _SaleUnit(label: 'لتر', factor: 1, priceFils: literPriceFils),
      ];
      for (final row in rows) {
        final name = (row['unitName'] ?? '').toString().trim();
        final factor = (row['factorToBase'] as num?)?.toDouble() ?? 0;
        if (name.isEmpty || name == 'لتر' || factor <= 0) continue;
        final sell = (row['sellPrice'] as num?)?.toDouble();
        units.add(
          _SaleUnit(
            variantId: (row['id'] as num?)?.toInt(),
            label: name,
            factor: factor,
            priceFils: sell != null && sell > 0 ? IqdMoney.toFils(sell) : null,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _saleUnits[productId] = units.length > 1 ? units : const [];
      });
    } catch (_) {
      _saleUnits.remove(productId);
    }
  }

  void _selectSaleUnit(OilChangeProductLine line, _SaleUnit unit) {
    final price = unit.priceFils != null && unit.priceFils! > 0
        ? unit.priceFils!
        : (line.literPriceFils * unit.factor).round();
    setState(() {
      line.unitVariantId = unit.variantId;
      line.unitLabel = unit.variantId == null ? '' : unit.label;
      line.unitFactor = unit.factor;
      line.priceFils = price;
    });
  }

  Future<void> _scanBarcode() async {
    final code = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح باركود المنتج',
      preferCompactHandsetOverlay: true,
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleBarcode(code.trim());
  }

  Future<void> _handleBarcode(String code) async {
    final msg = await OilChangeProductScan.handleBarcode(
      context,
      lines: _cart,
      barcode: code,
      suppressAddProductDialog: true,
    );
    if (!mounted) return;
    setState(() {});
    _warmSaleUnits();
    if (msg != null) _flash(msg);
  }

  Future<void> _openWidePicker() async {
    final picked = await ProductPickerDialog.show(context, allowHandset: true);
    if (!mounted || picked == null) return;
    _addProductRow(picked);
  }

  void _setQty(OilChangeProductLine line, int qty) {
    if (qty <= 0) {
      _cart.remove(line);
    } else {
      line.quantity = qty;
    }
    setState(() {});
  }

  void _onCustomerSelected(CustomerRecord c) {
    setState(() {
      _customerId = c.id;
      _customerLinked = true;
      _customerName.text = c.name;
    });
  }

  Future<void> _openNewCustomer() async {
    if (_saving) return;
    final rec = await Navigator.of(context).push<CustomerRecord>(
      FastContentPageRoute(builder: (_) => const CustomerFormScreen()),
    );
    if (!mounted || rec == null) return;
    CustomerSearchIndex.instance.invalidate();
    _onCustomerSelected(rec);
    _flash('تم ربط العميل: ${rec.name.trim()}');
  }

  Future<String?> _completeSale({
    bool closeRoute = true,
    bool cashWithoutCustomer = false,
  }) async {
    if (_saving) return 'جارٍ إتمام البيع';
    if (_cart.isEmpty) {
      const msg = 'أضف منتجاً إلى السلة أولاً';
      if (closeRoute) _flash(msg);
      return msg;
    }
    setState(() => _saving = true);
    try {
      final staff = context.read<AuthProvider>().username.trim();
      final result = await OilChangeDirectSaleService.instance.completeSale(
        lines: List<OilChangeProductLine>.from(_cart),
        isCredit: _isCredit,
        advanceFils: _isCredit ? _parseAdvanceFils() : 0,
        customerName: cashWithoutCustomer ? '' : _customerName.text,
        customerId: cashWithoutCustomer ? null : _customerId,
        createdByUserName: staff.isEmpty ? null : staff,
      );
      if (!mounted) return null;
      final totalLabel = IraqiCurrencyFormat.formatIqd(
        IqdMoney.fromFils(result.totalFils),
      );
      final String snack;
      if (result.invoiceType == InvoiceType.cash) {
        snack = 'تم البيع نقداً #${result.invoiceId} — $totalLabel';
      } else if (result.advanceFils > 0) {
        final paid = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(result.advanceFils),
        );
        final debt = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(result.remainderFils),
        );
        snack =
            'فاتورة آجلة #${result.invoiceId} — دُفع $paid والمتبقي دين $debt';
      } else {
        snack = 'تم إنشاء فاتورة آجلة #${result.invoiceId} — $totalLabel';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(snack)));
      unawaited(ProductQuickPickCache.instance.refresh(limit: _initialLimit));
      if (closeRoute) {
        Navigator.of(context).pop(result.invoiceId);
      } else {
        _completedInvoiceId = result.invoiceId;
      }
      return null;
    } on OilChangeDirectSaleException catch (e) {
      if (!mounted) return e.message;
      if (closeRoute) _flash(e.message);
      return e.message;
    } catch (_) {
      const msg = 'تعذّر إتمام البيع — حاول مجدداً';
      if (!mounted) return msg;
      if (closeRoute) _flash(msg);
      return msg;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPhoneCheckout() async {
    if (_saving || _cart.isEmpty) return;
    unawaited(CustomerSearchIndex.instance.ensureFresh());
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OilChangeLogStitchMetrics.surfaceWhite,
      builder: (ctx) {
        return _PhoneCheckoutSheet(
          totalFils: _cartTotalFils,
          customerName: _customerName,
          customerFocus: _customerFocus,
          customerLinked: _customerLinked,
          onCustomerSelected: _onCustomerSelected,
          onCustomerCleared: () => setState(() {
            _customerId = null;
            _customerLinked = false;
          }),
          onAddCustomer: _openNewCustomer,
          advancePaid: _advancePaid,
          advanceFocus: _advanceFocus,
          onPay: (credit) {
            _onCreditModeChanged(credit);
            return _completeSale(
              closeRoute: false,
              cashWithoutCustomer: !credit,
            );
          },
        );
      },
    );
    if (paid == true && mounted && _completedInvoiceId != null) {
      Navigator.of(context).pop(_completedInvoiceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.screenLayout;
    final twoColumn = !layout.isPhoneVariant && layout.size.width >= 700;
    final maxW = layout.isDesktopLG
        ? 1200.0
        : (layout.isDesktopSM ? 1040.0 : 960.0);

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
        backgroundColor: OilChangeLogStitchMetrics.background,
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'بيع مباشر',
          actions: [
            IconButton(
              tooltip: 'مسح باركود',
              onPressed: _saving ? null : () => unawaited(_scanBarcode()),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
            IconButton(
              tooltip: 'اختيار من المخزون',
              onPressed: _saving ? null : () => unawaited(_openWidePicker()),
              icon: const Icon(Icons.grid_view_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: layout.pageHorizontalGap,
                  vertical: OilChangeLogStitchMetrics.gapSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_banner != null) ...[
                      _BannerChip(text: _banner!),
                      const SizedBox(height: OilChangeLogStitchMetrics.gapSm),
                    ],
                    Expanded(
                      child: twoColumn
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _CatalogPanel(
                                    search: _search,
                                    searchFocus: _searchFocus,
                                    loading: _loading,
                                    error: _error,
                                    rows: _rows,
                                    cartQtyFor: _cartQtyFor,
                                    onAdd: _addProductRow,
                                    onRetry: () => unawaited(_loadProducts()),
                                    onSubmittedBarcode: (v) {
                                      final t = v.trim();
                                      if (t.isNotEmpty) {
                                        unawaited(_handleBarcode(t));
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(
                                  width: OilChangeLogStitchMetrics.gapMd,
                                ),
                                Expanded(
                                  flex: 4,
                                  child: _CartPanel(
                                    cart: _cart,
                                    totalFils: _cartTotalFils,
                                    isCredit: _isCredit,
                                    onCreditChanged: _onCreditModeChanged,
                                    customerName: _customerName,
                                    customerFocus: _customerFocus,
                                    customerLinked: _customerLinked,
                                    onCustomerSelected: _onCustomerSelected,
                                    onCustomerCleared: () => setState(() {
                                      _customerId = null;
                                      _customerLinked = false;
                                    }),
                                    onAddCustomer: () =>
                                        unawaited(_openNewCustomer()),
                                    advancePaid: _advancePaid,
                                    advanceFocus: _advanceFocus,
                                    advanceFils: _parseAdvanceFils(),
                                    onQty: _setQty,
                                    saleUnits: _saleUnits,
                                    onSelectUnit: _selectSaleUnit,
                                    saving: _saving,
                                    onComplete: () =>
                                        unawaited(_completeSale()),
                                    stickyFooter: false,
                                  ),
                                ),
                              ],
                            )
                          : _CartPanel(
                              cart: _cart,
                              totalFils: _cartTotalFils,
                              isCredit: _isCredit,
                              onCreditChanged: _onCreditModeChanged,
                              customerName: _customerName,
                              customerFocus: _customerFocus,
                              customerLinked: _customerLinked,
                              onCustomerSelected: _onCustomerSelected,
                              onCustomerCleared: () => setState(() {
                                _customerId = null;
                                _customerLinked = false;
                              }),
                              onAddCustomer: () =>
                                  unawaited(_openNewCustomer()),
                              advancePaid: _advancePaid,
                              advanceFocus: _advanceFocus,
                              advanceFils: _parseAdvanceFils(),
                              onQty: _setQty,
                              saleUnits: _saleUnits,
                              onSelectUnit: _selectSaleUnit,
                              saving: _saving,
                              onComplete: () => unawaited(_openPhoneCheckout()),
                              stickyFooter: false,
                              deferCheckout: true,
                              emptyLabel:
                                  'السلة فارغة\nاضغط أيقونة المربعات لإضافة منتج',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OilChangeLogStitchMetrics.secondaryContainer.withValues(
        alpha: 0.55,
      ),
      borderRadius: BorderRadius.circular(OilChangeLogStitchMetrics.cardRadius),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            color: OilChangeLogStitchMetrics.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _CatalogPanel extends StatelessWidget {
  const _CatalogPanel({
    required this.search,
    required this.searchFocus,
    required this.loading,
    required this.error,
    required this.rows,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRetry,
    required this.onSubmittedBarcode,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> rows;
  final int Function(int productId) cartQtyFor;
  final ValueChanged<Map<String, dynamic>> onAdd;
  final VoidCallback onRetry;
  final ValueChanged<String> onSubmittedBarcode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: OilChangeLogStitchMetrics.panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(OilChangeLogStitchMetrics.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: search,
              focusNode: searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmittedBarcode,
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'بحث المنتجات',
                hintText: 'الاسم أو الباركود…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        onPressed: () {
                          search.clear();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: OilChangeLogStitchMetrics.gapMd),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error!,
              style: TextStyle(
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'لا توجد منتجات مطابقة',
          style: TextStyle(color: OilChangeFormTheme.secondaryText(context)),
        ),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        final id = (row['id'] as num?)?.toInt() ?? 0;
        final name = (row['name'] ?? '').toString().trim();
        final sell =
            (row['sell'] as num?)?.toDouble() ??
            (row['sellPrice'] as num?)?.toDouble() ??
            0;
        final qty = (row['qty'] as num?)?.toDouble() ?? 0;
        final inCart = id > 0 ? cartQtyFor(id) : 0;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            name.isEmpty ? 'منتج' : name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: OilChangeFormTheme.emphasisText(context),
            ),
          ),
          subtitle: Text(
            'السعر: ${IraqiCurrencyFormat.formatIqd(sell)}'
            ' · المتاح: ${qty % 1 == 0 ? qty.toInt() : qty}'
            '${inCart > 0 ? ' · في السلة: $inCart' : ''}',
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
              fontSize: 12.5,
            ),
          ),
          trailing: IconButton(
            tooltip: 'إضافة',
            onPressed: () => onAdd(row),
            icon: const Icon(
              Icons.add_circle_rounded,
              color: OilChangeFormTheme.gold,
            ),
          ),
          onTap: () => onAdd(row),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.totalFils,
    required this.isCredit,
    required this.onCreditChanged,
    required this.customerName,
    required this.customerFocus,
    required this.customerLinked,
    required this.onCustomerSelected,
    required this.onCustomerCleared,
    required this.onAddCustomer,
    required this.advancePaid,
    required this.advanceFocus,
    required this.advanceFils,
    required this.onQty,
    required this.saleUnits,
    required this.onSelectUnit,
    required this.saving,
    required this.onComplete,
    required this.stickyFooter,
    this.deferCheckout = false,
    this.emptyLabel = 'السلة فارغة',
  });

  final List<OilChangeProductLine> cart;
  final int totalFils;
  final bool isCredit;
  final ValueChanged<bool> onCreditChanged;
  final TextEditingController customerName;
  final FocusNode customerFocus;
  final bool customerLinked;
  final ValueChanged<CustomerRecord> onCustomerSelected;
  final VoidCallback onCustomerCleared;
  final VoidCallback onAddCustomer;
  final TextEditingController advancePaid;
  final FocusNode advanceFocus;
  final int advanceFils;
  final void Function(OilChangeProductLine line, int qty) onQty;
  final Map<int, List<_SaleUnit>> saleUnits;
  final void Function(OilChangeProductLine line, _SaleUnit unit) onSelectUnit;
  final bool saving;
  final VoidCallback onComplete;
  final bool stickyFooter;
  final bool deferCheckout;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final totalLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(totalFils),
    );
    final paidFils = advanceFils.clamp(0, totalFils);
    final remainderFils = (totalFils - paidFils).clamp(0, totalFils);
    final paidLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(paidFils),
    );
    final remainderLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(remainderFils),
    );
    final completeLabel = deferCheckout
        ? 'إتمام الدفع'
        : (!isCredit
              ? 'إتمام البيع'
              : (remainderFils <=
                        OilChangeDirectSaleService.cashRemainderThresholdFils
                    ? 'إتمام البيع نقداً'
                    : (paidFils > 0
                          ? 'إتمام بيع (مدفوع + دين)'
                          : 'إتمام بيع آجل')));

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'السلة',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: OilChangeFormTheme.emphasisText(context),
          ),
        ),
        const SizedBox(height: OilChangeLogStitchMetrics.gapSm),
        if (!deferCheckout) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('نقدي'),
                icon: Icon(Icons.payments_outlined, size: 18),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('آجل'),
                icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
              ),
            ],
            selected: {isCredit},
            onSelectionChanged: saving ? null : (s) => onCreditChanged(s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return OilChangeFormTheme.navy;
                }
                return OilChangeFormTheme.secondaryText(context);
              }),
            ),
          ),
          const SizedBox(height: OilChangeLogStitchMetrics.gapMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OilChangeCustomerNameField(
                  controller: customerName,
                  focusNode: customerFocus,
                  customerLinked: customerLinked,
                  enabled: !saving,
                  hintText: isCredit
                      ? 'عميل مسجّل (مطلوب للآجل)'
                      : 'اسم العميل (اختياري للنقدي)',
                  onSelected: onCustomerSelected,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'عميل جديد',
                onPressed: saving ? null : onAddCustomer,
                style: IconButton.styleFrom(
                  foregroundColor: OilChangeFormTheme.navy,
                  backgroundColor: OilChangeLogStitchMetrics.secondaryContainer
                      .withValues(alpha: 0.55),
                ),
                icon: const Icon(Icons.person_add_alt_rounded),
              ),
            ],
          ),
          if (customerLinked)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: saving
                    ? null
                    : () {
                        customerName.clear();
                        onCustomerCleared();
                      },
                child: const Text('إلغاء ربط العميل'),
              ),
            ),
          if (isCredit && !customerLinked)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, bottom: 4),
              child: Text(
                'للبيع الآجل يلزم عميل مسجّل — استخدم + لإضافة عميل جديد',
                style: TextStyle(
                  fontSize: 12,
                  color: OilChangeFormTheme.secondaryText(context),
                ),
              ),
            ),
          if (isCredit) ...[
            const SizedBox(height: OilChangeLogStitchMetrics.gapSm),
            TextField(
              controller: advancePaid,
              focusNode: advanceFocus,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [
                _CappedIqdFormatter(
                  IqdMoney.fromFils(totalFils).round(),
                ),
              ],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              textInputAction: TextInputAction.done,
              decoration: OilChangeFormTheme.field(
                context: context,
                labelText: 'المدفوع الآن',
                hintText: '0 = دين كامل',
                helperText: 'المبلغ الذي يدفعه الزبون الآن (بالدينار)',
                prefixIcon: const Icon(Icons.payments_rounded, size: 20),
                suffixIcon: TextButton(
                  onPressed: saving || totalFils <= 0
                      ? null
                      : () {
                          advancePaid.text = IraqiCurrencyFormat.formatInt(
                            IqdMoney.fromFils(totalFils).round(),
                          );
                        },
                  child: const Text('الكل'),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: OilChangeLogStitchMetrics.gapSm),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text(
                    emptyLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final line = cart[i];
                    final units = saleUnits[line.productId] ?? const <_SaleUnit>[];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.productName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: OilChangeFormTheme.emphasisText(
                                          context,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      IraqiCurrencyFormat.formatIqd(
                                        IqdMoney.fromFils(line.priceFils),
                                      ),
                                      style: TextStyle(
                                        color: OilChangeFormTheme.secondaryText(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'إنقاص',
                                onPressed: saving
                                    ? null
                                    : () => onQty(line, line.quantity - 1),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(
                                '${line.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              IconButton(
                                tooltip: 'زيادة',
                                onPressed: saving
                                    ? null
                                    : () => onQty(line, line.quantity + 1),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: OilChangeFormTheme.gold,
                                ),
                              ),
                            ],
                          ),
                          if (units.length > 1)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final unit in units)
                                    ChoiceChip(
                                      label: Text(unit.label),
                                      selected: line.unitVariantId == unit.variantId,
                                      onSelected: saving
                                          ? null
                                          : (_) => onSelectUnit(line, unit),
                                      selectedColor: OilChangeFormTheme.gold,
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: OilChangeFormTheme.gold
                                            .withValues(alpha: 0.55),
                                      ),
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: line.unitVariantId == unit.variantId
                                            ? OilChangeFormTheme.navy
                                            : OilChangeFormTheme.emphasisText(
                                                context,
                                              ),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: OilChangeLogStitchMetrics.gapSm),
        _MoneyRow(label: 'الإجمالي', value: totalLabel, emphasis: true),
        if (!deferCheckout && isCredit) ...[
          const SizedBox(height: 4),
          _MoneyRow(label: 'المدفوع الآن', value: paidLabel),
          const SizedBox(height: 4),
          _MoneyRow(
            label: 'المتبقي دين',
            value: remainderLabel,
            valueColor: remainderFils > 0
                ? OilChangeLogStitchMetrics.error
                : OilChangeLogStitchMetrics.success,
          ),
        ],
        const SizedBox(height: OilChangeLogStitchMetrics.gapMd),
        SizedBox(
          height: OilChangeLogStitchMetrics.actionHeight,
          child: FilledButton(
            onPressed: saving || cart.isEmpty ? null : onComplete,
            style: FilledButton.styleFrom(
              backgroundColor: OilChangeLogStitchMetrics.secondaryContainer,
              foregroundColor: OilChangeLogStitchMetrics.onSecondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OilChangeLogStitchMetrics.pillRadius,
                ),
              ),
            ),
            child: saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(
                    completeLabel,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ],
    );

    if (!stickyFooter) {
      return DecoratedBox(
        decoration: OilChangeLogStitchMetrics.panelDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(OilChangeLogStitchMetrics.gapMd),
          child: body,
        ),
      );
    }

    final screenH = MediaQuery.sizeOf(context).height;
    final chrome = MediaQuery.paddingOf(context).vertical + 168;
    final available = (screenH - chrome).clamp(160.0, screenH);
    final wanted = screenH * (isCredit ? 0.58 : 0.48);
    final maxH = wanted < available ? wanted : available;

    return Material(
      color: OilChangeLogStitchMetrics.surfaceWhite,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.all(OilChangeLogStitchMetrics.gapMd),
          child: body,
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
            color: OilChangeFormTheme.secondaryText(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: emphasis ? 18 : 15,
            color: valueColor ?? OilChangeFormTheme.emphasisText(context),
          ),
        ),
      ],
    );
  }
}

/// وحدة بيع ظاهرة تحت سطر السلة (لتر أو عبوة الزيت/الهيدروليك).
class _SaleUnit {
  const _SaleUnit({
    this.variantId,
    required this.label,
    required this.factor,
    this.priceFils,
  });

  final int? variantId;
  final String label;
  final double factor;
  final int? priceFils;
}

/// دفع الهاتف: يظهر بعد «إتمام الدفع». النقدي بلا اسم عميل.
class _PhoneCheckoutSheet extends StatefulWidget {
  const _PhoneCheckoutSheet({
    required this.totalFils,
    required this.customerName,
    required this.customerFocus,
    required this.customerLinked,
    required this.onCustomerSelected,
    required this.onCustomerCleared,
    required this.onAddCustomer,
    required this.advancePaid,
    required this.advanceFocus,
    required this.onPay,
  });

  final int totalFils;
  final TextEditingController customerName;
  final FocusNode customerFocus;
  final bool customerLinked;
  final ValueChanged<CustomerRecord> onCustomerSelected;
  final VoidCallback onCustomerCleared;
  final Future<void> Function() onAddCustomer;
  final TextEditingController advancePaid;
  final FocusNode advanceFocus;
  final Future<String?> Function(bool credit) onPay;

  @override
  State<_PhoneCheckoutSheet> createState() => _PhoneCheckoutSheetState();
}

class _PhoneCheckoutSheetState extends State<_PhoneCheckoutSheet> {
  bool _credit = false;
  bool _busy = false;
  bool _linked = false;
  String? _error;
  double _trackedKeyboard = 0;

  @override
  void initState() {
    super.initState();
    _linked = widget.customerLinked;
    widget.advancePaid.addListener(_onAdvanceEdited);
  }

  @override
  void dispose() {
    widget.advancePaid.removeListener(_onAdvanceEdited);
    super.dispose();
  }

  void _onAdvanceEdited() {
    if (mounted) setState(() {});
  }

  void _keepFocusedFieldAboveKeyboard(double keyboardBottom) {
    if ((keyboardBottom - _trackedKeyboard).abs() < 1) return;
    _trackedKeyboard = keyboardBottom;
    if (keyboardBottom <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackedKeyboard <= 0) return;
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null || !focusContext.mounted) return;
      Scrollable.ensureVisible(
        focusContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: Duration.zero,
      );
    });
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onPay(_credit);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(widget.totalFils),
    );
    final capDinars = IqdMoney.fromFils(widget.totalFils).round();
    final enteredDinars = IraqiCurrencyFormat.parseIqdInt(
      widget.advancePaid.text,
    );
    if (enteredDinars > capDinars) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final again = IraqiCurrencyFormat.parseIqdInt(widget.advancePaid.text);
        if (again <= capDinars) return;
        widget.advancePaid.text = IraqiCurrencyFormat.formatInt(capDinars);
      });
    }
    // viewInsets مُصفَّرة في جذر التطبيق. الارتفاع الحقيقي يأتي من قناة IME
    // ويتغيّر مع حركة اللوحة، فترتفع الورقة معها دون قفزة ثانية.
    return RawKeyboardInsetBuilder(
      builder: (context, keyboardBottom) {
        _keepFocusedFieldAboveKeyboard(keyboardBottom);
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardBottom),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: OilChangeLogStitchMetrics.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'إتمام الدفع',
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: OilChangeFormTheme.emphasisText(context),
                  ),
                ),
                const SizedBox(height: 8),
                _MoneyRow(label: 'المبلغ', value: totalLabel, emphasis: true),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('نقدي'),
                      icon: Icon(Icons.payments_outlined, size: 18),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('آجل'),
                      icon: Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                    ),
                  ],
                  selected: {_credit},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _credit = s.first),
                ),
                if (_credit) ...[
                  const SizedBox(height: 8),
                  Text(
                    'يدفع لاحقاً، ويلزم اسم عميل محفوظ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: OilChangeCustomerNameField(
                          controller: widget.customerName,
                          focusNode: widget.customerFocus,
                          customerLinked: _linked,
                          enabled: !_busy,
                          hintText: 'اسم العميل',
                          onSelected: (customer) {
                            setState(() => _linked = true);
                            widget.onCustomerSelected(customer);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'عميل جديد',
                        onPressed: _busy
                            ? null
                            : () async {
                                await widget.onAddCustomer();
                                if (!mounted) return;
                                if (widget.customerName.text.trim().isNotEmpty) {
                                  setState(() => _linked = true);
                                }
                              },
                        style: IconButton.styleFrom(
                          foregroundColor: OilChangeFormTheme.navy,
                          backgroundColor:
                              OilChangeLogStitchMetrics.secondaryContainer
                                  .withValues(alpha: 0.85),
                          fixedSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  if (_linked)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                widget.customerName.clear();
                                setState(() => _linked = false);
                                widget.onCustomerCleared();
                              },
                        child: const Text('إلغاء ربط العميل'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.advancePaid,
                    focusNode: widget.advanceFocus,
                    enabled: !_busy,
                    scrollPadding: const EdgeInsets.only(bottom: 96),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: false,
                      signed: false,
                    ),
                    inputFormatters: [
                      _CappedIqdFormatter(
                        IqdMoney.fromFils(widget.totalFils).round(),
                      ),
                    ],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    decoration: OilChangeFormTheme.field(
                      context: context,
                      labelText: 'المبلغ المستلم',
                      hintText: '0',
                      helperText: 'بالدينار — الفرق يُسجَّل ديناً على العميل',
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.payments_rounded, size: 20),
                      suffixIcon: TextButton(
                        onPressed: _busy || widget.totalFils <= 0
                            ? null
                            : () {
                                widget.advancePaid.text =
                                    IraqiCurrencyFormat.formatInt(
                                  IqdMoney.fromFils(widget.totalFils).round(),
                                );
                              },
                        child: const Text('الكل'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PhoneDebtNote(
                    totalFils: widget.totalFils,
                    paidFils: IqdMoney.toFils(
                      IraqiCurrencyFormat.parseIqdInt(widget.advancePaid.text)
                          .toDouble(),
                    ),
                    customerName: widget.customerName.text.trim(),
                    linked: _linked,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: OilChangeLogStitchMetrics.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: OilChangeLogStitchMetrics.actionHeight,
                  child: FilledButton(
                    onPressed: _busy ? null : () => unawaited(_pay()),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          OilChangeLogStitchMetrics.secondaryContainer,
                      foregroundColor:
                          OilChangeLogStitchMetrics.onSecondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OilChangeLogStitchMetrics.cardRadius,
                        ),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text(
                            'دفع',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// المبلغ المستلم لا يتجاوز إجمالي الفاتورة أثناء الكتابة.
class _CappedIqdFormatter extends TextInputFormatter {
  _CappedIqdFormatter(this.maxDinars);

  final int maxDinars;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final grouped = IraqiCurrencyFormat.moneyInputFormatter().formatEditUpdate(
      oldValue,
      newValue,
    );
    final cap = maxDinars < 0 ? 0 : maxDinars;
    final entered = IraqiCurrencyFormat.parseIqdInt(grouped.text);
    if (entered <= cap) return grouped;
    final capped = IraqiCurrencyFormat.formatInt(cap);
    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}

/// المتبقي بعد المبلغ المستلم — نفس عتبة بطاقة الغيار، ويُحفظ فاتورة آجل على العميل.
class _PhoneDebtNote extends StatelessWidget {
  const _PhoneDebtNote({
    required this.totalFils,
    required this.paidFils,
    required this.customerName,
    required this.linked,
  });

  final int totalFils;
  final int paidFils;
  final String customerName;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final cappedPaid = paidFils.clamp(0, totalFils);
    final remainder = totalFils - cappedPaid;
    final hasDebt =
        remainder > OilChangeDirectSaleService.cashRemainderThresholdFils;
    final paidLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(cappedPaid),
    );
    final debtLabel = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(remainder),
    );
    final cs = Theme.of(context).colorScheme;
    if (!hasDebt) {
      return Text(
        'المستلم $paidLabel — مسدّد بالكامل',
        textAlign: TextAlign.start,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: OilChangeFormTheme.secondaryText(context),
        ),
      );
    }
    final who = linked && customerName.isNotEmpty ? customerName : '';
    final line = who.isEmpty
        ? 'متبقي دين $debtLabel — اختر عميلاً مسجّلاً ليُحفظ على حسابه'
        : 'يُسجَّل ديناً على $who: $debtLabel';
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        line,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: cs.onErrorContainer,
        ),
      ),
    );
  }
}
