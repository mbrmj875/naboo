import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('listOilChangeOrdersForCustomer', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    test('returns oil cards linked by customerId', () async {
      final db = await harness.database;
      final tid = await harness.tenantId();
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'عميل سجل زيت',
        'phone': '07701230000',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      final id1 = await builder.createPending(plate: 'C-OIL-1');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id1,
        patchCustomerIdField: true,
        customerId: customerId,
        customerNameSnapshot: 'عميل سجل زيت',
      );
      final id2 = await builder.createInProgress(plate: 'C-OIL-2');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id2,
        patchCustomerIdField: true,
        customerId: customerId,
        customerNameSnapshot: 'عميل سجل زيت',
      );

      // عميل آخر — لا يظهر.
      final otherCustomerId = await db.insert('customers', {
        'tenantId': tid,
        'name': 'آخر',
        'phone': '07709990000',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      final other = await builder.createPending(plate: 'OTHER-1');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        other,
        patchCustomerIdField: true,
        customerId: otherCustomerId,
        customerNameSnapshot: 'آخر',
      );

      final rows =
          await OilChangeOrdersRepository.instance.listOilChangeOrdersForCustomer(
        customerId: customerId,
        customerName: 'عميل سجل زيت',
      );

      expect(rows.length, 2);
      final ids = rows.map((r) => (r['id'] as num).toInt()).toSet();
      expect(ids, containsAll([id1, id2]));
      expect(ids.contains(other), isFalse);
    });
  });
}
