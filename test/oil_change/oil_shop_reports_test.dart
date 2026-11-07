import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/verticals/oil_change/reports/car_wash/car_wash_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/car_wash/car_wash_report_repository.dart';
import 'package:naboo/verticals/oil_change/reports/direct_sale/direct_sale_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/oil_change_reports_panel.dart';
import 'package:naboo/verticals/oil_change/reports/products/products_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/direct_sale/direct_sale_report_repository.dart';
import 'package:naboo/verticals/oil_change/reports/kit/oil_shop_report_sql.dart';
import 'package:naboo/verticals/oil_change/reports/kit/report_math.dart';
import 'package:naboo/verticals/oil_change/reports/products/products_report_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_direct_sale_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';

import 'helpers/oil_change_test_harness.dart';

/// فاتورة بسطورها مباشرة في القاعدة — بلا منطق البيع، لنختبر التقارير وحدها.
Future<int> _invoice(
  OilChangeTestHarness h, {
  required int totalFils,
  required List<(int?, String, double, int, double?)> lines,
  String? tag,
  int type = 0,
  int? returnOf,
  DateTime? date,
}) async {
  final db = await h.database;
  final tid = await h.tenantId();
  final id = await db.insert('invoices', {
    'tenantId': tid,
    'customerName': 'زبون',
    'date': (date ?? DateTime.now()).toIso8601String(),
    'type': type,
    'total': totalFils / 1000,
    'totalFils': totalFils,
    'advancePayment': type == 1 ? 0 : totalFils / 1000,
    'advancePaymentFils': type == 1 ? 0 : totalFils,
    'isReturned': returnOf == null ? 0 : 1,
    'originalInvoiceId': ?returnOf,
    'deliveryAddress': ?tag,
  });
  for (final (pid, name, qty, fils, unitCost) in lines) {
    await db.insert('invoice_items', {
      'invoiceId': id,
      'productId': pid,
      'productName': name,
      'quantity': qty,
      'price': fils / 1000 / qty,
      'total': fils / 1000,
      'totalFils': fils,
      'unitCost': unitCost,
    });
  }
  return id;
}

