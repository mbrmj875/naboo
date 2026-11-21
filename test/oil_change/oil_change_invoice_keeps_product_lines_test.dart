// المرحلة 1 — الفاتورة لا تُدمج في سطر واحد حين يختلف المبلغ المتفق عليه
// عن مجموع البنود، فيبقى رقم المنتج على سطره ويُخصم المخزون.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  late OilChangeTestHarness harness;

  setUp(() async {
    harness = OilChangeTestHarness.instance;
    await harness.reset();
    await harness.configureServiceOnly();
  });

  /// بطاقة فيها منتج من المخزون: قطعتان × 5,000 د.ع = 10,000 د.ع.
  Future<({int orderId, int productId})> cardWithProduct({
    required int agreedFils,
  }) async {
    final tid = await harness.tenantId();
    final productId = await seedLowStockOilProduct(
      DatabaseHelper(),
      tenantId: tid,
      name: 'منظف محرك',
      qty: 10,
    );
    final orderId =
        await OilChangeOrdersRepository.instance.createOilChangeOrder(
      customerNameSnapshot: basraCustomerName,
      deviceName: basraCarName,
      deviceSerial: 'KEEP-$agreedFils',
      oilType: basraOilBrand,
      odometerCurrent: basraOdometerCurrent,
      estimatedPriceFils: agreedFils,
      agreedPriceFils: agreedFils,
      advancePaymentFils: agreedFils,
      status: 'pending',
    );
    final order =
        (await OilChangeOrdersRepository.instance.getOilChangeOrderById(
      orderId,
    ))!;
    await ServiceOrdersRepository.instance.addItem(
      orderGlobalId: order['global_id'].toString(),
      productId: productId,
      productName: 'منظف محرك',
      quantity: 2,
      priceFils: IqdMoney.toFils(5000),
    );
    return (orderId: orderId, productId: productId);
  }

  Future<double> productQty(int productId) async {
    final db = await harness.database;
    final r = await db.query(
      'products',
      columns: ['qty'],
      where: 'id = ?',
      whereArgs: [productId],
    );
    return (r.single['qty'] as num).toDouble();
  }

  Future<void> checkout(int orderId) async {
    final order =
        (await OilChangeOrdersRepository.instance.getOilChangeOrderById(
      orderId,
    ))!;
    await OilChangeCheckoutService.instance.completeFromOrder(
      order: order,
      orderId: orderId,
    );
  }

  test('متفق عليه أقل من البنود: خصم على الفاتورة والمنتج يُخصم من المخزون',
      () async {
    final agreed = IqdMoney.toFils(8000);
    final c = await cardWithProduct(agreedFils: agreed);

    final order = (await OilChangeOrdersRepository.instance
        .getOilChangeOrderById(c.orderId))!;
    final items = await OilChangeInvoiceBuilder.buildItems(
      order,
      keepLinesWithDiscount: true,
    );
    expect(items.any((i) => i.productId == c.productId), isTrue);
    final expectedDiscount =
        OilChangeInvoiceBuilder.itemsTotalFils(items) - agreed;
    expect(expectedDiscount, greaterThan(0));
    expect(
      OilChangeInvoiceBuilder.discountFilsFor(order, items),
      expectedDiscount,
    );

    await checkout(c.orderId);
    expect(await productQty(c.productId), 8, reason: 'قطعتان خرجتا من المخزون');

    final db = await harness.database;
    final inv = (await db.query(
      'invoices',
      orderBy: 'id DESC',
      limit: 1,
    ))
        .single;
    expect(IqdMoney.toFils((inv['total'] as num).toDouble()), agreed);
    expect(
      IqdMoney.toFils((inv['discount'] as num).toDouble()),
      expectedDiscount,
    );
  });

  test('متفق عليه أكبر من البنود: سطر تسوية بالفرق والمنتج يُخصم', () async {
    final agreed = IqdMoney.toFils(60000);
    final c = await cardWithProduct(agreedFils: agreed);

    final order = (await OilChangeOrdersRepository.instance
        .getOilChangeOrderById(c.orderId))!;
    final items = await OilChangeInvoiceBuilder.buildItems(order);
    expect(items.any((i) => i.productId == c.productId), isTrue);
    // بلا أجرة أساسية: الفرق يصير سطر «خدمات» بالأجرة، لا تكرار للمنتج.
    final labor = items.where((i) => i.productId == null).toList();
    expect(
      OilChangeInvoiceBuilder.itemsTotalFils(labor),
      agreed - IqdMoney.toFils(10000),
    );
    expect(OilChangeInvoiceBuilder.itemsTotalFils(items), agreed);

    await checkout(c.orderId);
    expect(await productQty(c.productId), 8);
  });
}
