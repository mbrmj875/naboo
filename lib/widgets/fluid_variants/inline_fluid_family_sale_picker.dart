import 'package:flutter/material.dart';

import '../../models/fluid_grade_sale_option.dart';
import '../../utils/iraqi_currency_format.dart';

/// اختيار لزوجة/درجة ثم عبوة (لتر، علبة…) وكمية — مثل الملابس في البيع.
class InlineFluidFamilySalePicker extends StatelessWidget {
  const InlineFluidFamilySalePicker({
    super.key,
    required this.familyKindLabel,
    required this.options,
    required this.selectedGradeLinkedId,
    required this.onGradeSelected,
    required this.packQty,
    required this.onSelectionsChanged,
    required this.usedBaseLiters,
    required this.excludeLineId,
    this.allowNegative = false,
  });

  final String familyKindLabel;
  final List<FluidGradeSaleOption> options;
  final int? selectedGradeLinkedId;
  final ValueChanged<int?> onGradeSelected;
  final Map<String, double> packQty;
  final VoidCallback onSelectionsChanged;
  final double Function(
    int linkedProductId,
    double factorToBase, {
    int? excludeLineId,
  }) usedBaseLiters;
  final int excludeLineId;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    FluidGradeSaleOption? selectedGrade;
    if (selectedGradeLinkedId != null) {
      for (final o in options) {
        if (o.linkedProductId == selectedGradeLinkedId) {
          selectedGrade = o;
          break;
        }
      }
    }

    double remainingLiters(FluidGradeSaleOption g) {
      final used = usedBaseLiters(
        g.linkedProductId,
        1,
        excludeLineId: excludeLineId,
      );
      final rem = g.stockLiters - used;
      return rem < 0 ? 0 : rem;
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'اختيار $familyKindLabel (لزوجة/درجة ثم العبوة)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  Text(
                    'لا يمكن تغيير الكمية قبل الاختيار',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (options.isEmpty)
                Text(
                  'جارٍ تحميل اللزوجات/الدرجات…',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.start,
                )
              else ...[
                Text(
                  familyKindLabel == 'زيت' ? 'اللزوجة' : 'الدرجة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final g in options)
                      _GradeChip(
                        title: g.gradeLabel,
                        subtitle:
                            'متاح: ${remainingLiters(g).toStringAsFixed(1)} لتر',
                        disabled: remainingLiters(g) <= 1e-9 && !allowNegative,
                        selected: selectedGradeLinkedId == g.linkedProductId,
                        onTap: () => onGradeSelected(g.linkedProductId),
                      ),
                  ],
                ),
                if (selectedGrade != null) ...[
                  Builder(
                    builder: (ctx) {
                      final grade = selectedGrade!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => onGradeSelected(null),
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: Text(
                          familyKindLabel == 'زيت'
                              ? 'تغيير اللزوجة'
                              : 'تغيير الدرجة',
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'العبوة والكمية',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      for (final pack in grade.packs)
                        _PackQtyCard(
                          pack: pack,
                          grade: grade,
                          selectedQty: packQty[fluidSalePackKey(
                                grade.linkedProductId,
                                pack.unitVariantId,
                              )] ??
                              0,
                          maxBaseOnLine: () {
                            final used = usedBaseLiters(
                              grade.linkedProductId,
                              pack.factorToBase,
                              excludeLineId: excludeLineId,
                            );
                            final rem = grade.stockLiters - used;
                            if (rem < 0) return 0.0;
                            return rem / pack.factorToBase;
                          }(),
                          allowNegative: allowNegative,
                          onQtyChanged: (next) {
                            final key = fluidSalePackKey(
                              grade.linkedProductId,
                              pack.unitVariantId,
                            );
                            if (next <= 1e-9) {
                              packQty.remove(key);
                            } else {
                              packQty[key] = next;
                            }
                            onSelectionsChanged();
                          },
                        ),
                    ],
                  ),
                  if (packQty.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _SelectedSummary(
                      options: options,
                      packQty: packQty,
                    ),
                  ],
                        ],
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({
    required this.title,
    required this.subtitle,
    required this.disabled,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool disabled;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 132,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: disabled
              ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
              : selected
                  ? cs.primary.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? cs.primary : cs.onSurface,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }
}

class _PackQtyCard extends StatelessWidget {
  const _PackQtyCard({
    required this.pack,
    required this.grade,
    required this.selectedQty,
    required this.maxBaseOnLine,
    required this.allowNegative,
    required this.onQtyChanged,
  });

  final FluidPackSaleOption pack;
  final FluidGradeSaleOption grade;
  final double selectedQty;
  final double maxBaseOnLine;
  final bool allowNegative;
  final ValueChanged<double> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedQty > 1e-9;
    final sell = pack.sellPerUnit(grade.sellPerLiter);
    final disabled = maxBaseOnLine <= 1e-9 && !allowNegative && !isSelected;

    return Container(
      width: 148,
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  pack.displayLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.start,
                ),
                Text(
                  IraqiCurrencyFormat.formatInt(sell),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: selectedQty <= 1e-9
                      ? null
                      : () => onQtyChanged(selectedQty - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: Text(
                    selectedQty % 1 == 0
                        ? selectedQty.toInt().toString()
                        : selectedQty.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: disabled
                      ? null
                      : () {
                          final next = selectedQty + 1;
                          if (!allowNegative && next > maxBaseOnLine + 1e-9) {
                            return;
                          }
                          onQtyChanged(next);
                        },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedSummary extends StatelessWidget {
  const _SelectedSummary({
    required this.options,
    required this.packQty,
  });

  final List<FluidGradeSaleOption> options;
  final Map<String, double> packQty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var totalLiters = 0.0;
    final lines = <String>[];

    for (final e in packQty.entries) {
      if (e.value <= 1e-9) continue;
      final parsed = parseFluidSalePackKey(e.key);
      if (parsed == null) continue;
      FluidGradeSaleOption? grade;
      FluidPackSaleOption? pack;
      for (final g in options) {
        if (g.linkedProductId == parsed.linkedProductId) {
          grade = g;
          for (final p in g.packs) {
            if (p.unitVariantId == parsed.unitVariantId) {
              pack = p;
              break;
            }
          }
          break;
        }
      }
      if (grade == null || pack == null) continue;
      final base = e.value * pack.factorToBase;
      totalLiters += base;
      lines.add(
        '${grade.gradeLabel} · ${pack.displayLabel} × ${e.value % 1 == 0 ? e.value.toInt() : e.value} '
        '(≈ ${base.toStringAsFixed(1)} لتر)',
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'المحدد: ≈ ${totalLiters.toStringAsFixed(1)} لتر',
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
            textAlign: TextAlign.start,
          ),
          for (final l in lines) ...[
            const SizedBox(height: 4),
            Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
