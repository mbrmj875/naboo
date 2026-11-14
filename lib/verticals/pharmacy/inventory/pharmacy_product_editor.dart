import 'package:flutter/material.dart';

import '../../_contract/vertical_manifest.dart';
import 'pharmacy_product_editor_form.dart';
import 'pharmacy_product_editor_mode_a.dart';
import 'pharmacy_product_editor_mode.dart';
import 'pharmacy_product_editor_wizard.dart';

/// جلسة محرّr صيدلية — للدمج في Core أو الاختبارات.
final class PharmacyProductEditorSession
    extends VerticalPharmacyProductEditorSession {
  PharmacyProductEditorSession({
    int? tenantId,
    PharmacyProductEditorFormController? controller,
  }) : _controller = controller ?? PharmacyProductEditorFormController(tenantId: tenantId);

  final PharmacyProductEditorFormController _controller;

  PharmacyProductEditorFormController get controller => _controller;

  @override
  Widget buildAddProductSection({
    required BuildContext context,
    required VoidCallback onChanged,
    void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
        onDrugReferenceSelected,
    void Function(VerticalPharmacyBatchDraftSnapshot batch)? onBatchDraftChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'أدخل بيانات الدواء عبر المعالج خطوة بخطوة.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            showPharmacyProductEditorWizardSheet(
              context: context,
              controller: _controller,
              onDraftCompleted: onChanged,
              onDrugReferenceSelected: onDrugReferenceSelected,
              onBatchDraftChanged: onBatchDraftChanged,
            );
          },
          icon: const Icon(Icons.medication_outlined),
          label: const Text('فتح معالج إضافة دواء'),
        ),
      ],
    );
  }

  @override
  String? validateForSave() => _controller.validateForSave();

  @override
  Future<String?> resolveReferenceBeforeSave() =>
      _controller.resolveReferenceBeforeSave();

  @override
  Future<void> save({
    required int tenantId,
    required int productId,
  }) async {
    await _controller.saveForExistingProduct(productId);
  }

  @override
  String? suggestedProductName() => _controller.suggestedProductName();

  @override
  double? suggestedQty() => _controller.suggestedQty();

  @override
  int? suggestedCostFils() => _controller.suggestedCostFils();

  @override
  String? suggestedExpiryIso() => _controller.suggestedExpiryIso();

  @override
  void resetForm() => _controller.reset();

  @override
  void dispose() => _controller.dispose();
}

/// محرّr منتج صيدلاني — يدعم المعالj والدمج في «إضافة منتج».
final class PharmacyProductEditor extends VerticalPharmacyProductEditor {
  const PharmacyProductEditor();

  @override
  VerticalPharmacyProductEditorSession createSession({int? tenantId}) {
    return PharmacyProductEditorSession(tenantId: tenantId);
  }

  /// يفتح معالj إضافة دواء (حسب تفضيل المستخدم).
  Widget buildStandaloneLauncher({
    required BuildContext context,
    required VoidCallback onChanged,
  }) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        onPressed: () async {
          final result = await openPharmacyProductEditorWizard(context);
          if (result != null) onChanged();
        },
        icon: const Icon(Icons.medication_outlined),
        label: const Text('إضافة دواء'),
      ),
    );
  }
}

/// يفتح معالj Mode A — للمسارات والاختبارات.
Future<PharmacyProductEditorModeAResult?> openPharmacyProductEditorModeA(
  BuildContext context, {
  int? tenantId,
  PharmacyProductEditorFormController? controller,
}) {
  return openPharmacyProductEditorWizard(
    context,
    mode: PharmacyEditorMode.modeA,
    tenantId: tenantId,
    controller: controller,
  );
}
