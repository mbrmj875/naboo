import 'package:flutter/material.dart';

import 'package:naboo/widgets/milliliter_quantity_stepper.dart';

/// حالة بطاقة هيدروليك واحدة (كير أو باور) في نموذج غيار الزيت.
class OilChangeHydraulicCardSlot {
  OilChangeHydraulicCardSlot({required this.rowKeyPrefix});

  /// `hydraulic` للكير، `powerHydraulic` للباور.
  final String rowKeyPrefix;

  bool customerProvided = false;
  final type = TextEditingController();
  String? selectedGrade;
  String? selectedBrand;
  int? catalogSellPerLiterFils;
  final sizeAmount = TextEditingController();
  final litersStock = TextEditingController();
  int? stockProductId;
  int? warehouseId;
  double availableLiters = 0;
  double? pickSellPerLiter;
  int? selectedFamilyKey;
  int? editStockVoucherId;
  double editLitersUsed = 0;
  int? editProductId;
  int? editWarehouseId;
  bool editCustomerProvided = false;

  static OilChangeHydraulicCardSlot gear() =>
      OilChangeHydraulicCardSlot(rowKeyPrefix: 'hydraulic');

  static OilChangeHydraulicCardSlot power() =>
      OilChangeHydraulicCardSlot(rowKeyPrefix: 'powerHydraulic');

  String col(String suffix) => '$rowKeyPrefix$suffix';

  void dispose() {
    type.dispose();
    sizeAmount.dispose();
    litersStock.dispose();
  }

  void loadFromRow(Map<String, dynamic> row, {required bool stockEnabled}) {
    type.text = (row[col('Type')] ?? '').toString();
    final gradeRaw = row[col('Grade')]?.toString();
    selectedGrade = gradeRaw == null || gradeRaw.isEmpty ? null : gradeRaw;
    customerProvided = ((row[col('CustomerProvided')] as num?)?.toInt() ?? 0) != 0;
    stockProductId = (row[col('ProductId')] as num?)?.toInt();
    warehouseId = (row[col('WarehouseId')] as num?)?.toInt();
    final liters = (row[col('LitersUsed')] as num?)?.toDouble();
    if (liters != null && liters > 0) {
      litersStock.text = liters % 1 == 0
          ? liters.toInt().toString()
          : liters.toString();
      final ml = (liters * 1000).round();
      if (ml > 0) sizeAmount.text = formatOilVolumeDisplay(ml);
    }
    editStockVoucherId = (row[col('StockVoucherId')] as num?)?.toInt();
    editLitersUsed = liters ?? 0;
    editProductId = stockProductId;
    editWarehouseId = warehouseId;
    editCustomerProvided = customerProvided;
    if (!stockEnabled) {
      stockProductId = null;
      warehouseId = null;
      litersStock.clear();
    }
  }

  double litersForPricing() {
    final ml = parseOilVolumeDisplay(sizeAmount.text);
    return ml / 1000.0;
  }

  void syncLitersFromStepper() {
    final liters = litersForPricing();
    if (liters <= 1e-9) {
      litersStock.clear();
      return;
    }
    litersStock.text = formatOilLitersDisplay(liters);
  }

  String? sizeValueForSave({
    required bool usesWarehousePicker,
    required bool effectiveCustomerProvided,
  }) {
    if (usesWarehousePicker) {
      final liters = litersForPricing();
      if (liters <= 0) return null;
      final ml = (liters * 1000).round();
      return '${formatOilVolumeDisplay(ml)} L';
    }
    if (effectiveCustomerProvided || (catalogSellPerLiterFils ?? 0) > 0) {
      final ml = parseOilVolumeDisplay(sizeAmount.text);
      if (ml <= 0) return null;
      return '${formatOilVolumeDisplay(ml)} L';
    }
    final ml = parseOilVolumeDisplay(sizeAmount.text);
    if (ml <= 0) return null;
    return '${formatOilVolumeDisplay(ml)} L';
  }

  void clearStockSelection() {
    selectedFamilyKey = null;
    stockProductId = null;
    pickSellPerLiter = null;
    availableLiters = 0;
    selectedGrade = null;
  }

  void clearCatalogSelection() {
    selectedBrand = null;
    catalogSellPerLiterFils = null;
  }
}
