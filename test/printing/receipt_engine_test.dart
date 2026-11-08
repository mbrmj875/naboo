import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/escpos_raster.dart';
import 'package:naboo/printing/printer_connection.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_printer.dart';
import 'package:naboo/printing/receipt_renderer.dart';

/// محرك الإيصالات: الرسم، تحويل ESC/POS، والإرسال لطابعة شبكة وهمية.
///
/// لحفظ صور الإيصالات كما ستطبعها الطابعة: `RECEIPT_SHOTS_DIR=/path flutter test <file>`.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf']),
    ('Cairo', ['assets/fonts/restaurant/Cairo-Regular.ttf', 'assets/fonts/restaurant/Cairo-Bold.ttf']),
    ('NotoNaskhArabic', ['assets/fonts/NotoNaskhArabic-Regular.ttf', 'assets/fonts/NotoNaskhArabic-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }
}

Future<void> _saveRgbaPng(RenderedReceipt r, String name) async {
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (dir == null) return;
  File('$dir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(await r.pngBytes());
}

final _settings = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر، قرب الإشارة',
  storePhones: ['0780 000 0000'],
  footerExtra: 'شكراً لثقتكم — نراكم في الغيار القادم',
);

void _savePng(MonoBitmap b, String name) {
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (dir == null) return;
  final im = img.Image(width: b.width, height: b.height, numChannels: 1);
  for (var y = 0; y < b.height; y++) {
    for (var x = 0; x < b.width; x++) {
      final v = b.isBlack(x, y) ? 0 : 255;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  File('$dir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(im));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
  });

  test('كل القوالب على 58 و80 مم: عرض صحيح وترميز يُفك لنفس الصورة', () async {
    for (final kind in ReceiptKind.oilShop) {
      for (final paper in ReceiptPaper.rolls) {
        final doc = ReceiptBuilders.sample(kind);
        final r = await ReceiptRenderer.render(
          doc,
          settings: _settings,
          template: ReceiptTemplate.defaultsFor(kind),
          paper: paper,
        );
        expect(r.width, paper.dots, reason: '${kind.name} ${paper.name}');
        expect(r.height, greaterThan(300));
        final bmp = await MonoBitmap.fromRendered(r);
        final bytes = EscPosRaster.encode(bmp);
        expect(bytes.sublist(0, 2), [0x1B, 0x40]);
        expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
        final back = EscPosRaster.decode(bytes);
        expect(back, hasLength(1));
        expect(back.single.width, paper.dots);
        expect(back.single.height, bmp.height);
        expect(back.single.bits, bmp.bits);
        // فيه حبر فعلاً (ليس صورة بيضاء).
        final ink = bmp.bits.where((b) => b != 0).length;
        expect(ink, greaterThan(bmp.bits.length ~/ 50));
        _savePng(bmp, '${kind.name}_${paper.name}');
        r.dispose();
      }
    }
  });

  test('بطاقة الغيار: اللوحة والعداد والغيار القادم والفني', () {
    final doc = ReceiptBuilders.sample(ReceiptKind.oilChange);
    expect(doc.kind, ReceiptKind.oilChange);
    final labels = {for (final f in doc.fields) f.label: f.value};
    expect(labels['اللوحة'], 'بصرة 12345');
    expect(labels['العداد'], '120,500 كم');
    expect(labels['الفني'], 'علي');
    expect(labels['فلتر المحرك'], 'تويوتا أصلي');
    expect(labels['الزيت'], 'توتال 10W40');
    expect(labels['الكمية'], '4.5 لتر');
    expect(doc.highlights.single.value, '125,500 كم');
    expect(doc.totals.last.fils, 42000000);
  });

  test('البيع الآجل: المدفوع والمتبقي، والخصم', () {
    final doc = ReceiptBuilders.sample(ReceiptKind.directSale);
    expect(doc.kind, ReceiptKind.directSale);
    expect(doc.status, 'آجل');
    final t = {for (final x in doc.totals) x.label: x.fils};
    expect(t['المجموع'], 44000000);
    expect(t['الخصم'], 1000000);
    expect(t['الإجمالي'], 43000000);
    expect(t['المدفوع'], 20000000);
    expect(t['المتبقي'], 23000000);
  });

  test('إخفاء قسم من القالب يقصّر الإيصال', () async {
    final doc = ReceiptBuilders.sample(ReceiptKind.oilChange);
    final full = await ReceiptRenderer.render(
      doc,
      settings: _settings,
      template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
      paper: ReceiptPaper.mm58,
    );
    final slim = await ReceiptRenderer.render(
      doc,
      settings: _settings,
      template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange).copyWith(
        hidden: {ReceiptSection.nextService, ReceiptSection.filters},
        showQr: false,
      ),
      paper: ReceiptPaper.mm58,
    );
    expect(slim.height, lessThan(full.height));
  });

  test('القوالب تُحفظ وتُقرأ من إعدادات المحل', () {
    final t = ReceiptTemplate.defaultsFor(ReceiptKind.carWash).copyWith(
      autoPrint: false,
      copies: 2,
      hidden: {ReceiptSection.technician},
      footer: 'غسيل مضمون',
    );
    final s = _settings.copyWith(
      receiptTemplates: ReceiptTemplates(
        _settings.receiptTemplates,
      ).withTemplate(ReceiptKind.carWash, t),
    );
    final back = ReceiptTemplates(
      PrintSettingsData.mergeFromJsonString(s.toJsonString()).receiptTemplates,
    ).of(ReceiptKind.carWash);
    expect(back.autoPrint, isFalse);
    expect(back.copies, 2);
    expect(back.shows(ReceiptSection.technician), isFalse);
    expect(back.footer, 'غسيل مضمون');
    // الأعمال الأخرى بإعداداتها الافتراضية.
    expect(
      ReceiptTemplates(s.receiptTemplates).of(ReceiptKind.oilChange).autoPrint,
      isTrue,
    );
  });

  test('طابعة شبكة وهمية تستقبل الإيصال كاملاً', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<Uint8List>();
    server.listen((s) async {
      final b = BytesBuilder();
      await for (final chunk in s) {
        b.add(chunk);
      }
      received.complete(b.toBytes());
    });
    ReceiptPrinter.loadSettings = () async => _settings;
    final conn = PrinterConnection(
      type: PrinterType.lan,
      paper: ReceiptPaper.mm80,
      lanHost: '127.0.0.1',
      lanPort: server.port,
    );
    final r = await ReceiptPrinter.printDocument(
      ReceiptBuilders.sample(ReceiptKind.carWash),
      connection: conn,
    );
    expect(r.outcome, PrintOutcome.printed, reason: r.message);
    final bytes = await received.future.timeout(const Duration(seconds: 5));
    final pages = EscPosRaster.decode(bytes);
    expect(pages, hasLength(1));
    expect(pages.single.width, 576);
    _savePng(pages.single, 'virtual_lan_carWash');
    await server.close();
  });

  test('الطباعة التلقائية: تتخطى بصمت عند الإطفاء أو عدم وجود طابعة', () async {
    ReceiptPrinter.loadSettings = () async => _settings.copyWith(
      receiptTemplates: const ReceiptTemplates({}).withTemplate(
        ReceiptKind.expense,
        ReceiptTemplate.defaultsFor(ReceiptKind.expense),
      ),
    );
    final off = await ReceiptPrinter.printDocument(
      ReceiptBuilders.sample(ReceiptKind.expense),
      auto: true,
      connection: const PrinterConnection(type: PrinterType.lan, lanHost: 'x'),
    );
    expect(off.outcome, PrintOutcome.disabled);
    final none = await ReceiptPrinter.printDocument(
      ReceiptBuilders.sample(ReceiptKind.oilChange),
      auto: true,
      connection: const PrinterConnection(),
    );
    expect(none.outcome, PrintOutcome.notConfigured);
  });

  test('طابعة شبكة مطفأة: فشل برسالة واضحة دون استثناء', () async {
    ReceiptPrinter.loadSettings = () async => _settings;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final r = await ReceiptPrinter.printDocument(
      ReceiptBuilders.sample(ReceiptKind.oilChange),
      connection: PrinterConnection(
        type: PrinterType.lan,
        lanHost: '127.0.0.1',
        lanPort: port,
      ),
    );
    expect(r.outcome, PrintOutcome.failed);
    expect(r.message, isNotEmpty);
  });

  test('النمط يُحفظ ويُقرأ، والقوالب تبقى كما هي', () {
    const st = ReceiptStyle(
      font: ReceiptFont.cairo,
      size: ReceiptTextSize.large,
      shape: ReceiptHeaderShape.outlined,
      accent: ReceiptColor.green,
      ink: ReceiptColor.navy,
    );
    final raw = const ReceiptTemplates({}).withTemplate(
      ReceiptKind.carWash,
      ReceiptTemplate.defaultsFor(ReceiptKind.carWash).copyWith(copies: 2),
    );
    final withStyle = ReceiptTemplates(raw).withStyle(st);
    final back = ReceiptTemplates(
      PrintSettingsData.mergeFromJsonString(
        _settings.copyWith(receiptTemplates: withStyle).toJsonString(),
      ).receiptTemplates,
    );
    expect(back.style, st);
    expect(back.of(ReceiptKind.carWash).copies, 2);
  });

  test('الألوان تظهر في طابعة المكتب فقط، والحرارية بالأسود', () async {
    const st = ReceiptStyle(accent: ReceiptColor.green, ink: ReceiptColor.navy);
    Future<bool> hasColor(bool mono) async {
      final r = await ReceiptRenderer.render(
        ReceiptBuilders.sample(ReceiptKind.oilChange),
        settings: _settings,
        template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        paper: ReceiptPaper.mm80,
        style: st,
        monochrome: mono,
      );
      final px = (await r.image.toByteData())!.buffer.asUint8List();
      r.dispose();
      for (var i = 0; i < px.length; i += 4) {
        final d = (px[i] - px[i + 1]).abs() + (px[i + 1] - px[i + 2]).abs();
        if (d > 40) return true;
      }
      return false;
    }

    expect(await hasColor(false), isTrue);
    expect(await hasColor(true), isFalse);
  });

  test('كل الخطوط والأشكال والأحجام ترسم بلا خطأ، والحجم الكبير أطول', () async {
    Future<int> h(ReceiptStyle st) async {
      final r = await ReceiptRenderer.render(
        ReceiptBuilders.sample(ReceiptKind.directSale),
        settings: _settings,
        template: ReceiptTemplate.defaultsFor(ReceiptKind.directSale),
        paper: ReceiptPaper.mm58,
        style: st,
      );
      final v = r.height;
      r.dispose();
      return v;
    }

    for (final f in ReceiptFont.values) {
      for (final sh in ReceiptHeaderShape.values) {
        expect(await h(ReceiptStyle(font: f, shape: sh)), greaterThan(300));
      }
    }
    expect(
      await h(const ReceiptStyle(size: ReceiptTextSize.large)),
      greaterThan(await h(const ReceiptStyle(size: ReceiptTextSize.small))),
    );
  });

  test('A4 و A5: عرض الورقة وPDF بصفحات بمقاسها', () async {
    for (final paper in [ReceiptPaper.a5, ReceiptPaper.a4]) {
      final r = await ReceiptRenderer.render(
        ReceiptBuilders.sample(ReceiptKind.oilChange),
        settings: _settings,
        template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        paper: paper,
        style: const ReceiptStyle(
          font: ReceiptFont.cairo,
          accent: ReceiptColor.navy,
          shape: ReceiptHeaderShape.filled,
        ),
        monochrome: false,
      );
      expect(r.width, paper.dots);
      await _saveRgbaPng(r, 'sheet_${paper.name}');
      final pdf = await ReceiptPrinter.pdfBytes(r, paper);
      final text = String.fromCharCodes(pdf);
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
      final expected =
          (r.height / (r.width * paper.sheetHeightMm! / paper.widthMm)).ceil();
      expect(pages, expected, reason: paper.name);
      r.dispose();
    }
  });

  test('الحرارية لا تقبل A4: ترجع إلى 80 مم', () {
    const c = PrinterConnection(
      type: PrinterType.bluetooth,
      paper: ReceiptPaper.a4,
      btAddress: 'x',
    );
    expect(c.effectivePaper, ReceiptPaper.mm80);
    const sys = PrinterConnection(type: PrinterType.system, paper: ReceiptPaper.a4);
    expect(sys.effectivePaper, ReceiptPaper.a4);
  });

  test('نماذج ملوّنة للمراجعة', () async {
    for (final (name, st) in const [
      ('style_outlined_green', ReceiptStyle(shape: ReceiptHeaderShape.outlined, accent: ReceiptColor.green, font: ReceiptFont.cairo)),
      ('style_plain_maroon', ReceiptStyle(shape: ReceiptHeaderShape.plain, accent: ReceiptColor.maroon, ink: ReceiptColor.charcoal, font: ReceiptFont.naskh)),
    ]) {
      final r = await ReceiptRenderer.render(
        ReceiptBuilders.sample(ReceiptKind.oilChange),
        settings: _settings,
        template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        paper: ReceiptPaper.mm80,
        style: st,
        monochrome: false,
      );
      await _saveRgbaPng(r, name);
      r.dispose();
    }
  });
}
