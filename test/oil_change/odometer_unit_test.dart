// وحدة العداد لكل سيارة: كيلومتر أو ميل. تُحفظ في البطاقة، وتُنسخ من آخر
// زيارة للسيارة، وتُكتب بعد القراءة في البطاقة والإيصال والرسائل.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/services/vehicle_registry.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_auto_whatsapp_message.dart';
import 'package:naboo/verticals/oil_change/utils/oil_odometer_unit.dart';
import 'package:naboo/verticals/oil_change/utils/oil_service_whatsapp_message.dart';

import 'helpers/oil_change_test_harness.dart';
import 'helpers/oil_employee_home_harness.dart';

Future<int> _card(String plate, String odo, {String? unit}) =>
    OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: 'أحمد',
      deviceName: 'شيفروليه',
      deviceSerial: plate,
      odometerCurrent: odo,
      estimatedPriceFils: 0,
      status: 'completed',
      extraColumns: {'odometerUnit': ?unit},
    );

Map<String, dynamic> _order({String? unit}) => {
      'orderKind': ServiceOrderKinds.oilChange,
      'customerNameSnapshot': 'باقر',
      'deviceName': 'تاهو',
      'deviceSerial': '14212',
      'odometerCurrent': '85000',
      'odometerNext': '90000',
      'oilType': 'توتال',
      'agreedPriceFils': 25000000,
      'odometerUnit': ?unit,
    };

Invoice _invoice() => Invoice(
      id: 78,
      customerName: 'باقر',
      date: DateTime(2026, 11, 22, 10),
      type: InvoiceType.cash,
      items: [
        InvoiceItem(
          productName: 'غيار زيت',
          quantity: 1,
          price: 25000,
          total: 25000,
        ),
      ],
      discount: 0,
      tax: 0,
      advancePayment: 0,
      total: 25000,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  test('القراءة: كل ما ليس ميلاً كيلومتر', () {
    expect(OilOdometerUnit.parse('mi'), OilOdometerUnit.mi);
    expect(OilOdometerUnit.parse(null), OilOdometerUnit.km);
    expect(OilOdometerUnit.parse(''), OilOdometerUnit.km);
    expect(OilOdometerUnit.labelOf({'odometerUnit': 'mi'}), 'ميل');
    expect(OilOdometerUnit.labelOf(const {}), 'كم', reason: 'بطاقة قديمة');
  });

  test('الإيصال والرسالتان يكتبون وحدة السيارة', () {
    String odo(Map<String, dynamic> o) => ReceiptBuilders.fromInvoice(
          _invoice(),
          order: o,
        ).fields.firstWhere((f) => f.label == 'العداد').value;
    String next(Map<String, dynamic> o) => ReceiptBuilders.fromInvoice(
          _invoice(),
          order: o,
        ).highlights.firstWhere((h) => h.label == 'الغيار القادم عند').value;

    expect(odo(_order(unit: 'mi')), '85,000 ميل');
    expect(next(_order(unit: 'mi')), '90,000 ميل');
    expect(odo(_order()), '85,000 كم');

    final msg = buildOilServiceWhatsAppMessage(
      order: _order(unit: 'mi'),
      storeTitle: 'بابل',
      storeFooter: '',
    );
    expect(msg, contains('85000 ميل'));
    expect(msg, isNot(contains('85000 كم')));

    final auto = buildOilChangeAutoWhatsAppMessage(
      order: _order(unit: 'mi'),
      storeTitle: 'بابل',
      storeFooter: '',
    );
    expect(auto, contains('85000 ميل'));
  });

  test('الإيصال: دين سابق سُدِّد كله في البطاقة يظهر مع الرصيد صفراً', () {
    final doc = ReceiptBuilders.fromInvoice(
      Invoice(
        id: 79,
        customerName: 'باقر',
        customerId: 5,
        date: DateTime(2026, 11, 22, 10),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'غيار زيت',
            quantity: 1,
            price: 10000,
            total: 10000,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 10000,
        total: 10000,
      ),
      order: _order(),
      // إعادة طباعة بعد ديون لاحقة: الرصيد الحي 57,600 لا يغيّر الإيصال.
      accountBalanceFils: 57600000,
      cardDebtPayment: (paidFils: 15000000, beforeFils: 15000000),
    );
    final t = {for (final x in doc.totals) x.label: x.fils};
    expect(t['دين سابق'], 15000000);
    expect(t['تسديد من الدين السابق'], 15000000);
    expect(t['المستلم'], 25000000);
    expect(t['رصيد الحساب الآن'], 0);

    final none = ReceiptBuilders.fromInvoice(
      _invoice(),
      order: _order(),
      accountBalanceFils: 0,
    );
    expect(
      none.totals.map((x) => x.label),
      isNot(contains('دين سابق')),
      reason: 'لا دين ولا تسديد: لا سطور حساب',
    );
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

    test('الوحدة تُحفظ في البطاقة وتعود مع القراءة السابقة', () async {
      await _card('5050', '60000', unit: 'mi');
      final r = await VehicleRegistry.previousReading(
        await h.database,
        await h.tenantId(),
        plate: '5050',
      );
      expect(r!.km, 60000);
      expect(r.unit, OilOdometerUnit.mi);

      await _card('6060', '70000');
      final k = await VehicleRegistry.previousReading(
        await h.database,
        await h.tenantId(),
        plate: '6060',
      );
      expect(k!.unit, OilOdometerUnit.km);
    });
  });

  group('البطاقة', () {
    setUpEmployeeHomeEnvironment();

    setUpAll(() {
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final c in const [
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers',
      ]) {
        m.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
      }
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

    testWidgets('سيارة بالميل: الوحدة من آخر زيارة، ولا مقارنة بين وحدتين',
        (t) async {
      await t.runAsync(() async {
        final ts = TenantContextService.instance;
        if (!ts.loaded) await ts.load();
        await DatabaseHelper().database;
        await _card('97531', '85000', unit: 'mi');
      });
      await pumpEmployeeHome(
        t,
        const OilChangeFormScreen(),
        size: const Size(420, 1600),
      );
      await settle(t, rounds: 6);
      expect(field('القراءة الحالية (كم)'), findsOneWidget,
          reason: 'بطاقة جديدة بالكيلومتر');

      await t.enterText(field('اسم العميل').first, 'زبون');
      await t.enterText(field('الهاتف').first, '07711118888');
      await t.enterText(field('رقم اللوحة').first, '97531');
      await settle(t);
      expect(field('القراءة الحالية (ميل)'), findsOneWidget);
      expect(field('القراءة اللاحقة (ميل)'), findsOneWidget);
      expect(find.textContaining('السابقة: 85,000 ميل ·'), findsOneWidget);

      await t.enterText(field('القراءة الحالية').first, '58000');
      await settle(t, rounds: 3);
      expect(
        find.text('أقل من السابقة (85,000 ميل) — تأكّد من القراءة'),
        findsOneWidget,
      );

      // العداد بالكيلومتر الآن: 58,000 كم لا تُقارن بـ 85,000 ميل.
      final picker = find.byKey(const Key('odometerUnitPicker'));
      expect(picker, findsOneWidget);
      t
          .widget<SegmentedButton<String>>(picker)
          .onSelectionChanged!({OilOdometerUnit.km});
      await settle(t, rounds: 3);
      expect(field('القراءة الحالية (كم)'), findsOneWidget);
      expect(find.textContaining('أقل من السابقة'), findsNothing);
      expect(find.textContaining('السابقة: 85,000 ميل'), findsOneWidget);
    });
  });
}
