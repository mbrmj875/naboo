import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/tenant_context_service.dart';
import 'package:naboo/verticals/car_wash/services/wash_offer_engine.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_wash.dart';
import 'package:naboo/verticals/oil_change/reports/car_wash/car_wash_report_repository.dart';
import 'package:naboo/verticals/oil_change/services/card_wash_order_sync.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_post_sale_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  late OilChangeTestHarness harness;
  late ServiceOrderBuilder builder;

  setUp(() async {
    harness = OilChangeTestHarness.instance;
    await harness.reset();
    await harness.configureServiceOnly();
    builder = ServiceOrderBuilder(harness);
  });

  const oilFils = 40000000; // 40,000 د.ع
  const washGross = 10000000; // 10,000 د.ع

  OilCardWash paidWash() => const OilCardWash(
    lines: [OilCardWashLine(name: 'داخلي', priceFils: washGross)],
    washerName: 'علي',
  );

  OilCardWash freeWash() => const OilCardWash(
    lines: [OilCardWashLine(name: 'داخلي', priceFils: washGross)],
    washerName: 'علي',
    discountFils: washGross,
    offerCode: WashOfferCodes.withOil,
    offerNote: 'غسلة مجانية مع الغيار',
  );

  /// بطاقة غيار فيها غسلة، تُباع نقداً، ثم يُنشأ طلب غسيلها المرتبط.
  Future<({int cardId, int invoiceId})> sellCard(
    OilCardWash wash, {
    String plate = 'WSH-1',
  }) async {
    final total = oilFils + wash.netFils;
    final id = await builder.createPending(plate: plate, agreedPriceFils: total);
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      id,
      advancePaymentFils: total,
      agreedPriceFils: total,
      extraColumns: OilCardWash.columnsFor(wash),
    );
    final order = (await builder.byId(id))!;
    final sold = await OilChangeCheckoutService.instance.completeFromOrder(
      order: order,
      orderId: id,
    );
    await CardWashOrderSync.instance.syncForCardId(id);
    return (cardId: id, invoiceId: sold.invoiceId);
  }

  Future<List<Map<String, Object?>>> linkedWashes(int cardId) async {
    final db = await harness.database;
    final card = await db.query(
      'service_orders',
      columns: ['global_id'],
      where: 'id = ?',
      whereArgs: [cardId],
    );
    return db.query(
      'service_orders',
      where: 'orderKind = ? AND parentOrderGlobalId = ?',
      whereArgs: [ServiceOrderKinds.carWash, card.first['global_id']],
    );
  }

  ReportDateRange today() {
    final now = DateTime.now();
    return ReportDateRange(from: now, to: now);
  }

  test('الغسلة تُحفظ في البطاقة وتُقرأ كما هي', () {
    final cols = OilCardWash.columnsFor(freeWash());
    final back = OilCardWash.fromOrder({'cardWashJson': cols['cardWashJson']})!;
    expect(cols['cardWashNetFils'], 0);
    expect(back.isFree, isTrue);
    expect(back.washerName, 'علي');
    expect(back.offerCode, WashOfferCodes.withOil);
    expect(OilCardWash.columnsFor(null)['cardWashJson'], isNull);
  });

  test(
    'بيع بطاقة فيها غسلة: فاتورة واحدة، طلب غسيل مرتبط، ولا عدّ مزدوج',
    () async {
      final sold = await sellCard(paidWash());
      final db = await harness.database;

      final items = await db.query(
        'invoice_items',
        where: 'invoiceId = ?',
        whereArgs: [sold.invoiceId],
      );
      expect(items.map((i) => i['productName']), contains('غسيل: داخلي'));

      final linked = await linkedWashes(sold.cardId);
      expect(linked, hasLength(1));
      final w = linked.single;
      expect(w['invoiceId'], isNull);
      expect(w['agreedPriceFils'], washGross);
      expect(w['technicianName'], 'علي');
      expect(w['status'], 'delivered');
      expect(w['deviceSerial'], 'WSH-1');

      final wash = await CarWashReportRepository.instance.loadSnapshot(today());
      expect(wash.current.washes, 1);
      expect(wash.current.revenueFils, washGross);
      expect(wash.visits.single.withOil, isTrue);
      expect(wash.visits.single.washer, 'علي');

      final oil = await OilChangeReportsRepository.instance.loadSnapshot(
        today(),
      );
      expect(oil.current.revenueFils, oilFils);

      // إعادة المزامنة لا تكرّر الغسلة.
      await CardWashOrderSync.instance.syncForCardId(sold.cardId);
      expect(await linkedWashes(sold.cardId), hasLength(1));
    },
  );

  test(
    'الغسلة المجانية: سطرها في الفاتورة بصفر، وتُعدّ غسلة مجانية مع الغيار',
    () async {
      final sold = await sellCard(freeWash(), plate: 'WSH-2');
      final db = await harness.database;
      final items = await db.query(
        'invoice_items',
        where: 'invoiceId = ?',
        whereArgs: [sold.invoiceId],
      );
      expect(
        items.map((i) => i['productName']),
        contains('غسيل: داخلي (غسلة مجانية مع الغيار)'),
      );

      final wash = await CarWashReportRepository.instance.loadSnapshot(today());
      expect(wash.current.washes, 1);
      expect(wash.current.revenueFils, 0);
      expect(wash.offers.freeWashes, 1);
      expect(wash.offers.withOilCount, 1);
      expect(wash.offers.withOilDiscountFils, washGross);

      // لا تُحسب في عدّاد «تكرار الغسل».
      final tid = TenantContextService.instance.requireActiveTenantId();
      final linked = (await linkedWashes(sold.cardId)).single;
      expect(linked['washOfferCode'], WashOfferCodes.withOil);
      expect(tid, greaterThan(0));
    },
  );

  test('حذف البطاقة يلغي غسلتها ويخرجها من تقرير الغسيل', () async {
    final sold = await sellCard(paidWash(), plate: 'WSH-3');
    await OilChangePostSaleService.instance.voidOrder(orderId: sold.cardId);

    final linked = await linkedWashes(sold.cardId);
    expect(linked.single['status'], 'cancelled');
    final wash = await CarWashReportRepository.instance.loadSnapshot(today());
    expect(wash.current.washes, 0);
  });

  test('حذف الغسلة من البطاقة بالتعديل يلغي طلبها', () async {
    final sold = await sellCard(paidWash(), plate: 'WSH-4');
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      sold.cardId,
      extraColumns: OilCardWash.columnsFor(null),
    );
    await CardWashOrderSync.instance.syncForCardId(sold.cardId);
    expect((await linkedWashes(sold.cardId)).single['status'], 'cancelled');
  });

  test('فاتورة البطاقة لم تصل بعد من جهاز آخر: لا يُلغى شيء', () {
    final state = CardWashOrderSync.parentState(
      card: {'status': 'delivered', 'invoiceId': 9},
    );
    expect(state, CardWashParentState.unknown);
    expect(
      CardWashOrderSync.parentState(
        card: {'status': 'delivered', 'invoiceId': 9},
        invoice: {'isReturned': 0},
        invoiceReturned: true,
      ),
      CardWashParentState.ended,
    );
    expect(
      CardWashOrderSync.parentState(card: {'status': 'suspended'}),
      CardWashParentState.ended,
    );
  });
}
