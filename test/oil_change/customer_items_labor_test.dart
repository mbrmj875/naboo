// المرحلة 3 — «من العميل» للزيت والهيدروليك والفلاتر مع سطر أجرة اليد،
// وحفظ سعر لتر هيدروليك الكتالوج (الإصدار 51).
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/utils/oil_card_labor.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
  });

  group('قاعدة الأجرة', () {
    test('زيت المحل: الأجرة الأساسية', () {
      expect(
        effectiveOilLaborFils(
          customerOil: false,
          baseFils: 10000000,
          customerOilSettingFils: 7000000,
        ),
        10000000,
      );
    });

    test('زيت العميل: أجرته الخاصة تحل محل الأساسية ولا تُجمع معها', () {
      expect(
        effectiveOilLaborFils(
          customerOil: true,
          baseFils: 10000000,
          customerOilSettingFils: 7000000,
        ),
        7000000,
      );
    });

    test('زيت العميل بلا أجرة خاصة: الأساسية', () {
      expect(
        effectiveOilLaborFils(customerOil: true, baseFils: 10000000),
        10000000,
      );
    });

    test('ما كتبه الموظف في البطاقة يغلب الإعدادات', () {
      expect(
        effectiveOilLaborFils(
          customerOil: true,
          baseFils: 10000000,
          customerOilSettingFils: 7000000,
          cardFils: 5000000,
        ),
        5000000,
      );
    });

    test('هيدروليك/فلتر المحل بلا أجرة يد تلقائية', () {
      expect(
        effectiveCustomerItemLaborFils(
          customerProvided: false,
          settingFils: 3000000,
        ),
        0,
      );
      expect(
        effectiveCustomerItemLaborFils(
          customerProvided: true,
          settingFils: 3000000,
        ),
        3000000,
      );
    });
  });

  test('إعدادات أجور اليد تُحفظ وتُقرأ', () async {
    await OilChangeSettings.setCustomerLaborFils(
      OilChangeSettingsKeys.customerLaborOil,
      7000000,
    );
    await OilChangeSettings.setCustomerLaborFils(
      OilChangeSettingsKeys.customerLaborFilter,
      2000000,
    );
    final labor = (await OilChangeSettings.loadCardSettings()).customerLabor;
    expect(labor.oilFils, 7000000);
    expect(labor.filterFils, 2000000);
    expect(labor.hydraulicGearFils, 0);

    await OilChangeSettings.setCustomerLaborFils(
      OilChangeSettingsKeys.customerLaborOil,
      null,
    );
    expect(
      (await OilChangeSettings.loadCardSettings()).customerLabor.oilFils,
      isNull,
      reason: 'المسح يعيد زيت العميل إلى الأجرة الأساسية',
    );
  });

  test(
      'فاتورة بطاقة: زيت العميل + هيدروليك كير من العميل + فلتر من العميل '
      '+ هيدروليك باور من الكتالوج', () async {
    final filters = encodeOilFiltersJson([
      const OilFilterLineData(
        code: 'engine',
        name: 'فلتر أحضره الزبون',
        priceFils: 0,
        customerProvided: true,
        laborFils: 2000000,
      ),
    ]);
    final agreed = IqdMoney.toFils(7000 + 3000 + 2000 + 4 * 6000);
    final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: basraCustomerName,
      deviceName: basraCarName,
      deviceSerial: 'LABOR-1',
      oilType: 'زيت الزبون',
      oilCustomerProvided: true,
      hydraulicCustomerProvided: true,
      powerHydraulicType: 'دكسرون',
      powerHydraulicSize: '4 L',
      oilFiltersJson: filters,
      estimatedPriceFils: agreed,
      agreedPriceFils: agreed,
      advancePaymentFils: agreed,
      status: 'pending',
      extraColumns: {
        'oilLaborFils': IqdMoney.toFils(7000),
        'hydraulicLaborFils': IqdMoney.toFils(3000),
        'powerHydraulicSellPerLiterFils': IqdMoney.toFils(6000),
      },
    );
    final order =
        (await OilChangeOrdersRepository.instance.getOilChangeOrderById(id))!;
    expect(order['oilLaborFils'], IqdMoney.toFils(7000),
        reason: 'عمود الإصدار 51 محفوظ');

    final items = await OilChangeInvoiceBuilder.buildItems(
      order,
      keepLinesWithDiscount: true,
    );
    Map<String, int> byName() => {
          for (final i in items) i.productName: IqdMoney.toFils(i.total),
        };
    final lines = byName();

    expect(lines['أجرة التبديل (زيت العميل)'], IqdMoney.toFils(7000));
    expect(lines['أجرة هيدروليك الكير (من العميل)'], IqdMoney.toFils(3000));
    expect(lines['أجرة تركيب فلتر المحرك (من العميل)'], IqdMoney.toFils(2000));
    expect(
      lines.entries
          .where((e) => e.key.startsWith('دكسرون'))
          .single
          .value,
      IqdMoney.toFils(24000),
      reason: 'هيدروليك الكتالوج صار له سطر بسعر اللتر المحفوظ',
    );
    expect(
      items.any((i) => i.productName.contains('زيت الزبون')),
      isFalse,
      reason: 'لا ثمن لزيت العميل',
    );
    expect(OilChangeInvoiceBuilder.itemsTotalFils(items), agreed,
        reason: 'لا سطر تسوية: البنود تطابق الإجمالي');
  });
}
