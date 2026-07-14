import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_kpi_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('OilChangeHomeDashboard', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
      HomeKpiRepository.instance.invalidate();
    });

    test('service manifest exposes غيار زيت جديد primary CTA', () {
      final spec = harness.homeSpec(enablePos: false);
      expect(spec.primaryCta?.title, 'غيار زيت جديد');
      expect(spec.showOilKpiGrid, isTrue);
    });

    test('hybrid manifest adds quick sale tile', () {
      final spec = harness.homeSpec(enablePos: true);
      expect(
        spec.secondaryTiles.any((t) => t.id == 'hybrid_sale'),
        isTrue,
      );
    });

    test('garage KPI reflects workshop cards count', () async {
      await builder.createPending();
      await builder.createInProgress();
      final snap = await HomeKpiRepository.instance.load(force: true);
      expect(snap.activeCarsInGarage, 2);
    });

    test('stock KPI reflects volumeLiter shortages', () async {
      await seedLowStockOilProduct(harness.dbHelper);
      final snap = await HomeKpiRepository.instance.load(force: true);
      expect(snap.stockShortages, greaterThan(0));
    });

    test('cloud import invalidates home KPI cache path', () async {
      await builder.createPending();
      await HomeKpiRepository.instance.load(force: true);
      await builder.createInProgress(plate: 'KD-2');
      harness.mockCloudSnapshotImported();
      HomeKpiRepository.instance.invalidate();
      final after = await HomeKpiRepository.instance.load();
      expect(after.activeCarsInGarage, 2);
    });
  });
}
