import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/invoice.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/database_helper.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/invoice_barcode.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';

/// واجهة مرتجع مخصّصة: قائمة منتجات فقط + ملخص مالي يظهر عند اختيار الكميات.
/// الربط الصريح: [Invoice.originalInvoiceId] = رقم الفاتورة الأصلية المفتوحة.
class ProcessReturnScreen extends StatefulWidget {
  const ProcessReturnScreen({
    super.key,
    this.originalInvoice,
    this.invoiceId,
  }) : assert(
          originalInvoice != null || invoiceId != null,
          'مرّر originalInvoice أو invoiceId',
        );

  /// إن وُجدت تُستخدم مباشرة (بدون طلب شبكة).
  final Invoice? originalInvoice;
  final int? invoiceId;

  @override
  State<ProcessReturnScreen> createState() => _ProcessReturnScreenState();
}

class _LineReturn {
  _LineReturn({
    required this.original,
    this.stockBaseKind = 0,
  }) : returnEnteredQty = 0;

  final InvoiceItem original;
  /// يطابق [products.stockBaseKind] عند توفر [productId]؛ 1 = خطوات كمية بالكيلوغرام.
  final int stockBaseKind;

  String get productName => original.productName;
  double get unitPrice => original.price;
  int? get productId => original.productId;

  double get soldEnteredQty => original.enteredQtyResolved;
  double get unitFactor => original.unitFactor <= 0 ? 1.0 : original.unitFactor;

  /// كمية الإرجاع بنفس وحدة العرض الأصلية (قطعة/علبة/كيلوغرام…).
  double returnEnteredQty;
}

