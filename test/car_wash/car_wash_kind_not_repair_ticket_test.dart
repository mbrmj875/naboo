import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/service_order_kinds.dart';

/// يمنع رجوع خطأ قديم: اعتبار غسيل السيارات تذكرة تصليح.
void main() {
  group('ServiceOrderKinds — غسيل السيارات', () {
    Map<String, dynamic> row({String? orderKind, String? oilType}) => {
          if (orderKind != null) 'orderKind': orderKind,
          if (oilType != null) 'oilType': oilType,
        };

    test('car_wash ليس تذكرة تصليح', () {
      expect(
        ServiceOrderKinds.isRepairTicket(row(orderKind: 'car_wash')),
        isFalse,
      );
    });

    test('car_wash ليس سجل غيار زيت', () {
      expect(
        ServiceOrderKinds.isOilChange(row(orderKind: 'car_wash')),
        isFalse,
      );
      expect(
        ServiceOrderKinds.isOilChangeLogRow(row(orderKind: 'car_wash')),
        isFalse,
      );
    });

    test('car_wash يُعرَف بنوعه فقط', () {
      expect(ServiceOrderKinds.isCarWash(row(orderKind: 'car_wash')), isTrue);
      expect(
        ServiceOrderKinds.isCarWash(row(orderKind: 'oil_change')),
        isFalse,
      );
      expect(ServiceOrderKinds.isCarWash(row(orderKind: 'repair')), isFalse);
    });

    test('سجل قديم بلا orderKind يبقى تذكرة تصليح', () {
      expect(ServiceOrderKinds.isRepairTicket(const {}), isTrue);
      expect(ServiceOrderKinds.isRepairTicket(row(orderKind: '')), isTrue);
      expect(
        ServiceOrderKinds.isRepairTicket(row(orderKind: 'repair')),
        isTrue,
      );
    });

    test('oil_change ليس تذكرة تصليح ولا غسيل', () {
      final oil = row(orderKind: 'oil_change');
      expect(ServiceOrderKinds.isRepairTicket(oil), isFalse);
      expect(ServiceOrderKinds.isCarWash(oil), isFalse);
      expect(ServiceOrderKinds.isOilChange(oil), isTrue);
    });
  });
}
