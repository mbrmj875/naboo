import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/models/store_policy.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_printer.dart';
import 'package:naboo/printing/receipt_renderer.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/verticals/car_wash/services/wash_offer_engine.dart';

/// المرحلة 4: المشاركة صورة، معلومات المحل الإضافية، العروض والزيارات.
///
/// لحفظ صور المراجعة: `RECEIPT_SHOTS_DIR=/path flutter test <file>`.
Future<void> _loadFonts() async {
  final loader = FontLoader('Tajawal');
  for (final f in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf']) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

final _base = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر',
  storePhones: ['0780 000 0000'],
);

final _extras = _base.copyWith(
  storeSlogan: 'زيتك علينا وسيارتك بأمان',
  storeTaxNumber: '123-456-789',
  storeHours: 'يومياً 8 ص – 10 م',
  storeInstagram: '@basra.oil',
  storeTiktok: '@basra.oil',
);

Future<(String, RenderedReceipt)> _shot(
  ReceiptDocument doc, {
  PrintSettingsData? settings,
  ReceiptTemplate? template,
  ReceiptDesign design = const ReceiptDesign(),
  ReceiptPaper paper = ReceiptPaper.mm80,
  bool mono = false,
  String? save,
}) async {
  final r = await ReceiptRenderer.render(
    doc,
    settings: settings ?? _base,
    template: template ?? ReceiptTemplate.defaultsFor(doc.kind),
    paper: paper,
    design: design,
    monochrome: mono,
  );
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (save != null && dir != null) {
    File('$dir/phase4/$save.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(await r.pngBytes());
  }
  final px = (await r.image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  return ('${r.height}:${sha1.convert(px)}', r);
}

ReceiptDocument _wash(String note) => ReceiptBuilders.fromInvoice(
  Invoice(
    id: 1025,
    customerName: 'زبون',
    date: DateTime(2026, 11, 27, 10, 30),
    type: InvoiceType.cash,
    items: [InvoiceItem(productName: 'غسيل: داخلي وخارجي', quantity: 1, price: 10000, total: 10000)],
    discount: 0,
    tax: 0,
    total: 10000,
    advancePayment: 10000,
  ),
  order: {
    'orderKind': ServiceOrderKinds.carWash,
    'deviceSerial': 'بصرة 54321',
    'washOfferNote': note,
  },
);

ReceiptDocument _withoutLoyalty(ReceiptDocument d) => ReceiptDocument(
  kind: d.kind,
  date: d.date,
  number: d.number,
  status: d.status,
  fields: d.fields,
  lines: d.lines,
  totals: d.totals,
  highlights: d.highlights,
  notes: d.notes,
  qrData: d.qrData,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await _loadFonts();
  });

  group('قراءة تقدّم عرض الغسيل', () {
    test('صيغ السطر التي يكتبها المحرّك', () {
      expect(WashOfferEngine.progressOf('غسلتان من 3 — الغسلة القادمة مجانية'), (done: 2, total: 3));
      expect(WashOfferEngine.progressOf('غسلة واحدة من 2 — الغسلة القادمة مجانية'), (done: 1, total: 2));
      expect(WashOfferEngine.progressOf('4 غسلات من 5 — الغسلة القادمة عليها خصم'), (done: 4, total: 5));
      expect(WashOfferEngine.progressOf('الغسلة 2 من 5 خلال 30 أيام — الغسلة رقم 5 مجانية'), (done: 2, total: 5));
      expect(WashOfferEngine.progressOf('الغسلة 3 من 3 — مجانية (عرض تكرار الغسل)'), (done: 3, total: 3));
      expect(WashOfferEngine.progressOf('شكراً لتكرار زيارتك! العدّ يبدأ من جديد.'), isNull);
      expect(WashOfferEngine.progressOf('استُخدم خصم الغيار — يتجدد مع الغيار القادم'), isNull);
    });

    test('ما يكتبه المحرّك فعلاً يُقرأ', () {
      final now = DateTime(2026, 11, 27, 12);
      for (final (req, done) in [(3, 1), (3, 0), (5, 2), (5, 3), (4, 3)]) {
        final r = WashOfferEngine.evaluate(
          policy: StorePolicy(washRepeat: WashRepeatOffer(enabled: true, washesRequired: req, periodDays: 30)),
          history: WashOfferHistory(
            washes: [
              for (var i = 0; i < done; i++)
                WashVisit(at: now.subtract(Duration(days: i + 1)), serviceNames: const ['داخلي']),
            ],
          ),
          currentServicePrices: const {'داخلي': 5000},
          now: now,
        );
        // يُحفظ السطران معاً (السبب ثم التشجيع)، وأول سطر يُقرأ هو التقدّم.
        final lines = [r.reasonAr, r.encouragementAr].whereType<String>();
        final p = lines.map(WashOfferEngine.progressOf).firstWhere((p) => p != null, orElse: () => null);
        expect(p, (done: done + 1, total: req), reason: lines.join(' | '));
      }
    });
  });

  group('العروض والزيارات في الإيصال', () {
    test('سطر التقدّم يصير صندوق العرض، والباقي ملاحظات', () {
      final d = _wash('غسلتان من 3 — الغسلة القادمة مجانية');
      expect(d.loyalty?.done, 2);
      expect(d.loyalty?.total, 3);
      expect(d.notes, isEmpty);
      final reward = _wash('الغسلة 3 من 3 — مجانية (عرض تكرار الغسل)\nشكراً لتكرار زيارتك! العدّ يبدأ من جديد.');
      expect(reward.loyalty?.done, 3);
      expect(reward.notes, ['شكراً لتكرار زيارتك! العدّ يبدأ من جديد.']);
      expect(_wash('خصم الغيار').loyalty, isNull);
    });

    test('الصندوق يُرسم، وإخفاؤه من القالب يعيد الإيصال كما كان', () async {
      final d = ReceiptBuilders.sample(ReceiptKind.carWash);
      final (withBox, _) = await _shot(d, save: 'wash_loyalty');
      final (plain, _) = await _shot(_withoutLoyalty(d));
      final hidden = ReceiptTemplate.defaultsFor(d.kind).copyWith(hidden: {ReceiptSection.loyalty});
      final (off, _) = await _shot(d, template: hidden);
      expect(withBox, isNot(plain));
      expect(off, plain);
      await _shot(d, mono: true, save: 'wash_loyalty_mono');
    });

    test('رقم الزيارة وتاريخ الغيار القادم بالأشهر', () async {
      final d = ReceiptBuilders.sample(ReceiptKind.oilChange);
      expect(d.loyalty?.visit, 7);
      final t = ReceiptTemplate.defaultsFor(d.kind);
      final (visit, _) = await _shot(d, save: 'oil_visit');
      final (months, _) = await _shot(d, template: t.copyWith(nextServiceMonths: 3), save: 'oil_visit_months');
      final (plain, _) = await _shot(_withoutLoyalty(d));
      expect({visit, months, plain}.length, 3);
      // القالب يحفظ المدة ويقرؤها.
      final back = ReceiptTemplate.fromJson(d.kind, jsonDecode(jsonEncode(t.copyWith(nextServiceMonths: 3).toJson())));
      expect(back.nextServiceMonths, 3);
      expect(t.toJson().containsKey('nextServiceMonths'), isFalse);
    });

    test('على الصفحة الكبيرة أيضاً', () async {
      for (final k in [ReceiptKind.oilChange, ReceiptKind.carWash]) {
        final d = ReceiptBuilders.sample(k);
        final (a, _) = await _shot(d, paper: ReceiptPaper.a5, save: 'a5_${k.name}');
        final (b, _) = await _shot(_withoutLoyalty(d), paper: ReceiptPaper.a5);
        expect(a, isNot(b), reason: k.name);
      }
    });
  });

  group('معلومات المحل الإضافية', () {
    test('تُحفظ وتُقرأ، والفارغ لا يُكتب', () {
      final back = PrintSettingsData.fromJson(jsonDecode(jsonEncode(_extras.toJson())) as Map<String, dynamic>);
      expect(back.storeSlogan, _extras.storeSlogan);
      expect(back.storeTaxNumber, _extras.storeTaxNumber);
      expect(back.storeHours, _extras.storeHours);
      expect(back.storeInstagram, '@basra.oil');
      expect(back.storeFacebook, '');
      expect(_base.toJson().keys.where((k) => k.startsWith('storeS') || k == 'storeHours'), isEmpty);
      expect(_extras.receiptStoreHeaderExtras, ['زيتك علينا وسيارتك بأمان', 'الرقم الضريبي: \u2066123-456-789\u2069']);
      expect(_extras.receiptStoreFooterExtras, ['أوقات الدوام: يومياً 8 ص – 10 م', 'إنستغرام \u2066@basra.oil\u2069 · تيك توك \u2066@basra.oil\u2069']);
    });

    test('تُطبع في الرأس والتذييل، ومفتاح القالب يخفيها', () async {
      for (final paper in [ReceiptPaper.mm58, ReceiptPaper.mm80, ReceiptPaper.a5]) {
        final d = ReceiptBuilders.sample(ReceiptKind.directSale);
        final (a, ra) = await _shot(d, settings: _extras, paper: paper, save: 'extras_${paper.name}');
        final (b, rb) = await _shot(d, paper: paper);
        final hidden = ReceiptTemplate.defaultsFor(d.kind).copyWith(hidden: {ReceiptSection.storeExtras});
        final (c, _) = await _shot(d, settings: _extras, template: hidden, paper: paper);
        expect(a, isNot(b), reason: paper.name);
        expect(c, b, reason: paper.name);
        if (paper.isRoll) expect(ra.height, greaterThan(rb.height));
      }
    });
  });

  group('المشاركة', () {
    test('الصورة بالألوان وبعرض 80 مم حتى لو كانت الطابعة 58', () async {
      final d = ReceiptBuilders.sample(ReceiptKind.oilChange);
      final settings = _base.copyWith(
        receiptTemplates: const ReceiptTemplates({}).withDesign(
          const ReceiptDesign(palette: ReceiptPalette(accent: 0xFF1E3A5F, ink: 0xFF111827)),
        ),
      );
      final png = await ReceiptPrinter.shareImageBytes(d, settings: settings, paper: ReceiptPaper.mm58);
      final img = await decodeImageFromList(png);
      expect(img.width, ReceiptPaper.mm80.dots);
      final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      var colored = false;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i] != px[i + 1] || px[i + 1] != px[i + 2]) {
          colored = true;
          break;
        }
      }
      expect(colored, isTrue);
      final sheet = await ReceiptPrinter.shareImageBytes(d, settings: settings, paper: ReceiptPaper.a4);
      expect((await decodeImageFromList(sheet)).width, ReceiptPaper.a4.dots);
    });

    testWidgets('نافذة الاختيار: صورة أو PDF', (tester) async {
      ReceiptShareFormat? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await ReceiptPrinter.pickShareFormat(context),
              child: const Text('مشاركة'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();
      expect(find.text('صورة'), findsOneWidget);
      expect(find.text('ملف PDF'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-image')));
      await tester.pumpAndSettle();
      expect(picked, ReceiptShareFormat.image);
      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-pdf')));
      await tester.pumpAndSettle();
      expect(picked, ReceiptShareFormat.pdf);
    });
  });
}
