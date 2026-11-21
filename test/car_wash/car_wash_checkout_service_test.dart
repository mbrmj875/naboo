import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/car_wash/models/car_wash_service_item.dart';
import 'package:naboo/verticals/car_wash/services/car_wash_checkout_service.dart';

void main() {
  group('CarWashCheckoutService — حساب المبالغ', () {
    test('إجمالي الأنواع المختارة يجمع الأسعار بالفلس', () {
      final lines = [
        const CarWashLine(name: 'غسيل كامل', priceFils: 7000000),
        const CarWashLine(name: 'تنظيف داخلي', priceFils: 3000000),
      ];
      expect(CarWashCheckoutService.linesTotalFils(lines), 10000000);
    });

    test('الأنواع بسعر صفر لا تُضاف للإجمالي', () {
      final lines = [
        const CarWashLine(name: 'غسيل كامل', priceFils: 5000000),
        const CarWashLine(name: 'تلميع مجاني', priceFils: 0),
      ];
      expect(CarWashCheckoutService.linesTotalFils(lines), 5000000);
    });

    test('السعر السالب لا يخفض الإجمالي', () {
      final lines = [
        const CarWashLine(name: 'غسيل', priceFils: 5000000),
        const CarWashLine(name: 'خطأ إدخال', priceFils: -2000000),
      ];
      expect(CarWashCheckoutService.linesTotalFils(lines), 5000000);
    });
  });

  group('CarWashCheckoutService — بنود الفاتورة', () {
    test('سطر لكل نوع عندما يطابق المجموع الإجمالي', () {
      final lines = [
        const CarWashLine(name: 'غسيل كامل', priceFils: 7000000),
        const CarWashLine(name: 'تنظيف داخلي', priceFils: 3000000),
      ];
      final items = CarWashCheckoutService.buildItems(
        lines: lines,
        totalFils: 10000000,
        plate: '12345 بصرة',
      );
      expect(items.length, 2);
      expect(items.first.productName, 'غسيل: غسيل كامل');
      expect(IqdMoney.toFils(items.first.total), 7000000);
    });

    test('السعر اليدوي المختلف يُجمَع في سطر واحد بالإجمالي', () {
      final lines = [
        const CarWashLine(name: 'غسيل كامل', priceFils: 7000000),
      ];
      final items = CarWashCheckoutService.buildItems(
        lines: lines,
        totalFils: 5000000,
        plate: '12345 بصرة',
      );
      expect(items.length, 1);
      expect(IqdMoney.toFils(items.single.total), 5000000);
      expect(items.single.productName, contains('12345 بصرة'));
    });

    test('بلا أنواع مختارة يبقى سطر واحد بالإجمالي', () {
      final items = CarWashCheckoutService.buildItems(
        lines: const [],
        totalFils: 4000000,
        plate: 'أ 999',
      );
      expect(items.length, 1);
      expect(IqdMoney.toFils(items.single.total), 4000000);
    });

    test('مجموع البنود يساوي إجمالي الفاتورة دائماً', () {
      final lines = [
        const CarWashLine(name: 'غسيل كامل', priceFils: 7000000),
        const CarWashLine(name: 'تنظيف داخلي', priceFils: 3000000),
      ];
      for (final total in [10000000, 9500000, 12000000]) {
        final items = CarWashCheckoutService.buildItems(
          lines: lines,
          totalFils: total,
          plate: 'ب 111',
        );
        final sum = items.fold<int>(
          0,
          (acc, item) => acc + IqdMoney.toFils(item.total),
        );
        expect(sum, total, reason: 'إجمالي $total');
      }
    });
  });

  group('CarWashCheckoutService — عنوان البطاقة', () {
    test('يذكر الأنواع ورقم اللوحة', () {
      final label = CarWashCheckoutService.washLabel(
        lines: const [
          CarWashLine(name: 'غسيل كامل', priceFils: 5000000),
          CarWashLine(name: 'تلميع', priceFils: 2000000),
        ],
        plate: '12345 بصرة',
      );
      expect(label, 'غسيل: غسيل كامل، تلميع — 12345 بصرة');
    });

    test('بلا أنواع يبقى عنوان عام مع اللوحة', () {
      final label = CarWashCheckoutService.washLabel(
        lines: const [],
        plate: 'أ 77',
      );
      expect(label, 'غسيل سيارة — أ 77');
    });
  });

  group('نوع السجل car_wash منفصل عن الزيت والصيانة', () {
    Map<String, dynamic> row(String? kind) => {'orderKind': kind};

    test('بطاقة الغسيل ليست بطاقة زيت', () {
      expect(ServiceOrderKinds.isOilChange(row('car_wash')), isFalse);
      expect(ServiceOrderKinds.isOilChangeLogRow(row('car_wash')), isFalse);
    });

    test('بطاقة الغسيل ليست تذكرة صيانة', () {
      expect(ServiceOrderKinds.isRepairTicket(row('car_wash')), isFalse);
    });

    test('بطاقة الغسيل تُميَّز بنوعها', () {
      expect(ServiceOrderKinds.isCarWash(row('car_wash')), isTrue);
      expect(ServiceOrderKinds.isCarWash(row('oil_change')), isFalse);
      expect(ServiceOrderKinds.isCarWash(row(null)), isFalse);
    });

    test('السجلات القديمة بلا نوع تبقى تذاكر صيانة كما كانت', () {
      expect(ServiceOrderKinds.isRepairTicket(row(null)), isTrue);
      expect(ServiceOrderKinds.isRepairTicket(row('')), isTrue);
      expect(ServiceOrderKinds.isRepairTicket(row('repair')), isTrue);
      expect(ServiceOrderKinds.isRepairTicket(row('oil_change')), isFalse);
    });
  });

  group('CarWashServiceItem', () {
    test('يقرأ الصف ويقصّ المسافات', () {
      final item = CarWashServiceItem.fromMap({
        'id': 4,
        'name': '  غسيل كامل  ',
        'priceFils': 7000000,
        'sortOrder': 2,
      });
      expect(item.id, 4);
      expect(item.name, 'غسيل كامل');
      expect(item.priceFils, 7000000);
      expect(item.sortOrder, 2);
    });

    test('القيم الناقصة تعطي أصفاراً بلا استثناء', () {
      final item = CarWashServiceItem.fromMap({});
      expect(item.id, 0);
      expect(item.name, '');
      expect(item.priceFils, 0);
    });
  });
}
