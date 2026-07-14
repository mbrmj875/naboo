import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/oil_change_oil_catalog_entry.dart';
import '../services/oil_change_oil_catalog_repository.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
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
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: _OilChangeOilCatalogSheetBody(
        manageOnly: manageOnly,
        initialBrandName: initialBrandName,
      ),
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

  final _brandCtrl = TextEditingController();
  final _viscosityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _brandFocus = FocusNode();
  final _viscosityFocus = FocusNode();
  final _priceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
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
    for (final node in [_brandFocus, _viscosityFocus, _priceFocus]) {
      node.addListener(() {
        if (node.hasFocus) _ensureFieldVisible(node);
      });
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _brandFocus.dispose();
    _viscosityFocus.dispose();
    _priceFocus.dispose();
    _brandCtrl.dispose();
    _viscosityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _ensureFieldVisible(FocusNode node) {
    Future<void> scroll() async {
      if (!mounted || !node.hasFocus) return;
      final target = node.context;
      if (target == null) return;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.08,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(scroll());
      Future<void>.delayed(const Duration(milliseconds: 120), scroll);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await OilChangeOilCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
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
    if (_entries.any(
      (e) =>
          e.brandName.toLowerCase() == brand.toLowerCase() &&
          normalizeOilViscosityKey(e.viscosity) == visKey,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نفس الماركة ونفس اللزوجة موجودة — اخترها من القائمة أو غيّر اللزوجة',
          ),
        ),
      );
      return;
    }
    try {
      await OilChangeOilCatalogRepository.instance.insert(
        brandName: brand,
        viscosity: visKey,
        sellPerLiterFils: priceFils,
      );
      _viscosityCtrl.clear();
      _priceCtrl.clear();
      if (!mounted) return;
      setState(() {
        _brandLocked = true;
        _adding = true;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إضافة $visKey لـ $brand — يمكنك إضافة لزوجة أخرى لنفس الاسم',
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
      _brandCtrl.text = brandName;
      _brandLocked = true;
      _adding = true;
      _viscosityCtrl.clear();
      _priceCtrl.clear();
    });
  }

  void _unlockBrand() {
    setState(() {
      _brandLocked = false;
      _brandCtrl.clear();
      _viscosityCtrl.clear();
      _priceCtrl.clear();
    });
  }

  List<OilChangeOilCatalogEntry> _entriesForLockedBrand() {
    final b = _brandCtrl.text.trim();
    if (b.isEmpty) return const [];
    return OilChangeOilCatalogRepository.entriesForBrand(_entries, b);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final maxH = screenH * 0.92;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12 + bottom),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.opacity_rounded, color: _gold, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'كتالوج الزيت واللزوجات',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: _scrollCtrl,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        Text(
                          widget.manageOnly
                              ? 'اكتب اسم الزيت مرة واحدة، ثم أضف عدة لزوجات بسعر كل لزوجة. الاختيار في البطاقة من القوائم فقط.'
                              : 'اختر صنفاً للبطاقة، أو أضف اسم زيت ثم لزوجات متعددة بأسعارها.',
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
                          child: FilledButton.tonalIcon(
                            onPressed: () => setState(() => _adding = !_adding),
                            icon: Icon(
                              _adding ? Icons.expand_less : Icons.add_rounded,
                            ),
                            label: Text(
                              _adding ? 'إخفاء الإضافة' : 'إضافة زيت / لزوجة',
                            ),
                          ),
                        ),
                        if (_adding) ...[
                          const SizedBox(height: 8),
                          _buildAddForm(cs),
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
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 4,
                              ),
                              child: InkWell(
                                onTap: widget.manageOnly
                                    ? () => _beginAddForBrand(entry.key)
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
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
                                      if (widget.manageOnly)
                                        TextButton.icon(
                                          onPressed: () =>
                                              _beginAddForBrand(entry.key),
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('لزوجة'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            for (final e in entry.value)
                              OilChangeRoyalCard.listTileCard(
                                cs: cs,
                                onTap: widget.manageOnly
                                    ? null
                                    : () => _pick(e),
                                child: ListTile(
                                  title: Text(
                                    e.viscosity,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(e.sellPerLiterFils))} / لتر',
                                    textAlign: TextAlign.start,
                                  ),
                                  trailing: widget.manageOnly
                                      ? null
                                      : Icon(
                                          Icons.check_circle_outline,
                                          color: _gold,
                                        ),
                                ),
                              ),
                          ],
                        SizedBox(height: viewInsets > 0 ? 120 : 8),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddForm(ColorScheme cs) {
    final existing = _entriesForLockedBrand();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: OilChangeRoyalCard.decoration(
        cs,
        radius: 12,
        backgroundColor: _gold.withValues(alpha: 0.06),
        borderAlpha: 0.72,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_brandLocked) ...[
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'اسم الزيت (ثابت)',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'اسم / ماركة الزيت',
                border: OutlineInputBorder(),
                hintText: 'faza، موبيل 1…',
                helperText: 'يُحفظ الاسم عند أول لزوجة — ثم تضيف لزوجات أخرى دون إعادة كتابته',
              ),
              textAlign: TextAlign.start,
              onTap: () => _ensureFieldVisible(_brandFocus),
              onSubmitted: (_) {
                if (_brandCtrl.text.trim().isNotEmpty) {
                  setState(() => _brandLocked = true);
                }
              },
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
            decoration: const InputDecoration(
              labelText: 'اللزوجة',
              border: OutlineInputBorder(),
              hintText: '5W30',
            ),
            textAlign: TextAlign.start,
            autofocus: _brandLocked,
            onTap: () => _ensureFieldVisible(_viscosityFocus),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kCommonOilViscosities
                .map(
                  (v) => ActionChip(
                    label: Text(v),
                    onPressed: existing.any(
                      (e) =>
                          normalizeOilViscosityKey(e.viscosity) ==
                          normalizeOilViscosityKey(v),
                    )
                        ? null
                        : () {
                            _viscosityCtrl.text = v;
                            setState(() {});
                          },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            focusNode: _priceFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'سعر البيع / لتر (د.ع)',
              border: OutlineInputBorder(),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            onTap: () => _ensureFieldVisible(_priceFocus),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => unawaited(_saveNew()),
            icon: const Icon(Icons.save_rounded),
            label: Text(
              _brandLocked ? 'إضافة اللزوجة' : 'حفظ الاسم واللزوجة',
            ),
          ),
        ],
      ),
    );
  }
}
