import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/notification_provider.dart';
import '../../services/product_repository.dart';
import '../../theme/app_corner_style.dart';

class _VariantEditRow {
  _VariantEditRow({
    required this.variantId,
    required this.isDefault,
  })  : unitName = TextEditingController(),
        unitSymbol = TextEditingController(),
        factor = TextEditingController(),
        barcode = TextEditingController(),
        sell = TextEditingController(),
        minSell = TextEditingController();

  final int variantId;
  final bool isDefault;

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

class _NewUnitVariantDraft {
  _NewUnitVariantDraft()
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

class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final ProductRepository _repo = ProductRepository();

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _buy = TextEditingController();
  final _sell = TextEditingController();
  final _minSell = TextEditingController();
  final _qty = TextEditingController();
  final _low = TextEditingController();

  bool _track = true;
  bool _loading = true;
  bool _saving = false;
  int _stockBaseKind = 0;
  bool _variantsLoading = false;
  final List<_VariantEditRow> _variantRows = [];
  final List<_NewUnitVariantDraft> _newVariantDrafts = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _buy.dispose();
    _sell.dispose();
    _minSell.dispose();
    _qty.dispose();
    _low.dispose();
    for (final r in _variantRows) {
      r.dispose();
    }
    for (final r in _newVariantDrafts) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final p = await _repo.getProductDetailsById(widget.productId);
    if (!mounted) return;
    if (p == null) {
      setState(() => _loading = false);
      return;
    }
    double dnum(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    _name.text = (p['name']?.toString() ?? '').trim();
    _barcode.text = (p['barcode']?.toString() ?? '').trim();
    _buy.text = dnum(p['buyPrice']).toStringAsFixed(0);
    _sell.text = dnum(p['sellPrice']).toStringAsFixed(0);
    _minSell.text = dnum(p['minSellPrice']).toStringAsFixed(0);
    _qty.text = dnum(p['qty']).toStringAsFixed(0);
    _low.text = dnum(p['lowStockThreshold']).toStringAsFixed(0);
    _track = ((p['trackInventory'] as num?)?.toInt() ?? 1) == 1;
    _stockBaseKind = (p['stockBaseKind'] as num?)?.toInt() ?? 0;

    setState(() => _variantsLoading = true);
    try {
      final vs = await _repo.listActiveUnitVariantsForProduct(widget.productId);
      if (!mounted) return;
      for (final r in _variantRows) {
        r.dispose();
      }
      _variantRows.clear();
      for (final m in vs) {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final isDef = ((m['isDefault'] as num?)?.toInt() ?? 0) == 1;
        final row = _VariantEditRow(variantId: id, isDefault: isDef);
        row.unitName.text = (m['unitName'] ?? '').toString();
        row.unitSymbol.text = (m['unitSymbol'] ?? '').toString();
        row.factor.text = ((m['factorToBase'] as num?)?.toDouble() ?? 1.0)
            .toString()
            .replaceAll(',', '.');
        row.barcode.text = (m['barcode'] ?? '').toString();
        final sp = m['sellPrice'];
        final mp = m['minSellPrice'];
        if (sp is num) row.sell.text = sp.toString();
        if (mp is num) row.minSell.text = mp.toString();
        _variantRows.add(row);
      }
    } catch (_) {
      for (final r in _variantRows) {
        r.dispose();
      }
      _variantRows.clear();
    } finally {
      if (mounted) {
        setState(() {
          _variantsLoading = false;
          _loading = false;
        });
      }
    }
  }