Future<int> _product(
  OilChangeTestHarness h, {
  required String name,
  double qty = 10,
  double buy = 2000,
  double threshold = 0,
}) async {
  final db = await h.database;
  return db.insert('products', {
    'tenantId': await h.tenantId(),
    'name': name,
    'qty': qty,
    'lowStockThreshold': threshold,
    'isActive': 1,
    'trackInventory': 1,
    'isService': 0,
    'buyPrice': buy,
    'sellPrice': buy * 1.5,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

ReportDateRange _today() {
  final now = DateTime.now();
  return ReportDateRange(from: now, to: now);
}

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  late OilChangeTestHarness h;
  late ServiceOrderBuilder builder;

  setUp(() async {
    h = OilChangeTestHarness.instance;
    await h.reset();
    await h.configureHybrid();
    builder = ServiceOrderBuilder(h);
  });

  group('ReportMath', () {
    test('الفترة السابقة بنفس الطول وتنتهي قبل البداية بيوم', () {
      final prev = ReportMath.previousRange(
        ReportDateRange(from: DateTime(2026, 3, 10), to: DateTime(2026, 3, 16)),
      );
      expect(prev.from, DateTime(2026, 3, 3));
      expect(prev.to, DateTime(2026, 3, 9));
    });

    test('الأيام الفارغة تبقى صفراً في المخطط', () {
      final days = ReportMath.zeroFill(
        ReportDateRange(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 4)),
        counts: {'2026-03-02': 3},
        amountsFils: {'2026-03-02': 9000},
      );
      expect(days.map((d) => d.count), [0, 3, 0, 0]);
    });

    test('السبت أول أيام الأسبوع والجمعة آخرها', () {
      expect(ReportMath.weekdayRow(DateTime(2026, 11, 7)), 0); // سبت
      expect(ReportMath.weekdayRow(DateTime(2026, 11, 13)), 6); // جمعة
    });
  });

  group('تقرير غيار الزيت', () {
    test('البطاقة غير المفوترة لا يُضاف إليها ثمن الزيت مرتين', () async {
      final oil = await _product(h, name: 'زيت 5W-30', buy: 4000);
      await builder.createPending(
        plate: 'R1',
        agreedPriceFils: 30000,
        oilProductId: oil,
        oilLitersUsed: 4,
      );
      final r = await OilChangeReportsRepository.instance.loadSnapshot(
        _today(),
      );
      expect(r.current.revenueFils, 30000);
      expect(r.totalShopLiters, 4);
    });

    test(
      'البطاقة الملغاة لا تُحسب، والفاتورة المرتجعة تجعل إيرادها صفراً',
      () async {
        final cancelled = await builder.createPending(plate: 'C1');
        final returned = await builder.createPending(
          plate: 'C2',
          agreedPriceFils: 50000,
        );
        final db = await h.database;
        await db.update(
          'service_orders',
          {'status': 'cancelled'},
          where: 'id = ?',
          whereArgs: [cancelled],
        );
        final inv = await _invoice(h, totalFils: 50000, lines: const []);
        await db.update(
          'invoices',
          {'isReturned': 1},
          where: 'id = ?',
          whereArgs: [inv],
        );
        await linkOrderToInvoice(
          dbHelper: h.dbHelper,
          orderId: returned,
          invoiceId: inv,
          tenantId: await h.tenantId(),
        );

        final r = await OilChangeReportsRepository.instance.loadSnapshot(
          _today(),
        );
        expect(r.visitCount, 1);
        expect(r.current.revenueFils, 0);
      },
    );

    test('ربح البطاقة المفوترة = الفاتورة − تكلفة مواد البطاقة', () async {
      final oil = await _product(h, name: 'زيت', buy: 4000);
      final order = await builder.createPending(plate: 'P1');
      final db = await h.database;
      await db.update(
        'service_orders',
        {'oilProductId': oil, 'oilLitersUsed': 4},
        where: 'id = ?',
        whereArgs: [order],
      );
      // سطر الفاتورة بلا منتج (كما يحدث حين تُجمع البطاقة في سطر واحد).
      final inv = await _invoice(
        h,
        totalFils: 40000000,
        lines: [(null, 'غيار زيت', 1, 40000000, 0)],
      );
      await linkOrderToInvoice(
        dbHelper: h.dbHelper,
        orderId: order,
        invoiceId: inv,
        tenantId: await h.tenantId(),
      );
      final r = await OilChangeReportsRepository.instance.loadSnapshot(
        _today(),
      );
      // 4 لترات × 4,000 د.ع = 16,000 د.ع من فاتورة 40,000 د.ع.
      expect(r.current.invoicedRevenueFils, 40000000);
      expect(r.current.costFils, 16000000);
      expect(r.current.profitFils, 24000000);
      expect(r.costCoverage.missing, 0);
    });
  });

  group('تقرير البيع المباشر', () {
    test('الصافي يطرح المرتجع، ويتجاهل البيع السريع', () async {
      final filter = await _product(h, name: 'فلتر', buy: 3000);
      final sale = await _invoice(
        h,
        totalFils: 20000,
        tag: OilChangeDirectSaleService.sourceTag,
        lines: [(filter, 'فلتر', 4, 20000, 3)],
      );
      await _invoice(
        h,
        totalFils: 5000,
        returnOf: sale,
        lines: [(filter, 'فلتر', 1, 5000, 3)],
      );
      await _invoice(
        h,
        totalFils: 99000,
        lines: [(filter, 'فلتر', 1, 99000, 3000)],
      );

      final r = await DirectSaleReportRepository.instance.loadSnapshot(
        _today(),
      );
      expect(r.current.invoices, 1);
      expect(r.current.netFils, 15000);
      // تكلفة 4 مباعة − 1 مرتجعة = 3 × 3 دنانير.
      expect(r.current.costFils, 9000);
      expect(r.current.profitFils, 15000 - 9000);
      expect(r.returnCount, 1);
      expect(r.products.single.quantity, 3);
    });

    test('الآجل يُحسب منفصلاً مع المتبقي على العملاء', () async {
      final p = await _product(h, name: 'زيت');
      await _invoice(
        h,
        totalFils: 30000,
        type: 1,
        tag: OilChangeDirectSaleService.sourceTag,
        lines: [(p, 'زيت', 1, 30000, 2000)],
      );
      final r = await DirectSaleReportRepository.instance.loadSnapshot(
        _today(),
      );
      expect(r.creditFils, 30000);
      expect(r.cashFils, 0);
      expect(r.creditOutstandingFils, 30000);
    });
  });

  group('تقرير غسيل السيارات', () {
    Future<int> wash(
      String plate,
      String types,
      int fils, {
      DateTime? at,
    }) async {
      final id = await ServiceOrdersRepository.instance.createServiceOrder(
        customerNameSnapshot: 'زبون',
        deviceName: 'غسيل',
        deviceSerial: plate,
        estimatedPriceFils: fils,
        agreedPriceFils: fils,
        requestedServices: types,
        technicianName: 'علي',
        orderKind: ServiceOrderKinds.carWash,
      );
      if (at != null) {
        final db = await h.database;
        await db.update(
          'service_orders',
          {'createdAt': at.toIso8601String()},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return id;
    }

    test('الإيراد، الأنواع، والزبون العائد', () async {
      await wash(
        '١٢ب٣٤',
        'خارجي',
        5000,
        at: DateTime.now().subtract(const Duration(days: 40)),
      );
      await wash('١٢ب٣٤', 'خارجي,داخلي', 15000);
      await wash('99X', 'خارجي', 5000);

      final r = await CarWashReportRepository.instance.loadSnapshot(_today());
      expect(r.current.washes, 2);
      expect(r.current.revenueFils, 20000);
      expect(r.uniqueCars, 2);
      expect(r.returningCars, 1);
      final outside = r.types.firstWhere((t) => t.label == 'خارجي');
      expect(outside.count, 2);
      expect(
        r.types.fold<int>(0, (a, t) => a + t.amountFils),
        20000,
        reason: 'مجموع الأنواع يساوي الإيراد',
      );
    });

    test('لا يدخل في تقرير الزيت', () async {
      await wash('W1', 'خارجي', 5000);
      final oil = await OilChangeReportsRepository.instance.loadSnapshot(
        _today(),
      );
      expect(oil.visitCount, 0);
    });
  });

  group('تقرير المنتجات', () {
    test('كل سطر يُنسب لقناته، والمرتجع لقناة فاتورته الأصلية', () async {
      final oil = await _product(h, name: 'زيت', qty: 20, buy: 4000);
      final card = await builder.createPending(plate: 'K1');
      final cardInv = await _invoice(
        h,
        totalFils: 24000,
        lines: [(oil, 'زيت', 4, 24000, 4000)],
      );
      await linkOrderToInvoice(
        dbHelper: h.dbHelper,
        orderId: card,
        invoiceId: cardInv,
        tenantId: await h.tenantId(),
      );
      final direct = await _invoice(
        h,
        totalFils: 12000,
        tag: OilChangeDirectSaleService.sourceTag,
        lines: [(oil, 'زيت', 2, 12000, 4000)],
      );
      await _invoice(
        h,
        totalFils: 6000,
        returnOf: direct,
        lines: [(oil, 'زيت', 1, 6000, 4000)],
      );
      await _invoice(h, totalFils: 6000, lines: [(oil, 'زيت', 1, 6000, 4000)]);

      final r = await ProductsReportRepository.instance.loadSnapshot(_today());
      final row = r.products.firstWhere((p) => p.id == oil);
      expect(row.soldQtyByChannel[OilShopChannel.oilCard], 4);
      expect(row.soldQtyByChannel[OilShopChannel.directSale], 1);
      expect(row.soldQtyByChannel[OilShopChannel.quickSale], 1);
      expect(row.soldQty, 6);
      expect(r.revenueByChannelFils[OilShopChannel.directSale], 6000);
      expect(r.revenueFils, 24000 + 6000 + 6000);
      // 20 لتراً بمعدل 6 في يوم واحد.
      expect(row.daysOfCover(r.rangeDays), closeTo(20 / 6, 0.001));
    });

    test('الراكد والنواقص', () async {
      await _product(h, name: 'راكد', qty: 5, buy: 1000);
      await _product(h, name: 'ناقص', qty: 1, threshold: 3);
      final r = await ProductsReportRepository.instance.loadSnapshot(_today());
      expect(r.idle.map((p) => p.name), containsAll(['راكد', 'ناقص']));
      expect(r.shortageCount, 1);
      expect(r.idleCostFils, 5000 * 1000 + 2000 * 1000);
    });
  });

  group('اللوحات', () {
    Future<List<Widget>> seededPanels() async {
      final oil = await _product(h, name: 'زيت 5W-30', qty: 12, buy: 4);
      final order = await builder.createPending(plate: 'S1');
      final inv = await _invoice(
        h,
        totalFils: 40000,
        lines: [(oil, 'زيت 5W-30', 4, 24000, 4)],
      );
      await linkOrderToInvoice(
        dbHelper: h.dbHelper,
        orderId: order,
        invoiceId: inv,
        tenantId: await h.tenantId(),
      );
      await _invoice(
        h,
        totalFils: 12000,
        tag: OilChangeDirectSaleService.sourceTag,
        lines: [(oil, 'زيت 5W-30', 2, 12000, 4)],
      );
      await ServiceOrdersRepository.instance.createServiceOrder(
        customerNameSnapshot: 'زبون',
        deviceName: 'غسيل',
        deviceSerial: 'W9',
        estimatedPriceFils: 5000,
        agreedPriceFils: 5000,
        requestedServices: 'خارجي',
        technicianName: 'علي',
        orderKind: ServiceOrderKinds.carWash,
      );
      final range = ReportDateRange(
        from: DateTime.now().subtract(const Duration(days: 6)),
        to: DateTime.now(),
      );
      return [
        OilChangeReportsPanel(
          data: await OilChangeReportsRepository.instance.loadSnapshot(range),
        ),
        DirectSaleReportPanel(
          data: await DirectSaleReportRepository.instance.loadSnapshot(range),
        ),
        CarWashReportPanel(
          data: await CarWashReportRepository.instance.loadSnapshot(range),
        ),
        ProductsReportPanel(
          data: await ProductsReportRepository.instance.loadSnapshot(range),
        ),
      ];
    }

    testWidgets('تُرسم على الهاتف والشاشة العريضة بلا أخطاء', (tester) async {
      final panels = await tester.runAsync(seededPanels);
      for (final size in const [Size(360, 800), Size(1280, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final panel in panels!) {
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: panel),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${panel.runtimeType} $size',
          );
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
