import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../providers/notification_provider.dart';
import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';

const Color _kAccent = Color(0xFF1E3A5F);
const Color _kGreen  = Color(0xFF15803D);

/// أقصى عدد أسطر يُضاف دفعة واحدة من «الملء التلقائي» لتفادي بطء الواجهة.
const int _kMaxAutoPoLines = 150;

class AddPurchaseOrderScreen extends StatefulWidget {
  const AddPurchaseOrderScreen({super.key, this.poId, this.copyFromPoId});

  /// إذا كان [poId] غير null فهذا تعديل لأمر موجود.
  final int? poId;
  /// إنشاء أمر جديد عبر نسخ بيانات أمر موجود.
  final int? copyFromPoId;

  @override
  State<AddPurchaseOrderScreen> createState() => _AddPurchaseOrderScreenState();
}

class _AddPurchaseOrderScreenState extends State<AddPurchaseOrderScreen> {
  final _db     = DatabaseHelper();
  final _tenant = TenantContextService.instance;
  final _fmt    = DateFormat('dd/MM/yyyy');

  final _notesCtrl    = TextEditingController();
  final _supplierCtrl = TextEditingController();

  bool   _loading = true;
  bool   _saving  = false;
  String _status  = 'draft';
  DateTime _orderDate    = DateTime.now();
  DateTime? _expectedDate;

  int?   _supplierId;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _products  = [];

  // بنود الأمر
  final List<_PoLine> _lines = [];

