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
  }) : assert(
          editOrderId == null || prefillFromOrder == null,
          'لا يجمع التعديل مع التعبئة لبطاقة جديدة',
        );

  final int? editOrderId;
  final String? editOrderGlobalId;
  final Map<String, dynamic>? prefillFromOrder;

  @override
  Widget build(BuildContext context) {
    final stable = oilChangeFormStableKey(
      editOrderId: editOrderId,
      prefillFromOrder: prefillFromOrder,
    );
    return OilChangeOrderFormScreen(
      key: ValueKey(
        stable != null ? 'oil-form-$stable' : 'oil-form-new',
      ),
      editOrderId: editOrderId,
      editOrderGlobalId: editOrderGlobalId,
      prefillFromOrder: prefillFromOrder,
    );
  }
}
