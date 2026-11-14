import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../guides/guide_anchor.dart';
import '../models/oil_change_oil_catalog_entry.dart';
import '../services/oil_change_oil_catalog_repository.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../utils/oil_field_select_all.dart';
import 'oil_change_catalog_sheet_frame.dart';
import 'oil_change_royal_card.dart';
import '../../../widgets/oil_variants/oil_grade_draft.dart';

/// [manageOnly]: إدارة الكتالوج فقط (إضافة أصناف) دون اختيار للبطاقة.
Future<OilChangeOilCatalogPick?> showOilChangeOilCatalogSheet(
  BuildContext context, {
  bool manageOnly = false,
  String? initialBrandName,
}) {
  return showModalBottomSheet<OilChangeOilCatalogPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    enableDrag: false,
    showDragHandle: true,
    builder: (ctx) => _OilChangeOilCatalogSheetBody(
      manageOnly: manageOnly,
      initialBrandName: initialBrandName,
    ),
  );
}

class _OilChangeOilCatalogSheetBody extends StatefulWidget {
  const _OilChangeOilCatalogSheetBody({
    this.manageOnly = false,
    this.initialBrandName,
  });

  final bool manageOnly;
  final String? initialBrandName;

  @override
  State<_OilChangeOilCatalogSheetBody> createState() =>
      _OilChangeOilCatalogSheetBodyState();
}

