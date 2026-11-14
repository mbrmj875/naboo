import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/verticals/oil_change/utils/oil_service_whatsapp_message.dart';

void main() {
  group('buildOilServiceWhatsAppMessage', () {
    test('partial payment and prior debt appear in Arabic text', () {
      final msg = buildOilServiceWhatsAppMessage(
        order: {
          'customerNameSnapshot': 'أحمد',
          'deviceName': 'كورولا',
          'agreedPriceFils': 50000,
          'advancePaymentFils': 20000,
        },
        storeTitle: 'محل الاختبار',
        storeFooter: '',
        priorOpenDebtFils: 15000,
      );

      expect(msg, contains('ملخص الحساب'));
      expect(msg, contains('دفعت أقل من الإجمالي'));
      expect(msg, contains('دين سابق'));
      expect(msg, contains('إجمالاً تقريباً'));
    });

    test('full payment omits remainder debt line', () {
      final msg = buildOilServiceWhatsAppMessage(
        order: {
          'customerNameSnapshot': 'سارة',
          'agreedPriceFils': 30000,
          'advancePaymentFils': 30000,
        },
        storeTitle: 'محل',
        storeFooter: '',
      );

      expect(msg, contains('بالكامل'));
      expect(msg, isNot(contains('دفعت أقل من الإجمالي')));
    });
  });
}
