import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeHubScreen data layer', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    test('lists active oil change cards after create', () async {
      await builder.createPending(plate: 'HUB-100');
      final log = await OilChangeOrdersRepository.instance.getOilChangeLogPage();
      expect(log.any((r) => (r['deviceSerial'] ?? '') == 'HUB-100'), isTrue);
    });

    test('active filter excludes suspended cards', () async {
      await builder.createPending(plate: 'HUB-ACT');
      await builder.createSuspended(plate: 'HUB-SUS');

      final active = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.active,
      );
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'HUB-ACT'), isTrue);
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'HUB-SUS'), isFalse);
    });

    test('search filters by plate number', () async {
      await builder.createPending(plate: 'FIND-ME');
      await builder.createPending(plate: 'IGNORE');

      final hits = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        searchQuery: 'FIND-ME',
      );
      expect(hits.any((r) => (r['deviceSerial'] ?? '') == 'FIND-ME'), isTrue);
      expect(hits.any((r) => (r['deviceSerial'] ?? '') == 'IGNORE'), isFalse);
    });

    test('suspended filter shows only suspended cards', () async {
      await builder.createSuspended(plate: 'TAB-SUS');
      await builder.createPending(plate: 'TAB-ACT');

      final suspended = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.suspended,
      );
      expect(suspended.any((r) => (r['deviceSerial'] ?? '') == 'TAB-SUS'), isTrue);
      expect(suspended.any((r) => (r['deviceSerial'] ?? '') == 'TAB-ACT'), isFalse);
    });

    test('delivered card remains in active log tab', () async {
      await builder.createDelivered(plate: 'DEL-LOG');
      final active = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.active,
      );
      expect(active.any((r) => (r['deviceSerial'] ?? '') == 'DEL-LOG'), isTrue);
    });
  });
}
