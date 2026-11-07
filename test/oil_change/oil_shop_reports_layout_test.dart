import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/services/reports_repository.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/service_orders_repository.dart';
import 'package:naboo/verticals/oil_change/reports/car_wash/car_wash_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/car_wash/car_wash_report_repository.dart';
import 'package:naboo/verticals/oil_change/reports/direct_sale/direct_sale_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/direct_sale/direct_sale_report_repository.dart';
import 'package:naboo/verticals/oil_change/reports/oil_change_reports_panel.dart';
import 'package:naboo/verticals/oil_change/reports/products/products_report_panel.dart';
import 'package:naboo/verticals/oil_change/reports/products/products_report_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_direct_sale_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_reports_repository.dart';

import 'helpers/oil_change_test_harness.dart';

/// تقارير محل الزيت على كل مقاسات الشاشات: من هاتف صغير حتى شاشة 1920،
/// ومع تكبير الخط. أي فيضان أو خطأ رسم يُفشل الاختبار.
///
/// لحفظ صور للمراجعة: `REPORT_SHOTS_DIR=/path flutter test <this file>`.

const _sizes = <(String, Size)>[
  ('320', Size(320, 640)),
  ('360', Size(360, 800)),
  ('412', Size(412, 915)),
  ('600', Size(600, 960)),
  ('768', Size(768, 1024)),
  ('1024', Size(1024, 768)),
  ('1280', Size(1280, 900)),
  ('1920', Size(1920, 1080)),
];