class _OilChangeOilCatalogSheetBodyState
    extends State<_OilChangeOilCatalogSheetBody> {
  static const _gold = SaleBrandColors.gold;

  bool _loading = true;
  Object? _error;
  List<OilChangeOilCatalogEntry> _entries = const [];
  bool _adding = false;
  /// بعد أول حفظ أو اختيار ماركة من القائمة — يُبقى الاسم لإضافة لزوجات أخرى.
  bool _brandLocked = false;
  int? _editingId;

  final _brandCtrl = TextEditingController();
  final _viscosityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _brandFocus = FocusNode();
  final _viscosityFocus = FocusNode();
  final _priceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    oilAttachSelectAllOnFocus(_brandFocus, _brandCtrl);
    oilAttachSelectAllOnFocus(_viscosityFocus, _viscosityCtrl);
    _priceFocus.addListener(_onPriceFocusChanged);
    if (widget.manageOnly) {
      _adding = true;
    } else {
      final seed = widget.initialBrandName?.trim();
      if (seed != null && seed.isNotEmpty) {
        _brandCtrl.text = seed;
        _brandLocked = true;
        _adding = true;
      }
    }
    unawaited(_load());
  }

  void _onPriceFocusChanged() {
    if (!_priceFocus.hasFocus) return;
    _reformatPriceField();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_priceFocus.hasFocus) return;
      selectAllOilFieldText(_priceCtrl);
    });
  }

  void _reformatPriceField() {
    final n = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final formatted = n <= 0 ? '' : IraqiCurrencyFormat.formatInt(n);
    if (_priceCtrl.text == formatted) return;
    _priceCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  void dispose() {
    _priceFocus.removeListener(_onPriceFocusChanged);
    _brandFocus.dispose();
    _viscosityFocus.dispose();
    _priceFocus.dispose();
    _brandCtrl.dispose();
    _viscosityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await OilChangeOilCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Map<String, List<OilChangeOilCatalogEntry>> get _byBrand {
    final m = <String, List<OilChangeOilCatalogEntry>>{};
    for (final e in _entries) {
      m.putIfAbsent(e.brandName, () => []).add(e);
    }
    return m;
  }

  Future<void> _saveNew() async {
    final brand = _brandCtrl.text.trim();
    final vis = _viscosityCtrl.text.trim();
    final priceDinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final priceFils = IqdMoney.toFils(priceDinars.toDouble());
    if (brand.isEmpty || vis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الزيت واللزوجة')),
      );
      return;
    }
    if (priceFils <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل سعر البيع للتر')),
      );
      return;
    }
    final visKey = normalizeOilViscosityKey(vis);
    final editingId = _editingId;
    if (editingId == null &&
        _entries.any(
          (e) =>
              e.brandName.toLowerCase() == brand.toLowerCase() &&
              normalizeOilViscosityKey(e.viscosity) == visKey,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نفس الماركة ونفس اللزوجة موجودة — عدّلها من القائمة أو غيّر اللزوجة',
          ),
        ),
      );
      return;
    }
    try {
      if (editingId != null) {
        await OilChangeOilCatalogRepository.instance.updateById(
          id: editingId,
          brandName: brand,
          viscosity: visKey,
          sellPerLiterFils: priceFils,
        );
      } else {
        await OilChangeOilCatalogRepository.instance.insert(
          brandName: brand,
          viscosity: visKey,
          sellPerLiterFils: priceFils,
        );
      }
      if (!mounted) return;
      final wasEdit = editingId != null;
      _viscosityCtrl.clear();
      _priceCtrl.clear();
      setState(() {
        _editingId = null;
        _brandLocked = true;
        _adding = true;
      });
      await _load(silent: true);
      if (!mounted) return;
      _viscosityFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEdit
                ? 'تم تحديث $visKey لـ $brand'
                : 'تمت إضافة $visKey لـ $brand — يمكنك إضافة لزوجة أخرى',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_brand_viscosity'
          ? 'نفس الماركة ونفس اللزوجة موجودة مسبقاً'
          : 'تعذّر الحفظ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ')),
      );
    }
  }

  void _beginAddForBrand(String brandName) {
    setState(() {
      _editingId = null;
      _brandCtrl.text = brandName;
      _brandLocked = true;
      _adding = true;
      _viscosityCtrl.clear();
      _priceCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viscosityFocus.requestFocus();
    });
  }

  void _beginEdit(OilChangeOilCatalogEntry e) {
    setState(() {
      _editingId = e.id;
      _brandCtrl.text = e.brandName;
      _brandLocked = true;
      _adding = true;
      _viscosityCtrl.text = e.viscosity;
      _priceCtrl.text = IraqiCurrencyFormat.formatInt(
        IqdMoney.fromFils(e.sellPerLiterFils).round(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _priceFocus.requestFocus();
    });
  }

  void _unlockBrand() {
    setState(() {
      _editingId = null;
      _brandLocked = false;
      _brandCtrl.clear();
      _viscosityCtrl.clear();
      _priceCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _brandFocus.requestFocus();
    });
  }

  Future<void> _delete(OilChangeOilCatalogEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف؟'),
        content: Text('«${e.brandName} · ${e.viscosity}» لن يظهر في القوائم الجديدة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OilChangeOilCatalogRepository.instance.softDeleteById(e.id);
    if (!mounted) return;
    if (_editingId == e.id) {
      setState(() {
        _editingId = null;
        _viscosityCtrl.clear();
        _priceCtrl.clear();
      });
    }
    await _load(silent: true);
  }

  List<OilChangeOilCatalogEntry> _entriesForLockedBrand() {
    final b = _brandCtrl.text.trim();
    if (b.isEmpty) return const [];
    return OilChangeOilCatalogRepository.entriesForBrand(_entries, b);
  }

  void _pickViscosityChip(String v) {
    _viscosityCtrl.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    _priceFocus.requestFocus();
  }

  void _pick(OilChangeOilCatalogEntry e) {
    Navigator.pop(
      context,
      OilChangeOilCatalogPick(
        brandName: e.brandName,
        viscosity: e.viscosity,
        sellPerLiterFils: e.sellPerLiterFils,
        catalogEntryId: e.id,
      ),
    );
  }

  Widget _entryActions(OilChangeOilCatalogEntry e) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () => _beginEdit(e),
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          onPressed: () => unawaited(_delete(e)),
        ),
        if (!widget.manageOnly)
          Icon(
            Icons.check_circle_outline,
            color: _gold,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return OilChangeCatalogSheetFrame(
      title: 'كتالوج الزيت واللزوجات',
      icon: Icons.opacity_rounded,
      titleGuideAnchor: (row) => GuideAnchor(
        id: OilGuideAnchors.catalogOilTitle,
        child: row,
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 16),
              children: [
                Text(
                  widget.manageOnly
                      ? 'اكتب اسم الزيت مرة واحدة، ثم أضف عدة لزوجات بسعر كل لزوجة. يمكن تعديل أو حذف أي صنف من القائمة.'
                      : 'اختر صنفاً للبطاقة، أو أضف/عدّل أصنافاً من النموذج أعلاه.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: GuideAnchor(
                    id: OilGuideAnchors.catalogOilAdd,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() {
                          if (_adding) {
                            _adding = false;
                            _editingId = null;
                          } else {
                            _adding = true;
                          }
                        });
                        if (_adding) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            (_brandLocked ? _viscosityFocus : _brandFocus)
                                .requestFocus();
                          });
                        }
                      },
                      icon: Icon(
                        _adding ? Icons.expand_less : Icons.add_rounded,
                      ),
                      label: Text(
                        _adding
                            ? (_editingId != null
                                ? 'إخفاء التعديل'
                                : 'إخفاء الإضافة')
                            : 'إضافة زيت / لزوجة',
                      ),
                    ),
                  ),
                ),
                if (_adding) ...[
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: ValueKey('oil_catalog_form_${_editingId ?? 'new'}'),
                    child: _buildAddForm(cs),
                  ),
                ],
                const SizedBox(height: 10),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'تعذّر تحميل الكتالوج',
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                  )
                else if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'لا توجد أصناف بعد. أضف أول ماركة ولزوجة.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  for (final entry in _byBrand.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: cs.primary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _beginAddForBrand(entry.key),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('لزوجة'),
                          ),
                        ],
                      ),
                    ),
                    for (final e in entry.value)
                      OilChangeRoyalCard.listTileCard(
                        context: context,
                        cs: cs,
                        onTap: widget.manageOnly ? null : () => _pick(e),
                        child: ListTile(
                          title: Text(
                            e.viscosity,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(e.sellPerLiterFils))} / لتر',
                            textAlign: TextAlign.start,
                          ),
                          trailing: _entryActions(e),
                        ),
                      ),
                  ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildAddForm(ColorScheme cs) {
    final existing = _entriesForLockedBrand()
        .where((e) => e.id != _editingId)
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: OilChangeCatalogSheetFrame.addFormDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_editingId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'تعديل صنف موجود',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.start,
              ),
            ),
          if (_brandLocked) ...[
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'اسم الزيت (ثابت)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _brandCtrl.text.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  TextButton(
                    onPressed: _unlockBrand,
                    child: const Text('اسم جديد'),
                  ),
                ],
              ),
            ),
          ] else
            TextField(
              controller: _brandCtrl,
              focusNode: _brandFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _viscosityFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'اسم / ماركة الزيت',
                border: OutlineInputBorder(),
                hintText: 'faza، موبيل 1…',
                helperMaxLines: 2,
                helperText:
                    'بعد الحفظ يبقى الاسم ثابتاً لإضافة لزوجات أخرى بسهولة',
                isDense: true,
              ),
              textAlign: TextAlign.start,
            ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'لزوجات مسجّلة لهذا الاسم:',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: existing
                  .map(
                    (e) => Chip(
                      label: Text(e.viscosity),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _viscosityCtrl,
            focusNode: _viscosityFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _priceFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'اللزوجة',
              border: OutlineInputBorder(),
              hintText: '5W30',
              isDense: true,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kCommonOilViscosities
                .map(
                  (v) => ActionChip(
                    label: Text(v),
                    visualDensity: VisualDensity.compact,
                    onPressed: existing.any(
                      (e) =>
                          normalizeOilViscosityKey(e.viscosity) ==
                          normalizeOilViscosityKey(v),
                    )
                        ? null
                        : () => _pickViscosityChip(v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            focusNode: _priceFocus,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_saveNew()),
            onTap: () {
              _reformatPriceField();
              selectAllOilFieldText(_priceCtrl);
            },
            inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'سعر البيع / لتر (د.ع)',
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'مثال: 30,000',
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => unawaited(_saveNew()),
            icon: Icon(
              _editingId != null ? Icons.check_rounded : Icons.save_rounded,
            ),
            label: Text(
              _editingId != null
                  ? 'حفظ التعديل'
                  : (_brandLocked ? 'إضافة اللزوجة' : 'حفظ الاسم واللزوجة'),
            ),
          ),
        ],
      ),
    );
  }
}
