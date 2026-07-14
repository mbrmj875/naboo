import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_sections.dart';

class PharmacyProductEditorModeCStep extends StatelessWidget {
  const PharmacyProductEditorModeCStep({
    super.key,
    required this.stepIndex,
    required this.controller,
    required this.onChanged,
    this.onDrugReferenceSelected,
    this.onBatchDraftChanged,
    this.notesController,
    this.summaryLines,
  });

  final int stepIndex;
  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;
  final void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected;
  final void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged;
  final TextEditingController? notesController;
  final List<String>? summaryLines;

  PharmacyProductEditorStepLayout get _layout => switch (stepIndex) {
        0 => PharmacyProductEditorStepLayout.modeC1DrugReference,
        1 => PharmacyProductEditorStepLayout.modeC2Manufacturer,
        2 => PharmacyProductEditorStepLayout.modeC3FormStrength,
        3 => PharmacyProductEditorStepLayout.modeC4BatchExpiry,
        4 => PharmacyProductEditorStepLayout.modeC5PricingQty,
        _ => PharmacyProductEditorStepLayout.modeC6Notes,
      };

  @override
  Widget build(BuildContext context) {
    final summary = summaryLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null && summary.isNotEmpty) ...[
          const PharmacyEditorSectionTitle(title: 'ملخص قبل الحفظ'),
          Card(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in summary)
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
          onDrugReferenceSelected: onDrugReferenceSelected,
          onBatchDraftChanged: onBatchDraftChanged,
          notesController: notesController,
          stepLayout: _layout,
        ),
      ],
    );
  }
}
