import 'package:flutter/material.dart';

/// عبوة بيع لزوجة (علبة / كوارت / …).
class OilGradePackDraft {
  OilGradePackDraft({
    String unitName = '',
    String unitSymbol = '',
    String factor = '1',
  })  : unitNameCtrl = TextEditingController(text: unitName),
        unitSymbolCtrl = TextEditingController(text: unitSymbol),
        factorCtrl = TextEditingController(text: factor),
        sellCtrl = TextEditingController(),
        barcodeCtrl = TextEditingController();

  final TextEditingController unitNameCtrl;
  final TextEditingController unitSymbolCtrl;
  final TextEditingController factorCtrl;
  final TextEditingController sellCtrl;
  final TextEditingController barcodeCtrl;

  void dispose() {
    unitNameCtrl.dispose();
    unitSymbolCtrl.dispose();
    factorCtrl.dispose();
    sellCtrl.dispose();
    barcodeCtrl.dispose();
  }
}

/// صف لزوجة ضمن عائلة زيت.
class OilGradeDraft {
  OilGradeDraft({
    String viscosity = '',
    String qtyLiters = '0',
    String buy = '0',
    String sell = '0',
    this.gradeRowId,
    this.linkedProductId,
  })  : viscosityCtrl = TextEditingController(text: viscosity),
        qtyCtrl = TextEditingController(text: qtyLiters),
        buyCtrl = TextEditingController(text: buy),
        sellCtrl = TextEditingController(text: sell),
        barcodeCtrl = TextEditingController(),
        packs = <OilGradePackDraft>[];

  /// صف [product_oil_grades] عند التعديل.
  final int? gradeRowId;

  /// صنف المخزون المرتبط باللزوجة.
  final int? linkedProductId;

  final TextEditingController viscosityCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController buyCtrl;
  final TextEditingController sellCtrl;
  final TextEditingController barcodeCtrl;
  final List<OilGradePackDraft> packs;

  void dispose() {
    viscosityCtrl.dispose();
    qtyCtrl.dispose();
    buyCtrl.dispose();
    sellCtrl.dispose();
    barcodeCtrl.dispose();
    for (final p in packs) {
      p.dispose();
    }
  }
}

/// قوالب لزوجة زيت شائعة (كتالوج الغيار + عائلات المخزون).
const kCommonOilViscosities = [
  '0W8',
  '0W16',
  '0W20',
  '0W30',
  '5W20',
  '5W30',
  '5W40',
  '10W30',
  '10W40',
  '15W40',
  '20W50',
];

/// قوالب درجة هيدروليك شائعة.
const kCommonHydraulicGrades = [
  'ISO VG 32',
  'ISO VG 46',
  'ISO VG 68',
  'AW 32',
  'AW 46',
  'ATF DEXRON',
];

/// قوالب عبوات شائعة (الاسم + معامل لتر).
const kOilPackPresets = <({String name, String symbol, String factor})>[
  (name: 'علبة 1 لتر', symbol: 'L', factor: '1'),
  (name: 'علبة 4 لتر', symbol: 'L', factor: '4'),
  (name: 'علبة 5 لتر', symbol: 'L', factor: '5'),
  (name: 'كوارت', symbol: 'qt', factor: '0.946'),
  (name: 'تين', symbol: '', factor: '2'),
  (name: 'ثلاثة', symbol: '', factor: '3'),
];
