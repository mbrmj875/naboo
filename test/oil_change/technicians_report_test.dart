// المرحلة 7 — الشريحة 3: التقييم وعلامة الموقوف في بطاقة «الفنيون»
// بتقرير الغيار، وبلا إنترنت يظهر التقرير بلا تقييم.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/verticals/oil_change/reports/oil_change_reports_panel.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_technicians_store.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';

import 'helpers/oil_change_test_harness.dart';

const _rows = [
  OilChangeNamedRow(name: 'حيدر', count: 12, amountIqd: 600000),
  OilChangeNamedRow(name: 'كرار', count: 5, amountIqd: 250000),
];

Future<void> _pump(WidgetTester t, {Set<String> stopped = const {}}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OilTechniciansReportCard(
            rows: _rows,
            accent: Colors.teal,
            stopped: stopped,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  tearDown(() => OilTechniciansReportCard.debugExtrasLoader = null);

  testWidgets('التقييم بجانب السيارات والمبلغ، والموقوف معلَّم', (t) async {
    OilTechniciansReportCard.debugExtrasLoader = () async =>
        const OilTechReportExtras(ratings: {'حيدر': (avg: 8.64, count: 30)});
    // الموقوفون يأتون مع لقطة التقرير.
    await _pump(t, stopped: {'كرار'});
    expect(find.text('حيدر'), findsOneWidget);
    expect(find.textContaining('12 سيارة'), findsOneWidget);
    expect(find.textContaining('تقييم 8.6 (30)'), findsOneWidget);
    expect(find.text('كرار · موقوف'), findsOneWidget);
    expect(find.textContaining('التقييم من 10'), findsOneWidget);
  });

  testWidgets('بلا إنترنت: الأرقام باقية والتقييم غير متاح', (t) async {
    OilTechniciansReportCard.debugExtrasLoader = () async =>
        const OilTechReportExtras(ratingsAvailable: false);
    await _pump(t);
    expect(find.textContaining('12 سيارة'), findsOneWidget);
    expect(find.textContaining('· تقييم'), findsNothing);
    expect(find.textContaining('التقييم غير متاح'), findsOneWidget);
  });

  group('لقطة التقرير', () {
    setUpAll(() async {
      initOilChangeTestEnvironment();
      await initializeDateFormatting('ar');
    });

    test('تحمل الموقوفين، وبطاقاتهم باقية في الأرقام', () async {
      final h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      final store = OilChangeTechniciansStore.instance;
      await store.add('حيدر');
      await store.add('كرار');
      for (final tech in ['حيدر', 'كرار', 'كرار']) {
        await OilChangeOrdersRepository.instance.createOilChangeOrder(
          customerNameSnapshot: 'زبون',
          deviceName: 'كامري',
          deviceSerial: '9${tech.length}',
          estimatedPriceFils: 0,
          status: 'completed',
          technicianName: tech,
        );
      }
      await store.stop('كرار');
      final now = DateTime.now();
      final snap = await OilChangeReportsRepository.instance.loadSnapshot(
        ReportDateRange(from: now, to: now),
      );
      expect(snap.stoppedTechnicians, {'كرار'});
      expect(snap.topTechnicians.firstWhere((e) => e.name == 'كرار').count, 2);
    });
  });
}
