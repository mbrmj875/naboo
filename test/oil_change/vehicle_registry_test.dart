// المرحلة 6 — الشريحة 1: سجل السيارات. ترحيل البطاقات القديمة، ربط الحفظ
// بالسيارة، البحث باللوحة عبر السجل، واللوحة لا تملأ اسم الزبون وهاتفه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/vehicle_registry.dart';

import 'helpers/oil_change_test_harness.dart';
import 'helpers/oil_employee_home_harness.dart';

Future<int> _rawOrder(
  OilChangeTestHarness h, {
  required String plate,
  required String date,
  String kind = 'oil_change',
  String status = 'delivered',
  String customer = 'أحمد',
  String phone = '',
  String car = 'كامري',
  String odo = '',
}) async {
  final db = await h.database;
  // إدخال مباشر يحاكي بطاقة قديمة قبل السجل (بلا ربط).
  return db.insert('service_orders', {
    'tenantId': await h.tenantId(),
    'orderKind': kind,
    'status': status,
    'customerNameSnapshot': customer,
    'customerPhone': phone,
    'deviceName': car,
    'deviceSerial': plate,
    'odometerCurrent': odo,
    'estimatedPriceFils': 0,
    'advancePaymentFils': 0,
    'createdAt': date,
    'updatedAt': date,
  });
}

Future<List<Map<String, dynamic>>> _vehicles(OilChangeTestHarness h) async =>
    (await h.database).query(
      'vehicles',
      where: 'deletedAt IS NULL',
      orderBy: 'plate_key',
    );

