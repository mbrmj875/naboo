import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import 'dart:async' show unawaited;

import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../services/app_settings_repository.dart';
import '../../services/database_helper.dart';
import '../../services/inventory_policy_settings.dart';
import '../../services/permission_service.dart';
import '../../services/tenant_context_service.dart';
import '../../widgets/permission_guard.dart';

const Color _kNavy = Color(0xFF1E3A5F);
const Color _kGreen = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFECF0F4);

/// سند مخزوني — إيداع / صرف / نقل
class StockVoucherScreen extends StatefulWidget {
  const StockVoucherScreen({super.key});

  @override
  State<StockVoucherScreen> createState() => _StockVoucherScreenState();
}

class _StockVoucherScreenState extends State<StockVoucherScreen> {
  // ── Header state ──────────────────────────────────────────────────────
  String _voucherType = 'إذن إضافة مخزن';
  DateTime _selectedDate = DateTime.now();

  // ── Source data ───────────────────────────────────────────────────────
  final _referenceCtrl = TextEditingController();
  final _sourceNameCtrl = TextEditingController();
  final _sourceRefIdCtrl = TextEditingController();
  String _sourceType = 'supplier';

  // ── Other info ────────────────────────────────────────────────────────
  String _supplier = '';
  final _notesCtrl = TextEditingController();

  // ── Items table ───────────────────────────────────────────────────────
  final List<_VoucherItem> _items = [_VoucherItem()];

  static const _voucherTypes = [
    'إذن إضافة مخزن',
    'إذن صرف مخزن',
    'نقل بين مخازن',
    'جرد مخزن',
  ];

  static const _sourceTypes = <String, String>{
    'supplier': 'مورد',
    'branch': 'فرع/محل آخر',
    'mobile_vendor': 'مورد متنقل',
    'manual': 'يدوي',
  };

  final _fmt = NumberFormat('#,##0', 'ar');

  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _products = const [];
  int? _warehouseToId;
  int? _warehouseFromId;
  List<String> _supplierItems = const [
    '',
    'mbw',
    'مورد رئيسي',
    'مورد 1',
    'مورد 2',
  ];
  bool _metaLoaded = false;
  bool _saving = false;
  InventoryPolicySettingsData _policy = InventoryPolicySettingsData.defaults();
  bool _createSupplierBillOnInbound = true;
  bool _createSupplierReturnPayoutOnOutbound = true;

