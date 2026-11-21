import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../_contract/vertical_manifest.dart';
import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import '../models/pharmacy_rx_schedule.dart';
import '../services/drug_catalog_repository.dart';
import 'pharmacy_product_editor_save_service.dart';
import 'pharmacy_product_editor_validation.dart';

final class PharmacyDrugReferenceSnapshot
    implements VerticalPharmacyDrugReferenceSnapshot {
  PharmacyDrugReferenceSnapshot(this._inner);

  final PharmacyDrugReference _inner;

  @override
  int get id => _inner.id;

  @override
  String get nameAr => _inner.nameAr;

  @override
  String get nameEn => _inner.nameEn;

  @override
  String? get atcCode => _inner.atcCode;

  PharmacyDrugReference get inner => _inner;
}

final class PharmacyBatchDraftSnapshot
    implements VerticalPharmacyBatchDraftSnapshot {
  const PharmacyBatchDraftSnapshot({
    required this.batchNo,
    required this.expiryDate,
    required this.costFils,
    required this.qty,
  });

  @override
  final String batchNo;
  @override
  final DateTime expiryDate;
  @override
  final int costFils;
  @override
  final double qty;
}

/// حالة نموذج إضافة دواء — مشتركة بين Mode A والدمج في Core.
class PharmacyProductEditorFormController {
  PharmacyProductEditorFormController({
    int? tenantId,
    DrugCatalogRepository? catalog,
    PharmacyProductEditorSaveService? saveService,
    void Function()? scheduleSync,
  })  : _catalog = catalog ??
            DrugCatalogRepository(scheduleSync: scheduleSync ?? () {}),
        _saveService = saveService ??
            PharmacyProductEditorSaveService(
              catalog: catalog ??
                  DrugCatalogRepository(scheduleSync: scheduleSync ?? () {}),
            ),
        _tenantIdOverride = tenantId;

  final DrugCatalogRepository _catalog;
  final PharmacyProductEditorSaveService _saveService;
  final int? _tenantIdOverride;

  final drugReferenceController = TextEditingController();
  final strengthCtrl = TextEditingController();
  final batchCtrl = TextEditingController();
  final expiryCtrl = TextEditingController();
  final costFilsCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();

  int? _tenantId;
  bool loadingCatalog = true;
  String? loadError;

  List<PharmacyManufacturer> manufacturers = const [];
  List<PharmacyDosageForm> dosageForms = const [];

  PharmacyDrugReference? selectedReference;
  PharmacyManufacturer? selectedManufacturer;
  PharmacyDosageForm? selectedDosageForm;
  DateTime? expiryDate;
  String rxSchedule = PharmacyRxSchedule.otc;
  int formGeneration = 0;

  Future<void> load() async {
    loadingCatalog = true;
    loadError = null;
    try {
      _tenantId = _tenantIdOverride ?? await _catalog.resolveTenantId();
      manufacturers =
          await _catalog.listManufacturers(tenantId: _tenantId!);
      dosageForms = await _catalog.listDosageForms(tenantId: _tenantId!);
      loadingCatalog = false;
    } catch (_) {
      loadError = 'تعذّر تحميل بيانات الصيدلية';
      loadingCatalog = false;
    }
  }

  void dispose() {
    drugReferenceController.dispose();
    strengthCtrl.dispose();
    batchCtrl.dispose();
    expiryCtrl.dispose();
    costFilsCtrl.dispose();
    qtyCtrl.dispose();
  }

  void reset() {
    drugReferenceController.clear();
    strengthCtrl.clear();
    batchCtrl.clear();
    expiryCtrl.clear();
    costFilsCtrl.clear();
    qtyCtrl.clear();
    selectedReference = null;
    selectedManufacturer = null;
    selectedDosageForm = null;
    expiryDate = null;
    rxSchedule = PharmacyRxSchedule.otc;
    formGeneration++;
  }

  void selectReference(PharmacyDrugReference reference) {
    selectedReference = reference;
    drugReferenceController.text = reference.nameAr.isNotEmpty
        ? reference.nameAr
        : reference.nameEn;
  }

  void clearSelectedReference() {
    selectedReference = null;
  }

  PharmacyBatchDraftSnapshot? currentBatchDraft() {
    final costFils = int.tryParse(costFilsCtrl.text.trim());
    final qty = double.tryParse(qtyCtrl.text.trim());
    final batchNo = batchCtrl.text.trim();
    if (batchNo.isEmpty || expiryDate == null || costFils == null || qty == null) {
      return null;
    }
    return PharmacyBatchDraftSnapshot(
      batchNo: batchNo,
      expiryDate: expiryDate!,
      costFils: costFils,
      qty: qty,
    );
  }

