// المرحلة 6 — الشريحة 4: صفحة سجل السيارات. البحث، والمالكون من البطاقات،
// وزيارات السيارة بقراءات العداد.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/screens/vehicles_registry_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/vehicle_registry.dart';

import 'helpers/oil_change_test_harness.dart';

Map<String, dynamic> _o(String at, String name, {String phone = '', int? cid}) =>
    {
      'createdAt': at,
      'customerNameSnapshot': name,
      'customerPhone': phone,
      'customerId': cid,
    };

Future<int> _card(
  String plate, {
  required String customer,
  String phone = '',
  String car = 'كامري',
  String odo = '',
}) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: customer,
      customerPhone: phone,
      deviceName: car,
      deviceSerial: plate,
      odometerCurrent: odo,
      estimatedPriceFils: 0,
      status: 'completed',
    );

void main() {
  test('المالكون: فترات متتالية، وبطاقة بلا اسم لا تقطعها', () {
    // الأحدث أولاً كما تأتي من السجل.
    final p = VehicleRegistry.ownerPeriods([
      _o('2026-06-01T10:00:00', 'باقر', phone: '+9647700000002'),
      _o('2026-05-01T10:00:00', ''),
      _o('2026-04-01T10:00:00', 'باقر'),
      _o('2026-02-01T10:00:00', 'أحمد', phone: '+9647700000001'),
      _o('2026-01-01T10:00:00', 'احمد ', phone: '07700000001'),
    ]);
    expect(p.map((e) => e.name), ['أحمد', 'باقر'],
        reason: 'الهاتف نفسه بكتابتين = الشخص نفسه، والاسم الأحدث يُعرض');
    expect(p.first.visits, 2);
    expect(p.last.visits, 2);
    expect(p.last.from, DateTime(2026, 4, 1, 10));
    expect(p.last.to, DateTime(2026, 6, 1, 10));
    expect(p.last.phone, '+9647700000002');
  });

  group('البحث والصفحة', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;

    setUp(() async {
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      await VehicleRegistry.ensureSchema(await h.database);
    });

    test('البحث باللوحة بأي كتابة، وبالسيارة والزبون وهاتفه', () async {
      await _card('12345 B البصرة', customer: 'علي حسن', phone: '+9647701234567', car: 'سوناتا');
      await _card('777', customer: 'كرار', car: 'لاندكروزر');
      final repo = OilChangeOrdersRepository.instance;
      Future<List<String>> names(String q) async =>
          (await repo.listVehicles(query: q)).map((v) => '${v['name']}').toList();

      expect(await names(''), hasLength(2));
      expect(await names('١٢٣٤٥'), ['سوناتا']);
      expect(await names('12345b'), ['سوناتا']);
      expect(await names('لاند'), ['لاندكروزر']);
      expect(await names('علي'), ['سوناتا']);
      expect(await names('07701234567'), ['سوناتا']);
      expect(await names('غير موجود'), isEmpty);
    });

    testWidgets('القائمة ثم صفحة السيارة: المالكون والزيارات', (t) async {
      await t.runAsync(() async {
        await _card('2468', customer: 'أحمد', odo: '80000');
        await _card('2468', customer: 'باقر', odo: '85000');
      });
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: VehiclesRegistryScreen()));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      expect(find.text('2468'), findsOneWidget);
      expect(find.textContaining('زيارتان'), findsOneWidget);

      await t.tap(find.text('2468'));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      expect(find.byKey(const Key('vehiclePlate')), findsOneWidget);
      expect(find.text('الحالي'), findsOneWidget);
      // المالك الحالي أولاً.
      final first = t.widget<ListTile>(find.byKey(const Key('vehicleOwner_0')));
      expect((first.title as Text).data, 'باقر');
      expect(find.byKey(const Key('vehicleOwner_1')), findsOneWidget);
      expect(find.textContaining('85,000 كم'), findsWidgets);
      expect(find.textContaining('80,000 كم'), findsOneWidget);
    });
  });
}
