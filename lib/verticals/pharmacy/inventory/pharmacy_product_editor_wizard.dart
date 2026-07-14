import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_mode.dart';
import 'pharmacy_product_editor_mode_a_step1.dart';
import 'pharmacy_product_editor_mode_a_step2.dart';
import 'pharmacy_product_editor_mode_a_step3.dart';
import 'pharmacy_product_editor_mode_a_step4.dart';
import 'pharmacy_product_editor_mode_b_step1.dart';
import 'pharmacy_product_editor_mode_b_step2.dart';
import 'pharmacy_product_editor_mode_c_steps.dart';
import 'pharmacy_product_editor_result.dart';
import 'pharmacy_product_editor_sections.dart';
import 'pharmacy_product_editor_state_holder.dart';
import 'pharmacy_product_editor_validation.dart';

/// حفظ مستقل (منتج جديد) أو تعبئة نموذج Core فقط.
enum PharmacyProductEditorWizardSaveTarget {
  standalone,
  draftOnly,
}

/// متحكّم معالج إضافة الدواء — قابل للاختبار بدون Widget.
class PharmacyProductEditorWizardController {
  PharmacyProductEditorWizardController({
    required this.mode,
    PharmacyProductEditorStateHolder? stateHolder,
    DateTime Function()? now,
  })  : state = stateHolder ?? PharmacyProductEditorStateHolder(),
        _now = now ?? DateTime.now;

  final PharmacyEditorMode mode;
  final PharmacyProductEditorStateHolder state;
  final DateTime Function() _now;

  int currentStep = 0;

  int get totalSteps => mode.stepCount;

  bool get isFirstStep => currentStep <= 0;
  bool get isLastStep => currentStep >= totalSteps - 1;

  PharmacyProductEditorFormController get form => state.controller;

  String? validationErrorForCurrentStep() {
    return PharmacyProductEditorValidation.validationErrorForWizardStep(
      stepIndex: currentStep,
      totalSteps: totalSteps,
      reference: state.drugReference,
      manufacturer: state.manufacturer,
      dosageForm: state.dosageForm,
      strengthText: state.strengthText,
      batchNo: state.batchNo ?? '',
      expiryDate: state.expiryDate,
      costFils: state.costFils,
      qty: state.qty,
      today: _now(),
    );
  }

  bool canProceed() => validationErrorForCurrentStep() == null;

  void nextStep() {
    if (!canProceed() || isLastStep) return;
    currentStep++;
  }

  void previousStep() {
    if (currentStep > 0) currentStep--;
  }

  PharmacyProductEditorStepLayout stepLayoutFor(int stepIndex) {
    return switch (mode) {
      PharmacyEditorMode.modeA => switch (stepIndex) {
          0 => PharmacyProductEditorStepLayout.modeA1DrugReference,
          1 => PharmacyProductEditorStepLayout.modeA2Commercial,
          2 => PharmacyProductEditorStepLayout.modeA3BatchRx,
          _ => PharmacyProductEditorStepLayout.modeA4PricingNotes,
        },
      PharmacyEditorMode.modeB => switch (stepIndex) {
          0 => PharmacyProductEditorStepLayout.modeB1DrugCommercial,
          _ => PharmacyProductEditorStepLayout.modeB2BatchPricing,
        },
      PharmacyEditorMode.modeC => switch (stepIndex) {
          0 => PharmacyProductEditorStepLayout.modeC1DrugReference,
          1 => PharmacyProductEditorStepLayout.modeC2Manufacturer,
          2 => PharmacyProductEditorStepLayout.modeC3FormStrength,
          3 => PharmacyProductEditorStepLayout.modeC4BatchExpiry,
          4 => PharmacyProductEditorStepLayout.modeC5PricingQty,
          _ => PharmacyProductEditorStepLayout.modeC6Notes,
        },
    };
  }

  String stepTitleAr(int stepIndex) {
    return switch (mode) {
      PharmacyEditorMode.modeA => switch (stepIndex) {
          0 => 'بيانات الدواء',
          1 => 'بيانات تجارية',
          2 => 'دفعة وصلاحية',
          _ => 'السعر والكمية',
        },
      PharmacyEditorMode.modeB => switch (stepIndex) {
          0 => 'معلومات الدواء',
          _ => 'دفعة وسعر',
        },
      PharmacyEditorMode.modeC => switch (stepIndex) {
          0 => 'المادة الفعّالة',
          1 => 'الشركة',
          2 => 'الشكل والتركيز',
          3 => 'دفعة وصلاحية',
          4 => 'السعر والكمية',
          _ => 'ملاحظات',
        },
    };
  }

