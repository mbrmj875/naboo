import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/oil_change_hydraulic_catalog_entry.dart';
import '../services/oil_change_hydraulic_catalog_repository.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import 'oil_change_royal_card.dart';
import '../../../widgets/oil_variants/oil_grade_draft.dart';

/// [manageOnly]: إدارة الكتالوج فقط (إضافة أصناف) دون اختيار للبطاقة.
Future<OilChangeHydraulicCatalogPick?> showOilChangeHydraulicCatalogSheet(
  BuildContext context, {
  bool manageOnly = false,
  String? initialBrandName,
}) {
  return showModalBottomSheet<OilChangeHydraulicCatalogPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _OilChangeHydraulicCatalogSheetBody(
      manageOnly: manageOnly,
      initialBrandName: initialBrandName,
    ),
  );
}

class _OilChangeHydraulicCatalogSheetBody extends StatefulWidget {
  const _OilChangeHydraulicCatalogSheetBody({
    this.manageOnly = false,
    this.initialBrandName,
  });

  final bool manageOnly;
  final String? initialBrandName;

  @override
  State<_OilChangeHydraulicCatalogSheetBody> createState() =>
      _OilChangeHydraulicCatalogSheetBodyState();
}

class _OilChangeHydraulicCatalogSheetBodyState
    extends State<_OilChangeHydraulicCatalogSheetBody> {
  static const _gold = SaleBrandColors.gold;

  bool _loading = true;
  Object? _error;
  List<OilChangeHydraulicCatalogEntry> _entries = const [];
  bool _adding = false;
  bool _brandLocked = false;

  final _brandCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final seed = widget.initialBrandName?.trim();
    if (seed != null && seed.isNotEmpty) {
      _brandCtrl.text = seed;
      _brandLocked = true;
      _adding = true;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _gradeCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await OilChangeHydraulicCatalogRepository.instance.listActive();
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

  Map<String, List<OilChangeHydraulicCatalogEntry>> get _byBrand {
    final m = <String, List<OilChangeHydraulicCatalogEntry>>{};
    for (final e in _entries) {
      m.putIfAbsent(e.brandName, () => []).add(e);
    }
    return m;
  }

  Future<void> _saveNew() async {
    final brand = _brandCtrl.text.trim();
    final grade = _gradeCtrl.text.trim();
    final priceDinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final priceFils = IqdMoney.toFils(priceDinars.toDouble());
    if (brand.isEmpty || grade.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الهيدروليك والدرجة')),
      );
      return;
    }
    if (priceFils <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل سعر البيع للتر')),
      );
      return;
    }
    final gradeKey = normalizeHydraulicGradeKey(grade);
    if (_entries.any(
      (e) =>
          e.brandName.toLowerCase() == brand.toLowerCase() &&
          normalizeHydraulicGradeKey(e.grade) == gradeKey,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نفس الماركة ونفس الدرجة موجودة — اخترها من القائمة أو غيّر الدرجة',
          ),
        ),
      );
      return;
    }
    try {
      await OilChangeHydraulicCatalogRepository.instance.insert(
        brandName: brand,
        grade: gradeKey,
        sellPerLiterFils: priceFils,
      );
      _gradeCtrl.clear();
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
            'تمت إضافة $gradeKey لـ $brand — يمكنك إضافة درجة أخرى لنفس الاسم',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_brand_grade'
          ? 'نفس الماركة ونفس الدرجة موجودة مسبقاً'
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
      _gradeCtrl.clear();
      _priceCtrl.clear();
    });
  }

  void _unlockBrand() {
    setState(() {
      _brandLocked = false;
      _brandCtrl.clear();
      _gradeCtrl.clear();
      _priceCtrl.clear();
    });
  }

  List<OilChangeHydraulicCatalogEntry> _entriesForLockedBrand() {
    final b = _brandCtrl.text.trim();
    if (b.isEmpty) return const [];
    return OilChangeHydraulicCatalogRepository.entriesForBrand(_entries, b);
  }

  void _pick(OilChangeHydraulicCatalogEntry e) {
    Navigator.pop(
      context,
      OilChangeHydraulicCatalogPick(
        brandName: e.brandName,
        grade: e.grade,
        sellPerLiterFils: e.sellPerLiterFils,
        catalogEntryId: e.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12 + bottom),
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.water_drop_outlined, color: _gold, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'كتالوج الهيدروليك والدرجات',
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
            Text(
              widget.manageOnly
                  ? 'اكتب اسم الهيدروليك مرة واحدة، ثم أضف عدة درجات بسعر كل درجة. الاختيار في البطاقة من القوائم فقط.'
                  : 'اختر صنفاً للبطاقة، أو أضف اسم هيدروليك ثم درجات متعددة بأسعارها.',
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
                icon: Icon(_adding ? Icons.expand_less : Icons.add_rounded),
                label: Text(_adding ? 'إخفاء الإضافة' : 'إضافة هيدروليك / درجة'),
              ),
            ),
            if (_adding) ...[
              const SizedBox(height: 8),
              _buildAddForm(cs),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(
                            'تعذّر تحميل الكتالوج',
                            style: TextStyle(color: cs.error),
                          ),
                        )
                      : _entries.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد أصناف بعد. أضف أول ماركة ودرجة.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView(
                              children: [
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
                                                label: const Text('درجة'),
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
                                          e.grade,
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
                labelText: 'اسم الهيدروليك (ثابت)',
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
              decoration: const InputDecoration(
                labelText: 'اسم / ماركة الهيدروليك',
                border: OutlineInputBorder(),
                hintText: 'شل، كاسترول…',
                helperText:
                    'يُحفظ الاسم عند أول درجة — ثم تضيف درجات أخرى دون إعادة كتابته',
              ),
              textAlign: TextAlign.start,
              onSubmitted: (_) {
                if (_brandCtrl.text.trim().isNotEmpty) {
                  setState(() => _brandLocked = true);
                }
              },
            ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'درجات مسجّلة لهذا الاسم:',
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
                      label: Text(e.grade),
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _gradeCtrl,
            decoration: const InputDecoration(
              labelText: 'الدرجة',
              border: OutlineInputBorder(),
              hintText: 'AW 46',
            ),
            textAlign: TextAlign.start,
            autofocus: _brandLocked,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kCommonHydraulicGrades
                .map(
                  (v) => ActionChip(
                    label: Text(v),
                    onPressed: existing.any(
                      (e) =>
                          normalizeHydraulicGradeKey(e.grade) ==
                          normalizeHydraulicGradeKey(v),
                    )
                        ? null
                        : () {
                            _gradeCtrl.text = v;
                            setState(() {});
                          },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'سعر البيع / لتر (د.ع)',
              border: OutlineInputBorder(),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => unawaited(_saveNew()),
            icon: const Icon(Icons.save_rounded),
            label: Text(
              _brandLocked ? 'إضافة الدرجة' : 'حفظ الاسم والدرجة',
            ),
          ),
        ],
      ),
    );
  }
}