  double get _grandTotal => _items.fold(0, (s, item) => s + item.total);

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final wh = await _db.listWarehousesActive(
      tenantId: TenantContextService.instance.activeTenantId,
    );
    List<String> sup = const ['', 'mbw', 'مورد رئيسي', 'مورد 1', 'مورد 2'];
    try {
      sup = await _db.listActiveSupplierNamesForStockUi();
    } catch (_) {}
    final policy = await InventoryPolicySettingsData.load(
      AppSettingsRepository.instance,
    );
    final products = await _db.listActiveProductsForVoucher(
      tenantId: TenantContextService.instance.activeTenantId,
    );
    if (!mounted) return;
    setState(() {
      _warehouses = wh;
      final firstId = wh.isEmpty ? null : wh.first['id'] as int;
      _warehouseToId = firstId;
      _warehouseFromId = firstId;
      _supplierItems = sup;
      if (!_supplierItems.contains(_supplier)) {
        _supplier = _supplierItems.isNotEmpty ? _supplierItems.first : '';
      }
      _sourceNameCtrl.text = _supplier;
      _policy = policy;
      _products = products;
      _metaLoaded = true;
    });
  }

  Future<String> _allocateVoucherNo() async {
    final typeCode = switch (_voucherType) {
      'إذن إضافة مخزن' => 'IN',
      'إذن صرف مخزن' => 'OUT',
      'نقل بين مخازن' => 'TRF',
      _ => 'SV',
    };
    final base = '$typeCode-${DateTime.now().millisecondsSinceEpoch}';
    for (var i = 0; i < 12; i++) {
      final candidate = i == 0 ? base : '$base-$i';
      if (!await _db.isStockVoucherNoTaken(candidate)) {
        return candidate;
      }
    }
    return 'SV-${DateTime.now().microsecondsSinceEpoch}';
  }

  // ── Actions ───────────────────────────────────────────────────────────
  Future<void> _maybeCreateSupplierBillLink({
    required int voucherId,
    required String voucherNo,
    required String supplierName,
    required String? referenceNo,
    required double amount,
    required String? note,
    required int tenantId,
    required String? createdByUserName,
  }) async {
    final cleanSupplier = supplierName.trim();
    if (cleanSupplier.isEmpty ||
        !_createSupplierBillOnInbound ||
        _voucherType != 'إذن إضافة مخزن' ||
        _sourceType != 'supplier' ||
        amount <= 0) {
      return;
    }

    var supplierId = await _db.findActiveSupplierIdByName(
      cleanSupplier,
      tenantId: tenantId,
    );
    supplierId ??= await _db.insertSupplier(
      name: cleanSupplier,
      tenantId: tenantId,
    );

    final billId = await _db.insertSupplierBill(
      tenantId: tenantId,
      supplierId: supplierId,
      theirReference: referenceNo?.trim().isNotEmpty == true
          ? referenceNo!.trim()
          : voucherNo,
      theirBillDate: _selectedDate,
      amount: amount,
      note: note?.trim().isNotEmpty == true
          ? note!.trim()
          : 'من إذن وارد #$voucherNo',
      createdByUserName: createdByUserName?.trim().isNotEmpty == true
          ? createdByUserName!.trim()
          : null,
      linkedStockVoucherId: voucherId,
    );
    await _db.linkSupplierBillToStockVoucher(
      supplierBillId: billId,
      supplierId: supplierId,
      stockVoucherId: voucherId,
    );
  }

  Future<void> _maybeCreateSupplierReturnPayout({
    required String voucherNo,
    required String supplierName,
    required double amount,
    required int tenantId,
    required String? createdByUserName,
  }) async {
    final cleanSupplier = supplierName.trim();
    if (cleanSupplier.isEmpty ||
        !_createSupplierReturnPayoutOnOutbound ||
        _voucherType != 'إذن صرف مخزن' ||
        _sourceType != 'supplier' ||
        amount <= 0) {
      return;
    }

    var supplierId = await _db.findActiveSupplierIdByName(
      cleanSupplier,
      tenantId: tenantId,
    );
    supplierId ??= await _db.insertSupplier(
      name: cleanSupplier,
      tenantId: tenantId,
    );
    await _db.recordSupplierPayout(
      supplierId: supplierId,
      amount: amount,
      note: 'مرتجع مورد عبر سند صرف #$voucherNo',
      affectsCash: false,
      recordedByUserName: (createdByUserName ?? '').trim(),
    );
  }

  Future<void> _confirm() async {
    if (_saving) return;
    if (!_metaLoaded || _warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد مخزن نشط — أضف مخزناً أولاً')),
      );
      return;
    }
    if (_voucherType == 'جرد مخزن') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حفظ «جرد مخزن» غير مفعّل بعد')),
      );
      return;
    }

    final lines = <({int productId, double qty, double unitPrice})>[];
    final missing = <String>[];
    for (final it in _items) {
      if (it.qty <= 0) continue;
      if (it.productId != null) {
        lines.add((
          productId: it.productId!,
          qty: it.qty.toDouble(),
          unitPrice: it.unitPrice,
        ));
        continue;
      }
      final nm = it.name.trim();
      if (nm.isEmpty) {
        missing.add('بند بلا اسم');
        continue;
      }
      final row = await _db.findActiveProductByNameCaseInsensitive(nm);
      if (row == null) {
        missing.add(nm);
        continue;
      }
      lines.add((
        productId: row['id'] as int,
        qty: it.qty.toDouble(),
        unitPrice: it.unitPrice,
      ));
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing.isEmpty
                ? 'أدخل بنوداً بكميات وأسماء مطابقة لمنتجات مسجّلة'
                : 'لم تُعثر على منتجات بالأسماء: ${missing.join('، ')}',
          ),
        ),
      );
      return;
    }
    if (missing.isNotEmpty) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تنبيه'),
          content: Text(
            'بنود تُجاهل لعدم مطابقة الاسم: ${missing.join('، ')}\n'
            'المتابعة تحفظ ${lines.length} بنداً فقط.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (go != true) return;
    }

    final voucherNo = await _allocateVoucherNo();
    if (!mounted) return;
    final ref = _referenceCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    final sup = _supplier.trim();
    final sourceName = _sourceNameCtrl.text.trim().isEmpty
        ? (_sourceType == 'supplier' ? sup : '')
        : _sourceNameCtrl.text.trim();
    final sourceRefId = int.tryParse(_sourceRefIdCtrl.text.trim());
    final tenantId = TenantContextService.instance.activeTenantId;
    final currentUserName = context.read<AuthProvider>().username.trim();

    if (_voucherType == 'إذن إضافة مخزن' &&
        _policy.requireSourceOnInbound &&
        sourceName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تعبئة اسم مصدر الإذن الوارد')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      late final ({bool ok, String message, int? voucherId}) res;
      if (_voucherType == 'إذن إضافة مخزن') {
        if (_warehouseToId == null) return;
        res = await _db.commitInboundStockVoucherWithLines(
          tenantId: tenantId,
          warehouseToId: _warehouseToId!,
          voucherNo: voucherNo,
          voucherDate: _selectedDate,
          referenceNo: ref.isEmpty ? null : ref,
          supplierName: sup.isEmpty ? null : sup,
          sourceType: _sourceType,
          sourceName: sourceName.isEmpty ? null : sourceName,
          sourceRefId: sourceRefId,
          notes: notes.isEmpty ? null : notes,
          lines: lines,
        );
      } else if (_voucherType == 'إذن صرف مخزن') {
        if (_warehouseFromId == null) return;
        res = await _db.commitOutboundStockVoucherWithLines(
          tenantId: tenantId,
          warehouseFromId: _warehouseFromId!,
          voucherNo: voucherNo,
          voucherDate: _selectedDate,
          referenceNo: ref.isEmpty ? null : ref,
          supplierName: sup.isEmpty ? null : sup,
          sourceType: _sourceType,
          sourceName: sourceName.isEmpty ? null : sourceName,
          sourceRefId: sourceRefId,
          notes: notes.isEmpty ? null : notes,
          lines: lines,
        );
      } else if (_voucherType == 'نقل بين مخازن') {
        if (_warehouseFromId == null || _warehouseToId == null) return;
        res = await _db.commitTransferStockVoucherWithLines(
          tenantId: tenantId,
          warehouseFromId: _warehouseFromId!,
          warehouseToId: _warehouseToId!,
          voucherNo: voucherNo,
          voucherDate: _selectedDate,
          referenceNo: ref.isEmpty ? null : ref,
          sourceType: 'transfer',
          sourceName: sourceName.isEmpty ? null : sourceName,
          sourceRefId: sourceRefId,
          notes: notes.isEmpty ? null : notes,
          lines: lines,
        );
      } else {
        return;
      }

      if (!mounted) return;
      if (!res.ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res.message)));
        return;
      }
      try {
        if (res.voucherId != null) {
          await _maybeCreateSupplierBillLink(
            voucherId: res.voucherId!,
            voucherNo: voucherNo,
            supplierName: sup,
            referenceNo: ref.isEmpty ? null : ref,
            amount: _grandTotal,
            note: notes.isEmpty ? null : notes,
            tenantId: tenantId,
            createdByUserName: currentUserName.isEmpty ? null : currentUserName,
          );
        }
        await _maybeCreateSupplierReturnPayout(
          voucherNo: voucherNo,
          supplierName: sup,
          amount: _grandTotal,
          tenantId: tenantId,
          createdByUserName: currentUserName.isEmpty ? null : currentUserName,
        );
        if (!mounted) return;
        await context.read<ProductProvider>().loadProducts();
        unawaited(context.read<NotificationProvider>().refresh());
      } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ السند #${res.voucherId} ($voucherNo)'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ar', 'SA'),
    );
    if (d != null) {
      setState(() => _selectedDate = d);
    }
  }

  void _addItem() => setState(() => _items.add(_VoucherItem()));
  void _removeItem(int i) {
    if (_items.length > 1) setState(() => _items.removeAt(i));
  }

  @override
  void dispose() {
    _referenceCtrl.dispose();
    _sourceNameCtrl.dispose();
    _sourceRefIdCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permissionKey: PermissionKeys.inventoryVoucherIn,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            backgroundColor: _kNavy,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'سند مخزوني',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: const CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Action bar ────────────────────────────────────────────
              _buildActionBar(),
              const Divider(height: 1, color: Color(0xFFD1D9E0)),
              // ── Scrollable form ───────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _buildVoucherDataPanel(),
                      const SizedBox(height: 12),
                      _buildWarehousePanel(),
                      const SizedBox(height: 12),
                      _buildSourcePanel(),
                      const SizedBox(height: 12),
                      _buildOtherInfoPanel(),
                      const SizedBox(height: 12),
                      _buildItemsTable(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Action bar ────────────────────────────────────────────────────────
  Widget _buildActionBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              _saving ? 'جاري الحفظ…' : 'تأكيد',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('إلغاء'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehousePanel() {
    if (!_metaLoaded) {
      return _panel(
        title: 'المخزن',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (_warehouses.isEmpty) {
      return _panel(
        title: 'المخزن',
        child: Text(
          'لا يوجد مخزن نشط. أضف مخزناً من «المخازن».',
          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
        ),
      );
    }
    if (_voucherType == 'إذن إضافة مخزن') {
      return _panel(
        title: 'المخزن المستقبل',
        child: _warehouseDropdown(
          _warehouseToId,
          (v) => setState(() => _warehouseToId = v),
        ),
      );
    }
    if (_voucherType == 'إذن صرف مخزن') {
      return _panel(
        title: 'من مخزن',
        child: _warehouseDropdown(
          _warehouseFromId,
          (v) => setState(() => _warehouseFromId = v),
        ),
      );
    }
    if (_voucherType == 'نقل بين مخازن') {
      return _panel(
        title: 'المخازن',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldCol(
              label: 'من مخزن',
              child: _warehouseDropdown(
                _warehouseFromId,
                (v) => setState(() => _warehouseFromId = v),
              ),
            ),
            const SizedBox(height: 12),
            _fieldCol(
              label: 'إلى مخزن',
              child: _warehouseDropdown(
                _warehouseToId,
                (v) => setState(() => _warehouseToId = v),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _warehouseDropdown(int? value, void Function(int?) onChanged) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          hint: const Text('اختر', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          items: [
            for (final w in _warehouses)
              DropdownMenuItem<int>(
                value: w['id'] as int,
                child: Text('${w['name']}'),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Section 1: بيانات الإذن المخزني ──────────────────────────────────
  Widget _buildVoucherDataPanel() {
    return _panel(
      title: 'بيانات الإذن المخزني',
      child: Row(
        children: [
          // نوع الأذن
          Expanded(
            child: _fieldCol(
              label: 'نوع الأذن',
              child: _dropdown(
                value: _voucherType,
                items: _voucherTypes,
                onChange: (v) => setState(() {
                  _voucherType = v!;
                  if (_warehouses.isNotEmpty) {
                    final a = _warehouses.first['id'] as int;
                    _warehouseFromId ??= a;
                    _warehouseToId ??= a;
                    if (_voucherType == 'نقل بين مخازن' &&
                        _warehouseFromId == _warehouseToId &&
                        _warehouses.length > 1) {
                      _warehouseToId = _warehouses[1]['id'] as int;
                    }
                  }
                }),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // التاريخ
          Expanded(
            child: _fieldCol(
              label: 'التاريخ',
              child: GestureDetector(
                onTap: _pickDate,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${DateFormat('HH:mm').format(_selectedDate)}  '
                          '${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2: بيانات المصدر ──────────────────────────────────────────
  Widget _buildSourcePanel() {
    return _panel(
      title: 'بيانات المصدر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Expanded(
                child: _fieldCol(
                  label: 'نوع المصدر',
                  child: _dropdown(
                    value: _sourceType,
                    items: _sourceTypes.keys.toList(),
                    hints: _sourceTypes.values.toList(),
                    onChange: (v) {
                      if (v == null) return;
                      setState(() {
                        _sourceType = v;
                        if (v == 'supplier') {
                          _sourceNameCtrl.text = _supplier;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _fieldCol(
                  label: 'مرجع المصدر (ID اختياري)',
                  child: TextFormField(
                    controller: _sourceRefIdCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec('مثال: 15'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _fieldCol(
            label: 'اسم المصدر',
            child: TextFormField(
              controller: _sourceNameCtrl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: _dec(
                _sourceType == 'supplier' ? 'اسم المورد' : 'اسم الجهة المصدر',
              ),
            ),
          ),
          const SizedBox(height: 12),
          // المرجع row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {},
                icon: Icon(
                  Icons.settings,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                tooltip: 'إعدادات المرجع',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              _label('المرجع'),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.zero,
            ),
            child: TextFormField(
              controller: _referenceCtrl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'رقم المرجع...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                suffixIcon: Icon(
                  Icons.link,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3: معلومات أخرى ───────────────────────────────────────────
  Widget _buildOtherInfoPanel() {
    return _panel(
      title: 'معلومات أخرى',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // المورد + الملاحظات
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _fieldCol(
                  label: 'المورد',
                  child: _dropdown(
                    value: _supplier,
                    items: _supplierItems,
                    hints: _supplierItems,
                    onChange: (v) => setState(() {
                      _supplier = v!;
                      if (_sourceType == 'supplier' &&
                          _sourceNameCtrl.text.trim().isEmpty) {
                        _sourceNameCtrl.text = _supplier;
                      }
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // الملاحظات
              Expanded(
                child: _fieldCol(
                  label: 'الملاحظات',
                  child: TextFormField(
                    controller: _notesCtrl,
                    textAlign: TextAlign.right,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(''),
                  ),
                ),
              ),
            ],
          ),
          if (_voucherType == 'إذن إضافة مخزن' &&
              _sourceType == 'supplier') ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إنشاء وصل مورد تلقائي وربطه بالسند'),
              subtitle: const Text(
                'يسجّل وصلاً في الذمم بنفس مبلغ السند ثم يربطه به.',
                style: TextStyle(fontSize: 12),
              ),
              value: _createSupplierBillOnInbound,
              onChanged: (v) =>
                  setState(() => _createSupplierBillOnInbound = v ?? true),
            ),
          ],
          if (_voucherType == 'إذن صرف مخزن' && _sourceType == 'supplier') ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تسجيل مرتجع المورد تلقائيًا في الذمم'),
              subtitle: const Text(
                'يسجّل دفعة مورد بدون صندوق لتخفيض الذمة عند صرف بضاعة كمردود.',
                style: TextStyle(fontSize: 12),
              ),
              value: _createSupplierReturnPayoutOnOutbound,
              onChanged: (v) => setState(
                () => _createSupplierReturnPayoutOnOutbound = v ?? true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Items Table ───────────────────────────────────────────────────────
  Widget _buildItemsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header row
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.zero,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // remove placeholder
                const SizedBox(width: 44),
                ..._colHeader('الإجمالي', flex: 2),
                ..._colHeader('الكمية', flex: 2),
                ..._colHeader('سعر الوحدة', flex: 2),
                ..._colHeader('البنود', flex: 3),
              ],
            ),
          ),

          // ── Item rows
          ...List.generate(_items.length, (i) => _buildItemRow(i)),

          // ── Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.zero,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 44),
                // grand total
                Expanded(
                  flex: 2,
                  child: Text(
                    _fmt.format(_grandTotal),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                ),
                const Spacer(flex: 4),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'الإجمالي',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Add row button
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addItem,
                icon: Icon(
                  Icons.add_circle_outline,
                  color: Colors.blue.shade700,
                  size: 18,
                ),
                label: Text(
                  'إضافة بند',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int i) {
    final item = _items[i];
    return Container(
      decoration: BoxDecoration(
        color: i.isOdd ? const Color(0xFFFAFCFF) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          // remove button
          SizedBox(
            width: 44,
            child: IconButton(
              onPressed: () => _removeItem(i),
              icon: Icon(
                Icons.remove_circle_outline,
                color: Colors.red.shade400,
                size: 20,
              ),
              tooltip: 'حذف البند',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          // الإجمالي (auto)
          Expanded(
            flex: 2,
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                item.qty > 0 && item.unitPrice > 0
                    ? _fmt.format(item.total)
                    : '',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E3A5F),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // الكمية
          Expanded(
            flex: 2,
            child: _editCell(
              item.qty > 0 ? item.qty.toString() : '',
              hint: 'الكمية',
              onChanged: (v) => setState(() => item.qty = int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 4),
          // سعر الوحدة
          Expanded(
            flex: 2,
            child: _editCell(
              item.unitPrice > 0 ? item.unitPrice.toString() : '',
              hint: 'سعر الوحدة',
              onChanged: (v) =>
                  setState(() => item.unitPrice = double.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 4),
          // البنود (picker + manual fallback)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.zero,
                    color: Colors.white,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: item.productId,
                      hint: const Text(
                        'اختر منتجاً',
                        style: TextStyle(fontSize: 11),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            'اختيار يدوي',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        ..._products.map(
                          (p) => DropdownMenuItem<int?>(
                            value: (p['id'] as num).toInt(),
                            child: Text(
                              p['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          item.productId = v;
                          if (v != null) {
                            final selected = _products.firstWhere(
                              (p) => (p['id'] as num).toInt() == v,
                            );
                            item.name = selected['name']?.toString() ?? '';
                            item.unitPrice =
                                (selected['purchasePrice'] as num?)
                                    ?.toDouble() ??
                                0;
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _editCell(
                  item.name,
                  hint: 'اسم البند اليدوي',
                  onChanged: (v) {
                    setState(() {
                      item.name = v;
                      if (v.trim().isNotEmpty) item.productId = null;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────
  List<Widget> _colHeader(String text, {int flex = 2}) => [
    Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
      ),
    ),
  ];

  Widget _editCell(
    String initial, {
    String hint = '',
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
        color: Colors.white,
      ),
      child: TextFormField(
        initialValue: initial,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _fieldCol({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _label(label),
            if (required) ...[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: Color(0xFF374151),
    ),
  );

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: _kNavy, width: 1.5),
    ),
  );

  Widget _dropdown({
    required String value,
    required List<String> items,
    List<String>? hints,
    required ValueChanged<String?> onChange,
  }) {
    final labels = hints ?? items;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          items: List.generate(
            items.length,
            (i) => DropdownMenuItem(
              value: items[i],
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  color: items[i].isEmpty
                      ? Colors.grey.shade500
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          onChanged: onChange,
        ),
      ),
    );
  }
}

// ── Item model ────────────────────────────────────────────────────────────
class _VoucherItem {
  int? productId;
  String name = '';
  double unitPrice = 0;
  int qty = 0;

  double get total => unitPrice * qty;
}
