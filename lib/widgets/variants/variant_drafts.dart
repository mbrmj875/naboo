import 'package:flutter/material.dart';

class VariantSizeDraft {
  VariantSizeDraft({
    String size = '',
    int qty = 0,
    String barcode = '',
  })  : sizeCtrl = TextEditingController(text: size),
        qtyCtrl = TextEditingController(text: '$qty'),
        barcodeCtrl = TextEditingController(text: barcode);

  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController barcodeCtrl;

  void dispose() {
    sizeCtrl.dispose();
    qtyCtrl.dispose();
    barcodeCtrl.dispose();
  }
}

class VariantColorDraft {
  VariantColorDraft({
    String name = '',
    String hex = '',
    List<VariantSizeDraft>? sizes,
  })  : nameCtrl = TextEditingController(text: name),
        hexCtrl = TextEditingController(text: hex),
        sizes = sizes ?? <VariantSizeDraft>[];

  final TextEditingController nameCtrl;
  final TextEditingController hexCtrl;
  final List<VariantSizeDraft> sizes;

  /// إذا عدّل المستخدم الاسم يدوياً مرة، لا نعيد تعبئته تلقائياً لاحقاً.
  bool nameManuallyEdited = false;

  void dispose() {
    nameCtrl.dispose();
    hexCtrl.dispose();
    for (final s in sizes) {
      s.dispose();
    }
  }
}

