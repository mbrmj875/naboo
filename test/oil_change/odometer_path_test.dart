// المرحلة 6 — الشريحة 3: مسار العداد. القراءة السابقة من سجل السيارة تلميحاً،
// وتنبيه وسؤال قبل الحفظ إن كانت الجديدة أقل منها.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/vehicle_registry.dart';

import 'helpers/oil_change_test_harness.dart';
import 'helpers/oil_employee_home_harness.dart';

Future<int> _card(
  String plate,
  String odo, {
  String status = 'completed',
  String car = 'كامري',
}) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: 'أحمد',
      deviceName: car,
      deviceSerial: plate,
      odometerCurrent: odo,
      estimatedPriceFils: 0,
      status: status,
    );

void main() {
  group('القراءة السابقة من السجل', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;

    setUp(() async {
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      await VehicleRegistry.ensureSchema(await h.database);
    });

    test('آخر قراءة مسجّلة؛ المعلّقة والفارغة لا تُحسب، والتعديل يرى ما قبله',
        () async {
      final db = await h.database;
      final tid = await h.tenantId();
      final first = await _card('1111', '80,000');
      final second = await _card('1111', '85000');
      await _card('1111', ''); // زيارة بلا قراءة
      await _card('1111', '99999', status: 'suspended');

      var r = await VehicleRegistry.previousReading(db, tid, plate: '1111');
      expect(r!.km, 85000);
      expect(r.at, isNotEmpty);

      // تعديل الزيارة الثانية: السابقة لها هي الأولى.
      r = await VehicleRegistry.previousReading(
        db,
        tid,
        plate: '1111',
        excludeOrderId: second,
      );
      expect(r!.km, 80000);
      r = await VehicleRegistry.previousReading(
        db,
        tid,
        plate: '1111',
        excludeOrderId: first,
      );
      expect(r!.km, isNull, reason: 'لا شيء قبل أول زيارة');

      expect(
        await VehicleRegistry.previousReading(db, tid, plate: '9999'),
        isNull,
        reason: 'سيارة غير معروفة',
      );
    });
  });

  group('البطاقة', () {
    setUpEmployeeHomeEnvironment();

    setUpAll(() {
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (_) async => null,
      );
      m.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (_) async => null,
      );
    });

    setUp(() async {
      for (final f in OilCardField.values) {
        await OilChangeSettings.setFieldRequired(f, false);
      }
      await OilChangeSettings.setDefaultPlateProvince(null);
      await OilChangeSettings.setBaseOilChangePriceFils(25000000);
    });

    Future<void> settle(WidgetTester t, {int rounds = 12}) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Finder field(String label) => find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText ?? '').contains(label),
        );

    Future<void> pressSave(WidgetTester t) async {
      await t.scrollUntilVisible(
        find.text('حفظ وبيع'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      final btn = find.ancestor(
        of: find.text('حفظ وبيع'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      t.widget<ButtonStyleButton>(btn.first).onPressed!();
    }

    Future<int> count(String plate) async {
      final db = await DatabaseHelper().database;
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM service_orders WHERE deviceSerial = ? AND deletedAt IS NULL',
        [plate],
      );
      return (r.first['n'] as num).toInt();
    }

    testWidgets('التلميح من السجل، والتنبيه، وسؤال الحفظ', (t) async {
      await t.runAsync(() async {
        final ts = TenantContextService.instance;
        if (!ts.loaded) await ts.load();
        await DatabaseHelper().database;
        await _card('86420', '85000');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      await t.enterText(field('اسم العميل').first, 'زبون');
      await t.enterText(field('الهاتف').first, '07711119999');
      await t.enterText(field('رقم اللوحة').first, '86420');
      await settle(t);
      expect(find.textContaining('السابقة: 85,000 كم ·'), findsOneWidget);

      await t.enterText(field('القراءة الحالية').first, '58000');
      await settle(t, rounds: 3);
      expect(
        find.text('أقل من السابقة (85,000 كم) — تأكّد من القراءة'),
        findsOneWidget,
      );

      await pressSave(t);
      await settle(t, rounds: 4);
      expect(find.text('القراءة أقل من السابقة'), findsOneWidget);
      t.widget<ButtonStyleButton>(find.byKey(const Key('odoLowerFix'))).onPressed!();
      await settle(t, rounds: 6);
      expect(
        (await t.runAsync(() => count('86420')))!,
        1,
        reason: '«تصحيح القراءة» لا يحفظ',
      );

      await t.scrollUntilVisible(
        field('القراءة الحالية'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(field('القراءة الحالية').first, '86000');
      await settle(t, rounds: 3);
      expect(find.textContaining('أقل من السابقة'), findsNothing);
    });
  });
}
