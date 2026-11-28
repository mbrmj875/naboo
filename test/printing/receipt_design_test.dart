import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/escpos_raster.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';

/// محرّك التصميم: النموذج، الحفظ، التباين، وأن كل خيار يغيّر الورقة.
///
/// لحفظ صور المراجعة: `RECEIPT_SHOTS_DIR=/path flutter test <file>`.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf']),
    ('Cairo', ['assets/fonts/restaurant/Cairo-Regular.ttf', 'assets/fonts/restaurant/Cairo-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }
}

final _logo = File('assets/images/splash_logo_mark.png').readAsBytesSync();

final _settings = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر، قرب الإشارة',
  storePhones: ['0780 000 0000'],
  storeLogoBase64: base64Encode(_logo),
);

ReceiptDocument _doc(ReceiptKind k) {
  final b = ReceiptBuilders.sample(k);
  return ReceiptDocument(
    kind: b.kind,
    date: DateTime(2026, 11, 27, 10, 30),
    number: b.number,
    status: b.status,
    fields: b.fields,
    lines: b.lines,
    totals: b.totals,
    highlights: b.highlights,
    notes: b.notes,
    qrData: b.qrData,
    titleOverride: b.titleOverride,
  );
}

Future<(String, RenderedReceipt)> _shot(
  ReceiptDesign d, {
  ReceiptKind kind = ReceiptKind.oilChange,
  ReceiptPaper paper = ReceiptPaper.mm80,
  bool mono = false,
  String? save,
}) async {
  final r = await ReceiptRenderer.render(
    _doc(kind),
    settings: _settings,
    template: ReceiptTemplate.defaultsFor(kind),
    paper: paper,
    design: d,
    monochrome: mono,
  );
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (dir != null && save != null) {
    File('$dir/$save.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(await r.pngBytes());
  }
  final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  return ('${r.height}:${sha1.convert(px)}', r);
}

Future<Uint8List> _rgba(RenderedReceipt r) async =>
    (await r.image.toByteData(format: ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

const _navy = ReceiptPalette(accent: 0xFF1E3A5F, ink: 0xFF111827);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
    ReceiptRenderer.nabooLogoLoader = () async => _logo;
  });

  group('النموذج والحفظ', () {
    test('من المظهر القديم: نفس الخط والحجم والشكل والألوان', () {
      const st = ReceiptStyle(
        font: ReceiptFont.cairo,
        size: ReceiptTextSize.large,
        shape: ReceiptHeaderShape.outlined,
        accent: ReceiptColor.green,
        ink: ReceiptColor.navy,
      );
      final d = ReceiptDesign.fromStyle(st);
      expect(d.font, ReceiptFont.cairo);
      expect(d.size, ReceiptTextSize.large);
      expect(d.title, ReceiptHeaderShape.outlined);
      expect(d.totals, ReceiptHeaderShape.outlined);
      expect(d.palette.accent, ReceiptColor.green.argb);
      expect(d.palette.ink, ReceiptColor.navy.argb);
      expect(d.palette.paper, 0xFFFFFFFF);
      expect(d.toLegacyStyle(), st);
    });

    test('بلا تصميم محفوظ: يُقرأ من `_style` القديم', () {
      const st = ReceiptStyle(accent: ReceiptColor.maroon);
      final raw = const ReceiptTemplates({}).withStyle(st);
      expect(
        ReceiptTemplates(raw).design,
        ReceiptDesign.fromStyle(st),
      );
    });

    test('يُحفظ ويُقرأ عبر إعدادات المحل، ومعه المظهر القديم', () {
      final d = const ReceiptDesign().copyWith(
        preset: 'watermark',
        palette: _navy.copyWith(paper: 0xFFFFF8E7),
        header: ReceiptHeaderLayout.boxed,
        title: ReceiptHeaderShape.ribbon,
        info: ReceiptInfoStyle.zebra,
        items: ReceiptItemsStyle.table,
        highlight: ReceiptHighlightStyle.filled,
        watermark: ReceiptWatermark.storeLogo,
        watermarkOpacity: 0.15,
        frame: ReceiptFrame.corners,
        density: ReceiptDensity.compact,
      );
      final raw = const ReceiptTemplates({}).withDesign(d);
      final back = ReceiptTemplates(
        PrintSettingsData.mergeFromJsonString(
          _settings.copyWith(receiptTemplates: raw).toJsonString(),
        ).receiptTemplates,
      );
      expect(back.design, d);
      expect(back.style.shape, ReceiptHeaderShape.filled);
      expect(back.style.accent, ReceiptColor.navy);
    });

    test('تصميم خاص لنوع واحد، والباقي يأخذ تصميم المحل', () {
      final shop = const ReceiptDesign().copyWith(palette: _navy);
      final wash = shop.copyWith(frame: ReceiptFrame.border);
      var raw = const ReceiptTemplates({}).withDesign(shop);
      raw = ReceiptTemplates(raw).withKindDesign(ReceiptKind.carWash, wash);
      var t = ReceiptTemplates(raw);
      expect(t.designFor(ReceiptKind.carWash), wash);
      expect(t.designFor(ReceiptKind.oilChange), shop);
      expect(t.hasOwnDesign(ReceiptKind.carWash), isTrue);

      // تعديل إعدادات القالب لا يمسح تصميمه الخاص.
      raw = t.withTemplate(
        ReceiptKind.carWash,
        t.of(ReceiptKind.carWash).copyWith(copies: 2),
      );
      t = ReceiptTemplates(raw);
      expect(t.designFor(ReceiptKind.carWash), wash);
      expect(t.of(ReceiptKind.carWash).copies, 2);

      // الرجوع لتصميم المحل.
      t = ReceiptTemplates(t.withKindDesign(ReceiptKind.carWash, null));
      expect(t.hasOwnDesign(ReceiptKind.carWash), isFalse);
      expect(t.designFor(ReceiptKind.carWash), shop);
      expect(t.of(ReceiptKind.carWash).copies, 2);
    });

    test('قيم تالفة لا تكسر القراءة', () {
      final d = ReceiptDesign.fromJson({
        'font': 'nope',
        'palette': {'accent': '#1d4ed8', 'ink': 'zz', 'paper': 12},
        'watermarkOpacity': 9,
        'items': 42,
      });
      expect(d.font, ReceiptFont.tajawal);
      expect(d.palette.accent, 0xFF1D4ED8);
      expect(d.palette.ink, 0xFF000000);
      expect(d.watermarkOpacity, 0.3);
      expect(d.items, ReceiptItemsStyle.simple);
      expect(ReceiptDesign.fromJson('x'), const ReceiptDesign());
    });

    test('الحجم المحفوظ صغير (لا صور في صف المزامنة)', () {
      final d = const ReceiptDesign().copyWith(
        watermark: ReceiptWatermark.storeLogo,
      );
      expect(jsonEncode(d.toJson()).length, lessThan(600));
    });
  });

  group('التباين', () {
    test('أسود على أبيض 21، ونفس اللون 1', () {
      expect(ReceiptDesign.contrast(0xFF000000, 0xFFFFFFFF), closeTo(21, 0.01));
      expect(ReceiptDesign.contrast(0xFF336699, 0xFF336699), closeTo(1, 0.01));
    });

    test('الكلاسيكي بلا تحذيرات، والألوان الباهتة تُحذَّر', () {
      expect(const ReceiptDesign().contrastWarnings(), isEmpty);
      final pale = const ReceiptDesign().copyWith(
        palette: const ReceiptPalette(
          accent: 0xFFFDE68A,
          ink: 0xFFD1D5DB,
          paper: 0xFFFFFFFF,
        ),
      );
      final w = pale.contrastWarnings();
      expect(w, contains('لون النص غير واضح على لون الورقة.'));
      expect(w, contains('لون العنوان والإجمالي قريب من لون الورقة.'));
      expect(
        w.any((e) => e.startsWith('النص فوق لون العنوان')),
        isTrue,
      );
    });

    test('الحرارية: العلامة المائية لا تتجاوز الحد', () {
      final d = const ReceiptDesign().copyWith(watermarkOpacity: 0.3);
      expect(d.watermarkOpacityFor(monochrome: true), ReceiptDesign.thermalWatermarkCap);
      expect(d.watermarkOpacityFor(monochrome: false), 0.3);
    });
  });

  group('الرسم', () {
    final base = const ReceiptDesign().copyWith(palette: _navy);
    final options = <String, ReceiptDesign>{
      'header-boxed': base.copyWith(header: ReceiptHeaderLayout.boxed),
      'header-banner': base.copyWith(header: ReceiptHeaderLayout.banner),
      'title-ribbon': base.copyWith(title: ReceiptHeaderShape.ribbon),
      'totals-outlined': base.copyWith(totals: ReceiptHeaderShape.outlined),
      'info-zebra': base.copyWith(info: ReceiptInfoStyle.zebra),
      'info-boxed': base.copyWith(info: ReceiptInfoStyle.boxed),
      'items-table': base.copyWith(items: ReceiptItemsStyle.table),
      'items-zebra': base.copyWith(items: ReceiptItemsStyle.zebra),
      'highlight-filled': base.copyWith(highlight: ReceiptHighlightStyle.filled),
      'wm-store': base.copyWith(watermark: ReceiptWatermark.storeLogo),
      'wm-naboo': base.copyWith(watermark: ReceiptWatermark.nabooLogo),
      'frame-border': base.copyWith(frame: ReceiptFrame.border),
      'frame-corners': base.copyWith(frame: ReceiptFrame.corners),
      'density-compact': base.copyWith(density: ReceiptDensity.compact),
      'paper-ivory': base.copyWith(palette: _navy.copyWith(paper: 0xFFFFF8E7)),
      'muted-labels': base.copyWith(palette: _navy.copyWith(muted: 0xFF6B7280)),
    };

    test('كل خيار يغيّر الورقة الملوّنة', () async {
      final (ref, r0) = await _shot(base, save: 'design/base');
      r0.dispose();
      for (final e in options.entries) {
        final (h, r) = await _shot(e.value, save: 'design/${e.key}');
        expect(h, isNot(ref), reason: e.key);
        r.dispose();
      }
    });

    test('الموفّر للورق أقصر، والجدول بعرض الورقة على 58 مم', () async {
      final (_, normal) = await _shot(base, paper: ReceiptPaper.mm58);
      final (_, compact) = await _shot(
        base.copyWith(density: ReceiptDensity.compact),
        paper: ReceiptPaper.mm58,
      );
      expect(compact.height, lessThan(normal.height));
      final (_, table) = await _shot(
        base.copyWith(items: ReceiptItemsStyle.table),
        kind: ReceiptKind.directSale,
        paper: ReceiptPaper.mm58,
        save: 'design/table-58',
      );
      expect(table.width, ReceiptPaper.mm58.dots);
      for (final r in [normal, compact, table]) {
        r.dispose();
      }
    });

    test('كل الخيارات معاً على كل المقاسات والأنواع، حراري وملوّن', () async {
      final all = base.copyWith(
        header: ReceiptHeaderLayout.banner,
        title: ReceiptHeaderShape.ribbon,
        totals: ReceiptHeaderShape.ribbon,
        info: ReceiptInfoStyle.boxed,
        items: ReceiptItemsStyle.table,
        highlight: ReceiptHighlightStyle.filled,
        watermark: ReceiptWatermark.storeLogo,
        frame: ReceiptFrame.border,
        palette: _navy.copyWith(paper: 0xFFEFF6FF),
      );
      for (final kind in ReceiptKind.oilShop) {
        for (final paper in ReceiptPaper.values) {
          for (final mono in [true, false]) {
            final (_, r) = await _shot(
              all,
              kind: kind,
              paper: paper,
              mono: mono,
              save: kind == ReceiptKind.oilChange
                  ? 'design/all-${paper.name}-${mono ? 'mono' : 'color'}'
                  : null,
            );
            expect(r.width, paper.dots);
            expect(r.height, greaterThan(300));
            if (mono && paper.isRoll) {
              final bmp = await MonoBitmap.fromRendered(r);
              expect(EscPosRaster.encode(bmp).length, greaterThan(100));
            }
            r.dispose();
          }
        }
      }
    });

    test('الحرارية: ورقة بيضاء ونص أسود مهما كانت الألوان', () async {
      final d = base.copyWith(
        palette: const ReceiptPalette(
          accent: 0xFF166534,
          ink: 0xFF1E3A5F,
          paper: 0xFFFFF1F2,
        ),
        info: ReceiptInfoStyle.zebra,
        items: ReceiptItemsStyle.zebra,
      );
      final (_, r) = await _shot(d, mono: true);
      final px = await _rgba(r);
      // الزاوية بيضاء.
      expect(px.sublist(0, 4), [255, 255, 255, 255]);
      // لا ألوان خارج الشعار.
      final logo = r.logoRect!;
      var colored = 0;
      for (var y = 0; y < r.height; y++) {
        if (y >= logo.top && y <= logo.bottom) continue;
        for (var x = 0; x < r.width; x++) {
          final i = (y * r.width + x) * 4;
          final d = (px[i] - px[i + 1]).abs() + (px[i + 1] - px[i + 2]).abs();
          if (d > 6) colored++;
        }
      }
      expect(colored, 0);
      r.dispose();
    });

    test('العلامة المائية على الحرارية نقاط خفيفة، والطول نفسه', () async {
      final (_, plain) = await _shot(base, mono: true);
      final (_, wm) = await _shot(
        base.copyWith(watermark: ReceiptWatermark.nabooLogo, watermarkOpacity: 0.3),
        mono: true,
        save: 'design/wm-mono',
      );
      expect(wm.height, plain.height);
      int black(MonoBitmap b) {
        var n = 0;
        for (final v in b.bits) {
          var x = v;
          while (x != 0) {
            n += x & 1;
            x >>= 1;
          }
        }
        return n;
      }

      final a = black(await MonoBitmap.fromRendered(plain));
      final b = black(await MonoBitmap.fromRendered(wm));
      expect(b, greaterThan(a));
      // خفيفة: أقل من 12% من مساحة الورقة زيادة.
      expect(b - a, lessThan(plain.width * plain.height * 0.12));
      plain.dispose();
      wm.dispose();
    });

    test('بلا شعار للمحل: العلامة المائية بشعار المحل لا ترسم شيئاً', () async {
      final r = await ReceiptRenderer.render(
        _doc(ReceiptKind.oilChange),
        settings: _settings.copyWith(storeLogoBase64: ''),
        template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        design: base.copyWith(watermark: ReceiptWatermark.storeLogo),
        monochrome: false,
      );
      final r2 = await ReceiptRenderer.render(
        _doc(ReceiptKind.oilChange),
        settings: _settings.copyWith(storeLogoBase64: ''),
        template: ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        design: base,
        monochrome: false,
      );
      expect(sha1.convert(await _rgba(r)), sha1.convert(await _rgba(r2)));
      r.dispose();
      r2.dispose();
    });
  });
}