class _ProcessReturnScreenState extends State<ProcessReturnScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final _barcodeCtrl = TextEditingController();
  final _barcodeFocus = FocusNode();

  Invoice? _original;
  bool _loading = true;
  String? _loadError;
  final List<_LineReturn> _lines = [];

  static final _df = DateFormat('yyyy/MM/dd — HH:mm', 'ar');

  double _returnStepForLine(_LineReturn l) {
    final sold = l.soldEnteredQty;
    if (l.stockBaseKind == 1) {
      if (sold >= 10) return 1.0;
      if (sold >= 2) return 0.5;
      return 0.25;
    }
    if ((sold % 1).abs() > 1e-9) return 0.25;
    return 1;
  }

  String _formatReturnQty(double q) {
    if (!q.isFinite) return '0';
    if ((q % 1).abs() < 1e-9) {
      return IraqiCurrencyFormat.formatInt(q);
    }
    return IraqiCurrencyFormat.formatDecimal2(q);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.originalInvoice != null) {
      final inv = widget.originalInvoice!;
      if (inv.type == InvoiceType.debtCollection ||
          inv.type == InvoiceType.installmentCollection ||
          inv.type == InvoiceType.supplierPayment) {
        setState(() {
          _loading = false;
          _loadError =
              'سندات القبض أو دفع المورد لا تُعالج من شاشة المرتجع.';
        });
        return;
      }
      await _applyInvoice(inv);
      setState(() => _loading = false);
      return;
    }
    final id = widget.invoiceId;
    if (id == null) {
      setState(() {
        _loading = false;
        _loadError = 'لا يوجد رقم فاتورة';
      });
      return;
    }
    try {
      final inv = await _db.getInvoiceById(id);
      if (!mounted) return;
      if (inv == null) {
        setState(() {
          _loading = false;
          _loadError = 'الفاتورة غير موجودة';
        });
        return;
      }
      if (inv.isReturned) {
        setState(() {
          _loading = false;
          _loadError = 'هذه الفاتورة مسجّلة كمرتجع مسبقاً';
        });
        return;
      }
      if (inv.type == InvoiceType.debtCollection ||
          inv.type == InvoiceType.installmentCollection ||
          inv.type == InvoiceType.supplierPayment) {
        setState(() {
          _loading = false;
          _loadError =
              'سندات القبض أو دفع المورد لا تُعالج من شاشة المرتجع.';
        });
        return;
      }
      await _applyInvoice(inv);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<void> _applyInvoice(Invoice inv) async {
    _original = inv;
    _lines.clear();
    final pids = inv.items.map((e) => e.productId).whereType<int>().toSet().toList();
    final kindByPid = <int, int>{};
    if (pids.isNotEmpty) {
      final db = await _db.database;
      final ph = List.filled(pids.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, stockBaseKind FROM products WHERE id IN ($ph)',
        pids,
      );
      for (final r in rows) {
        kindByPid[(r['id'] as num).toInt()] =
            (r['stockBaseKind'] as num?)?.toInt() ?? 0;
      }
    }
    for (final it in inv.items) {
      final k = it.productId != null ? (kindByPid[it.productId!] ?? 0) : 0;
      _lines.add(
        _LineReturn(
          original: it,
          stockBaseKind: k,
        ),
      );
    }
  }

  double get _origLineSubtotal => _original!.items.fold<double>(
        0,
        (s, e) => s + e.enteredQtyResolved * e.price,
      );

  /// مجموع أسطر الإرجاع الحالية (قبل خصم/ضريبة الفاتورة).
  double get _returnLinesGross {
    var g = 0.0;
    for (final l in _lines) {
      g += l.returnEnteredQty * l.unitPrice;
    }
    return g;
  }

  double get _discountReturn {
    final o = _original!;
    if (_returnLinesGross <= 0) return 0;
    return _returnLinesGross * (o.discountPercent / 100.0);
  }

  double get _taxReturn {
    final o = _original!;
    final denom = _origLineSubtotal;
    if (denom <= 0 || _returnLinesGross <= 0) return 0;
    return o.tax * (_returnLinesGross / denom);
  }

  double get _refundTotal {
    if (_returnLinesGross <= 0) return 0;
    return _returnLinesGross - _discountReturn + _taxReturn;
  }

  String _paymentLabel(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
        return 'نقدي';
      case InvoiceType.credit:
        return 'دين (آجل)';
      case InvoiceType.installment:
        return 'تقسيط';
      case InvoiceType.delivery:
        return 'توصيل';
      case InvoiceType.debtCollection:
        return 'سند تحصيل دين';
      case InvoiceType.installmentCollection:
        return 'سند تسديد قسط';
      case InvoiceType.supplierPayment:
        return 'سند دفع مورد';
    }
  }

  String _refundHint(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
      case InvoiceType.delivery:
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
        return 'يُسجَّل خروجاً من الصندوق بنفس المبلغ.';
      case InvoiceType.installment:
        return 'يُحدَّث إجمالي خطة التقسيط المرتبطة بهذه الفاتورة؛ ويُسجَّل خروج نقدي إن وُجد مقدم يُسترد.';
      case InvoiceType.credit:
        return 'يُسجَّل المرتجع كفاتورة مرتبطة بالأصل؛ راجع قائمة الفواتير لحالة الدين.';
      case InvoiceType.supplierPayment:
        return 'لا يُستعمل لهذا النوع.';
    }
  }

  Future<void> _submitReturn() async {
    final o = _original;
    if (o == null || o.id == null) return;
    if (_refundTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر كمية إرجاع واحدة على الأقل')),
      );
      return;
    }

    final staff = context.read<AuthProvider>().username.trim();
    final items = <InvoiceItem>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.returnEnteredQty <= 0) continue;
      final orig = o.items[i];
      final baseReturned = l.returnEnteredQty * l.unitFactor;
      items.add(
        InvoiceItem(
          productName: l.productName,
          quantity: baseReturned,
          price: l.unitPrice,
          total: l.returnEnteredQty * l.unitPrice,
          productId: orig.productId,
          unitVariantId: orig.unitVariantId,
          unitLabel: orig.unitLabel,
          unitFactor: l.unitFactor,
          enteredQty: l.returnEnteredQty,
          baseQty: baseReturned,
        ),
      );
    }
    if (items.isEmpty) return;

    final disc = _discountReturn;
    final tax = _taxReturn;
    final total = _refundTotal;
    final adv = (o.type == InvoiceType.installment || o.type == InvoiceType.credit)
        ? total
        : 0.0;

    final ret = Invoice(
      customerName: o.customerName,
      date: DateTime.now(),
      type: o.type,
      items: items,
      discount: disc,
      tax: tax,
      advancePayment: adv,
      total: total,
      isReturned: true,
      originalInvoiceId: o.id,
      deliveryAddress: o.deliveryAddress,
      createdByUserName: staff.isEmpty ? o.createdByUserName : staff,
      discountPercent: o.discountPercent,
    );

    try {
      final newId =
          await context.read<InvoiceProvider>().addInvoice(ret);
      if (o.type == InvoiceType.installment) {
        await _db.applyInstallmentAdjustmentAfterReturn(
          originalInvoiceId: o.id!,
          returnDocumentTotal: total,
        );
      }
      if (!mounted) return;
      await context.read<ProductProvider>().loadProducts();
      if (!mounted) return;
      unawaited(context.read<NotificationProvider>().refresh());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل المرتجع #$newId ← مرتبط صراحة بالفاتورة الأصلية #${o.id}. ${_refundSnack(o.type)}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $e')),
      );
    }
  }

  String _refundSnack(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
      case InvoiceType.delivery:
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
        return 'خُصم من الصندوق.';
      case InvoiceType.installment:
        return 'خُصم من إجمالي التقسيط.';
      case InvoiceType.credit:
        return '';
      case InvoiceType.supplierPayment:
        return '';
    }
  }

  Future<void> _onBarcodeSubmitted(String raw) async {
    final id = tryParseInvoiceIdFromBarcode(raw);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('للمرتجع استخدم باركود الفاتورة فقط (مثل INV-12)'),
        ),
      );
      return;
    }
    if (id == _original?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه هي نفس الفاتورة المعروضة')),
      );
      return;
    }
    final inv = await _db.getInvoiceById(id);
    if (!mounted) return;
    if (inv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا توجد فاتورة برقم $id')),
      );
      return;
    }
    if (inv.isReturned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فاتورة مرتجعة مسبقاً')),
      );
      return;
    }
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final ac = ctx.appCorners;
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: ac.lg),
              title: Text(
                'الانتقال إلى فاتورة #$id؟',
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
              ),
              content: Text(
                'سيتم استبدال المنتجات المعروضة بفاتورة أخرى.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('موافق'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!ok || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProcessReturnScreen(originalInvoice: inv),
      ),
    );
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  PreferredSizeWidget _returnAppBar(BuildContext context, String title) {
    final s = Theme.of(context).colorScheme;
    return AppBar(
      title: Text(title),
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: s.onPrimary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final gap = context.screenLayout.pageHorizontalGap;

    if (_loading) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: _returnAppBar(context, 'مرتجع'),
          body: Center(
            child: CircularProgressIndicator(
              color: scheme.primary,
            ),
          ),
        ),
      );
    }

    if (_loadError != null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: _returnAppBar(context, 'مرتجع'),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: scheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface,
                      height: 1.45,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final o = _original!;
    final borderRadius = ac.md;
    final outlineBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.outline),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: _returnAppBar(
          context,
          'مرتجع — فاتورة #${o.id}',
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(gap, 14, gap, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _barcodeCtrl,
                    focusNode: _barcodeFocus,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'تبديل الفاتورة (INV-رقم)',
                      hintText: 'امسح باركود إيصال آخر ثم Enter',
                      prefixIcon: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: scheme.primary,
                      ),
                      filled: true,
                      fillColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      isDense: true,
                      border: outlineBorder,
                      enabledBorder: outlineBorder,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: borderRadius,
                        borderSide:
                            BorderSide(color: scheme.primary, width: 1.5),
                      ),
                    ),
                    onSubmitted: _onBarcodeSubmitted,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: ac.lg,
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: ac.isRounded
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              size: 20,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الفاتورة الأصلية #${o.id}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer
                                    .withValues(alpha: 0.65),
                                borderRadius: ac.sm,
                              ),
                              child: Text(
                                _paymentLabel(o.type),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'التاريخ: ${_df.format(o.date)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (o.customerName.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'العميل: ${o.customerName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                        if (o.createdByUserName != null &&
                            o.createdByUserName!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'بائع أصلي: ${o.createdByUserName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        Builder(
                          builder: (ctx) {
                            final u = ctx.watch<AuthProvider>().username;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'المُسجِّل الآن: ${u.isEmpty ? '—' : u}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(gap, 0, gap, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 22,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الأصناف — اختر كمية الإرجاع',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsetsDirectional.fromSTEB(gap, 0, gap, 12),
                itemCount: _lines.length,
                itemBuilder: (ctx, i) {
                  final l = _lines[i];
                  final active = l.returnEnteredQty > 0;
                  final step = _returnStepForLine(l);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: ac.md,
                        border: Border.all(
                          color: active
                              ? scheme.primary.withValues(alpha: 0.45)
                              : scheme.outlineVariant,
                          width: active ? 1.5 : 1,
                        ),
                        boxShadow: ac.isRounded
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.035),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l.productName.isEmpty ? 'صنف' : l.productName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'المباع: ${_formatReturnQty(l.soldEnteredQty)} × ${IraqiCurrencyFormat.formatIqd(l.unitPrice)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  'كمية الإرجاع',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                _qtyIcon(
                                  scheme: scheme,
                                  ac: ac,
                                  icon: Icons.remove_rounded,
                                  onTap: l.returnEnteredQty > 0
                                      ? () => setState(() {
                                            final next =
                                                (l.returnEnteredQty - step)
                                                    .clamp(0.0, l.soldEnteredQty);
                                            l.returnEnteredQty = next;
                                          })
                                      : null,
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: ac.sm,
                                  ),
                                  child: Text(
                                    _formatReturnQty(l.returnEnteredQty),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                _qtyIcon(
                                  scheme: scheme,
                                  ac: ac,
                                  icon: Icons.add_rounded,
                                  onTap: l.returnEnteredQty < l.soldEnteredQty
                                      ? () => setState(() {
                                            final next =
                                                (l.returnEnteredQty + step)
                                                    .clamp(0.0, l.soldEnteredQty);
                                            l.returnEnteredQty = next;
                                          })
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_returnLinesGross > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.42),
                  border: Border(
                    top: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calculate_outlined,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ملخص المرتجع',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _sumRow(context, 'مجموع الأسطر', _returnLinesGross),
                    _sumRow(context, 'خصم نسبة الفاتورة', _discountReturn),
                    _sumRow(context, 'حصة الضريبة', _taxReturn),
                    Divider(height: 20, color: scheme.outlineVariant),
                    _sumRow(
                      context,
                      'المبلغ المسترد للعميل',
                      _refundTotal,
                      strong: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _refundHint(o.type),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: FilledButton.icon(
                  onPressed: _refundTotal > 0 ? _submitReturn : null,
                  icon: const Icon(Icons.assignment_turned_in_rounded),
                  label: const Text(
                    'تأكيد المرتجع',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: ac.lg,
                    ),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyIcon({
    required ColorScheme scheme,
    required AppCornerStyle ac,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: ac.sm,
      child: InkWell(
        onTap: onTap,
        borderRadius: ac.sm,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 22,
            color: onTap != null ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _sumRow(
    BuildContext context,
    String label,
    double v, {
    bool strong = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              fontSize: strong ? 15 : 13,
              color: scheme.onSurface,
            ),
          ),
          Text(
            IraqiCurrencyFormat.formatIqd(v),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              fontSize: strong ? 17 : 13,
              color: strong ? scheme.primary : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