  bool get _isEdit => widget.poId != null;
  bool get _isCopy => !_isEdit && widget.copyFromPoId != null;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    setState(() => _loading = true);
    final db = await _db.database;
    final sups = await db.query(
      'suppliers',
      columns: ['id', 'name'],
      where: 'isActive = 1 AND tenantId = ?',
      whereArgs: [_tenant.activeTenantId],
      orderBy: 'name COLLATE NOCASE',
    );
    final prods = await db.query(
      'products',
      columns: ['id', 'name', 'buyPrice'],
      where: 'isActive = 1 AND tenantId = ?',
      whereArgs: [_tenant.activeTenantId],
      orderBy: 'name COLLATE NOCASE',
      limit: 500,
    );
    if (_isEdit || _isCopy) {
      await _loadExistingPo(db, poId: _isEdit ? widget.poId : widget.copyFromPoId);
    }
    if (!mounted) return;
    setState(() {
      _suppliers = List.from(sups);
      _products  = List.from(prods);
      _loading   = false;
    });
  }

  Future<void> _loadExistingPo(Database db, {required int? poId}) async {
    final rows = await db.query(
      'purchase_orders',
      where: 'id = ?',
      whereArgs: [poId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final po = rows.first as Map<String, dynamic>;
    _status       = (po['status'] as String?) ?? 'draft';
    _supplierId   = po['supplierId'] as int?;
    _supplierCtrl.text = (po['supplierName'] as String? ?? '');
    _notesCtrl.text    = (po['notes'] as String? ?? '');
    try {
      _orderDate = DateTime.parse(po['orderDate'] as String? ?? '');
    } catch (_) {}
    try {
      final exp = po['expectedDate'] as String?;
      if (exp != null && exp.isNotEmpty) _expectedDate = DateTime.parse(exp);
    } catch (_) {}

    final items = await db.query(
      'purchase_order_items',
      where: 'poId = ?',
      whereArgs: [poId],
    ) as List<Map<String, dynamic>>;
    for (final item in items) {
      _lines.add(_PoLine(
        itemId:      item['id'] as int?,
        productId:   item['productId'] as int?,
        productName: (item['productName'] as String?) ?? '',
        orderedQty:  (item['orderedQty'] as num?)?.toDouble() ?? 0,
        receivedQty: (item['receivedQty'] as num?)?.toDouble() ?? 0,
        unitPrice:   (item['unitPrice'] as num?)?.toDouble() ?? 0,
        qtyCtrl:     TextEditingController(
          text: _fmt2((item['orderedQty'] as num?)?.toDouble() ?? 0),
        ),
        priceCtrl: TextEditingController(
          text: _fmt2((item['unitPrice'] as num?)?.toDouble() ?? 0),
        ),
      ));
    }

    if (_isCopy) {
      // عند النسخ: نبدأ أمر جديد بمسودة وتاريخ اليوم، ونصفّر الاستلام.
      _status = 'draft';
      _orderDate = DateTime.now();
      _expectedDate = null;
      for (final l in _lines) {
        l.receivedQty = 0;
      }
    }
  }

  String _fmt2(double v) => v == 0 ? '' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 3);

  double get _grandTotal => _lines.fold(0.0, (s, l) => s + l.lineTotal);

  Future<void> _pickDate({required bool isOrder}) async {
    final initial  = isOrder ? _orderDate : (_expectedDate ?? _orderDate);
    final firstDate = isOrder ? DateTime(2020) : _orderDate;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (isOrder) {
        _orderDate = d;
        if (_expectedDate != null && _expectedDate!.isBefore(d)) _expectedDate = null;
      } else {
        _expectedDate = d;
      }
    });
  }

  void _addLine() {
    setState(() {
      _lines.add(_PoLine(
        productName: '',
        orderedQty:  0,
        receivedQty: 0,
        unitPrice:   0,
        qtyCtrl:   TextEditingController(),
        priceCtrl: TextEditingController(),
      ));
    });
  }

  /// يضيف أسطراً لمنتجات **تتبع مخزونها** ورصيدها عند أو تحت حد التنبيه (`qty <= lowStockThreshold`).
  /// الكمية تُترك فارغة لتعبئتها يدوياً؛ سعر الوحدة يُملأ من `buyPrice` عند توفره.
  Future<void> _appendLowStockProductLines() async {
    final tid = _tenant.activeTenantId;
    final db = await _db.database;
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.rawQuery(
        '''
        SELECT id, name, buyPrice, qty, lowStockThreshold, stockBaseKind
        FROM products
        WHERE isActive = 1
          AND tenantId = ?
          AND IFNULL(trackInventory, 1) = 1
          AND (
            qty <= 0
            OR (IFNULL(lowStockThreshold, 0) > 0 AND qty <= lowStockThreshold)
            OR (
              IFNULL(stockBaseKind, 0) = 1
              AND IFNULL(lowStockThreshold, 0) <= 0
              AND qty > 0
              AND qty < 1
            )
          )
        ORDER BY qty ASC, name COLLATE NOCASE
        LIMIT ?
        ''',
        [tid, _kMaxAutoPoLines + 1],
      );
    } catch (_) {
      _snack('تعذر جلب الأصناف المنخفضة. تأكد من تحديث قاعدة البيانات.', error: true);
      return;
    }

    final existingIds = _lines.map((l) => l.productId).whereType<int>().toSet();
    final existingNames = _lines
        .map((l) => l.productName.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    var added = 0;
    var skippedDup = 0;
    var truncated = false;
    if (rows.length > _kMaxAutoPoLines) {
      truncated = true;
      rows = rows.sublist(0, _kMaxAutoPoLines);
    }

    for (final m in rows) {
      final id = m['id'] as int?;
      final name = (m['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      if (id != null && existingIds.contains(id)) {
        skippedDup++;
        continue;
      }
      final key = name.toLowerCase();
      if (existingNames.contains(key)) {
        skippedDup++;
        continue;
      }
      if (id != null) existingIds.add(id);
      existingNames.add(key);

      final buy = (m['buyPrice'] as num?)?.toDouble() ?? 0;
      final priceText = buy > 0
          ? buy.toStringAsFixed(
              buy.truncateToDouble() == buy ? 0 : 3,
            )
          : '';

      _lines.add(_PoLine(
        productId: id,
        productName: name,
        orderedQty: 0,
        receivedQty: 0,
        unitPrice: buy,
        qtyCtrl: TextEditingController(),
        priceCtrl: TextEditingController(text: priceText),
      ));
      added++;
    }

    if (!mounted) return;
    setState(() {});

    if (added == 0) {
      if (skippedDup > 0) {
        _snack(
          'لا توجد أصناف جديدة: كل المنتجات المنخفضة مضافة مسبقاً في القائمة.',
        );
      } else {
        _snack(
          'لا توجد منتجات منخفضة المخزون (رصيد عند أو تحت حد التنبيه، مع تفعيل تتبع المخزون).',
        );
      }
      return;
    }

    var msg =
        'تمت إضافة $added صنفاً من المخزون المنخفض/النافض. عُدّل الكميات ثم احفظ.';
    if (skippedDup > 0) {
      msg += ' (تُجاهل $skippedDup مكرراً)';
    }
    if (truncated) {
      msg += ' — عُرض أول $_kMaxAutoPoLines صنفاً فقط.';
    }
    _snack(msg);
  }

  void _removeLine(int i) {
    final line = _lines[i];
    line.qtyCtrl.dispose();
    line.priceCtrl.dispose();
    setState(() => _lines.removeAt(i));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_lines.isEmpty) {
      _snack('أضف صنفاً واحداً على الأقل', error: true);
      return;
    }
    final validLines = _lines.where((l) =>
        l.productName.trim().isNotEmpty &&
        l.parsedQty > 0).toList();
    if (validLines.isEmpty) {
      _snack('تأكد من اسم المنتج والكمية في كل صنف', error: true);
      return;
    }

    setState(() => _saving = true);
    final db  = await _db.database;
    final now = DateTime.now().toIso8601String();
    final tid = _tenant.activeTenantId;

    final supplierName = _supplierId != null
        ? (_suppliers
            .firstWhere((s) => s['id'] == _supplierId, orElse: () => {})['name'] as String? ?? '')
        : _supplierCtrl.text.trim();

    final poData = {
      'tenantId':      tid,
      'supplierId':    _supplierId,
      'supplierName':  supplierName,
      'status':        _status,
      'orderDate':     _orderDate.toIso8601String(),
      'expectedDate':  _expectedDate?.toIso8601String(),
      'notes':         _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'totalAmount':   _grandTotal,
      'receivedAmount': _isEdit
          ? (await _getExistingReceived(db) ?? 0)
          : 0,
      'updatedAt':     now,
    };

    try {
      if (_isEdit) {
        await db.update('purchase_orders', poData,
            where: 'id = ?', whereArgs: [widget.poId]);
        // حذف البنود القديمة ثم إعادة إدخالها
        await db.delete('purchase_order_items',
            where: 'poId = ?', whereArgs: [widget.poId]);
        for (final l in validLines) {
          await db.insert('purchase_order_items', {
            'tenantId':    tid,
            'poId':        widget.poId,
            'productId':   l.productId,
            'productName': l.productName.trim(),
            'orderedQty':  l.parsedQty,
            'receivedQty': l.receivedQty,
            'unitPrice':   l.parsedPrice,
            'total':       l.lineTotal,
          });
        }
      } else {
        // رقم أمر تلقائي
        final count = await db.rawQuery(
            'SELECT COUNT(*)+1 AS n FROM purchase_orders WHERE tenantId = ?', [tid]);
        final n = (count.first['n'] as num?)?.toInt() ?? 1;
        final poNo = 'PO-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';

        final poId = await db.insert('purchase_orders', {
          ...poData,
          'poNumber': poNo,
          'createdAt': now,
        });
        for (final l in validLines) {
          await db.insert('purchase_order_items', {
            'tenantId':    tid,
            'poId':        poId,
            'productId':   l.productId,
            'productName': l.productName.trim(),
            'orderedQty':  l.parsedQty,
            'receivedQty': 0,
            'unitPrice':   l.parsedPrice,
            'total':       l.lineTotal,
          });
        }
      }
      if (!mounted) return;
      try {
        unawaited(context.read<NotificationProvider>().refresh());
      } catch (_) {}
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('حدث خطأ: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<double?> _getExistingReceived(Database db) async {
    final r = await db.query('purchase_orders',
        columns: ['receivedAmount'],
        where: 'id = ?', whereArgs: [widget.poId], limit: 1);
    return r.isEmpty ? null : (r.first['receivedAmount'] as num?)?.toDouble();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : _kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##0.000', 'ar');
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _kAccent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _isEdit ? 'تعديل أمر شراء' : 'أمر شراء جديد',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              )
            else
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                label: const Text('حفظ', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ── معلومات الأمر ────────────────────────────────────
                        _Section(
                          title: 'معلومات الأمر',
                          child: Column(
                            children: [
                              // المورد
                              _LabelField(
                                label: 'المورد',
                                child: DropdownButtonFormField<int?>(
                                  value: _supplierId,
                                  isExpanded: true,
                                  decoration: _dec(context, 'اختر مورداً (اختياري)'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('— بدون مورد —')),
                                    ..._suppliers.map((s) => DropdownMenuItem(
                                          value: s['id'] as int,
                                          child: Text(s['name'] as String? ?? ''),
                                        )),
                                  ],
                                  onChanged: (v) => setState(() => _supplierId = v),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // التواريخ
                              Row(
                                children: [
                                  Expanded(
                                    child: _LabelField(
                                      label: 'تاريخ الأمر',
                                      child: _DateTile(
                                        date: _orderDate,
                                        fmt: _fmt,
                                        onTap: () => _pickDate(isOrder: true),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _LabelField(
                                      label: 'تاريخ الاستلام المتوقع',
                                      child: _DateTile(
                                        date: _expectedDate,
                                        fmt: _fmt,
                                        hint: 'اختر (اختياري)',
                                        onTap: () => _pickDate(isOrder: false),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // الحالة
                              _LabelField(
                                label: 'الحالة',
                                child: DropdownButtonFormField<String>(
                                  value: _status,
                                  isExpanded: true,
                                  decoration: _dec(context, ''),
                                  items: const [
                                    DropdownMenuItem(value: 'draft',    child: Text('مسودة')),
                                    DropdownMenuItem(value: 'sent',     child: Text('مرسل للمورد')),
                                    DropdownMenuItem(value: 'partial',  child: Text('مستلم جزئياً')),
                                    DropdownMenuItem(value: 'received', child: Text('مستلم بالكامل')),
                                    DropdownMenuItem(value: 'cancelled',child: Text('ملغى')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() => _status = v); },
                                ),
                              ),
                              const SizedBox(height: 12),
                              // ملاحظات
                              _LabelField(
                                label: 'ملاحظات',
                                child: TextField(
                                  controller: _notesCtrl,
                                  textAlign: TextAlign.right,
                                  maxLines: 2,
                                  decoration: _dec(context, 'شروط، تفاصيل، ملاحظات…'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── الأصناف ──────────────────────────────────────────
                        _Section(
                          title: 'أصناف الأمر',
                          trailing: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: _appendLowStockProductLines,
                                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                label: const Text('ملء من المخزون النافض'),
                                style: TextButton.styleFrom(
                                  foregroundColor: _kGreen,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة صنف'),
                                style: TextButton.styleFrom(
                                  foregroundColor: _kAccent,
                                ),
                              ),
                            ],
                          ),
                          child: _lines.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.add_shopping_cart_outlined,
                                            size: 40, color: Colors.grey.shade400),
                                        const SizedBox(height: 8),
                                        Text(
                                          'اضغط «ملء من المخزون النافض» أو «إضافة صنف» لبدء القائمة',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    // رأس الجدول
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      color: _kAccent.withOpacity(0.06),
                                      child: const Row(
                                        children: [
                                          Expanded(flex: 4, child: Text('الصنف',      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                                          Expanded(flex: 2, child: Text('الكمية',     style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                                          Expanded(flex: 2, child: Text('سعر الوحدة',style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                                          Expanded(flex: 2, child: Text('الإجمالي',  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.end)),
                                          SizedBox(width: 32),
                                        ],
                                      ),
                                    ),
                                    ...List.generate(_lines.length, (i) {
                                      final line = _lines[i];
                                      return _PoLineRow(
                                        line:      line,
                                        products:  _products,
                                        fmtMoney:  fmtMoney,
                                        onRemove:  () => _removeLine(i),
                                        onChanged: () => setState(() {}),
                                      );
                                    }),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  // ── شريط الإجمالي ──────────────────────────────────────────
                  Container(
                    color: cs.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Text('الإجمالي', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          fmtMoney.format(_grandTotal),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _kAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _dec(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    );
  }
}

// ── بند في الأمر ──────────────────────────────────────────────────────────────

class _PoLine {
  _PoLine({
    this.itemId,
    this.productId,
    required this.productName,
    required this.orderedQty,
    required this.receivedQty,
    required this.unitPrice,
    required this.qtyCtrl,
    required this.priceCtrl,
  });

  int?   itemId;
  int?   productId;
  String productName;
  double orderedQty;
  double receivedQty;
  double unitPrice;
  TextEditingController qtyCtrl;
  TextEditingController priceCtrl;

  double get parsedQty  => double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
  double get parsedPrice => double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
  double get lineTotal  => parsedQty * parsedPrice;
}

// ── صف بند في الجدول ─────────────────────────────────────────────────────────

class _PoLineRow extends StatelessWidget {
  const _PoLineRow({
    required this.line,
    required this.products,
    required this.fmtMoney,
    required this.onRemove,
    required this.onChanged,
  });

  final _PoLine                    line;
  final List<Map<String, dynamic>> products;
  final NumberFormat               fmtMoney;
  final VoidCallback               onRemove;
  final VoidCallback               onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // اسم الصنف (autocomplete)
          Expanded(
            flex: 4,
            child: Autocomplete<Map<String, dynamic>>(
              initialValue: TextEditingValue(text: line.productName),
              displayStringForOption: (m) => m['name'] as String? ?? '',
              optionsBuilder: (tv) {
                final q = tv.text.toLowerCase();
                if (q.isEmpty) return products.take(20);
                return products
                    .where((p) =>
                        (p['name'] as String? ?? '').toLowerCase().contains(q))
                    .take(20);
              },
              onSelected: (m) {
                line.productId   = m['id'] as int?;
                line.productName = m['name'] as String? ?? '';
                final buyPrice   = (m['buyPrice'] as num?)?.toDouble() ?? 0;
                if (buyPrice > 0 && line.priceCtrl.text.trim().isEmpty) {
                  line.priceCtrl.text =
                      buyPrice.toStringAsFixed(buyPrice.truncateToDouble() == buyPrice ? 0 : 3);
                }
                onChanged();
              },
              fieldViewBuilder: (ctx, ctrl, fn, onFieldSubmitted) {
                return TextField(
                  controller: ctrl,
                  focusNode: fn,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'اسم الصنف',
                    hintStyle: const TextStyle(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (v) {
                    line.productName = v;
                    onChanged();
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          // الكمية
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          // سعر الوحدة
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          // الإجمالي
          Expanded(
            flex: 2,
            child: Text(
              fmtMoney.format(line.lineTotal),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          // حذف
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ── مكونات مساعدة ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String  title;
  final Widget  child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
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
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            Container(
                height: 2, width: 40, color: cs.primary.withOpacity(0.3),
                margin: const EdgeInsets.only(top: 4, bottom: 14)),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabelField extends StatelessWidget {
  const _LabelField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.date,
    required this.fmt,
    required this.onTap,
    this.hint = '',
  });
  final DateTime?    date;
  final DateFormat   fmt;
  final String       hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date != null ? fmt.format(date!) : hint,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null ? null : Colors.grey,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
