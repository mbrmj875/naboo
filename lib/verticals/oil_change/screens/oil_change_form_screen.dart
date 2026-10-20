import 'package:flutter/material.dart';

import 'oil_change_order_form_screen.dart';

/// مفتاح ثابت لحالة النموذج — لا يعتمد على [Map.hashCode] حتى لا تُعاد تهيئة الحقول.
int? oilChangeFormStableKey({
  int? editOrderId,
  Map<String, dynamic>? prefillFromOrder,
}) {
  if (editOrderId != null && editOrderId > 0) return editOrderId;
  final prefillId = (prefillFromOrder?['id'] as num?)?.toInt();
  if (prefillId != null && prefillId > 0) return -prefillId;
  return null;
}

/// نموذج بطاقة غيار الزيت — منفصل عن تذاكر الصيانة (لا يستخدم مسارات التذاكر).
class OilChangeFormScreen extends StatelessWidget {
  const OilChangeFormScreen({
    super.key,
    this.editOrderId,
    this.editOrderGlobalId,
    this.prefillFromOrder,
    this.amendInvoicedOrder = false,
  }) : assert(
          !amendInvoicedOrder || editOrderId != null,
          'تصحيح الفاتورة يتطلب بطاقة موجودة',
        );

  final int? editOrderId;
  final String? editOrderGlobalId;

  /// لقطة صف من السجل لفتح فوري (تعديل/تصحيح أو بطاقة جديدة من زيارة سابقة).
  final Map<String, dynamic>? prefillFromOrder;

  /// تعديل بطاقة مكتملة مربوطة بفاتورة — يحدّث نفس الفاتورة والصندوق.
  final bool amendInvoicedOrder;

  @override
  Widget build(BuildContext context) {
    final stable = oilChangeFormStableKey(
      editOrderId: editOrderId,
      prefillFromOrder: prefillFromOrder,
    );
    final keySuffix = amendInvoicedOrder ? 'amend' : 'std';
    return OilChangeOrderFormScreen(
      key: ValueKey(
        stable != null ? 'oil-form-$stable-$keySuffix' : 'oil-form-new',
      ),
      editOrderId: editOrderId,
      editOrderGlobalId: editOrderGlobalId,
      prefillFromOrder: prefillFromOrder,
      amendInvoicedOrder: amendInvoicedOrder,
    );
  }
}
