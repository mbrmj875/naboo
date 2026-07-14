import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/home/home_kpi_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('HomeKpiRepository oil', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
      HomeKpiRepository.instance.invalidate();
    });

    test('load caches snapshot for 45 seconds', () async {
      await builder.createPending();
      await builder.createInProgress();

      final first = await HomeKpiRepository.instance.load(force: true);
      expect(first.activeCarsInGarage, 2);

      await builder.createPending(plate: 'CACHE-NEW');
      final cached = await HomeKpiRepository.instance.load();
      expect(cached.activeCarsInGarage, 2);

      final fresh = await HomeKpiRepository.instance.load(force: true);
      expect(fresh.activeCarsInGarage, 3);
    });

    test('invalidate clears cache so next load reflects DB changes', () async {
      await builder.createPending();
      await HomeKpiRepository.instance.load(force: true);

      await builder.createPending(plate: 'INV-PLATE');
      HomeKpiRepository.instance.invalidate();

      final snap = await HomeKpiRepository.instance.load();
      expect(snap.activeCarsInGarage, 2);
    });

    test('after cloud import invalidate reloads garage KPI', () async {
      await builder.createPending();
      await HomeKpiRepository.instance.load(force: true);

      await builder.createInProgress(plate: 'RT-1');
      harness.mockCloudSnapshotImported();
      HomeKpiRepository.instance.invalidate();

      final after = await HomeKpiRepository.instance.load();
      expect(after.activeCarsInGarage, 2);
    });
  });
}
