import '../../../utils/customer_validation.dart';

/// مفتاح مطابقة بطاقة + رقم. فارغ إن نقص أحدهما حتى لا نُسقط رسالة أخرى.
String? whatsappDeliveryProofKey({
  required String orderRef,
  required String phone,
}) {
  final order = orderRef.trim();
  if (order.isEmpty || order == '0') return null;
  final phoneKey = CustomerValidation.phoneMatchKey(phone);
  if (phoneKey == null || phoneKey.isEmpty) return null;
  return '$order|$phoneKey';
}
