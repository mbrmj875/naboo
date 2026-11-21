// المرحلة 6 — الشريحة 2: إدخال اللوحة المنظم. رقم + حرف اختياري + محافظة
// (افتراض المحل)، وسؤال واحد عن سيارة قديمة لوحتها ناقصة بالرقم نفسه.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_card_settings_screen.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/vehicle_registry.dart';
import 'package:naboo/verticals/oil_change/utils/iraq_plate.dart';

import 'helpers/oil_change_test_harness.dart';
import 'helpers/oil_employee_home_harness.dart';

Future<int> _card(String plate, {String customer = 'أحمد', String car = 'كامري'}) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: customer,
      deviceName: car,
      deviceSerial: plate,
      estimatedPriceFils: 0,
      status: 'completed',
    );

void main() {
  group('قراءة اللوحة وكتابتها', () {
    test('الصيغ المختلفة', () {
      var p = IraqPlate.parse('12345 B البصرة');
      expect([p.number, p.letter, p.province], ['12345', 'B', 'البصرة']);
      p = IraqPlate.parse('12345-اربيل');
      expect([p.number, p.letter, p.province], ['12345', null, 'أربيل']);
      p = IraqPlate.parse('12345 ذي قار');
      expect(p.province, 'ذي قار');
      p = IraqPlate.parse('12345 b');
      expect(p.letter, 'B');
      p = IraqPlate.parse('12345-14');
      expect([p.number, p.letter, p.province], ['12345-14', null, null],
          reason: 'رمز قديم يبقى كما كُتب');
      expect(IraqPlate.parse('12345').isPlainNumber, isTrue);
      expect(
        const IraqPlate(number: '12345', letter: 'B', province: 'البصرة')
            .format(),
        '12345 B البصرة',
      );
      expect(const IraqPlate(number: '', province: 'البصرة').format(), '');
      expect(kIraqProvinces, hasLength(18));
    });
  });

  group('السجل', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;

    setUp(() async {
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureServiceOnly();
      await VehicleRegistry.ensureSchema(await h.database);
    });

    test('أجزاء اللوحة تُحفظ في السيارة', () async {
      await _card('777 C بغداد');
      final v = (await (await h.database).query('vehicles')).single;
      expect(v['plate_number'], '777');
      expect(v['plate_letter'], 'C');
      expect(v['plate_province'], 'بغداد');
    });

    test('المرشحون: القديمة الناقصة بالرقم نفسه فقط، ثم الإكمال يربط بها',
        () async {
      await _card('12345', car: 'كامري');
      await _card('12345-14', car: 'سوناتا');
      await _card('123456');
      await _card('12345 الأنبار', car: 'كيا');
      final db = await h.database;
      final tid = await h.tenantId();

      expect(
        await VehicleRegistry.legacyCandidates(db, tid, '12345'),
        isEmpty,
        reason: 'لوحة بلا حرف ولا محافظة تطابق مباشرة، بلا سؤال',
      );
      final c = await VehicleRegistry.legacyCandidates(db, tid, '12345 B البصرة');
      expect(c.map((v) => v['name']).toSet(), {'كامري', 'سوناتا'});

      final gid = c.firstWhere((v) => v['name'] == 'كامري')['global_id'] as String;
      expect(await VehicleRegistry.adoptPlate(db, tid, gid, '12345 B البصرة'), isTrue);
      await _card('12345 B البصرة', customer: 'باقر', car: 'كامري');
      final v = (await db.query(
        'vehicles',
        where: 'global_id = ?',
        whereArgs: [gid],
      )).single;
      expect(v['visits_count'], 2, reason: 'الزيارتان على السيارة نفسها');
      expect(v['plate_display'], '12345 B البصرة');
      expect(v['plate_province'], 'البصرة');
      expect(
        (await VehicleRegistry.legacyCandidates(db, tid, '12345 B البصرة'))
            .map((v) => v['name']),
        ['سوناتا'],
        reason: 'كامري أُكملت فلا يُسأل عنها ثانية؛ «12345-14» سيارة أخرى محتملة',
      );
    });
  });

  group('البطاقة والإعدادات', () {
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

    Future<void> press(WidgetTester t, Finder f) async {
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first);
    }

    Future<void> settle(WidgetTester t, {int rounds = 12}) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('محافظة المحل تُضاف للرقم، وسؤال السيارة القديمة يجلبها',
        (t) async {
      await t.runAsync(() async {
        final ts = TenantContextService.instance;
        if (!ts.loaded) await ts.load();
        await DatabaseHelper().database;
        await OilChangeSettings.setDefaultPlateProvince('البصرة');
        await _card('24680', customer: 'المالك', car: 'لاندكروزر');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      expect(find.text('البصرة'), findsOneWidget, reason: 'افتراض المحل');

      await t.enterText(find.byKey(const Key('plateNumberField')), '24680');
      await settle(t, rounds: 4);
      await press(t, find.byKey(const Key('plateLetterButton')));
      await settle(t, rounds: 3);
      await press(t, find.byKey(const Key('plateLetter_B')));
      await settle(t);

      // السؤال: سيارة بالرقم نفسه بلوحة ناقصة.
      expect(find.text('هل هي سيارة مسجّلة؟'), findsOneWidget);
      await press(t, find.textContaining('لاندكروزر').first);
      await settle(t);
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'لاندكروزر',
        ),
        findsOneWidget,
      );
      // اللوحة الكاملة باقية كما كُتبت.
      expect(find.text('الحرف B'), findsOneWidget);
      expect(find.text('البصرة'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == '24680',
        ),
        findsOneWidget,
      );
    });

    testWidgets('«سيارة أخرى» لا يُسأل بعدها في البطاقة', (t) async {
      await t.runAsync(() async {
        final ts = TenantContextService.instance;
        if (!ts.loaded) await ts.load();
        await DatabaseHelper().database;
        await OilChangeSettings.setDefaultPlateProvince('بغداد');
        await _card('13579', car: 'أكسنت');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      await t.enterText(find.byKey(const Key('plateNumberField')), '13579');
      await settle(t, rounds: 4);
      // «13579 بغداد» لا تطابق مباشرة؛ زر الجلب يسأل عن القديمة.
      await press(t, find.byIcon(Icons.sync_rounded));
      await settle(t);
      expect(find.text('هل هي سيارة مسجّلة؟'), findsOneWidget);
      await press(t, find.byKey(const Key('legacyPlateOther')));
      await settle(t);
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'أكسنت',
        ),
        findsNothing,
      );
      await press(t, find.byIcon(Icons.sync_rounded));
      await settle(t);
      expect(find.text('هل هي سيارة مسجّلة؟'), findsNothing);
    });

    testWidgets('إعداد محافظة المحل يُحفظ', (t) async {
      await pumpEmployeeHome(
        t,
        const OilChangeCardSettingsScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      expect(find.textContaining('غير محددة'), findsOneWidget);
      await press(t, find.byKey(const Key('defaultPlateProvinceTile')));
      await settle(t, rounds: 3);
      await press(t, find.byKey(const Key('defaultProvince_ميسان')));
      await settle(t);
      expect(
        await t.runAsync(OilChangeSettings.getDefaultPlateProvince),
        'ميسان',
      );
      expect(find.textContaining('ميسان'), findsOneWidget);
    });
  });
}
