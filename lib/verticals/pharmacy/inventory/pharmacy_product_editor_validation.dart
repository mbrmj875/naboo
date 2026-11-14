import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';

/// نتيجة التحقق من نموذج إضافة دواء (Mode A).
class PharmacyProductEditorValidationResult {
  const PharmacyProductEditorValidationResult.valid()
      : errorMessage = null;

  const PharmacyProductEditorValidationResult.invalid(this.errorMessage);

  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

/// قواعد التحقق — قابلة للاختبار بدون Widget.
abstract final class PharmacyProductEditorValidation {
  PharmacyProductEditorValidation._();

  static final _strengthNumberPattern = RegExp(r'(\d+(?:\.\d+)?)');

  static List<String> collectErrors({
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    final errors = <String>[];
    if (reference == null) {
      errors.add('اختر المادة الفعّالة من القائمة');
    }
    if (manufacturer == null) {
      errors.add('اختر الشركة');
    }
    if (dosageForm == null) {
      errors.add('اختر الشكل الصيدلاني');
    }
    if (parseStrengthValue(strengthText) <= 0) {
      errors.add('أدخل تركيزاً صحيحاً أكبر من صفر');
    }
    if (batchNo.trim().isEmpty) {
      errors.add('أدخل رقم الدفعة');
    }
    if (expiryDate == null) {
      errors.add('اختر تاريخ الصلاحية');
    } else {
      final startOfToday = _startOfDay(today ?? DateTime.now());
      if (_startOfDay(expiryDate).isBefore(startOfToday)) {
        errors.add('تاريخ الصلاحية يجب أن يكون اليوم أو بعده');
      }
    }
    if (costFils == null || costFils <= 0) {
      errors.add('أدخل سعر شراء صحيحاً أكبر من صفر');
    }
    if (qty == null || qty <= 0) {
      errors.add('أدخل كمية صحيحة أكبر من صفر');
    }
    return errors;
  }

  static PharmacyProductEditorValidationResult validate({
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    final errors = collectErrors(
      reference: reference,
      manufacturer: manufacturer,
      dosageForm: dosageForm,
      strengthText: strengthText,
      batchNo: batchNo,
      expiryDate: expiryDate,
      costFils: costFils,
      qty: qty,
      today: today,
    );
    if (errors.isEmpty) {
      return const PharmacyProductEditorValidationResult.valid();
    }
    return PharmacyProductEditorValidationResult.invalid(errors.join('\n'));
  }

  static double parseStrengthValue(String strengthText) {
    final match = _strengthNumberPattern.firstMatch(strengthText.trim());
    if (match == null) return 0;
    return double.tryParse(match.group(1)!) ?? 0;
  }

  /// أخطاء خطوة واحدة في معالج إضافة الدواء — `null` = يمكن المتابعة.
  static String? validationErrorForWizardStep({
    required int stepIndex,
    required int totalSteps,
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    if (totalSteps == 4) {
      return _modeAStepError(
        stepIndex: stepIndex,
        reference: reference,
        manufacturer: manufacturer,
        dosageForm: dosageForm,
        strengthText: strengthText,
        batchNo: batchNo,
        expiryDate: expiryDate,
        costFils: costFils,
        qty: qty,
        today: today,
      );
    }
    if (totalSteps == 2) {
      return _modeBStepError(
        stepIndex: stepIndex,
        reference: reference,
        manufacturer: manufacturer,
        dosageForm: dosageForm,
        strengthText: strengthText,
        batchNo: batchNo,
        expiryDate: expiryDate,
        costFils: costFils,
        qty: qty,
        today: today,
      );
    }
    if (totalSteps == 6) {
      return _modeCStepError(
        stepIndex: stepIndex,
        reference: reference,
        manufacturer: manufacturer,
        dosageForm: dosageForm,
        strengthText: strengthText,
        batchNo: batchNo,
        expiryDate: expiryDate,
        costFils: costFils,
        qty: qty,
        today: today,
      );
    }
    return 'خطوة غير معروفة';
  }

  static bool canProceedWizardStep({
    required int stepIndex,
    required int totalSteps,
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    return validationErrorForWizardStep(
          stepIndex: stepIndex,
          totalSteps: totalSteps,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        ) ==
        null;
  }

  static String? _modeAStepError({
    required int stepIndex,
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    switch (stepIndex) {
      case 0:
        if (reference == null) return 'اختر المادة الفعّالة من القائمة';
        return null;
      case 1:
        if (manufacturer == null) return 'اختر الشركة';
        if (dosageForm == null) return 'اختر الشكل الصيدلاني';
        if (parseStrengthValue(strengthText) <= 0) {
          return 'أدخل تركيزاً صحيحاً أكبر من صفر';
        }
        return null;
      case 2:
        if (batchNo.trim().isEmpty) return 'أدخل رقم الدفعة';
        if (expiryDate == null) return 'اختر تاريخ الصلاحية';
        final startOfToday = _startOfDay(today ?? DateTime.now());
        if (_startOfDay(expiryDate).isBefore(startOfToday)) {
          return 'تاريخ الصلاحية يجب أن يكون اليوم أو بعده';
        }
        return null;
      case 3:
        if (costFils == null || costFils <= 0) {
          return 'أدخل سعر شراء صحيحاً أكبر من صفر';
        }
        if (qty == null || qty <= 0) {
          return 'أدخل كمية صحيحة أكبر من صفر';
        }
        return null;
      default:
        return 'خطوة غير معروفة';
    }
  }

  static String? _modeBStepError({
    required int stepIndex,
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    switch (stepIndex) {
      case 0:
        return _modeAStepError(
          stepIndex: 0,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        ) ??
            _modeAStepError(
              stepIndex: 1,
              reference: reference,
              manufacturer: manufacturer,
              dosageForm: dosageForm,
              strengthText: strengthText,
              batchNo: batchNo,
              expiryDate: expiryDate,
              costFils: costFils,
              qty: qty,
              today: today,
            );
      case 1:
        return _modeAStepError(
          stepIndex: 2,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        ) ??
            _modeAStepError(
              stepIndex: 3,
              reference: reference,
              manufacturer: manufacturer,
              dosageForm: dosageForm,
              strengthText: strengthText,
              batchNo: batchNo,
              expiryDate: expiryDate,
              costFils: costFils,
              qty: qty,
              today: today,
            );
      default:
        return 'خطوة غير معروفة';
    }
  }

  static String? _modeCStepError({
    required int stepIndex,
    required PharmacyDrugReference? reference,
    required PharmacyManufacturer? manufacturer,
    required PharmacyDosageForm? dosageForm,
    required String strengthText,
    required String batchNo,
    required DateTime? expiryDate,
    required int? costFils,
    required double? qty,
    DateTime? today,
  }) {
    switch (stepIndex) {
      case 0:
        return _modeAStepError(
          stepIndex: 0,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        );
      case 1:
        if (manufacturer == null) return 'اختر الشركة';
        return null;
      case 2:
        if (dosageForm == null) return 'اختر الشكل الصيدلاني';
        if (parseStrengthValue(strengthText) <= 0) {
          return 'أدخل تركيزاً صحيحاً أكبر من صفر';
        }
        return null;
      case 3:
        return _modeAStepError(
          stepIndex: 2,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        );
      case 4:
        return _modeAStepError(
          stepIndex: 3,
          reference: reference,
          manufacturer: manufacturer,
          dosageForm: dosageForm,
          strengthText: strengthText,
          batchNo: batchNo,
          expiryDate: expiryDate,
          costFils: costFils,
          qty: qty,
          today: today,
        );
      case 5:
        return null;
      default:
        return 'خطوة غير معروفة';
    }
  }

  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
