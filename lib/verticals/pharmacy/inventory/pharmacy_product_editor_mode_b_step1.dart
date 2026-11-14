import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_sections.dart';

class PharmacyProductEditorModeBStep1 extends StatelessWidget {
  const PharmacyProductEditorModeBStep1({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onDrugReferenceSelected,
  });

  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;
  final void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected;

  @override
  Widget build(BuildContext context) {
    return PharmacyProductEditorSections(
      controller: controller,
      onChanged: onChanged,
      onDrugReferenceSelected: onDrugReferenceSelected,
      stepLayout: PharmacyProductEditorStepLayout.modeB1DrugCommercial,
    );
  }
}
