import 'package:flutter/material.dart';

import '../../utils/clothing_intl_sizes.dart';

/// قيمة داخلية؛ لا تُستخدم كقيمة مقاس نهائية.
const String _kCustomSizeChoice = '__CUSTOM_SIZE__';

/// قائمة مقاسات سريعة إضافة إلى الجدول العالمي.
const List<String> kVariantQuickSizes = <String>[
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  'XXXL',
  '28',
  '30',
  '32',
  '34',
  '36',
  '38',
  '40',
  '42',
  '44',
  '46',
  '48',
  '50',
  '52',
];

Future<String?> _promptCustomSize(BuildContext context) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('مقاس مخصص'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اكتب المقاس',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.ltr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('تم'),
          ),
        ],
      );
    },
  );
  ctrl.dispose();
  return result;
}

Widget _intlColumnHeader(String label, ColorScheme cs) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: cs.primary,
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

Widget _intlCell(String text, ColorScheme cs, {bool emphasizeUk = false}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        color: emphasizeUk
            ? cs.secondaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: emphasizeUk ? cs.onSecondaryContainer : cs.onSurface,
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// يفتح القاع السفلي: جدول المقاسات العالمية + مقاسات سريعة + مقاس مخصص.
/// يعيد النص الكامل للمقاس أو null عند الإلغاء.
Future<String?> showVariantSizePickerSheet(
  BuildContext context, {
  required String current,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  final chosen = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المقاسات العالمية',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 4),
              Text(
                'اضغط صفاً كاملاً أو أي خلية فيه — يُحفظ الصف كاملاً كنص واحد.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 12),
              Row(
                textDirection: TextDirection.ltr,
                children: [
                  _intlColumnHeader('AR', cs),
                  _intlColumnHeader('US', cs),
                  _intlColumnHeader('EN', cs),
                  _intlColumnHeader('UK', cs),
                ],
              ),
              for (final row in ClothingIntlSizeRow.standard)
                Material(
                  color: current == row.storageLabel
                      ? cs.primary.withValues(alpha: 0.06)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, row.storageLabel),
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        _intlCell('${row.ar}', cs),
                        _intlCell('${row.us}', cs),
                        _intlCell('${row.en}', cs),
                        _intlCell(row.uk.toUpperCase(), cs, emphasizeUk: true),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'أو اختر سريعاً',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  for (final s in kVariantQuickSizes)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, s),
                      child: Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          10,
                          12,
                          10,
                        ),
                        decoration: BoxDecoration(
                          color: current == s
                              ? cs.primary.withValues(alpha: 0.10)
                              : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                          border: Border.all(
                            color: current == s ? cs.primary : cs.outlineVariant,
                            width: current == s ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: current == s ? cs.primary : cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(ctx, _kCustomSizeChoice),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('مقاس مخصص (اكتب بنفسك)'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (chosen == null) return null;
  if (chosen == _kCustomSizeChoice) {
    final custom = await _promptCustomSize(context);
    if (!context.mounted) return null;
    if (custom == null || custom.isEmpty) return null;
    return custom;
  }
  return chosen;
}
