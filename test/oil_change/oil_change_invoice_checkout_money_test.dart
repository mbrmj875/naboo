import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/utils/invoice_validation.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_customer_debt.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('بناء الفاتورة من بطاقة غيار الزيت — فلس صحيح', () {
    late OilChangeTestHarness harness;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
    });

    test('المتفق عليه يتقدّم على التقديري', () {
      expect(
        OilChangeInvoiceBuilder.orderTotalFils({
          'agreedPriceFils': basraAgreedFils,
          'estimatedPriceFils': basraEstimatedFils,
        }),
        basraAgreedFils,
      );
      expect(
        OilChangeInvoiceBuilder.orderTotalFils({
          'estimatedPriceFils': basraEstimatedFils,
        }),
        basraEstimatedFils,
      );
    });

    test('زيت العميل لا يُضاعف الإجمالي بسعر اللتر', () async {
      const targetFils = 55000000;
      final items = await OilChangeInvoiceBuilder.buildItems({
        'agreedPriceFils': targetFils,
        'estimatedPriceFils': targetFils,
        'oilCustomerProvided': 1,
        'oilLitersUsed': 5,
        'oilSellPerLiterFils': 8000000,
        'oilType': basraOilBrand,
        'oilViscosity': basraOilGrade,
        'engineFilterName': basraEngineFilter,
        'engineFilterPriceFils': basraEngineFilterFils,
        'deviceName': basraCarName,
        'deviceSerial': basraPlate,
      });
      expect(items, isNotEmpty);
      expect(
        OilChangeInvoiceBuilder.itemsTotalFils(items),
        targetFils,
      );
      final names = items.map((i) => i.productName).join(' | ');
      expect(
        items.any((i) => i.productName.contains('كاسترول')),
        isFalse,
        reason: 'زيت العميل ظهر كبند مادة: $names',
      );
    });

    test('إجمالي البنود يساوي المتفق عليه حتى لو اختلفت التفاصيل', () async {
      final items = await OilChangeInvoiceBuilder.buildItems({
        'agreedPriceFils': basraAgreedFils,
        'estimatedPriceFils': basraEstimatedFils,
        'oilType': basraOilBrand,
        'deviceName': basraCarName,
        'deviceSerial': basraPlate,
        'engineFilterName': basraEngineFilter,
        'engineFilterPriceFils': 1000,
      });
      expect(OilChangeInvoiceBuilder.itemsTotalFils(items), basraAgreedFils);
      expect(items, isNotEmpty);
      expect(
        items.fold<int>(0, (s, i) => s + IqdMoney.toFils(i.total)),
        basraAgreedFils,
      );
    });

    test('متبقي الزيارة بالفلس لا يستخدم double', () {
      expect(
        oilChangeVisitRemainderFils(basraOilVisitOrder()),
        basraRemainderFils,
      );
      expect(
        oilChangeVisitRemainderFils(
          basraOilVisitOrder(advancePaymentFils: basraAgreedFils),
        ),
        0,
      );
      expect(
        oilChangeVisitRemainderFils({
          'agreedPriceFils': 1000,
          'advancePaymentFils': 5000,
        }),
        0,
      );
    });
  });

  group('إتمام البيع من البطاقة — رصيد الفاتورة والمستأجر', () {
    late OilChangeTestHarness harness;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
    });

    test('بيع نقدي كامل يربط فاتورة متوازنة بالبطاقة', () async {
      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerNameSnapshot: basraCustomerName,
        deviceName: basraCarName,
        deviceSerial: 'CHK-CASH-14212',
        carModel: basraCarModel,
        odometerCurrent: basraOdometerCurrent,
        oilType: basraOilBrand,
        oilViscosity: basraOilGrade,
        estimatedPriceFils: oilTestAgreedPriceFils,
        agreedPriceFils: oilTestAgreedPriceFils,
        advancePaymentFils: oilTestAgreedPriceFils,
        status: 'pending',
        technicianName: basraTechnician,
      );
      final order = await OilChangeOrdersRepository.instance
          .getOilChangeOrderById(id);
      expect(order, isNotNull);

      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order!,
        orderId: id,
        createdByUserName: basraTechnician,
      );

      expect(result.invoiceId, greaterThan(0));
      expect(result.totalFils, oilTestAgreedPriceFils);
      expect(result.remainderFils, 0);
      expect(result.invoiceType, InvoiceType.cash);

      final updated =
          await OilChangeOrdersRepository.instance.getOilChangeOrderById(id);
      expect(updated!['status'], 'delivered');
      expect(updated['invoiceId'], result.invoiceId);

      final tid = TenantContextService.instance.requireActiveTenantId();
      final db = await harness.database;
      final inv = await db.query(
        'invoices',
        where: 'id = ? AND tenantId = ? AND deleted_at IS NULL',
        whereArgs: [result.invoiceId, tid],
        limit: 1,
      );
      expect(inv, hasLength(1));
      expect(
        IqdMoney.toFils((inv.first['total'] as num).toDouble()),
        oilTestAgreedPriceFils,
      );
    });

    test('آجل لعميل مسجّل يُنشئ فاتورة credit بعد تحقق التوازن', () async {
      final db = await harness.database;
      final tid = await harness.tenantId();
      final customerId = await db.insert('customers', {
        'tenantId': tid,
        'name': basraCustomerName,
        'phone': basraCustomerPhone,
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      final id = await OilChangeOrdersRepository.instance.createOilChangeOrder(
        customerNameSnapshot: basraCustomerName,
        customerId: customerId,
        deviceName: basraCarName,
        deviceSerial: 'CHK-CRD-14212',
        oilType: basraOilBrand,
        odometerCurrent: basraOdometerCurrent,
        estimatedPriceFils: oilTestAgreedPriceFils,
        agreedPriceFils: oilTestAgreedPriceFils,
        advancePaymentFils: 0,
        status: 'pending',
      );
      final order = (await OilChangeOrdersRepository.instance
          .getOilChangeOrderById(id))!;

      final result = await OilChangeCheckoutService.instance.completeFromOrder(
        order: order,
        orderId: id,
      );
      expect(result.invoiceType, InvoiceType.credit);
      expect(result.remainderFils, oilTestAgreedPriceFils);
      expect(result.remainderFils, greaterThan(500));
    });

    test('معرّف بطاقة غير صالح يُرفض قبل أي كتابة', () async {
      expect(
        () => OilChangeCheckoutService.instance.completeFromOrder(
          order: basraOilVisitOrder(),
          orderId: 0,
        ),
        throwsA(
          isA<OilChangeCheckoutException>().having(
            (e) => e.message,
            'message',
            contains('غير صالح'),
          ),
        ),
      );
    });

    test('فاتورة مبنية من البطاقة تجتاز validateInvoiceBalance', () async {
      final items = await OilChangeInvoiceBuilder.buildItems({
        'agreedPriceFils': oilTestAgreedPriceFils,
        'estimatedPriceFils': oilTestAgreedPriceFils,
        'deviceName': basraCarName,
        'deviceSerial': basraPlate,
        'oilType': basraOilBrand,
      });
      final total = IqdMoney.fromFils(
        OilChangeInvoiceBuilder.itemsTotalFils(items),
      );
      final invoice = Invoice(
        customerName: basraCustomerName,
        date: DateTime.now(),
        type: InvoiceType.cash,
        items: items,
        discount: 0,
        tax: 0,
        advancePayment: total,
        total: total,
      );
      final balance = validateInvoiceBalance(invoice);
      expect(balance.isValid, isTrue, reason: balance.errorMessage);
    });
  });
}
