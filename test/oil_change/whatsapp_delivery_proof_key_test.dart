import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/whatsapp_delivery_proof_key.dart';

void main() {
  test('نفس البطاقة تطابق 07 و964', () {
    final local = whatsappDeliveryProofKey(
      orderRef: '14212',
      phone: '07801112233',
    );
    final intl = whatsappDeliveryProofKey(
      orderRef: '14212',
      phone: '+9647801112233',
    );
    expect(local, isNotNull);
    expect(local, intl);
  });

  test('بلا رقم بطاقة لا تُطابق حتى لا تُسقط رسالة أخرى', () {
    expect(
      whatsappDeliveryProofKey(orderRef: '', phone: '07801112233'),
      isNull,
    );
    expect(
      whatsappDeliveryProofKey(orderRef: '0', phone: '07801112233'),
      isNull,
    );
  });

  test('بطاقتان مختلفتان لا تشتركان المفتاح', () {
    final a = whatsappDeliveryProofKey(orderRef: '10', phone: '07801112233');
    final b = whatsappDeliveryProofKey(orderRef: '11', phone: '07801112233');
    expect(a, isNot(b));
  });
}
