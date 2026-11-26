// المرحلة 3 — بطاقة بلا زيت (بند ح-4): لا تُحسب «غيار زيت» في التقرير،
// وعنوان الإيصال والبطاقة ورسالة واتساب بمحتواها.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_auto_whatsapp_message.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';
import 'package:naboo/verticals/oil_change/utils/oil_order_has_oil.dart';
import 'package:naboo/verticals/oil_change/utils/oil_service_whatsapp_message.dart';

import 'helpers/oil_change_test_harness.dart';

final _filterJson = encodeOilFiltersJson(const [
  OilFilterLineData(
    code: 'engine',
    name: 'فلتر تويوتا',
    priceFils: 15000000,
    label: 'فلتر المحرك',
  ),
]);

Map<String, dynamic> _filterOnly() => {
      'orderKind': ServiceOrderKinds.oilChange,
      'customerNameSnapshot': 'باقر',
      'deviceSerial': '14212',
      'odometerCurrent': '120500',
      'oilFiltersJson': _filterJson,
      'agreedPriceFils': 25000000,
    };

Invoice _invoice() => Invoice(
      id: 77,
      customerName: 'باقر',
      date: DateTime(2026, 11, 17, 10),
      type: InvoiceType.cash,
      items: [
        InvoiceItem(
          productName: 'فلتر المحرك: فلتر تويوتا',
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
    initOilChangeTestEnvironment();
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('اسم العمل من محتوى البطاقة', () {
    test('فيها زيت ← غيار زيت، وزيت العميل وحده يكفي', () {
      expect(oilCardWorkLabel({'oilType': 'توتال'}), 'غيار زيت');
      expect(oilCardWorkLabel({'oilCustomerProvided': 1}), 'غيار زيت');
    });

    test('فلتر فقط، فلتر وهيدروليك، خدمة فقط', () {
      expect(oilCardWorkLabel(_filterOnly()), 'تبديل فلتر');
      expect(
        oilCardWorkLabel({..._filterOnly(), 'powerHydraulicType': 'دكسرون'}),
        'تبديل فلتر وهيدروليك',
      );
      expect(oilCardWorkLabel({'requestedServices': 'غسيل محرك'}), 'خدمات');
      expect(oilCardWorkLabel(const {}), 'غيار زيت',
          reason: 'بطاقة قديمة بلا محتوى معروف تبقى كما كانت');
    });
  });

  test('الإيصال: «إيصال تبديل فلتر» بدل «إيصال غيار زيت»', () {
    final noOil = ReceiptBuilders.fromInvoice(_invoice(), order: _filterOnly());
    expect(noOil.title, 'إيصال تبديل فلتر');
    final withOil = ReceiptBuilders.fromInvoice(
      _invoice(),
      order: {..._filterOnly(), 'oilType': 'توتال'},
    );
    expect(withOil.title, 'إيصال غيار زيت');
  });

  test('قائمة الفواتير: العلامة «تبديل فلتر» مثل عنوان الإيصال', () {
    final order = _filterOnly();
    final kind = ReceiptBuilders.kindOf(_invoice(), order: order);
    expect(ReceiptBuilders.workLabelOf(kind, order), 'تبديل فلتر');
    expect(
      ReceiptBuilders.workLabelOf(kind, {...order, 'oilType': 'توتال'}),
      'غيار زيت',
    );
    expect(ReceiptBuilders.workLabelOf(kind, null), kind.shortLabel);
  });

  test('رسالتا واتساب تشكران على ما في البطاقة', () {
    final auto = buildOilChangeAutoWhatsAppMessage(
      order: _filterOnly(),
      storeTitle: 'محل البصرة',
    );
    expect(auto, contains('لتبديل فلتر'));
    expect(auto, isNot(contains('لغيار الزيت')));
    final manual = buildOilServiceWhatsAppMessage(
      order: {..._filterOnly(), 'oilType': 'توتال'},
      storeTitle: 'محل البصرة',
      storeFooter: '',
    );
    expect(manual, contains('لغيار الزيت'));
  });

  test('التقرير: بطاقة الفلتر ضمن البطاقات لا ضمن زيت المحل', () async {
    final h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
    await ServiceOrderBuilder(h).createPending(plate: 'OIL-1');
    await OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: 'باقر',
      deviceName: 'كامري',
      deviceSerial: 'FLT-1',
      oilFiltersJson: _filterJson,
      estimatedPriceFils: 25000000,
      agreedPriceFils: 25000000,
      status: 'pending',
      extraColumns: {'oilLaborFils': 10000000},
    );
    final now = DateTime.now();
    final r = await OilChangeReportsRepository.instance.loadSnapshot(
      ReportDateRange(from: now, to: now),
    );
    expect(r.visitCount, 2);
    expect(r.shopOilCount, 1);
    expect(r.customerOilCount, 0);
    expect(r.noOilCount, 1);
    expect(
      r.topServices.map((s) => s.name),
      contains('أجرة اليد (بلا زيت)'),
    );
  });
}
