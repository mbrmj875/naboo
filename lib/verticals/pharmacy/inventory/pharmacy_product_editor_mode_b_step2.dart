import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_sections.dart';

class PharmacyProductEditorModeBStep2 extends StatelessWidget {
  const PharmacyProductEditorModeBStep2({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onBatchDraftChanged,
    this.summaryLines = const [],
  });

  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;
  final void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged;
  final List<String> summaryLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summaryLines.isNotEmpty) ...[
          const PharmacyEditorSectionTitle(title: 'ملخص قبل الحفظ'),
          Card(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in summaryLines)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 4),
                      child: Text('• $line'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        PharmacyProductEditorSections(
          controller: controller,
          onChanged: onChanged,
          onBatchDraftChanged: onBatchDraftChanged,
          stepLayout: PharmacyProductEditorStepLayout.modeB2BatchPricing,
        ),
      ],
    );
  }
}