void main() {
  group('السجل والترحيل', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;

    setUp(() async {
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      await VehicleRegistry.ensureSchema(await h.database);
    });

    test('البطاقات القديمة تصير سيارات: اللوحة نفسها بأي كتابة سيارة واحدة',
        () async {
      await _rawOrder(h, plate: '12345', date: '2026-01-01T10:00:00', customer: 'أحمد', odo: '80,000');
      await _rawOrder(h, plate: '١٢٣٤٥', date: '2026-04-01T10:00:00', customer: 'باقر', phone: '+9647700000001', car: 'كامري 2018', odo: '85000');
      // معلّقة: تُربط لكنها ليست زيارة ولا يُؤخذ عدادها.
      await _rawOrder(h, plate: '12 345', date: '2026-05-01T10:00:00', status: 'suspended', customer: 'باقر', car: 'كامري 2018', odo: '99999');
      await _rawOrder(h, plate: '777-14', date: '2026-02-01T10:00:00', kind: 'car_wash');
      // تذكرة صيانة أجهزة: رقمها التسلسلي ليس لوحة.
      await _rawOrder(h, plate: 'SN-1', date: '2026-02-01T10:00:00', kind: 'repair');
      await _rawOrder(h, plate: '555', date: '2026-02-01T10:00:00', status: 'cancelled');

      final db = await h.database;
      final linked = await VehicleRegistry.reconcile(db);
      expect(linked, 5);

      final v = await _vehicles(h);
      expect(v.map((r) => r['plate_key']), ['12345', '77714']);
      final car = v.first;
      expect(car['visits_count'], 2);
      expect(car['last_odometer'], 85000);
      expect(car['last_visit_at'], '2026-04-01T10:00:00');
      expect(car['customer_name'], 'باقر', reason: 'صاحب آخر بطاقة');
      expect(car['name'], 'كامري 2018');
      expect(car['plate_number'], '12345');
      expect(car['global_id'], startsWith('veh-'));
      expect(v.last['plate_number'], isNull, reason: 'رمز المحافظة يُكمَّل لاحقاً');

      final updatedAt = car['updatedAt'];
      expect(await VehicleRegistry.reconcile(db), 0, reason: 'آمن للتكرار');
      expect((await _vehicles(h)).first['updatedAt'], updatedAt);
    });

    test('الحفظ يربط البطاقة، وتغيير اللوحة ينقلها ويحدّث السيارتين', () async {
      final repo = OilChangeOrdersRepository.instance;
      final id = await repo.createOilChangeOrder(
        customerNameSnapshot: 'علي',
        deviceName: 'سوناتا',
        deviceSerial: '4321',
        estimatedPriceFils: 0,
        odometerCurrent: '120000',
        status: 'completed',
      );
      var v = await _vehicles(h);
      expect(v.single['plate_key'], '4321');
      expect(v.single['last_odometer'], 120000);

      await repo.updateOilChangeOrder(id, deviceSerial: '9876');
      v = await _vehicles(h);
      expect(v.single['plate_key'], '9876', reason: 'القديمة بلا بطاقات تُخفى');
      final row = (await (await h.database).query(
        'service_orders',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['vehicle_global_id'], v.single['global_id']);
    });

    test('البحث باللوحة عبر السجل، والمعلّقة ليست زيارة', () async {
      final repo = OilChangeOrdersRepository.instance;
      final done = await repo.createOilChangeOrder(
        customerNameSnapshot: 'علي',
        deviceName: 'سوناتا',
        deviceSerial: '١١٢٢٣',
        estimatedPriceFils: 0,
        status: 'completed',
      );
      await repo.createOilChangeOrder(
        customerNameSnapshot: 'علي',
        deviceName: 'سوناتا',
        deviceSerial: '11223',
        estimatedPriceFils: 0,
        status: 'suspended',
      );
      final r = await repo.getLatestOilChangeByPlate('11 223');
      expect(r?['id'], done);
      expect(await repo.getLatestOilChangeByPlate('99999'), isNull);
    });

    test('حذف آخر بطاقة يعيد العداد والمالك إلى ما قبلها', () async {
      final repo = OilChangeOrdersRepository.instance;
      await repo.createOilChangeOrder(
        customerNameSnapshot: 'علي',
        deviceName: 'سوناتا',
        deviceSerial: '5050',
        estimatedPriceFils: 0,
        odometerCurrent: '100000',
        status: 'completed',
      );
      final last = await repo.createOilChangeOrder(
        customerNameSnapshot: 'حسين',
        deviceName: 'سوناتا',
        deviceSerial: '5050',
        estimatedPriceFils: 0,
        odometerCurrent: '105000',
        status: 'completed',
      );
      expect((await _vehicles(h)).single['customer_name'], 'حسين');
      final db = await h.database;
      await ServiceOrdersSqlOps.softDeleteServiceOrderById(
        db,
        await h.tenantId(),
        id: last,
        nowIso: DateTime.now().toUtc().toIso8601String(),
      );
      final v = (await _vehicles(h)).single;
      expect(v['customer_name'], 'علي');
      expect(v['last_odometer'], 100000);
      expect(v['visits_count'], 1);
    });
  });

  group('البطاقة', () {
    setUpEmployeeHomeEnvironment();

    setUp(() async {
      for (final f in OilCardField.values) {
        await OilChangeSettings.setFieldRequired(f, false);
      }
    });

    Finder field(String label) => find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText ?? '').contains(label),
        );

    Future<void> settle(WidgetTester t, {int rounds = 12}) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('اللوحة تجلب السيارة ولا تملأ اسم الزبون ولا هاتفه',
        (t) async {
      await t.runAsync(() async {
        final ts = TenantContextService.instance;
        if (!ts.loaded) await ts.load();
        await DatabaseHelper().database;
        await OilChangeOrdersRepository.instance.createOilChangeOrder(
          customerNameSnapshot: 'المالك السابق',
          customerPhone: '+9647700000009',
          deviceName: 'لاندكروزر',
          deviceSerial: '24680',
          estimatedPriceFils: 0,
          status: 'completed',
        );
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      await t.enterText(field('رقم اللوحة').first, '24680');
      await settle(t);

      String text(String label) =>
          t.widget<TextField>(field(label).first).controller!.text;
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'لاندكروزر',
        ),
        findsOneWidget,
        reason: 'السيارة تُجلب',
      );
      expect(text('اسم العميل'), isEmpty);
      expect(text('الهاتف'), isNot(contains('7700000009')));
    });
  });
}
