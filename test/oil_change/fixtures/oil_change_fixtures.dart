/// بيانات تجريبية ثابتة لاختبارات تخصص غيار الزيت.
library;

import 'package:naboo/services/service_order_kinds.dart';

/// بيانات سيارة تجريبية.
const oilTestCarPlate = 'ABC-1234';
const oilTestCarModel = 'Toyota Corolla 2020';
const oilTestOdometerCurrent = '50000';
const oilTestOdometerNext = '52000';
const oilTestDeviceName = 'كورولا';

/// بيانات زيت تجريبية.
const oilTestOilType = 'Synthetic';
const oilTestOilViscosity = '5W-30';
const oilTestOilSize = '5L';
const oilTestOilLiters = 4.5;
const oilTestAgreedPriceFils = 50000;
const oilTestCustomerName = 'عميل تجريبي';

/// فني تجريبي.
const oilTestTechnicianName = 'أحمد علي';

/// معرّفات tenant افتراضية في اختبارات SQLite.
const oilTestTenantId = 1;

Map<String, dynamic> oilTestOrderPayload({
  String status = 'pending',
  int? agreedPriceFils = oilTestAgreedPriceFils,
  int? estimatedPriceFils,
  int advancePaymentFils = 0,
  int? invoiceId,
  String? deviceSerial = oilTestCarPlate,
  String? technicianName = oilTestTechnicianName,
  bool oilCustomerProvided = false,
  int? oilProductId,
  double? oilLitersUsed,
  String? createdAt,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'global_id': 'oil-fixture-${DateTime.now().microsecondsSinceEpoch}',
    'orderKind': ServiceOrderKinds.oilChange,
    'customerNameSnapshot': oilTestCustomerName,
    'deviceName': oilTestDeviceName,
    'deviceSerial': deviceSerial,
    'carModel': oilTestCarModel,
    'odometerCurrent': oilTestOdometerCurrent,
    'odometerNext': oilTestOdometerNext,
    'oilType': oilTestOilType,
    'oilViscosity': oilTestOilViscosity,
    'oilSize': oilTestOilSize,
    'estimatedPriceFils': estimatedPriceFils ?? agreedPriceFils ?? 0,
    'agreedPriceFils': agreedPriceFils,
    'advancePaymentFils': advancePaymentFils,
    'status': status,
    'technicianName': technicianName,
    'oilCustomerProvided': oilCustomerProvided ? 1 : 0,
    if (oilProductId != null) 'oilProductId': oilProductId,
    if (oilLitersUsed != null) 'oilLitersUsed': oilLitersUsed,
    if (invoiceId != null) 'invoiceId': invoiceId,
    'createdAt': createdAt ?? now,
    'updatedAt': createdAt ?? now,
    'deletedAt': null,
  };
}
