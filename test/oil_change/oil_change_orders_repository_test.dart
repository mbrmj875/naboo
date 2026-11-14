import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeOrdersRepository', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    test('createOilChangeOrder inserts service_orders and sync_queue pending', () async {
      final before = await countSyncQueueForEntity(SyncEntityTypes.serviceOrder);
      final id = await builder.createPending(plate: 'NEW-1001');
      expect(id, greaterThan(0));

      final row = await builder.byId(id);
      expect(row, isNotNull);
      expect(row!['deviceSerial'], 'NEW-1001');
      expect(row['orderKind'], 'oil_change');
      expect(row['status'], 'pending');

      final after = await countSyncQueueForEntity(SyncEntityTypes.serviceOrder);
      expect(after, before + 1);
    });

    test('updateOilChangeOrder updates all patched fields', () async {
      final id = await builder.createPending(plate: 'UPD-2002');
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        deviceSerial: 'UPD-9999',
        carModel: 'Honda Civic',
        odometerCurrent: '88000',
        oilType: 'Mineral',
        oilViscosity: '10W-40',
        agreedPriceFils: 75000,
        status: 'in_progress',
        technicianName: 'سعد',
      );

      final row = await builder.byId(id);
      expect(row!['deviceSerial'], 'UPD-9999');
      expect(row['carModel'], 'Honda Civic');
      expect(row['odometerCurrent'], '88000');
      expect(row['oilType'], 'Mineral');
      expect(row['oilViscosity'], '10W-40');
      expect(row['agreedPriceFils'], 75000);
      expect(row['status'], 'in_progress');
      expect(row['technicianName'], 'سعد');
    });

    test('getOilChangeLogPage filters active vs suspended status', () async {
      await builder.createPending(plate: 'ACT-1');
      await builder.createSuspended(plate: 'SUS-1');

      final active = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.active,
      );
      final suspended = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.suspended,
      );

      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'ACT-1'), isTrue);
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'SUS-1'), isFalse);
      expect(suspended.any((r) => (r['deviceSerial'] ?? '') == 'SUS-1'), isTrue);
      expect(suspended.any((r) => (r['deviceSerial'] ?? '') == 'ACT-1'), isFalse);
    });

    test('getOilChangeLogPage search matches plate number', () async {
      await builder.createPending(plate: 'SRCH-5555');
      await builder.createPending(plate: 'OTHER-0000');

      final hits = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        searchQuery: 'SRCH-5555',
      );

      expect(hits, isNotEmpty);
      expect(hits.every((r) => (r['deviceSerial'] ?? '').contains('SRCH')), isTrue);
    });

    test('status counts pending in_progress delivered separately', () async {
      await builder.createPending(plate: 'P-1');
      await builder.createInProgress(plate: 'IP-1');
      await builder.createDelivered(plate: 'D-1');

      expect(
        await countServiceOrdersByStatus(harness.dbHelper, status: 'pending'),
        1,
      );
      expect(
        await countServiceOrdersByStatus(harness.dbHelper, status: 'in_progress'),
        1,
      );
      expect(
        await countServiceOrdersByStatus(harness.dbHelper, status: 'delivered'),
        1,
      );
    });
  });
}
