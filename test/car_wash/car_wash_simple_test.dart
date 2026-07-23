import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/verticals/car_wash/car_wash_types.dart';

void main() {
  test('car wash types have positive default prices in fils', () {
    for (final t in CarWashTypes.all) {
      expect(t.defaultPriceFils, greaterThan(0));
      expect(t.nameAr, isNotEmpty);
    }
    expect(CarWashTypes.byId('full')?.nameAr, 'غسيل كامل');
  });

  test('service order kinds distinguish car wash from oil', () {
    expect(
      ServiceOrderKinds.isCarWash({'orderKind': ServiceOrderKinds.carWash}),
      isTrue,
    );
    expect(
      ServiceOrderKinds.isOilChange({'orderKind': ServiceOrderKinds.carWash}),
      isFalse,
    );
    expect(
      ServiceOrderKinds.isRepairTicket({'orderKind': ServiceOrderKinds.carWash}),
      isFalse,
    );
  });
}
