import 'package:flutter/material.dart';

import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_sections.dart';

class PharmacyProductEditorModeAStep2 extends StatelessWidget {
  const PharmacyProductEditorModeAStep2({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return PharmacyProductEditorSections(
      controller: controller,
      onChanged: onChanged,
      stepLayout: PharmacyProductEditorStepLayout.modeA2Commercial,
    );
  }
}
