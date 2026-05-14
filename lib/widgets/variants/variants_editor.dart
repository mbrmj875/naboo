import 'package:flutter/material.dart';

import '../app_color_picker_dialog.dart';
import '../../utils/color_name_ar.dart';
import 'variant_drafts.dart';
import 'variant_size_picker_sheet.dart';

class VariantsEditor extends StatelessWidget {
  const VariantsEditor({
    super.key,
    required this.colorDrafts,
    required this.onChanged,
  });

  final List<VariantColorDraft> colorDrafts;
  final VoidCallback onChanged;

  bool _hasSize(VariantColorDraft c, String size) {
    final t = size.trim();
    if (t.isEmpty) return false;
    return c.sizes.any((s) => s.sizeCtrl.text.trim().toUpperCase() == t.toUpperCase());
  }

  void _addPresetSize(VariantColorDraft c, String size) {
    final t = size.trim();
    if (t.isEmpty) return;
    if (_hasSize(c, t)) return;
    c.sizes.add(VariantSizeDraft(size: t, qty: 0));
    onChanged();
  }

  Future<void> _pickSizeFor(
    BuildContext context, {
    required VariantSizeDraft size,
  }) async {
    final chosen = await showVariantSizePickerSheet(
      context,
      current: size.sizeCtrl.text.trim(),
    );
    if (chosen == null) return;
    size.sizeCtrl.text = chosen;
    onChanged();
  }

  int _parseNonNegativeInt(String raw) {
    final t = raw.trim();
    final n = int.tryParse(t);
    return (n == null || n < 0) ? -1 : n;
  }

  int _totalAll() {
    var sum = 0;
    for (final c in colorDrafts) {
      for (final s in c.sizes) {
        final q = _parseNonNegativeInt(s.qtyCtrl.text);
        if (q > 0) sum += q;
      }
    }
    return sum;
  }

  int _totalForColor(VariantColorDraft c) {
    var sum = 0;
    for (final s in c.sizes) {
      final q = _parseNonNegativeInt(s.qtyCtrl.text);
      if (q > 0) sum += q;
    }
    return sum;
  }

  Future<void> _pickColorFor(BuildContext context, VariantColorDraft c) async {
    final cs = Theme.of(context).colorScheme;
    final current = parseFlexibleHexColor(c.hexCtrl.text) ?? cs.primary;
    final chosen = await showAppColorPickerDialog(
      context: context,
      initialColor: current,
      title: 'اختيار لون',
      subtitle: 'اختر لوناً يمثّل هذا الخيار (اختياري).',
    );
    if (chosen == null) return;
    final hex =
        '#${(chosen.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    c.hexCtrl.text = hex;
    if (!c.nameManuallyEdited) {
      final autoName = arabicColorNameFor(chosen);
      if (autoName.trim().isNotEmpty) {
        c.nameCtrl.text = autoName;
      }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget sizeRow(VariantColorDraft c, VariantSizeDraft s, int sizeIndex) {
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
                onTap: () => _pickSizeFor(context, size: s),
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
              onPressed: () => _pickSizeFor(context, size: s),
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
                final removed = c.sizes.removeAt(sizeIndex);
                removed.dispose();
                onChanged();
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
      );
    }

    Widget colorCard(VariantColorDraft c, int colorIndex) {
      final hexColor = parseFlexibleHexColor(c.hexCtrl.text);
      final preview = hexColor ?? cs.surfaceContainerHighest;

      return Card(
        elevation: 0,
        margin: const EdgeInsetsDirectional.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        onChanged();
                      },
                      textAlign: TextAlign.start,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'اختيار لون (HEX)',
                    child: InkWell(
                      key: ValueKey('variant_color_swatch_$colorIndex'),
                      onTap: () => _pickColorFor(context, c),
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
                      final idx = colorDrafts.indexOf(c);
                      if (idx >= 0) {
                        final removed = colorDrafts.removeAt(idx);
                        removed.dispose();
                        onChanged();
                      }
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
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'مقاسات جاهزة (اختياري)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
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
                        for (final s in kVariantQuickSizes)
                          ActionChip(
                            onPressed: _hasSize(c, s) ? null : () => _addPresetSize(c, s),
                            label: Text(
                              s,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            side: BorderSide(
                              color: _hasSize(c, s) ? cs.outlineVariant : cs.primary,
                            ),
                            backgroundColor: _hasSize(c, s)
                                ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                                : cs.primary.withValues(alpha: 0.08),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: cs.outlineVariant),
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
                                sizeRow(c, c.sizes[i], i),
                            ],
                          );
                          if (wide) return list;
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(width: 760, child: list),
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              // اختيار مقاس لسطر جديد مباشرة.
                              final draft = VariantSizeDraft();
                              await _pickSizeFor(context, size: draft);
                              final picked = draft.sizeCtrl.text.trim();
                              if (picked.isEmpty) {
                                draft.dispose();
                                return;
                              }
                              if (_hasSize(c, picked)) {
                                draft.dispose();
                                return;
                              }
                              c.sizes.add(draft);
                              onChanged();
                            },
                            icon: const Icon(Icons.view_module_outlined, size: 18),
                            label: const Text('اختيار مقاس'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              c.sizes.add(VariantSizeDraft());
                              onChanged();
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('مقاس مخصص'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'إجمالي اللون: ${_totalForColor(c)}',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الألوان والمقاسات',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
            Text(
              'الإجمالي: ${_totalAll()}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: () {
              final c = VariantColorDraft();
              c.sizes.add(VariantSizeDraft());
              colorDrafts.add(c);
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('إضافة لون جديد'),
          ),
        ),
        const SizedBox(height: 12),
        if (colorDrafts.isEmpty)
          Text(
            'لا توجد ألوان بعد. أضف لوناً للبدء.',
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.end,
          )
        else
          Column(
            children: [
              for (var i = 0; i < colorDrafts.length; i++)
                colorCard(colorDrafts[i], i),
            ],
          ),
      ],
    );
  }
}

