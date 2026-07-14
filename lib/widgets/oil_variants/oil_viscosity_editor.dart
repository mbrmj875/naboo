import 'package:flutter/material.dart';

import '../../models/oil_grade_pack_input.dart';
import '../../theme/sale_brand.dart';
import '../../utils/iraqi_currency_format.dart';
import 'fluid_family_editor_mode.dart';
import 'oil_grade_draft.dart';

/// محرّر لزوجات/درجات عائلة زيت أو هيدروليك — منفصل عن الملابس.
class OilViscosityEditor extends StatelessWidget {
  const OilViscosityEditor({
    super.key,
    required this.mode,
    required this.grades,
    required this.onChanged,
  });

  final FluidFamilyEditorMode mode;
  final List<OilGradeDraft> grades;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                labels.gradesTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.start,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                grades.add(OilGradeDraft());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(labels.addGradeLabel),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (grades.isEmpty)
          Text(
            labels.emptyHint,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            textAlign: TextAlign.start,
          ),
        for (var i = 0; i < grades.length; i++)
          _GradeCard(
            mode: mode,
            index: i,
            grade: grades[i],
            onRemove: grades.length <= 1
                ? null
                : () {
                    grades[i].dispose();
                    grades.removeAt(i);
                    onChanged();
                  },
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({
    required this.mode,
    required this.index,
    required this.grade,
    required this.onChanged,
    this.onRemove,
  });

  final FluidFamilyEditorMode mode;
  final int index;
  final OilGradeDraft grade;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = mode;
    final presets =
        mode.isOil ? kCommonOilViscosities : kCommonHydraulicGrades;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: SaleBrandColors.gold.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  mode.isOil
                      ? Icons.opacity_rounded
                      : Icons.water_drop_outlined,
                  color: SaleBrandColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${labels.gradeCardTitlePrefix} ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    tooltip: labels.deleteGradeTooltip,
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: presets
                  .map(
                    (v) => ActionChip(
                      label: Text(v),
                      onPressed: () {
                        grade.viscosityCtrl.text = v;
                        onChanged();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: grade.viscosityCtrl,
              decoration: InputDecoration(
                labelText: labels.gradeFieldLabel,
                border: const OutlineInputBorder(),
                hintText: labels.gradeFieldHint,
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: grade.qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'رصيد افتتاحي (لتر)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: grade.buyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'سعر الشراء / لتر',
                      border: const OutlineInputBorder(),
                      hintText: '0 د.ع',
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: grade.sellCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'سعر البيع / لتر',
                      border: const OutlineInputBorder(),
                      hintText: '0 د.ع',
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: grade.barcodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'باركود (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              labels.packsForGradeTitle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Text(
              'اللتر مضمّن تلقائياً. أضف علبة أو كوارت — مجموع اللترات = معامل العبوة.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kOilPackPresets
                  .map(
                    (p) => ActionChip(
                      label: Text(p.name),
                      onPressed: () {
                        grade.packs.add(
                          OilGradePackDraft(
                            unitName: p.name,
                            unitSymbol: p.symbol,
                            factor: p.factor,
                          ),
                        );
                        onChanged();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () {
                  grade.packs.add(OilGradePackDraft());
                  onChanged();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('عبوة مخصصة'),
              ),
            ),
            for (var pi = 0; pi < grade.packs.length; pi++)
              _PackRow(
                pack: grade.packs[pi],
                onRemove: () {
                  grade.packs[pi].dispose();
                  grade.packs.removeAt(pi);
                  onChanged();
                },
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.onRemove,
    required this.onChanged,
  });

  final OilGradePackDraft pack;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'وحدة عبوة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: pack.unitNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العبوة',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: pack.factorCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'لتر/وحدة',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: pack.sellCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'سعر البيع (اختياري)',
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: '0 د.ع',
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

/// تحويل مسودات اللزوجات لمدخلات الحفظ.
List<OilGradeInput> oilGradesFromDrafts(List<OilGradeDraft> drafts) {
  final out = <OilGradeInput>[];
  for (final g in drafts) {
    final vis = g.viscosityCtrl.text.trim();
    if (vis.isEmpty) continue;
    final qty = double.tryParse(g.qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final buy = IraqiCurrencyFormat.parseIqdInt(g.buyCtrl.text).toDouble();
    final sell = IraqiCurrencyFormat.parseIqdInt(g.sellCtrl.text).toDouble();
    final packs = <OilGradePackInput>[];
    for (final p in g.packs) {
      final un = p.unitNameCtrl.text.trim();
      if (un.isEmpty) continue;
      if (un == 'لتر' || un.toLowerCase() == 'l') continue;
      final f = double.tryParse(p.factorCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      if (f <= 0) continue;
      final sellRaw = p.sellCtrl.text.trim();
      packs.add(
        OilGradePackInput(
          unitName: un,
          unitSymbol: p.unitSymbolCtrl.text.trim().isEmpty
              ? null
              : p.unitSymbolCtrl.text.trim(),
          factorToBase: f,
          barcode: p.barcodeCtrl.text.trim().isEmpty
              ? null
              : p.barcodeCtrl.text.trim(),
          sellPrice: sellRaw.isEmpty
              ? null
              : IraqiCurrencyFormat.parseIqdInt(sellRaw).toDouble(),
        ),
      );
    }
    out.add(
      OilGradeInput(
        viscosity: vis,
        openingQtyLiters: qty,
        buyPrice: buy,
        sellPrice: sell,
        barcode: g.barcodeCtrl.text.trim().isEmpty
            ? null
            : g.barcodeCtrl.text.trim(),
        packs: packs,
      ),
    );
  }
  return out;
}
