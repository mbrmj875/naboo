import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeCheckoutService', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    test('completeFromOrder links delivered card and creates invoice', () async {
      final id = await builder.createPending(plate: 'CHK-1');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: oilTestAgreedPriceFils,
      );
      final order = (await builder.byId(id))!;

      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order,
        orderId: id,
        createdByUserName: oilTestTechnicianName,
      );

      expect(result.invoiceId, greaterThan(0));
      expect(result.totalFils, oilTestAgreedPriceFils);

      final updated = await builder.byId(id);
      expect(updated!['status'], 'delivered');
      expect(updated['invoiceId'], result.invoiceId);
    });

    test('completeFromOrder cash sale sets remainder within cash threshold', () async {
      final id = await builder.createPending(plate: 'CASH-1');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: oilTestAgreedPriceFils,
      );
      final order = (await builder.byId(id))!;

      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order,
        orderId: id,
      );

      expect(result.remainderFils, lessThanOrEqualTo(500));
      expect(result.invoiceType, InvoiceType.cash);
    });

    test('completeFromOrder credit without registered customer throws', () async {
      final id = await builder.createPending(plate: 'CRD-1');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: 0,
        agreedPriceFils: 50000,
      );
      final order = (await builder.byId(id))!;

      expect(
        () => OilChangeCheckoutService.instance.completeFromOrder(
          order: order,
          orderId: id,
        ),
        throwsA(
          isA<OilChangeCheckoutException>().having(
            (e) => e.message,
            'message',
            contains('عميل'),
          ),
        ),
      );
    });

    test('completeFromOrder rejects zero total card', () async {
      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerNameSnapshot: oilTestCustomerName,
        deviceName: oilTestDeviceName,
        deviceSerial: 'ZERO-1',
        estimatedPriceFils: 0,
        agreedPriceFils: 0,
        advancePaymentFils: 0,
        oilType: oilTestOilType,
        odometerCurrent: oilTestOdometerCurrent,
      );
      final order = (await builder.byId(id))!;

      expect(
        () => OilChangeCheckoutService.instance.completeFromOrder(
          order: order,
          orderId: id,
        ),
        throwsA(isA<OilChangeCheckoutException>()),
      );
    });
  });
}