Future<void> _loadFonts() async {
  final loader = FontLoader('Tajawal');
  for (final f in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf']) {
    final bytes = File('assets/fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<int> _product(
  OilChangeTestHarness h, {
  required String name,
  required double qty,
  required double buy,
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
    'sellPrice': buy * 1.4,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<int> _invoice(
  OilChangeTestHarness h, {
  required DateTime date,
  required List<(int?, String, double, int, double?)> lines,
  String? tag,
  int type = 0,
  String customer = 'زبون',
}) async {
  final db = await h.database;
  final total = lines.fold<int>(0, (a, l) => a + l.$4);
  final id = await db.insert('invoices', {
    'tenantId': await h.tenantId(),
    'customerName': customer,
    'date': date.toIso8601String(),
    'type': type,
    'total': total / 1000,
    'totalFils': total,
    'advancePayment': type == 1 ? 0 : total / 1000,
    'advancePaymentFils': type == 1 ? 0 : total,
    'isReturned': 0,
    'deliveryAddress': ?tag,
  });
  for (final (pid, name, qty, fils, cost) in lines) {
    await db.insert('invoice_items', {
      'invoiceId': id,
      'productId': pid,
      'productName': name,
      'quantity': qty,
      'price': fils / 1000 / qty,
      'total': fils / 1000,
      'totalFils': fils,
      'unitCost': cost,
    });
  }
  return id;
}

/// أسبوعان من عمل محل حقيقي تقريباً.
Future<List<Widget>> _seed(OilChangeTestHarness h) async {
  final db = await h.database;
  final tid = await h.tenantId();
  final oils = [
    (
      await _product(h, name: 'ديفلون 15W40', qty: 40, buy: 3500),
      'ديفلون 15W40',
    ),
    (
      await _product(h, name: 'موبيل 5W30 فل سنثتك', qty: 6, buy: 7000),
      'موبيل 5W30 فل سنثتك',
    ),
    (
      await _product(h, name: 'توتال 10W40', qty: 120, buy: 4200),
      'توتال 10W40',
    ),
  ];
  final filter = await _product(
    h,
    name: 'فلتر زيت تويوتا',
    qty: 3,
    buy: 3000,
    threshold: 5,
  );
  final wiper = await _product(h, name: 'ماسحات', qty: 14, buy: 2500);
  await _product(h, name: 'معطر جو', qty: 25, buy: 1000);
  await _product(h, name: 'زيت كير ATF', qty: 9, buy: 0);

  final techs = ['علي', 'جبار', 'حسين عمار'];
  final washers = ['كرار', 'مصطفى'];
  final today = DateTime.now();
  var n = 0;
  for (var d = 13; d >= 0; d--) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: d));
    final cards = 2 + (d * 7) % 5;
    for (var c = 0; c < cards; c++) {
      n++;
      final at = day.add(
        Duration(hours: 9 + (c * 3) % 10, minutes: (c * 17) % 60),
      );
      final (pid, oilName) = oils[n % oils.length];
      final liters = 4.0 + (n % 3);
      final price = 25000 + (n % 4) * 7500;
      final order = await ServiceOrdersRepository.instance.createServiceOrder(
        customerNameSnapshot: 'زبون $n',
        deviceName: n.isEven ? 'كامري 2018' : 'سوناتا 2020',
        deviceSerial: 'بصرة ${10000 + n % 9}',
        estimatedPriceFils: price * 1000,
        agreedPriceFils: price * 1000,
        requestedServices: '',
        technicianName: techs[n % techs.length],
        orderKind: ServiceOrderKinds.oilChange,
      );
      await db.update(
        'service_orders',
        {
          'oilProductId': pid,
          'oilLitersUsed': liters,
          'oilType': oilName,
          'createdAt': at.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [order],
      );
      if (n % 5 != 0) {
        final inv = await _invoice(
          h,
          date: at,
          lines: [(null, 'غيار زيت — $oilName', 1, price * 1000, null)],
        );
        await db.update(
          'service_orders',
          {'invoiceId': inv},
          where: 'id = ?',
          whereArgs: [order],
        );
      }
    }
    for (var s = 0; s < 1 + d % 3; s++) {
      await _invoice(
        h,
        date: day.add(Duration(hours: 11 + s * 2)),
        tag: OilChangeDirectSaleService.sourceTag,
        type: s == 1 ? 1 : 0,
        customer: s == 1 ? 'محمد الباقر' : 'بيع مباشر',
        lines: [
          (filter, 'فلتر زيت تويوتا', 1, 6000000, 3000),
          if (s.isEven) (wiper, 'ماسحات', 2, 8000000, 2500),
          if (d % 4 == 0) (oils[0].$1, oils[0].$2, 4, 20000000, 3500),
        ],
      );
    }
    for (var w = 0; w < d % 4; w++) {
      final order = await ServiceOrdersRepository.instance.createServiceOrder(
        customerNameSnapshot: 'زبون غسيل',
        deviceName: 'غسيل',
        deviceSerial: 'بصرة ${20000 + (d + w) % 6}',
        estimatedPriceFils: 10000000,
        agreedPriceFils: 10000000,
        requestedServices: 'خارجي',
        technicianName: washers[w % 2],
        orderKind: ServiceOrderKinds.carWash,
      );
      final at = day.add(Duration(hours: 16 + w));
      final inv = await _invoice(
        h,
        date: at,
        lines: [
          (
            null,
            'غسيل: ${w.isEven ? 'خارجي' : 'داخلي وخارجي'}',
            1,
            10000000,
            null,
          ),
        ],
      );
      await db.update(
        'service_orders',
        {'invoiceId': inv, 'createdAt': at.toUtc().toIso8601String()},
        where: 'id = ? AND tenantId = ?',
        whereArgs: [order, tid],
      );
    }
  }

  final range = ReportDateRange(
    from: today.subtract(const Duration(days: 13)),
    to: today,
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

Widget _host(Widget panel, {double textScale = 1}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Tajawal', useMaterial3: true),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: RepaintBoundary(key: const ValueKey('shot'), child: panel),
      ),
    ),
  ),
);

const _names = ['oil', 'direct', 'wash', 'products'];

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    await _loadFonts();
  });

  testWidgets('التقارير الأربعة على كل المقاسات وبخط مكبّر بلا فيضان', (
    tester,
  ) async {
    final h = OilChangeTestHarness.instance;
    final panels = await tester.runAsync(() async {
      await h.reset();
      await h.configureHybrid();
      return _seed(h);
    });
    final shotsDir = Platform.environment['REPORT_SHOTS_DIR'];

    Future<void> render(
      int i,
      String label,
      Size size, {
      double textScale = 1,
    }) async {
      // ارتفاع كبير يكفي لرسم الصفحة كاملة دون تمرير.
      tester.view.physicalSize = Size(
        size.width,
        shotsDir == null ? size.height : 7000,
      );
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_host(panels![i], textScale: textScale));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '${_names[i]} @ $label × $textScale',
      );
      if (shotsDir == null) return;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotsDir/${_names[i]}_$label${textScale == 1 ? '' : '_big'}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (var i = 0; i < panels!.length; i++) {
      for (final (label, size) in _sizes) {
        await render(i, label, size);
      }
      // تكبير الخط على الهاتف الصغير والمتوسط.
      await render(i, '320', const Size(320, 640), textScale: 1.3);
      await render(i, '412', const Size(412, 915), textScale: 1.3);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
