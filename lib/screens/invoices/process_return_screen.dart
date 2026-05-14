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
import '../../theme/design_tokens.dart';
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
    this.alreadyReturnedEnteredQty = 0,
  }) : returnEnteredQty = 0;

  final InvoiceItem original;

  /// يطابق [products.stockBaseKind] عند توفر [productId]؛ 1 = خطوات كمية بالكيلوغرام.
  final int stockBaseKind;

  /// الكمية المُرجَعة سابقاً لهذا البند عبر فواتير مرتجع سابقة لنفس الفاتورة
  /// الأصلية (Aggregated عبر `invoices.originalInvoiceId = X AND isReturned = 1`).
  /// **هذا الحقل أساس التحقق التجاري** لمنع إرجاع نفس البند مراراً وتكراراً
  /// بأكثر من الكمية المباعة فعلياً.
  final double alreadyReturnedEnteredQty;

  String get productName => original.productName;
  double get unitPrice => original.price;
  int? get productId => original.productId;

  double get soldEnteredQty => original.enteredQtyResolved;
  double get unitFactor => original.unitFactor <= 0 ? 1.0 : original.unitFactor;

  /// أقصى كمية يُسمح بإرجاعها الآن = ‏الكمية المباعة − ما أُرجع سابقاً.
  /// تُحسب بنفس وحدة العرض. قد تكون 0 إن استُرد البند بالكامل.
  double get maxReturnableEnteredQty {
    final remaining = soldEnteredQty - alreadyReturnedEnteredQty;
    return remaining > 0 ? remaining : 0;
  }

  /// هل هذا البند مُرجَع بالكامل (لا يمكن إرجاعه أكثر).
  bool get isFullyReturned =>
      alreadyReturnedEnteredQty >= soldEnteredQty - 1e-9;

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
      var inv = widget.originalInvoice!;
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
      // الفاتورة المُمرَّرة من قائمة `invoices_screen` تأتي بـ items فارغة
      // (lazy-load للأداء). لذا إن كانت فارغة وللفاتورة id، نُعيد التحميل
      // الكامل من DB عبر `getInvoiceById` التي تجلب البنود معها.
      if (inv.items.isEmpty && inv.id != null) {
        try {
          final full = await _db.getInvoiceById(inv.id!);
          if (full != null) inv = full;
        } catch (_) {/* نُكمل بالـ inv الفارغ ونظهر الحالة الفارغة */}
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
    final db = await _db.database;
    if (pids.isNotEmpty) {
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

    // ====== جلب الكميات المُرجَعة سابقاً (أساس التحقق التجاري) ======
    // نجمع `enteredQty` عبر بنود الفواتير المرتجعة المرتبطة بـ originalInvoiceId
    // الحالي. نُجمّع أولاً عبر productId (الحالة الطبيعية)، ثم Fallback بالاسم
    // للبنود اليدوية بدون productId — مع مفتاح مركّب (name|price) لتجنب الخلط.
    final returnedByPid = <int, double>{};
    final returnedByNamePrice = <String, double>{};
    if (inv.id != null) {
      final retRows = await db.rawQuery(
        '''
        SELECT ii.productId AS pid,
               ii.productName AS name,
               ii.price AS price,
               ii.enteredQty AS qty
        FROM invoice_items ii
        INNER JOIN invoices inv ON inv.id = ii.invoiceId
        WHERE inv.originalInvoiceId = ? AND inv.isReturned = 1
        ''',
        [inv.id],
      );
      for (final r in retRows) {
        final qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) continue;
        final pid = (r['pid'] as num?)?.toInt();
        if (pid != null) {
          returnedByPid[pid] = (returnedByPid[pid] ?? 0) + qty;
        } else {
          final name = (r['name'] as String?) ?? '';
          final price = (r['price'] as num?)?.toDouble() ?? 0.0;
          final key = '$name|${price.toStringAsFixed(4)}';
          returnedByNamePrice[key] =
              (returnedByNamePrice[key] ?? 0) + qty;
        }
      }
    }

    for (final it in inv.items) {
      final k = it.productId != null ? (kindByPid[it.productId!] ?? 0) : 0;
      double already;
      if (it.productId != null) {
        already = returnedByPid[it.productId!] ?? 0;
      } else {
        final key = '${it.productName}|${it.price.toStringAsFixed(4)}';
        already = returnedByNamePrice[key] ?? 0;
      }
      // قَيِّد على المباع كحد علوي (دفاع ضد بيانات تاريخية شاذة).
      final cap = it.enteredQtyResolved;
      if (already > cap) already = cap;
      _lines.add(
        _LineReturn(
          original: it,
          stockBaseKind: k,
          alreadyReturnedEnteredQty: already,
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

    // ====== Race-condition Guard: إعادة تحقق من المرتجعات السابقة ======
    // يُحتمل أن تكون قد أُنشئت فاتورة مرتجع لنفس الفاتورة الأصلية في جلسة
    // أخرى (شاشة ثانية / مستخدم آخر) منذ تحميل هذه الشاشة. نُعيد التحقق
    // قبل الكتابة لمنع التجاوز التراكمي.
    try {
      final fresh = await _refetchAlreadyReturnedQtys(o.id!);
      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        if (l.returnEnteredQty <= 0) continue;
        final orig = o.items[i];
        final key = orig.productId != null
            ? 'pid:${orig.productId}'
            : 'name:${orig.productName}|${orig.price.toStringAsFixed(4)}';
        final freshAlready = fresh[key] ?? 0.0;
        final freshMax = (l.soldEnteredQty - freshAlready).clamp(0.0, double.infinity);
        if (l.returnEnteredQty > freshMax + 1e-6) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم إرجاع "${l.productName}" في فاتورة أخرى منذ فتح هذه الشاشة. '
                'المتبقي القابل للإرجاع: ${_formatReturnQty(freshMax)}. '
                'أعِد تحميل الشاشة وحاول مجدداً.',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
      }
    } catch (_) {
      // إن فشل الاستعلام (خلل DB نادر) نسمح بالاستمرار اعتماداً على Clamp الـ UI
      // — لا نحبس المستخدم بسبب خطأ تحقق ثانوي.
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

  /// إعادة جلب المرتجعات السابقة للفاتورة الأصلية (Race-condition guard).
  /// يُرجِع map: `pid:<id>` أو `name:<name>|<price>` → الكمية المُرجَعة الكلية.
  Future<Map<String, double>> _refetchAlreadyReturnedQtys(int originalId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT ii.productId AS pid,
             ii.productName AS name,
             ii.price AS price,
             ii.enteredQty AS qty
      FROM invoice_items ii
      INNER JOIN invoices inv ON inv.id = ii.invoiceId
      WHERE inv.originalInvoiceId = ? AND inv.isReturned = 1
      ''',
      [originalId],
    );
    final out = <String, double>{};
    for (final r in rows) {
      final qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
      if (qty <= 0) continue;
      final pid = (r['pid'] as num?)?.toInt();
      final key = pid != null
          ? 'pid:$pid'
          : 'name:${(r['name'] as String?) ?? ''}|'
              '${((r['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)}';
      out[key] = (out[key] ?? 0) + qty;
    }
    return out;
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
    unawaited(Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProcessReturnScreen(originalInvoice: inv),
      ),
    ));
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
    final isWide = context.screenLayout.isWideVariant;
    // `allMaxed` = كل البنود إما (أ) مُرجَعة بالكامل سابقاً، أو (ب) المستخدم
    // اختار إرجاع كل المتبقي منها في هذه الجلسة. نخفي عندها زر "إرجاع كامل"
    // لأن لا شيء قابل للإرجاع.
    final allMaxed = _lines.isEmpty ||
        _lines.every(
          (l) => l.isFullyReturned ||
              l.returnEnteredQty >= l.maxReturnableEnteredQty - 1e-9,
        );

    // هل تم إرجاع كل بنود الفاتورة الأصلية بالكامل في فواتير مرتجع سابقة؟
    // عندها لا يوجد ما يمكن إرجاعه، ونعرض بانر تنبيهي بدل حالة فارغة محيرة.
    final allFullyReturnedAlready =
        _lines.isNotEmpty && _lines.every((l) => l.isFullyReturned);

    final summaryPanel = _ReturnSummaryPanel(
      gross: _returnLinesGross,
      discount: _discountReturn,
      tax: _taxReturn,
      refund: _refundTotal,
      refundHint: _refundHint(o.type),
      canSubmit: _refundTotal > 0,
      onSubmit: _submitReturn,
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
          children: [
            if (allFullyReturnedAlready)
              _FullyReturnedBanner(invoiceId: o.id ?? 0),
            Expanded(
              child: isWide
                  ? _buildWideBody(
                      context, o, gap, scheme, allMaxed, summaryPanel)
                  : _buildNarrowBody(context, o, gap, scheme, allMaxed),
            ),
          ],
        ),
        // Sticky Footer للموبايل — يُبقي زر "تأكيد المرتجع" ظاهراً دائماً
        // مهما طالت قائمة الأصناف. على wide نضع اللوحة في عمود اليسار.
        bottomNavigationBar: isWide
            ? null
            : Material(
                color: scheme.surface,
                elevation: 8,
                child: summaryPanel,
              ),
      ),
    );
  }

  // ── Narrow body (موبايل/تابلت طولي) ────────────────────────────────────
  Widget _buildNarrowBody(
    BuildContext context,
    Invoice o,
    double gap,
    ColorScheme scheme,
    bool allMaxed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(gap, 14, gap, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BarcodeSwitchField(
                controller: _barcodeCtrl,
                focusNode: _barcodeFocus,
                onSubmitted: _onBarcodeSubmitted,
              ),
              const SizedBox(height: 12),
              _OriginalInvoiceCard(
                invoice: o,
                paymentLabel: _paymentLabel(o.type),
                dateFormat: _df,
              ),
            ],
          ),
        ),
        _ItemsHeader(
          gap: gap,
          allMaxed: allMaxed,
          onFullReturn: _setAllToMax,
        ),
        Expanded(child: _buildLinesList(gap)),
      ],
    );
  }

  // ── Wide body (Two-Pane: Items يميناً، Summary يساراً) ───────────────
  Widget _buildWideBody(
    BuildContext context,
    Invoice o,
    double gap,
    ColorScheme scheme,
    bool allMaxed,
    Widget summaryPanel,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Right pane (الأصناف) — يأخذ كل المساحة المتبقية
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ItemsHeader(
                gap: gap,
                allMaxed: allMaxed,
                onFullReturn: _setAllToMax,
                topPadding: 14,
              ),
              Expanded(child: _buildLinesList(gap)),
            ],
          ),
        ),
        // فاصل عمودي ناعم
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        // Left pane (Sticky Workspace Panel) — عرض ثابت 400dp
        SizedBox(
          width: 400,
          child: Material(
            color: scheme.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BarcodeSwitchField(
                    controller: _barcodeCtrl,
                    focusNode: _barcodeFocus,
                    onSubmitted: _onBarcodeSubmitted,
                  ),
                  const SizedBox(height: 12),
                  _OriginalInvoiceCard(
                    invoice: o,
                    paymentLabel: _paymentLabel(o.type),
                    dateFormat: _df,
                  ),
                  summaryPanel,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // قائمة بطاقات الأصناف — تُستعمل في كلا الـ layouts.
  Widget _buildLinesList(double gap) {
    if (_lines.isEmpty) {
      return _LinesEmptyState(gap: gap);
    }
    return ListView.builder(
      padding: EdgeInsetsDirectional.fromSTEB(gap, 0, gap, 12),
      itemCount: _lines.length,
      itemBuilder: (ctx, i) {
        final l = _lines[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ReturnLineCard(
            line: l,
            step: _returnStepForLine(l),
            formatQty: _formatReturnQty,
            onQuantityChanged: (next) => setState(() {
              // الحد الأعلى = ‏الكمية المباعة − ما أُرجع سابقاً (وليس المباع
              // فقط) — يمنع إرجاع نفس البند في فواتير مرتجع متتالية بأكثر من
              // الكمية المسموحة.
              l.returnEnteredQty = next.clamp(0.0, l.maxReturnableEnteredQty);
            }),
          ),
        );
      },
    );
  }

  /// "إرجاع كامل" — يضع كل بند على **المتبقي** القابل للإرجاع (وليس المباع
  /// الكلي)، احتراماً للكميات المُرجَعة سابقاً عبر فواتير مرتجع سابقة لنفس
  /// الفاتورة الأصلية. إجراء كاشير شائع عند إلغاء فاتورة كاملة.
  void _setAllToMax() {
    setState(() {
      for (final l in _lines) {
        l.returnEnteredQty = l.maxReturnableEnteredQty;
      }
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-widgets — استُخرجت كـ Stateless لتنظيم build وتمكين تخطيط Two-Pane.
// كلها تستقبل callbacks، ولا تحوي business logic — فقط presentation.
// ════════════════════════════════════════════════════════════════════════════

/// بانر علوي يَظهر فوق المحتوى عندما تكون **كل بنود الفاتورة الأصلية**
/// مُرجَعة بالكامل في فواتير مرتجع سابقة. يمنع المستخدم من فقدان الوقت
/// محاولاً إرجاع شيء غير قابل للإرجاع.
class _FullyReturnedBanner extends StatelessWidget {
  const _FullyReturnedBanner({required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context) {
    final ac = context.appCorners;
    final color = AppSemanticColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ac.md,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.assignment_turned_in_rounded, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تم إرجاع جميع بنود الفاتورة #$invoiceId بالكامل في فواتير '
              'مرتجع سابقة. لا يوجد ما يمكن إرجاعه إضافياً من هذه الفاتورة.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة فارغة لقائمة الأصناف — تظهر إن لم تحوِ الفاتورة بنوداً
/// (نادر؛ سندات/فواتير قديمة تالفة). ترشد المستخدم بدلاً من شاشة بيضاء.
class _LinesEmptyState extends StatelessWidget {
  const _LinesEmptyState({required this.gap});

  final double gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              'لا توجد أصناف في هذه الفاتورة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'تأكّد من رقم الفاتورة، أو استعمل حقل تبديل الباركود لاختيار '
              'فاتورة أخرى تحتوي بنوداً قابلة للإرجاع.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// رأس قسم "الأصناف" — يضمّ العنوان وزر "إرجاع كامل" (Quick Action ERP).
///
/// زر "إرجاع كامل" يضع كل الأصناف على كمياتها المباعة دفعة واحدة.
/// مُصمَّم بحجم متواضع (TextButton) ليُتعمَّد ضغطه؛ لا يُخلط مع زر التأكيد.
class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader({
    required this.gap,
    required this.allMaxed,
    required this.onFullReturn,
    this.topPadding = 0,
  });

  final double gap;
  final bool allMaxed;
  final VoidCallback onFullReturn;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(gap, topPadding, gap, 8),
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
          TextButton.icon(
            onPressed: allMaxed ? null : onFullReturn,
            icon: const Icon(Icons.select_all_rounded, size: 18),
            label: const Text('إرجاع كامل'),
            style: TextButton.styleFrom(
              foregroundColor: AppSemanticColors.danger,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل تبديل الفاتورة عبر الباركود — مكوّن مستقل قابل لإعادة الاستخدام
/// في الـ Single Column (أعلى الشاشة) أو في لوحة الملخص اليسرى (Two-Pane).
class _BarcodeSwitchField extends StatelessWidget {
  const _BarcodeSwitchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final borderRadius = ac.md;
    final outlineBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.outline),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
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
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        isDense: true,
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}

/// بطاقة معلومات الفاتورة الأصلية (رقم/تاريخ/عميل/البائع/المُسجِّل الحالي).
class _OriginalInvoiceCard extends StatelessWidget {
  const _OriginalInvoiceCard({
    required this.invoice,
    required this.paymentLabel,
    required this.dateFormat,
  });

  final Invoice invoice;
  final String paymentLabel;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
                  'الفاتورة الأصلية #${invoice.id}',
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
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: ac.sm,
                ),
                child: Text(
                  paymentLabel,
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
            'التاريخ: ${dateFormat.format(invoice.date)}',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (invoice.customerName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'العميل: ${invoice.customerName}',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface,
              ),
            ),
          ],
          if (invoice.createdByUserName != null &&
              invoice.createdByUserName!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'بائع أصلي: ${invoice.createdByUserName}',
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
                  'المُسجِّل الآن: ${u.isEmpty ? '—' : u}',
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
    );
  }
}

/// بطاقة صنف واحد مع أزرار +/- لاختيار الكمية المرتجعة.
///
/// `onQuantityChanged(newQty)` يستقبل القيمة المُحسوبة بعد clamp في الـ State.
class _ReturnLineCard extends StatelessWidget {
  const _ReturnLineCard({
    required this.line,
    required this.step,
    required this.formatQty,
    required this.onQuantityChanged,
  });

  final _LineReturn line;
  final double step;
  final String Function(double) formatQty;

  /// يُستدعى مع الكمية الجديدة المُقترحة (قبل الـ clamp النهائي في الـ State).
  final ValueChanged<double> onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final active = line.returnEnteredQty > 0;
    final isFullyReturned = line.isFullyReturned;
    final hasPriorReturns = line.alreadyReturnedEnteredQty > 1e-9;
    // أزرار +/- أكبر على التابلت لتسهيل اللمس بإصبع/قلم في POS الميداني.
    final isTablet = context.screenLayout.isTabletVariant;
    final qtyIconSize = isTablet ? 26.0 : 22.0;
    final qtyPadding = isTablet ? 12.0 : 8.0;
    final canIncrement =
        line.returnEnteredQty < line.maxReturnableEnteredQty - 1e-9;
    return Opacity(
      opacity: isFullyReturned ? 0.6 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isFullyReturned
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : scheme.surface,
          borderRadius: ac.md,
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.outlineVariant,
            width: active ? 1.5 : 1,
          ),
          boxShadow: (ac.isRounded && !isFullyReturned)
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      line.productName.isEmpty ? 'صنف' : line.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (isFullyReturned)
                    const _LineStatusBadge(
                      label: 'مُرجَع بالكامل',
                      color: AppSemanticColors.success,
                      icon: Icons.check_circle_rounded,
                    )
                  else if (hasPriorReturns)
                    const _LineStatusBadge(
                      label: 'مُرجَع جزئياً',
                      color: AppSemanticColors.warning,
                      icon: Icons.history_rounded,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'المباع: ${formatQty(line.soldEnteredQty)} × ${IraqiCurrencyFormat.formatIqd(line.unitPrice)}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (hasPriorReturns) ...[
                const SizedBox(height: 4),
                Text(
                  'مُرجَع سابقاً: ${formatQty(line.alreadyReturnedEnteredQty)}'
                  '   •   المتبقي: ${formatQty(line.maxReturnableEnteredQty)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isFullyReturned
                        ? AppSemanticColors.success
                        : AppSemanticColors.warning,
                  ),
                ),
              ],
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
                  _QtyIconButton(
                    icon: Icons.remove_rounded,
                    iconSize: qtyIconSize,
                    padding: qtyPadding,
                    onTap: (line.returnEnteredQty > 0 && !isFullyReturned)
                        ? () => onQuantityChanged(line.returnEnteredQty - step)
                        : null,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: ac.sm,
                    ),
                    child: Text(
                      formatQty(line.returnEnteredQty),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  _QtyIconButton(
                    icon: Icons.add_rounded,
                    iconSize: qtyIconSize,
                    padding: qtyPadding,
                    onTap: canIncrement
                        ? () => onQuantityChanged(line.returnEnteredQty + step)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارة حالة صغيرة للبند داخل بطاقة المرتجع — تُستخدم لـ "مُرجَع بالكامل"
/// و "مُرجَع جزئياً". مكتفية ذاتياً وخفيفة (بدون state).
class _LineStatusBadge extends StatelessWidget {
  const _LineStatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ac.sm,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// زر +/- لتغيير الكمية. حجم اللمس قابل للتكييف بناءً على نوع الجهاز:
/// - الموبايل والديسكتوب: 22px / padding 8 (target 38dp).
/// - التابلت (Touch POS): 26px / padding 12 (target 50dp ≥ معيار 48dp).
class _QtyIconButton extends StatelessWidget {
  const _QtyIconButton({
    required this.icon,
    required this.onTap,
    required this.iconSize,
    required this.padding,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double iconSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: ac.sm,
      child: InkWell(
        onTap: onTap,
        borderRadius: ac.sm,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Icon(
            icon,
            size: iconSize,
            color: onTap != null
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// لوحة ملخص المرتجع + زر التأكيد + رسالة التوجيه.
///
/// تُستعمل في الموضعين:
/// - أسفل الـ Single Column body (الموبايل والتابلت الطولي).
/// - عمود اليسار الثابت (Two-Pane على الديسكتوب).
class _ReturnSummaryPanel extends StatelessWidget {
  const _ReturnSummaryPanel({
    required this.gross,
    required this.discount,
    required this.tax,
    required this.refund,
    required this.refundHint,
    required this.canSubmit,
    required this.onSubmit,
  });

  final double gross;
  final double discount;
  final double tax;
  final double refund;
  final String refundHint;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gross > 0)
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
                _SummaryRow(label: 'مجموع الأسطر', value: gross),
                _SummaryRow(label: 'خصم نسبة الفاتورة', value: discount),
                _SummaryRow(label: 'حصة الضريبة', value: tax),
                Divider(height: 20, color: scheme.outlineVariant),
                _SummaryRow(
                  label: 'المبلغ المسترد للعميل',
                  value: refund,
                  strong: true,
                ),
                const SizedBox(height: 8),
                Text(
                  refundHint,
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
              onPressed: canSubmit ? onSubmit : null,
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
    );
  }
}

/// سطر داخل ملخص المرتجع: تسمية + قيمة بصيغة د.ع.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
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
            IraqiCurrencyFormat.formatIqd(value),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              fontSize: strong ? 17 : 13,
              // المبلغ المسترد بـ AppSemanticColors.info (أزرق محايد)
              // — اتساقاً مع نمط ERP العالمي (Odoo/SAP). لا نستعمل success
              // لأن الإرجاع خسارة على المتجر، وليس success إيجابياً.
              color: strong
                  ? AppSemanticColors.info
                  : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
