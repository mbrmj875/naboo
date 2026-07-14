import '../../../utils/iqd_money.dart';
import '../models/oil_change_filter_kind.dart';
import 'oil_change_filter_format.dart';

/// يبني حمولة `order` لـ Webhook n8n — نفس حقول رسالة الواتساب التلقائية (بدون رقم فاتورة).
Map<String, dynamic> buildOilChangeWebhookOrderPayload({
  required Map<String, dynamic> order,
  required String storeTitle,
}) {
  void putIf(String key, String? value, Map<String, dynamic> map) {
    final v = value?.trim();
    if (v != null && v.isNotEmpty) map[key] = v;
  }

  final customerName =
      (order['customerNameSnapshot'] ?? '').toString().trim();
  final shop = storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim();

  final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
  final estimatedF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
  final totalFils = agreedF ?? estimatedF;
  final paidFils = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
  final remainderFils =
      totalFils > 0 ? (totalFils - paidFils).clamp(0, totalFils) : 0;

  int toIqd(int fils) => fils > 0 ? IqdMoney.fromFils(fils).round() : 0;

  final services = (order['requestedServices'] ?? '').toString().trim();
  final serviceList = services.isEmpty
      ? <String>[]
      : services
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

  final filters = <String>[];
  for (final kind in OilChangeFilterKind.all) {
    final name = (order[kind.nameColumnKey] ?? '').toString().trim();
    if (name.isNotEmpty) filters.add('${kind.label}: $name');
  }

  final payload = <String, dynamic>{
    'customer_name':
        customerName.isEmpty ? 'عميلنا الكريم' : customerName,
    'store_name': shop,
  };

  putIf('car_name', (order['deviceName'] ?? '').toString(), payload);
  putIf('car_model', (order['carModel'] ?? '').toString(), payload);
  putIf('engine_size', (order['engineSize'] ?? '').toString(), payload);
  putIf('plate', (order['deviceSerial'] ?? '').toString(), payload);
  putIf('odometer_current', (order['odometerCurrent'] ?? '').toString(), payload);
  putIf('odometer_next', (order['odometerNext'] ?? '').toString(), payload);
  putIf('oil_brand', (order['oilType'] ?? '').toString(), payload);
  putIf('oil_grade', (order['oilViscosity'] ?? '').toString(), payload);
  putIf('oil_size', (order['oilSize'] ?? '').toString(), payload);

  final gearHyd = _hydraulicPayload(
    type: (order['hydraulicType'] ?? '').toString(),
    grade: (order['hydraulicGrade'] ?? '').toString(),
    size: (order['hydraulicSize'] ?? '').toString(),
    customerProvided: order['hydraulicCustomerProvided'] == 1,
    label: 'هيدروليك القير',
  );
  final powerHyd = _hydraulicPayload(
    type: (order['powerHydraulicType'] ?? '').toString(),
    grade: (order['powerHydraulicGrade'] ?? '').toString(),
    size: (order['powerHydraulicSize'] ?? '').toString(),
    customerProvided: order['powerHydraulicCustomerProvided'] == 1,
    label: 'هيدروليك الباور',
  );
  if (gearHyd != null) payload['hydraulic_gear'] = gearHyd;
  if (powerHyd != null) payload['hydraulic_power'] = powerHyd;
  if (filters.isNotEmpty) payload['filters'] = filters;
  if (serviceList.isNotEmpty) payload['oil_ticket_services'] = serviceList;

  if (totalFils > 500) payload['total_iqd'] = toIqd(totalFils);
  if (paidFils > 500) payload['paid_iqd'] = toIqd(paidFils);
  if (remainderFils > 500) payload['remainder_iqd'] = toIqd(remainderFils);

  // invoiceId و priorOpenDebtFils عمداً لا يُرسلان للرسالة — للتوافق الخلفي فقط.
  return payload;
}

String? _hydraulicPayload({
  required String type,
  required String grade,
  required String size,
  required bool customerProvided,
  required String label,
}) {
  if (customerProvided) return '$label: من العميل';
  final parts = <String>[
    if (type.trim().isNotEmpty) type.trim(),
    if (grade.trim().isNotEmpty) grade.trim(),
    if (size.trim().isNotEmpty) size.trim(),
  ];
  if (parts.isEmpty) return null;
  return '$label: ${parts.join(' — ')}';
}
