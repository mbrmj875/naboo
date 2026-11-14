import 'package:flutter/material.dart';

import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_validation.dart';

/// حالة محرّr الدواء — تغليف [PharmacyProductEditorFormController].
class PharmacyProductEditorStateHolder {
  PharmacyProductEditorStateHolder({
    PharmacyProductEditorFormController? controller,
  }) : controller = controller ?? PharmacyProductEditorFormController();

  final PharmacyProductEditorFormController controller;
  final TextEditingController notesCtrl = TextEditingController();

  PharmacyDrugReference? get drugReference => controller.selectedReference;
  PharmacyManufacturer? get manufacturer => controller.selectedManufacturer;
  PharmacyDosageForm? get dosageForm => controller.selectedDosageForm;
  String get strengthText => controller.strengthCtrl.text;
  String get rxSchedule => controller.rxSchedule;
  String? get batchNo =>
      controller.batchCtrl.text.trim().isEmpty ? null : controller.batchCtrl.text.trim();
  DateTime? get expiryDate => controller.expiryDate;
  int? get costFils => int.tryParse(controller.costFilsCtrl.text.trim());
  double? get qty => double.tryParse(controller.qtyCtrl.text.trim());
  String? get notes =>
      notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();

  int? get strengthMg {
    final v = PharmacyProductEditorValidation.parseStrengthValue(strengthText);
    return v > 0 ? v.round() : null;
  }

  Future<void> load() => controller.load();

  void dispose() {
    notesCtrl.dispose();
    controller.dispose();
  }
}