  double _parseMoney(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '');
    return double.tryParse(t) ?? 0.0;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    for (final row in _newVariantDrafts) {
      final unit = row.unitName.text.trim();
      if (unit.isEmpty) continue;
      final f = double.tryParse(row.factor.text.trim().replaceAll(',', '.')) ?? 0;
      if (!(f > 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('عامل التحويل يجب أن يكون أكبر من 0 لكل وحدة جديدة.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final buy = _parseMoney(_buy);
      final sell = _parseMoney(_sell);
      final minSell = _parseMoney(_minSell);
      final qty = _parseMoney(_qty);
      final low = _parseMoney(_low);
      await _repo.updateProductBasic(
        productId: widget.productId,
        name: _name.text,
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        buyPrice: buy,
        sellPrice: sell,
        minSellPrice: minSell,
        qty: qty,
        lowStockThreshold: low,
        trackInventory: _track,
        stockBaseKind: _stockBaseKind,
      );

      for (final r in _variantRows) {
        if (r.isDefault) continue;
        final f = double.tryParse(r.factor.text.trim().replaceAll(',', '.')) ?? 0;
        if (!(f > 0)) {
          throw StateError('bad_unit_factor');
        }
        final bc = r.barcode.text.trim();
        final s = r.sell.text.trim();
        final ms = r.minSell.text.trim();
        await _repo.updateProductUnitVariant(
          id: r.variantId,
          unitName: r.unitName.text.trim(),
          unitSymbol: r.unitSymbol.text.trim(),
          factorToBase: f,
          barcode: bc,
          sellPrice: s.isEmpty ? null : double.tryParse(s.replaceAll(',', '.')),
          minSellPrice: ms.isEmpty ? null : double.tryParse(ms.replaceAll(',', '.')),
        );
      }

      for (final row in _newVariantDrafts) {
        final unit = row.unitName.text.trim();
        if (unit.isEmpty) continue;
        final f = double.tryParse(row.factor.text.trim().replaceAll(',', '.')) ?? 0;
        final bc = row.barcode.text.trim();
        final s = row.sell.text.trim();
        final ms = row.minSell.text.trim();
        await _repo.insertProductUnitVariant(
          productId: widget.productId,
          unitName: unit,
          unitSymbol:
              row.unitSymbol.text.trim().isEmpty ? null : row.unitSymbol.text.trim(),
          factorToBase: f,
          barcode: bc.isEmpty ? null : bc,
          sellPrice: s.isEmpty ? null : double.tryParse(s.replaceAll(',', '.')),
          minSellPrice: ms.isEmpty ? null : double.tryParse(ms.replaceAll(',', '.')),
          isDefault: false,
        );
      }
      if (!mounted) return;
      unawaited(context.read<NotificationProvider>().refresh());
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('duplicate_barcode')
          ? 'الباركود مستخدم لمنتج/وحدة أخرى'
          : (e is StateError && e.message == 'bad_unit_factor')
              ? 'عامل التحويل يجب أن يكون أكبر من 0'
              : 'تعذر حفظ التعديلات';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text('تعديل المنتج', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: ac.md,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _field(
                            label: 'اسم المنتج',
                            controller: _name,
                            hint: 'مثال: سكر 1 كغم',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الاسم مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            label: 'الباركود (اختياري)',
                            controller: _barcode,
                            hint: 'SEED-...',
                            keyboard: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            value: _track,
                            onChanged: (v) => setState(() => _track = v),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تتبع المخزون', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              _track ? 'يحسب الكمية والتنبيه منخفض' : 'الكمية تُصبح 0 ولا تظهر تنبيهات مخزون',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: ac.md,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('التسعير', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  label: 'سعر البيع',
                                  controller: _sell,
                                  hint: '0',
                                  keyboard: TextInputType.number,
                                  validator: (v) => (_parseMoney(_sell) <= 0)
                                      ? 'أدخل سعر بيع'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  label: 'سعر الشراء',
                                  controller: _buy,
                                  hint: '0',
                                  keyboard: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _field(
                            label: 'الحد الأدنى للبيع',
                            controller: _minSell,
                            hint: '0',
                            keyboard: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: ac.md,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'نوع المخزون الأساسي',
                            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            value: _stockBaseKind,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('عدد (قطعة كأساس)')),
                              DropdownMenuItem(value: 1, child: Text('وزن (كيلوغرام كأساس)')),
                            ],
                            onChanged: (v) => setState(() => _stockBaseKind = v ?? 0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: ac.md,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'وحدات البيع والباركود',
                            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'الوحدة الافتراضية تُدار تلقائياً مع المنتج؛ يمكنك تعديل الوحدات الإضافية أو إضافة وحدة جديدة.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                          ),
                          const SizedBox(height: 10),
                          if (_variantsLoading)
                            const Center(child: Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(),
                            ))
                          else ...[
                            for (final r in _variantRows) ...[
                              if (r.isDefault)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('الوحدة الافتراضية', style: TextStyle(fontWeight: FontWeight.w900)),
                                  subtitle: Text(
                                    '${r.unitName.text.trim()} — عامل ${r.factor.text.trim()}',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                )
                              else ...[
                                Text('وحدة #${r.variantId}', style: const TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.unitName,
                                        textAlign: TextAlign.right,
                                        decoration: const InputDecoration(
                                          labelText: 'اسم الوحدة',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.unitSymbol,
                                        textAlign: TextAlign.right,
                                        decoration: const InputDecoration(
                                          labelText: 'رمز',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.factor,
                                        textAlign: TextAlign.right,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'عامل التحويل إلى الأساس',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.barcode,
                                        textAlign: TextAlign.right,
                                        decoration: const InputDecoration(
                                          labelText: 'باركود (اختياري)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.sell,
                                        textAlign: TextAlign.right,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'سعر بيع الوحدة (اختياري)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: r.minSell,
                                        textAlign: TextAlign.right,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'أدنى سعر (اختياري)',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _newVariantDrafts.add(_NewUnitVariantDraft())),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة وحدة جديدة'),
                              ),
                            ),
                            for (final n in _newVariantDrafts) ...[
                              const SizedBox(height: 10),
                              Material(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: ac.sm,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text('وحدة جديدة', style: TextStyle(fontWeight: FontWeight.w900)),
                                          ),
                                          IconButton(
                                            tooltip: 'إلغاء',
                                            onPressed: () => setState(() {
                                              final idx = _newVariantDrafts.indexOf(n);
                                              if (idx >= 0) {
                                                final r = _newVariantDrafts.removeAt(idx);
                                                r.dispose();
                                              }
                                            }),
                                            icon: const Icon(Icons.close, color: Colors.red),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.unitName,
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                labelText: 'اسم الوحدة',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.unitSymbol,
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                labelText: 'رمز',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.factor,
                                              textAlign: TextAlign.right,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                              ],
                                              decoration: const InputDecoration(
                                                labelText: 'عامل التحويل إلى الأساس',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.barcode,
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                labelText: 'باركود (اختياري)',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.sell,
                                              textAlign: TextAlign.right,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'سعر بيع الوحدة (اختياري)',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: n.minSell,
                                              textAlign: TextAlign.right,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'أدنى سعر (اختياري)',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: ac.md,
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('المخزون', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  label: 'الكمية',
                                  controller: _qty,
                                  hint: '0',
                                  keyboard: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  label: 'حد التنبيه منخفض',
                                  controller: _low,
                                  hint: '0',
                                  keyboard: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: const Text('حفظ التعديلات'),
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

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboard,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            border: OutlineInputBorder(borderRadius: ac.sm, borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

