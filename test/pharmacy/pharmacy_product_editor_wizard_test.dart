import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_form.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_mode.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_state_holder.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_validation.dart';
import 'package:naboo/verticals/pharmacy/inventory/pharmacy_product_editor_wizard.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_dosage_form.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_drug_reference.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_manufacturer.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  final today = DateTime(2026, 6, 11);
  final validExpiry = DateTime(2027, 1, 1);

  PharmacyProductEditorWizardController wizard({
    PharmacyEditorMode mode = PharmacyEditorMode.modeA,
    PharmacyProductEditorFormController? form,
  }) {
    final controller = form ?? PharmacyProductEditorFormController(tenantId: tenantId);
    return PharmacyProductEditorWizardController(
      mode: mode,
      stateHolder: PharmacyProductEditorStateHolder(controller: controller),
      now: () => today,
    );
  }

  void fillAllFields(PharmacyProductEditorFormController form) {
    form.selectReference(_reference());
    form.selectedManufacturer = _manufacturer();
    form.selectedDosageForm = _dosageForm();
    form.strengthCtrl.text = '500 mg';
    form.rxSchedule = PharmacyRxSchedule.otc;
    form.batchCtrl.text = 'B2401';
    form.expiryDate = validExpiry;
    form.costFilsCtrl.text = '2000';
    form.qtyCtrl.text = '50';
  }

  group('PharmacyProductEditorWizardController — Mode A (4 steps)', () {
    test('starts at step 0 with 4 total steps', () {
      final w = wizard();
      expect(w.currentStep, 0);
      expect(w.totalSteps, 4);
      expect(w.isFirstStep, isTrue);
      expect(w.isLastStep, isFalse);
    });

    test('step 1 requires drug reference', () {
      final w = wizard();
      expect(w.canProceed(), isFalse);
      expect(w.validationErrorForCurrentStep(), contains('المادة'));
    });

    test('advances through 4 steps when fields are valid', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(form: form);

      form.selectReference(_reference());
      expect(w.canProceed(), isTrue);
      w.nextStep();
      expect(w.currentStep, 1);

      form.selectedManufacturer = _manufacturer();
      form.selectedDosageForm = _dosageForm();
      form.strengthCtrl.text = '500 mg';
      expect(w.canProceed(), isTrue);
      w.nextStep();
      expect(w.currentStep, 2);

      form.batchCtrl.text = 'B2401';
      form.expiryDate = validExpiry;
      expect(w.canProceed(), isTrue);
      w.nextStep();
      expect(w.currentStep, 3);
      expect(w.isLastStep, isTrue);

      form.costFilsCtrl.text = '2000';
      form.qtyCtrl.text = '50';
      expect(w.canProceed(), isTrue);
    });

    test('previousStep decrements until zero', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(form: form);
      form.selectReference(_reference());
      w.nextStep();
      form.selectedManufacturer = _manufacturer();
      form.selectedDosageForm = _dosageForm();
      form.strengthCtrl.text = '500 mg';
      w.nextStep();
      expect(w.currentStep, 2);
      w.previousStep();
      expect(w.currentStep, 1);
      w.previousStep();
      expect(w.currentStep, 0);
      w.previousStep();
      expect(w.currentStep, 0);
    });

    test('summary includes filled fields on last step', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(form: form);
      fillAllFields(form);
      w.currentStep = 3;
      final summary = w.buildSummaryLines();
      expect(summary.any((l) => l.contains('500 mg')), isTrue);
      expect(summary.any((l) => l.contains('B2401')), isTrue);
      expect(summary.any((l) => l.contains('2000 fils')), isTrue);
    });
  });

  group('PharmacyProductEditorWizardController — Mode B (2 steps)', () {
    test('step 1 bundles drug + commercial fields', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(mode: PharmacyEditorMode.modeB, form: form);
      expect(w.totalSteps, 2);

      form.selectReference(_reference());
      expect(w.canProceed(), isFalse);

      form.selectedManufacturer = _manufacturer();
      form.selectedDosageForm = _dosageForm();
      form.strengthCtrl.text = '500 mg';
      expect(w.canProceed(), isTrue);
    });

    test('step 2 requires batch pricing', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(mode: PharmacyEditorMode.modeB, form: form);
      fillAllFields(form);
      w.currentStep = 1;
      expect(w.canProceed(), isTrue);
    });
  });

  group('PharmacyProductEditorWizardController — Mode C (6 steps)', () {
    test('each step validates independently', () {
      final form = PharmacyProductEditorFormController(tenantId: tenantId);
      final w = wizard(mode: PharmacyEditorMode.modeC, form: form);
      expect(w.totalSteps, 6);

      expect(w.canProceed(), isFalse);
      form.selectReference(_reference());
      expect(w.canProceed(), isTrue);

      w.currentStep = 1;
      expect(w.canProceed(), isFalse);
      form.selectedManufacturer = _manufacturer();
      expect(w.canProceed(), isTrue);

      w.currentStep = 2;
      expect(w.canProceed(), isFalse);
      form.selectedDosageForm = _dosageForm();
      form.strengthCtrl.text = '250 mg';
      expect(w.canProceed(), isTrue);

      w.currentStep = 3;
      expect(w.canProceed(), isFalse);
      form.batchCtrl.text = 'X1';
      form.expiryDate = validExpiry;
      expect(w.canProceed(), isTrue);

      w.currentStep = 4;
      expect(w.canProceed(), isFalse);
      form.costFilsCtrl.text = '1000';
      form.qtyCtrl.text = '10';
      expect(w.canProceed(), isTrue);

      w.currentStep = 5;
      expect(w.canProceed(), isTrue);
    });
  });

  group('PharmacyProductEditorValidation wizard steps', () {
    test('mode A step indices map to expected errors', () {
      expect(
        PharmacyProductEditorValidation.validationErrorForWizardStep(
          stepIndex: 0,
          totalSteps: 4,
          reference: null,
          manufacturer: null,
          dosageForm: null,
          strengthText: '',
          batchNo: '',
          expiryDate: null,
          costFils: null,
          qty: null,
          today: today,
        ),
        isNotNull,
      );
      expect(
        PharmacyProductEditorValidation.canProceedWizardStep(
          stepIndex: 3,
          totalSteps: 4,
          reference: _reference(),
          manufacturer: _manufacturer(),
          dosageForm: _dosageForm(),
          strengthText: '500 mg',
          batchNo: 'B2401',
          expiryDate: validExpiry,
          costFils: 2000,
          qty: 50,
          today: today,
        ),
        isTrue,
      );
    });
  });

  group('PharmacyEditorMode', () {
    test('step counts', () {
      expect(PharmacyEditorMode.modeA.stepCount, 4);
      expect(PharmacyEditorMode.modeB.stepCount, 2);
      expect(PharmacyEditorMode.modeC.stepCount, 6);
    });
  });
}

PharmacyDrugReference _reference() {
  return PharmacyDrugReference(
    id: 1,
    tenantId: 1,
    nameAr: 'باراسيتامول',
    nameEn: 'Paracetamol',
    atcCode: 'N02BE01',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

PharmacyManufacturer _manufacturer() {
  return PharmacyManufacturer(
    id: 1,
    tenantId: 1,
    name: 'شركة الأدوية',
    type: 'generic',
    qualityTier: 'A',
    countryCode: 'IQ',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

PharmacyDosageForm _dosageForm() {
  return PharmacyDosageForm(
    id: 1,
    tenantId: 1,
    nameAr: 'أقراص',
    nameEn: 'Tablets',
    code: 'tab',
    isSplittable: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}