  List<String> buildSummaryLines() {
    final ref = state.drugReference;
    final mfg = state.manufacturer;
    final formType = state.dosageForm;
    final lines = <String>[
      if (ref != null)
        'المادة: ${ref.nameAr.isNotEmpty ? ref.nameAr : ref.nameEn}',
      if (mfg != null) 'الشركة: ${mfg.name}',
      if (formType != null) 'الشكل: ${formType.nameAr}',
      if (state.strengthText.trim().isNotEmpty) 'التركيز: ${state.strengthText}',
      'Rx/OTC: ${state.rxSchedule == 'rx' ? 'Rx' : 'OTC'}',
      if (state.batchNo != null) 'الدفعة: ${state.batchNo}',
      if (state.expiryDate != null)
        'الصلاحية: ${state.expiryDate!.year}-${state.expiryDate!.month.toString().padLeft(2, '0')}-${state.expiryDate!.day.toString().padLeft(2, '0')}',
      if (state.costFils != null) 'سعر الشراء: ${state.costFils} fils',
      if (state.qty != null) 'الكمية: ${state.qty}',
      if (state.notes != null) 'ملاحظات: ${state.notes}',
    ];
    return lines;
  }

  Future<PharmacyProductEditorModeAResult?> saveProduct({
    required PharmacyProductEditorWizardSaveTarget target,
  }) async {
    if (!PharmacyProductEditorValidation.canProceedWizardStep(
      stepIndex: totalSteps - 1,
      totalSteps: totalSteps,
      reference: state.drugReference,
      manufacturer: state.manufacturer,
      dosageForm: state.dosageForm,
      strengthText: state.strengthText,
      batchNo: state.batchNo ?? '',
      expiryDate: state.expiryDate,
      costFils: state.costFils,
      qty: state.qty,
      today: _now(),
    )) {
      return null;
    }

    final resolveErr = await form.resolveReferenceBeforeSave();
    if (resolveErr != null) {
      throw StateError(resolveErr);
    }
    final err = form.validateForSave();
    if (err != null) {
      throw StateError(err);
    }

    if (target == PharmacyProductEditorWizardSaveTarget.draftOnly) {
      return null;
    }

    final result = await form.saveStandalone();
    return PharmacyProductEditorModeAResult(
      productId: result.productId,
      profileId: result.profileId,
    );
  }
}

/// معالج إضافة دواء — Modes A · B · C.
class PharmacyProductEditorWizard extends StatefulWidget {
  const PharmacyProductEditorWizard({
    super.key,
    required this.mode,
    this.tenantId,
    this.controller,
    this.stateHolder,
    this.saveTarget = PharmacyProductEditorWizardSaveTarget.standalone,
    this.onSaved,
    this.onDraftCompleted,
    this.onDrugReferenceSelected,
    this.onBatchDraftChanged,
    this.useScaffold = true,
  });

  final PharmacyEditorMode mode;
  final int? tenantId;
  final PharmacyProductEditorFormController? controller;
  final PharmacyProductEditorStateHolder? stateHolder;
  final PharmacyProductEditorWizardSaveTarget saveTarget;
  final void Function(PharmacyProductEditorModeAResult result)? onSaved;
  final VoidCallback? onDraftCompleted;
  final void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected;
  final void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged;
  final bool useScaffold;

  @override
  State<PharmacyProductEditorWizard> createState() =>
      _PharmacyProductEditorWizardState();
}

