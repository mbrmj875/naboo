import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_auto_whatsapp_message.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_webhook_order_payload.dart';

void main() {
  const sampleOrder = {
    'customerNameSnapshot': 'محمد',
    'deviceName': 'بليزر',
    'carModel': '2002',
    'engineSize': '3500',
    'deviceSerial': '14212',
    'odometerCurrent': '153000',
    'odometerNext': '158000',
    'oilType': 'كاسترول',
    'oilViscosity': '5W-30',
    'oilSize': '5 لتر',
    'engineFilterName': 'فلتر محرك',
    'hydraulicType': 'شل',
    'hydraulicGrade': 'ATF',
    'hydraulicSize': '2 لتر',
    'hydraulicCustomerProvided': 0,
    'powerHydraulicCustomerProvided': 1,
    'requestedServices': 'غيار زيت,فحص',
    'agreedPriceFils': 75000000,
    'advancePaymentFils': 25000000,
  };

  test('auto whatsapp message includes requested fields without invoice', () {
    final msg = buildOilChangeAutoWhatsAppMessage(
      storeTitle: 'مركز النجوم',
      order: sampleOrder,
    );

    expect(msg.contains('محمد'), isTrue);
    expect(msg.contains('بليزر'), isTrue);
    expect(msg.contains('2002'), isTrue);
    expect(msg.contains('3500'), isTrue);
    expect(msg.contains('14212'), isTrue);
    expect(msg.contains('153000'), isTrue);
    expect(msg.contains('158000'), isTrue);
    expect(msg.contains('كاسترول'), isTrue);
    expect(msg.contains('5W-30'), isTrue);
    expect(msg.contains('فلتر المحرك'), isTrue);
    expect(msg.contains('هيدروليك القير'), isTrue);
    expect(msg.contains('هيدروليك الباور'), isTrue);
    expect(msg.contains('غيار زيت'), isTrue);
    expect(msg.contains('75,000'), isTrue);
    expect(msg.contains('25,000'), isTrue);
    expect(msg.contains('فاتورة'), isFalse);
    expect(msg.contains('invoice'), isFalse);
  });

  test('webhook payload mirrors auto message fields', () {
    final payload = buildOilChangeWebhookOrderPayload(
      storeTitle: 'مركز النجوم',
      order: sampleOrder,
    );

    expect(payload['customer_name'], 'محمد');
    expect(payload['car_name'], 'بليزر');
    expect(payload['engine_size'], '3500');
    expect(payload['oil_ticket_services'], ['غيار زيت', 'فحص']);
    expect(payload.containsKey('invoice_id'), isFalse);
  });
}
