import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_phone_correction.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);
  setUp(() => OilChangeTestHarness.instance.reset());

  Future<String?> phoneOf(ServiceOrderBuilder b, int id) async =>
      (await b.byId(id))?['customerPhone']?.toString();

  Future<void> correct(int id, String oldPhone) async {
    try {
      await OilChangeWhatsappPhoneCorrection.instance.correctPhoneAndResend(
        newPhoneRaw: '07701112222',
        oldPhoneRaw: oldPhone,
        logId: '',
        orderRef: '$id',
        customerName: 'x',
        shopName: 's',
        detailsBlock: 'd',
        templateParams: const {},
        employeeName: 'e',
      );
    } catch (_) {}
  }

  test('الرقم يدل على بطاقة بهاتف آخر: لا تُعدَّل', () async {
    final b = ServiceOrderBuilder(OilChangeTestHarness.instance);
    final id = await b.createPending(plate: 'G-1', agreedPriceFils: 1000);
    await OilChangeOrdersRepository.instance
        .updateOilChangeOrder(id, customerPhone: '07709998888');
    final before = await phoneOf(b, id);
    await correct(id, '07705554444');
    expect(await phoneOf(b, id), before);
  });

  test('ضابط: الهاتف القديم مطابق: تُعدَّل', () async {
    final b = ServiceOrderBuilder(OilChangeTestHarness.instance);
    final id = await b.createPending(plate: 'G-2', agreedPriceFils: 1000);
    await OilChangeOrdersRepository.instance
        .updateOilChangeOrder(id, customerPhone: '07705554444');
    await correct(id, '07705554444');
    expect(await phoneOf(b, id), contains('7701112222'));
  });
}
