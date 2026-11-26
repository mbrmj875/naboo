// المرحلة 6 — الشريحة 5: ربط السيارات بالعملاء. سيارات العميل الحالية،
// البحث عن العميل بلوحة سيارته أو اسمها، وأزرار سياراته في البطاقة.
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

Future<int> _customer(String name, String phone) async {
  final t = TenantContextService.instance;
  if (!t.loaded) await t.load();
  return DatabaseHelper().insertCustomer(
    name: name,
    phone: phone,
    tenantId: t.requireActiveTenantId(),
  );
}

Future<int> _card(String plate, {int? cid, required String name, String car = 'كامري'}) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerId: cid,
      customerNameSnapshot: name,
      deviceName: car,
      deviceSerial: plate,
      estimatedPriceFils: 0,
      status: 'completed',
    );

void main() {
  group('قاعدة البيانات', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;

    setUp(() async {
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      await VehicleRegistry.ensureSchema(await h.database);
    });

    test('سيارات العميل الحالية فقط: المبيعة لغيره تخرج', () async {
      final ali = await _customer('علي', '+9647700000011');
      final karar = await _customer('كرار', '+9647700000012');
      await _card('1001', cid: ali, name: 'علي', car: 'كامري');
      await _card('1002', cid: ali, name: 'علي', car: 'سوناتا');
      // باع السوناتا لكرار.
      await _card('1002', cid: karar, name: 'كرار', car: 'سوناتا');
      final repo = OilChangeOrdersRepository.instance;
      expect(
        (await repo.vehiclesForCustomer(ali)).map((v) => v['name']),
        ['كامري'],
      );
      expect(
        (await repo.vehiclesForCustomer(karar)).map((v) => v['name']),
        ['سوناتا'],
      );
    });

    test('البحث في العملاء باللوحة بأي كتابة وباسم السيارة', () async {
      final ali = await _customer('علي', '+9647700000021');
      await _customer('حسين', '+9647700000022');
      await _card('55667 B البصرة', cid: ali, name: 'علي', car: 'لاندكروزر');
      Future<List<String>> find(String q) async =>
          (await DatabaseHelper().queryCustomersPage(
            query: q,
            statusArabic: 'الكل',
            sortKey: 'name_asc',
            limit: 10,
            offset: 0,
          )).map((r) => '${r['name']}').toList();
      expect(await find('٥٥٦٦٧'), ['علي']);
      expect(await find('55667b'), ['علي']);
      expect(await find('لاند'), ['علي']);
      expect(await find('حسين'), ['حسين'], reason: 'البحث بالاسم كما كان');
      expect(
        await DatabaseHelper().countCustomersMatching(
          query: '55667',
          statusArabic: 'الكل',
        ),
        1,
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

    Finder editable(String text) => find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == text,
        );

    Future<void> press(WidgetTester t, Finder f) async {
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first);
    }

    testWidgets('عميل بسيارتين: أزرار للاختيار، و«سيارة جديدة» تفرغ السيارة',
        (t) async {
      await t.runAsync(() async {
        await DatabaseHelper().database;
        final cid = await _customer('ذو السيارتين', '+9647711117777');
        await _card('3131', cid: cid, name: 'ذو السيارتين', car: 'كامري');
        await _card('4242', cid: cid, name: 'ذو السيارتين', car: 'تاهو');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      await t.enterText(field('الهاتف').first, '07711117777');
      await settle(t);

      expect(find.text('سيارات العميل — اختر السيارة التي أحضرها:'), findsOneWidget);
      expect(find.byKey(const Key('customerCarNew')), findsOneWidget);
      expect(editable('3131'), findsNothing, reason: 'لا تعبئة قبل الاختيار');
      expect(editable('4242'), findsNothing);

      await press(t, find.textContaining('4242 · تاهو'));
      await settle(t);
      expect(editable('4242'), findsOneWidget);
      expect(editable('تاهو'), findsOneWidget);
      await t.scrollUntilVisible(
        field('اسم العميل'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        t.widget<TextField>(field('اسم العميل').first).controller!.text,
        'ذو السيارتين',
        reason: 'الزبون باقٍ',
      );

      await press(t, find.byKey(const Key('customerCarNew')));
      await settle(t, rounds: 4);
      expect(editable('4242'), findsNothing);
      expect(editable('تاهو'), findsNothing);
      // القائمة تبقى في مكانها فلا تقفز الحقول تحتها.
      expect(find.byKey(const Key('customerCarNew')), findsOneWidget);
    });

    testWidgets('عميل بسيارة واحدة: تُجلب سيارته لا التي باعها', (t) async {
      await t.runAsync(() async {
        await DatabaseHelper().database;
        final cid = await _customer('بائع', '+9647711118888');
        final other = await _customer('مشترٍ', '+9647711118889');
        await _card('5151', cid: cid, name: 'بائع', car: 'أكورد');
        await _card('6161', cid: cid, name: 'بائع', car: 'يوكن');
        await _card('6161', cid: other, name: 'مشترٍ', car: 'يوكن');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      await t.enterText(field('الهاتف').first, '07711118888');
      await settle(t);
      expect(find.byKey(const Key('customerCarNew')), findsNothing);
      expect(editable('أكورد'), findsOneWidget);
      expect(editable('يوكن'), findsNothing);
    });
  });
}