  String? validateForSave() {
    final costFils = int.tryParse(costFilsCtrl.text.trim());
    final qty = double.tryParse(qtyCtrl.text.trim());
    return PharmacyProductEditorValidation.validate(
      reference: selectedReference,
      manufacturer: selectedManufacturer,
      dosageForm: selectedDosageForm,
      strengthText: strengthCtrl.text,
      batchNo: batchCtrl.text,
      expiryDate: expiryDate,
      costFils: costFils,
      qty: qty,
    ).errorMessage;
  }

  /// يحلّ المادة الفعّالة قبل الحفظ: اختيار مطابق، أو إنشاء مرجع جديد من النص.
  Future<String?> resolveReferenceBeforeSave() async {
    if (selectedReference != null) return null;
    final query = drugReferenceController.text.trim();
    if (query.isEmpty) {
      return 'اختر المادة الفعّالة من القائمة';
    }
    final tenantId = _tenantId;
    if (tenantId == null) {
      return 'تعذّر تحميل بيانات الصيدلية';
    }

    final matches = await _catalog.searchDrugReferences(
      tenantId: tenantId,
      query: query,
    );
    if (matches.length == 1) {
      selectReference(matches.single);
      return null;
    }

    final normalized = query.toLowerCase();
    for (final match in matches) {
      if (match.nameAr.trim().toLowerCase() == normalized ||
          match.nameEn.trim().toLowerCase() == normalized) {
        selectReference(match);
        return null;
      }
    }

    try {
      final id = await _catalog.insertDrugReference(
        tenantId: tenantId,
        nameAr: query,
        nameEn: query,
      );
      final created = await _catalog.getDrugReferenceById(
        tenantId: tenantId,
        id: id,
      );
      if (created == null) {
        return 'تعذّر إنشاء المادة الفعّالة';
      }
      selectReference(created);
      return null;
    } catch (_) {
      return 'تعذّر إنشاء المادة الفعّالة';
    }
  }

  PharmacyProductEditorSaveInput? buildSaveInput() {
    final tenantId = _tenantId;
    if (tenantId == null) return null;
    final costFils = int.tryParse(costFilsCtrl.text.trim());
    final qty = double.tryParse(qtyCtrl.text.trim());
    final validation = PharmacyProductEditorValidation.validate(
      reference: selectedReference,
      manufacturer: selectedManufacturer,
      dosageForm: selectedDosageForm,
      strengthText: strengthCtrl.text,
      batchNo: batchCtrl.text,
      expiryDate: expiryDate,
      costFils: costFils,
      qty: qty,
    );
    if (!validation.isValid) return null;
    return PharmacyProductEditorSaveInput(
      tenantId: tenantId,
      reference: selectedReference!,
      manufacturer: selectedManufacturer!,
      dosageForm: selectedDosageForm!,
      strengthText: strengthCtrl.text.trim(),
      rxSchedule: rxSchedule,
      batchNo: batchCtrl.text.trim(),
      expiryDate: expiryDate!,
      costFils: costFils!,
      qty: qty!,
    );
  }

  String? suggestedProductName() {
    final input = buildSaveInput();
    if (input == null) return null;
    return PharmacyProductEditorSaveService.buildProductName(input);
  }

  double? suggestedQty() {
    return double.tryParse(qtyCtrl.text.trim());
  }

  int? suggestedCostFils() {
    return int.tryParse(costFilsCtrl.text.trim());
  }

  String? suggestedExpiryIso() {
    if (expiryDate == null) return null;
    return DateTime(
      expiryDate!.year,
      expiryDate!.month,
      expiryDate!.day,
    ).toIso8601String();
  }

  Future<PharmacyProductEditorSaveResult> saveStandalone() async {
    final resolveErr = await resolveReferenceBeforeSave();
    if (resolveErr != null) {
      throw StateError(resolveErr);
    }
    final input = buildSaveInput();
    if (input == null) {
      throw StateError(validateForSave() ?? 'invalid_input');
    }
    return _saveService.save(input);
  }

  Future<PharmacyProductEditorSaveResult> saveForExistingProduct(
    int productId,
  ) async {
    final resolveErr = await resolveReferenceBeforeSave();
    if (resolveErr != null) {
      throw StateError(resolveErr);
    }
    final input = buildSaveInput();
    if (input == null) {
      throw StateError(validateForSave() ?? 'invalid_input');
    }
    return _saveService.saveForExistingProduct(
      productId: productId,
      input: input,
    );
  }

  void setExpiryDate(DateTime date) {
    expiryDate = date;
    expiryCtrl.text = DateFormat.yMMMd('ar').format(date);
  }

  DrugCatalogRepository get catalog => _catalog;
  int? get tenantId => _tenantId;
}

/// Alias للتوافق مع مواصفات Mode A.
typedef PharmacyProductEditorModeAController = PharmacyProductEditorFormController;