class _PharmacyProductEditorWizardState extends State<PharmacyProductEditorWizard> {
  late final PharmacyProductEditorWizardController _wizard;
  late final bool _ownsStateHolder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ownsStateHolder = widget.stateHolder == null && widget.controller == null;
    final holder = widget.stateHolder ??
        PharmacyProductEditorStateHolder(
          controller: widget.controller ??
              PharmacyProductEditorFormController(tenantId: widget.tenantId),
        );
    _wizard = PharmacyProductEditorWizardController(
      mode: widget.mode,
      stateHolder: holder,
    );
  }

  @override
  void dispose() {
    if (_ownsStateHolder) {
      _wizard.state.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onNext() async {
    final err = _wizard.validationErrorForCurrentStep();
    if (err != null) {
      _showMessage(err);
      return;
    }
    setState(_wizard.nextStep);
  }

  void _onPrevious() {
    setState(_wizard.previousStep);
  }

  Future<void> _onSave() async {
    final stepErr = _wizard.validationErrorForCurrentStep();
    if (stepErr != null) {
      _showMessage(stepErr);
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _wizard.saveProduct(target: widget.saveTarget);
      if (!mounted) return;
      if (widget.saveTarget == PharmacyProductEditorWizardSaveTarget.draftOnly) {
        widget.onDraftCompleted?.call();
        Navigator.of(context).pop();
        return;
      }
      if (result != null) {
        widget.onSaved?.call(result);
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e is StateError && e.message.isNotEmpty
            ? e.message
            : 'تعذّر حفظ الدواء — حاول مجدداً',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildStepContent() {
    final step = _wizard.currentStep;
    final common = (
      controller: _wizard.form,
      onChanged: _onChanged,
      onDrugReferenceSelected: widget.onDrugReferenceSelected,
      onBatchDraftChanged: widget.onBatchDraftChanged,
      notesController: _wizard.state.notesCtrl,
    );

    switch (widget.mode) {
      case PharmacyEditorMode.modeA:
        switch (step) {
          case 0:
            return PharmacyProductEditorModeAStep1(
              controller: common.controller,
              onChanged: common.onChanged,
              onDrugReferenceSelected: common.onDrugReferenceSelected,
            );
          case 1:
            return PharmacyProductEditorModeAStep2(
              controller: common.controller,
              onChanged: common.onChanged,
            );
          case 2:
            return PharmacyProductEditorModeAStep3(
              controller: common.controller,
              onChanged: common.onChanged,
              onBatchDraftChanged: common.onBatchDraftChanged,
            );
          default:
            return PharmacyProductEditorModeAStep4(
              controller: common.controller,
              onChanged: common.onChanged,
              notesController: common.notesController,
              summaryLines: _wizard.buildSummaryLines(),
            );
        }
      case PharmacyEditorMode.modeB:
        return step == 0
            ? PharmacyProductEditorModeBStep1(
                controller: common.controller,
                onChanged: common.onChanged,
                onDrugReferenceSelected: common.onDrugReferenceSelected,
              )
            : PharmacyProductEditorModeBStep2(
                controller: common.controller,
                onChanged: common.onChanged,
                onBatchDraftChanged: common.onBatchDraftChanged,
                summaryLines: _wizard.buildSummaryLines(),
              );
      case PharmacyEditorMode.modeC:
        return PharmacyProductEditorModeCStep(
          stepIndex: step,
          controller: common.controller,
          onChanged: common.onChanged,
          onDrugReferenceSelected: common.onDrugReferenceSelected,
          onBatchDraftChanged: common.onBatchDraftChanged,
          notesController: common.notesController,
          summaryLines:
              step == _wizard.totalSteps - 1 ? _wizard.buildSummaryLines() : null,
        );
    }
  }

  Widget _buildNavButtons() {
    final showPrevious = !_wizard.isFirstStep;
    final showNext = !_wizard.isLastStep;
    final showSave = _wizard.isLastStep;

    return Row(
      children: [
        if (showPrevious)
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : _onPrevious,
              child: const Text('السابق'),
            ),
          ),
        if (showPrevious && (showNext || showSave)) const SizedBox(width: 12),
        if (showNext)
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _onNext,
              child: const Text('التالي'),
            ),
          ),
        if (showSave) ...[
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _onSave,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.saveTarget ==
                              PharmacyProductEditorWizardSaveTarget.draftOnly
                          ? 'تطبيق'
                          : 'حفظ',
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepHuman = _wizard.currentStep + 1;
    final title =
        'إضافة دواء — الخطوة $stepHuman من ${_wizard.totalSteps}';
    final subtitle = _wizard.stepTitleAr(_wizard.currentStep);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: stepHuman / _wizard.totalSteps,
          minHeight: 4,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: _buildStepContent(),
          ),
        ),
        const SizedBox(height: 16),
        _buildNavButtons(),
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );

    if (!widget.useScaffold) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة دواء')),
      body: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: body,
      ),
    );
  }
}

/// يفتح المعالj حسب تفضيل المستخدم.
Future<PharmacyProductEditorModeAResult?> openPharmacyProductEditorWizard(
  BuildContext context, {
  PharmacyEditorMode? mode,
  int? tenantId,
  PharmacyProductEditorFormController? controller,
  PharmacyProductEditorWizardSaveTarget saveTarget =
      PharmacyProductEditorWizardSaveTarget.standalone,
  void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected,
  void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged,
  VoidCallback? onDraftCompleted,
}) async {
  final resolvedMode = mode ?? await PharmacyEditorModeStore.load();
  if (!context.mounted) return null;

  return Navigator.of(context).push<PharmacyProductEditorModeAResult>(
    MaterialPageRoute(
      builder: (_) => PharmacyProductEditorWizard(
        mode: resolvedMode,
        tenantId: tenantId,
        controller: controller,
        saveTarget: saveTarget,
        onDrugReferenceSelected: onDrugReferenceSelected,
        onBatchDraftChanged: onBatchDraftChanged,
        onDraftCompleted: onDraftCompleted,
      ),
    ),
  );
}

/// bottom sheet للدمج في «إضافة منتج».
Future<void> showPharmacyProductEditorWizardSheet({
  required BuildContext context,
  required PharmacyProductEditorFormController controller,
  PharmacyEditorMode? mode,
  required VoidCallback onDraftCompleted,
  void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected,
  void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged,
}) async {
  final resolvedMode = mode ?? await PharmacyEditorModeStore.load();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.92;
      return SizedBox(
        height: height,
        child: PharmacyProductEditorWizard(
          mode: resolvedMode,
          controller: controller,
          saveTarget: PharmacyProductEditorWizardSaveTarget.draftOnly,
          useScaffold: false,
          onDraftCompleted: onDraftCompleted,
          onDrugReferenceSelected: onDrugReferenceSelected,
          onBatchDraftChanged: onBatchDraftChanged,
        ),
      );
    },
  );
}
