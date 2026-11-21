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
      await builder.createSuspended();
      await builder.createSuspended(plate: 'SUS-3333');

      final first = await HomeKpiRepository.instance.load(force: true);
      expect(first.suspendedCars, 2);

      await builder.createSuspended(plate: 'CACHE-NEW');
      final cached = await HomeKpiRepository.instance.load();
      expect(cached.suspendedCars, 2);

      final fresh = await HomeKpiRepository.instance.load(force: true);
      expect(fresh.suspendedCars, 3);
    });

    test('invalidate clears cache so next load reflects DB changes', () async {
      await builder.createSuspended();
      await HomeKpiRepository.instance.load(force: true);

      await builder.createSuspended(plate: 'INV-PLATE');
      HomeKpiRepository.instance.invalidate();

      final snap = await HomeKpiRepository.instance.load();
      expect(snap.suspendedCars, 2);
    });

    test('after cloud import invalidate reloads garage KPI', () async {
      await builder.createSuspended();
      await HomeKpiRepository.instance.load(force: true);

      await builder.createSuspended(plate: 'RT-1');
      harness.mockCloudSnapshotImported();
      HomeKpiRepository.instance.invalidate();

      final after = await HomeKpiRepository.instance.load();
      expect(after.suspendedCars, 2);
    });
  });
}
