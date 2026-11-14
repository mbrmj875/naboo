import 'package:flutter/material.dart';

import '../../../models/fluid_grade_sale_option.dart';
import '../../../services/oil_product_grades_repository.dart';
import '../../../widgets/oil_variants/fluid_family_editor_mode.dart';
import '../../../widgets/oil_variants/oil_grade_draft.dart';
import '../../../widgets/oil_variants/oil_viscosity_editor.dart';
import '../../_contract/vertical_manifest.dart';

/// تنفيذ [VerticalFluidInventoryEditor] لغيار الزيت.
final class OilChangeFluidInventoryEditor extends VerticalFluidInventoryEditor {
  const OilChangeFluidInventoryEditor();

  static const stockTypeHydraulicFamily = 4;
  static const stockTypeOilFamily = 5;

  FluidFamilyEditorMode _mode({required bool isOilFamily}) =>
      isOilFamily ? FluidFamilyEditorMode.oil : FluidFamilyEditorMode.hydraulic;

  List<OilGradeDraft> _castGrades(List<Object> grades) =>
      grades.cast<OilGradeDraft>();

  @override
  List<int> get addProductStockTypes =>
      const [stockTypeHydraulicFamily, stockTypeOilFamily];

  @override
  Object newGradeDraft() => OilGradeDraft();

  @override
  void disposeGradeDraft(Object draft) {
    (draft as OilGradeDraft).dispose();
  }

  @override
  void disposeGradeDrafts(Iterable<Object> drafts) {
    for (final d in drafts) {
      disposeGradeDraft(d);
    }
  }

  @override
  Widget buildGradesEditor({
    required BuildContext context,
    required bool isOilFamily,
    required List<Object> grades,
    required VoidCallback onChanged,
  }) {
    return OilViscosityEditor(
      mode: _mode(isOilFamily: isOilFamily),
      grades: _castGrades(grades),
      onChanged: onChanged,
    );
  }

  @override
  FluidFamilyEditorLabels labels({required bool isOilFamily}) {
    final mode = _mode(isOilFamily: isOilFamily);
    return FluidFamilyEditorLabels(
      familyNoun: mode.familyNoun,
      familyNameExample: mode.familyNameExample,
      gradeNoun: mode.gradeNoun,
      pricingHint:
          'سعر الشراء والبيع لكل ${mode.gradeNoun} يُحدَّد في الجدول أعلاه (باللتر). '
          'العبوات (علبة، كوارت…) لها أسعار اختيارية لكل ${mode.gradeNoun}.',
    );
  }

  @override
  String? validateFluidFamilyDrafts({
    required bool isOilFamily,
    required String familyName,
    required List<Object> gradeDrafts,
  }) {
    final mode = _mode(isOilFamily: isOilFamily);
    if (familyName.trim().isEmpty) {
      return 'أدخل اسم عائلة ${mode.familyNoun} (مثال: ${mode.familyNameExample}).';
    }
    final grades = oilGradesFromDrafts(_castGrades(gradeDrafts));
    if (grades.isEmpty) {
      return 'أضف ${mode.gradeNoun} واحدة على الأقل مع اسم صحيح.';
    }
    return null;
  }

  @override
  Future<int> createFluidFamily({
    required bool isOilFamily,
    required String familyName,
    required List<Object> gradeDrafts,
    int? categoryId,
    int? brandId,
    int? warehouseId,
    required double lowStockThreshold,
  }) async {
    final grades = oilGradesFromDrafts(_castGrades(gradeDrafts));
    final repo = OilProductGradesRepository.instance;
    if (isOilFamily) {
      return repo.createOilFamily(
        familyName: familyName.trim(),
        grades: grades,
        categoryId: categoryId,
        brandId: brandId,
        warehouseId: warehouseId,
        lowStockThreshold: lowStockThreshold,
      );
    }
    return repo.createHydraulicFamily(
      familyName: familyName.trim(),
      grades: grades,
      categoryId: categoryId,
      brandId: brandId,
      warehouseId: warehouseId,
      lowStockThreshold: lowStockThreshold,
    );
  }

  @override
  Future<List<FluidGradeSaleOption>> listSaleOptionsForParent(
    int parentProductId,
  ) {
    return OilProductGradesRepository.instance
        .listSaleOptionsForParent(parentProductId);
  }

  @override
  bool hasDirtyGradeDrafts(Iterable<Object> drafts) {
    bool dirty(String text, {String? ignore}) {
      final t = text.trim();
      if (ignore != null && t == ignore) return false;
      return t.isNotEmpty;
    }

    for (final raw in drafts) {
      final g = raw as OilGradeDraft;
      if (dirty(g.viscosityCtrl.text) ||
          dirty(g.qtyCtrl.text) ||
          dirty(g.buyCtrl.text) ||
          dirty(g.sellCtrl.text)) {
        return true;
      }
      for (final p in g.packs) {
        if (dirty(p.unitNameCtrl.text) ||
            dirty(p.unitSymbolCtrl.text) ||
            dirty(p.factorCtrl.text, ignore: '1') ||
            dirty(p.sellCtrl.text) ||
            dirty(p.barcodeCtrl.text)) {
          return true;
        }
      }
    }
    return false;
  }
}
