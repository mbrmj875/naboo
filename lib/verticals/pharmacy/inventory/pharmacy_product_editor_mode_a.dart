import 'package:flutter/material.dart';

import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_mode.dart';
import 'pharmacy_product_editor_wizard.dart';

export 'pharmacy_product_editor_result.dart';

/// شاشة Mode A — معالج 4 خطوات.
class PharmacyProductEditorModeA extends StatelessWidget {
  const PharmacyProductEditorModeA({
    super.key,
    this.tenantId,
    this.controller,
  });

  final int? tenantId;
  final PharmacyProductEditorFormController? controller;

  @override
  Widget build(BuildContext context) {
    return PharmacyProductEditorWizard(
      mode: PharmacyEditorMode.modeA,
      tenantId: tenantId,
      controller: controller,
    );
  }
}
