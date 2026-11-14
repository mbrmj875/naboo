/// زيارة غيار زيت واقعية من محل في البصرة — ليست بيانات عشوائية.
///
/// المبالغ بالفلس (INTEGER): 1 دينار = 1000 فلس.
library;

import 'package:naboo/services/service_order_kinds.dart';

/// باقر — زبون متكرر في مركز النجوم / شارع الجزائر.
const basraCustomerName = 'باقر عبد الأمير';
const basraCustomerPhone = '07884289711';
const basraTechnician = 'علي كرار';
const basraStoreTitle = 'مركز النجوم';
const basraStoreFooter = 'شارع الجزائر — البصرة';

const basraPlate = '14212';
const basraPlateSpaced = '14-212';
const basraPlateArabicIndic = '١٤٢١٢';
const basraCarName = 'بليزر';
const basraCarModel = '2002';
const basraEngineSize = '3500';
const basraOdometerCurrent = '153000';
const basraOdometerNext = '158000';

const basraOilBrand = 'كاسترول EDGE';
const basraOilGrade = '5W-30';
const basraOilSize = '5 لتر';

const basraEngineFilter = 'تويوتا أصلي 90915-YZZD3';
const basraAirFilter = 'K&N 33-2304';

/// 80,000 د.ع قبل التخفيض.
const basraEstimatedFils = 80000000;

/// 75,000 د.ع المتفق عليه بعد تخفيض 5,000.
const basraAgreedFils = 75000000;

/// دفعة 25,000 د.ع — يبقى 50,000 د.ع ديناً على الزيارة.
const basraPaidFils = 25000000;
const basraRemainderFils = 50000000;
const basraDiscountFils = 5000000;

/// فلتر محرك 15,000 د.ع.
const basraEngineFilterFils = 15000000;

Map<String, dynamic> basraOilVisitOrder({
  int? invoiceId,
  String? globalId,
  String? notes,
  int agreedPriceFils = basraAgreedFils,
  int estimatedPriceFils = basraEstimatedFils,
  int advancePaymentFils = basraPaidFils,
  int hydraulicCustomerProvided = 0,
  int powerHydraulicCustomerProvided = 1,
  String? createdAt,
}) {
  return {
    'global_id': globalId ?? 'oil-basra-blazer-14212',
    'orderKind': ServiceOrderKinds.oilChange,
    'customerNameSnapshot': basraCustomerName,
    'customerPhone': basraCustomerPhone,
    'deviceName': basraCarName,
    'deviceSerial': basraPlate,
    'carModel': basraCarModel,
    'engineSize': basraEngineSize,
    'odometerCurrent': basraOdometerCurrent,
    'odometerNext': basraOdometerNext,
    'oilType': basraOilBrand,
    'oilViscosity': basraOilGrade,
    'oilSize': basraOilSize,
    'engineFilterName': basraEngineFilter,
    'engineFilterPriceFils': basraEngineFilterFils,
    'airFilterName': basraAirFilter,
    'hydraulicType': 'شل',
    'hydraulicGrade': 'ATF Dexron III',
    'hydraulicSize': '2 لتر',
    'hydraulicCustomerProvided': hydraulicCustomerProvided,
    'powerHydraulicCustomerProvided': powerHydraulicCustomerProvided,
    'requestedServices': 'غيار زيت,فحص كفرات,تنظيف ثروتل',
    'technicianName': basraTechnician,
    'issueDescription': notes ?? 'استهلاك زيت خفيف مع الحر',
    'estimatedPriceFils': estimatedPriceFils,
    'agreedPriceFils': agreedPriceFils,
    'advancePaymentFils': advancePaymentFils,
    if (invoiceId != null) 'invoiceId': invoiceId,
    'createdAt': createdAt ?? '2026-08-13T08:15:00.000Z',
    'updatedAt': createdAt ?? '2026-08-13T08:15:00.000Z',
    'deletedAt': null,
  };
}
