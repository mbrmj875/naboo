import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../services/oil_product_grades_repository.dart';
import '../../theme/sale_brand.dart';

/// نتيجة اختيار زيت من المخزون (لزوجة + عبوة + كمية → لتر).
class OilStockPickResult {
  const OilStockPickResult({
    required this.productId,
    required this.liters,
    required this.title,
    required this.packLabel,
    this.sellPerLiterIqd,
  });

  final int productId;
  final double liters;
  final String title;
  final String packLabel;
  final double? sellPerLiterIqd;
}

/// منتقي زيت المحل: عائلة → لزوجة → عبوة → عدد.
Future<OilStockPickResult?> showOilStockPickSheet(BuildContext context) {
  return showModalBottomSheet<OilStockPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => const _OilStockPickSheetBody(),
  );
}

class _OilStockPickSheetBody extends StatefulWidget {
  const _OilStockPickSheetBody();

  @override
  State<_OilStockPickSheetBody> createState() => _OilStockPickSheetBodyState();
}

class _OilStockPickSheetBodyState extends State<_OilStockPickSheetBody> {
  static const _gold = SaleBrandColors.gold;

  bool _loading = true;
  Object? _error;
  List<OilPickLine> _lines = const [];

  OilPickLine? _selectedLine;
  OilPackUnit? _selectedPack;
  final _countCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await OilProductGradesRepository.instance.listOilPickLines();
      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  double _previewLiters() {
    final pack = _selectedPack;
    if (pack == null) return 0;
    final c = double.tryParse(_countCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (c <= 0) return 0;
    return c * pack.factorToBase;
  }

  void _confirm() {
    final line = _selectedLine;
    final pack = _selectedPack;
    if (line == null || pack == null) return;
    final c = double.tryParse(_countCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (c <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل عدداً أكبر من صفر')),
      );
      return;
    }
    final liters = c * pack.factorToBase;
    if (liters <= 1e-9) return;
    final countLabel = c % 1 == 0 ? c.toInt().toString() : c.toString();
    Navigator.pop(
      context,
      OilStockPickResult(
        productId: line.linkedProductId,
        liters: liters,
        title: line.lineTitle,
        packLabel: '${pack.displayLabel} × $countLabel',
        sellPerLiterIqd: line.sellPerLiterIqd,
      ),
    );
  }

  Map<String, List<OilPickLine>> _grouped() {
    final map = <String, List<OilPickLine>>{};
    for (final l in _lines) {
      final key = l.parentProductId != null ? l.parentName : l.lineTitle;
      map.putIfAbsent(key, () => []).add(l);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'اختيار الزيت من المخزون',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 4),
          Text(
            'اختر اللزوجة ثم العبوة (لتر / علبة / كوارت…) — يُحسب الخصم باللتر.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              children: [
                Text(
                  'تعذّر تحميل الأصناف',
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.start,
                ),
                TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
              ],
            )
          else if (_lines.isEmpty)
            Text(
              'لا توجد أصناف زيت. أضف «زيت مفرد» أو «زيت — عائلة» من المخزون.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            )
          else ...[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in _grouped().entries) ...[
                      if (entry.value.first.parentProductId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 4),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _gold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((line) {
                          final sel = _selectedLine?.linkedProductId ==
                              line.linkedProductId;
                          return Material(
                            color: sel
                                ? cs.primary.withValues(alpha: 0.12)
                                : cs.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedLine = line;
                                  _selectedPack = line.packs.isNotEmpty
                                      ? line.packs.first
                                      : null;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 148,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: sel
                                        ? cs.primary
                                        : _gold.withValues(alpha: 0.35),
                                    width: sel ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  line.viscosity.isEmpty
                                      ? line.parentName
                                      : line.viscosity,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: sel ? cs.primary : cs.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            if (_selectedLine != null) ...[
              const Divider(height: 20),
              Text(
                'العبوة',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedLine!.packs.map((pack) {
                  final sel = _selectedPack?.unitName == pack.unitName &&
                      (_selectedPack?.factorToBase ?? 0) ==
                          pack.factorToBase;
                  return ChoiceChip(
                    label: Text(pack.displayLabel),
                    selected: sel,
                    onSelected: (_) =>
                        setState(() => _selectedPack = pack),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _countCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'العدد (وحدات العبوة)',
                  border: const OutlineInputBorder(),
                  helperText: _previewLiters() > 0
                      ? '≈ ${_previewLiters().toStringAsFixed(2)} لتر من المخزون'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selectedPack == null ? null : _confirm,
                child: const Text('تأكيد الاختيار'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
