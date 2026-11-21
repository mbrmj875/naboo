import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_sections.dart';

class PharmacyProductEditorModeAStep3 extends StatelessWidget {
  const PharmacyProductEditorModeAStep3({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onBatchDraftChanged,
  });

  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;
  final void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged;

  @override
  Widget build(BuildContext context) {
    return PharmacyProductEditorSections(
      controller: controller,
      onChanged: onChanged,
      onBatchDraftChanged: onBatchDraftChanged,
      stepLayout: PharmacyProductEditorStepLayout.modeA3BatchRx,
    );
  }
}
