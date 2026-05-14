import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/notification_provider.dart';
import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../services/product_variants_repository.dart';
import '../../services/product_variants_sql_ops.dart';
import '../../services/tenant_context.dart';
import '../../utils/color_name_ar.dart';
import '../../widgets/app_color_picker_dialog.dart';
import '../../widgets/variants/variant_size_picker_sheet.dart';
import '../../theme/app_corner_style.dart';
import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';

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

class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final ProductRepository _repo = ProductRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper();

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
  int _stockTypeUi = 0; // 0 عدد | 1 وزن | 2 ملابس (ألوان ومقاسات)
  bool _variantsLoading = false;
  final List<_VariantEditRow> _variantRows = [];
  final List<_NewUnitVariantDraft> _newVariantDrafts = [];

  bool _multiVariantEnabled = false;
  final List<_VariantColorDraft> _colorDrafts = [];
  bool _enableWeightSales = true;
  bool _enableClothingVariants = false;

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
    for (final c in _colorDrafts) {
      c.dispose();
    }
    super.dispose();
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

  Future<void> _bootstrap() async {
    try {
      final biz = await BusinessSetupSettingsData.load(AppSettingsRepository.instance);
      _enableWeightSales = biz.enableWeightSales;
      _enableClothingVariants = biz.enableClothingVariants;
    } catch (_) {}
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
    _stockTypeUi = _stockBaseKind;

    // Load color+size variants (new system)
    try {
      final db = await _dbHelper.database;
      final tid = int.tryParse(TenantContext.instance.requireTenantId()) ?? 0;
      final colors =
          await ProductVariantsSqlOps.listColorsForProduct(db, tid, widget.productId);
      final variants =
          await ProductVariantsSqlOps.listVariantsForProduct(db, tid, widget.productId);

      for (final c in _colorDrafts) {
        c.dispose();
      }
      _colorDrafts.clear();

      final draftByColorId = <int, _VariantColorDraft>{};
      for (final row in colors) {
        final id = (row['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final d = _VariantColorDraft(
          name: (row['name'] ?? '').toString(),
          hex: (row['hexCode'] ?? '').toString(),
        );
        draftByColorId[id] = d;
        _colorDrafts.add(d);
      }
      for (final v in variants) {
        final colorId = (v['colorId'] as num?)?.toInt() ?? 0;
        final cd = draftByColorId[colorId];
        if (cd == null) continue;
        cd.sizes.add(
          _VariantSizeDraft(
            size: (v['size'] ?? '').toString(),
            qty: (v['quantity'] as num?)?.toInt() ?? 0,
            barcode: (v['barcode'] ?? '').toString(),
          ),
        );
      }
      _multiVariantEnabled = _colorDrafts.isNotEmpty;
      if (_multiVariantEnabled) {
        _track = true;
      }
      _stockTypeUi = _multiVariantEnabled ? 2 : _stockBaseKind;
    } catch (_) {
      // ignore: fallback to no-variants UI
    }

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

  String? _validateVariantDrafts() {
    if (!_multiVariantEnabled) return null;
    if (_colorDrafts.isEmpty) return 'أضف لوناً واحداً على الأقل.';

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

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final variantErr = _validateVariantDrafts();
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
      final qty = _multiVariantEnabled ? 0.0 : _parseMoney(_qty);
      final low = _multiVariantEnabled ? 0.0 : _parseMoney(_low);
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

      if (_multiVariantEnabled) {
        final db = await _dbHelper.database;
        final tid = int.tryParse(TenantContext.instance.requireTenantId()) ?? 0;
        await db.transaction((txn) async {
          // (1) soft-delete existing variants & colors for product
          final existingColors =
              await ProductVariantsSqlOps.listColorsForProduct(txn, tid, widget.productId);
          final existingVars =
              await ProductVariantsSqlOps.listVariantsForProduct(txn, tid, widget.productId);
          for (final v in existingVars) {
            final id = (v['id'] as num?)?.toInt() ?? 0;
            if (id > 0) {
              await ProductVariantsSqlOps.softDeleteVariant(txn, tid, id);
            }
          }
          for (final c in existingColors) {
            final id = (c['id'] as num?)?.toInt() ?? 0;
            if (id > 0) {
              await ProductVariantsSqlOps.softDeleteColor(txn, tid, id);
            }
          }

          // (2) insert new colors + variants (same transaction)
          final now = DateTime.now().toUtc().toIso8601String();
          for (var colorIndex = 0; colorIndex < _colorDrafts.length; colorIndex++) {
            final c = _colorDrafts[colorIndex];
            final name = c.nameCtrl.text.trim();
            final hex = c.hexCtrl.text.trim();
            final colorId = await ProductVariantsSqlOps.insertColor(txn, tid, {
              'productId': widget.productId,
              'name': name,
              'hexCode': hex.isEmpty ? null : hex,
              'sortOrder': colorIndex,
              'createdAt': now,
              'updatedAt': now,
            });
            for (final s in c.sizes) {
              final size = s.sizeCtrl.text.trim();
              final q = _parseNonNegativeInt(s.qtyCtrl.text);
              final bc = s.barcodeCtrl.text.trim().toUpperCase();
              if (bc.isNotEmpty) {
                // ensure tenant-scoped uniqueness for variants
                final taken = await ProductVariantsSqlOps.isBarcodeTakenInTenant(
                  txn,
                  tid,
                  bc,
                );
                if (taken) throw StateError('duplicate_variant_barcode');
                // ensure global uniqueness against products + unit variants
                if (await _repo.isBarcodeTakenAnywhere(
                  bc,
                  excludeProductId: widget.productId,
                  executor: txn,
                )) {
                  throw StateError('duplicate_barcode');
                }
              }
              final sku = ProductVariantsRepository.buildSku(
                productId: widget.productId,
                colorIndex: colorIndex,
                size: size,
              );
              await ProductVariantsSqlOps.insertVariant(txn, tid, {
                'productId': widget.productId,
                'colorId': colorId,
                'size': size,
                'quantity': q,
                'barcode': bc.isEmpty ? null : bc,
                'sku': sku,
                'createdAt': now,
                'updatedAt': now,
              });
            }
          }
        });
      }

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
          : e.toString().contains('duplicate_variant_barcode')
              ? 'باركود المتغير مستخدم مسبقاً'
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
    final ac = context.appCorners;

    Future<void> pickColorFor(_VariantColorDraft c) async {
      final current = parseFlexibleHexColor(c.hexCtrl.text) ?? cs.primary;
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

      return Material(
        color: cs.surface,
        borderRadius: ac.md,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: ac.md,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
          ),
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
                        fontWeight: FontWeight.w900,
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
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 760),
                              child: list,
                            ),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الألوان والمقاسات',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                'الإجمالي: ${_totalQtyAllVariants()}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _colorDrafts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => colorCard(_colorDrafts[i]),
            ),
        ],
      ),
    );
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
                            onChanged: _multiVariantEnabled
                                ? null
                                : (v) => setState(() => _track = v),
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
                            value: _stockTypeUi,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: 0, child: Text('عدد (قطعة كأساس)')),
                              if (_enableWeightSales || _stockTypeUi == 1)
                                const DropdownMenuItem(value: 1, child: Text('وزن (كيلوغرام كأساس)')),
                              if (_enableClothingVariants || _stockTypeUi == 2)
                                const DropdownMenuItem(
                                  value: 2,
                                  child: Text('ملابس (ألوان ومقاسات)'),
                                ),
                            ],
                            onChanged: (v) {
                              final next = v ?? 0;
                              setState(() {
                                _stockTypeUi = next;
                                if (next == 2) {
                                  _multiVariantEnabled = true;
                                  _track = true;
                                  _stockBaseKind = 0;
                                  if (_colorDrafts.isEmpty) {
                                    final c = _VariantColorDraft();
                                    c.sizes.add(_VariantSizeDraft());
                                    _colorDrafts.add(c);
                                  }
                                } else {
                                  _multiVariantEnabled = false;
                                  _stockBaseKind = next;
                                }
                              });
                            },
                          ),
                          if (_stockTypeUi == 2) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'الألوان والمقاسات',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                    ),
                                    textAlign: TextAlign.start,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _variantsSummaryLine(),
                                    style: TextStyle(color: cs.onSurfaceVariant),
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
                          if (_multiVariantEnabled)
                            Text(
                              'المخزون يُدار عبر الألوان والمقاسات. الإجمالي الحالي: ${_totalQtyAllVariants()}',
                              textAlign: TextAlign.end,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            )
                          else
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

