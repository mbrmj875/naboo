import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_gallery.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';

/// معرض القوالب الجاهزة: كل قالب يُرسم على كل مقاس، بالألوان وبالأبيض والأسود،
/// بلا تحذير وضوح، ولا يشبه قالباً آخر.
///
/// لحفظ صور المراجعة: `RECEIPT_SHOTS_DIR=/path flutter test <file>`.
Future<void> _loadFonts() async {
  const r = 'assets/fonts/restaurant';
  for (final (family, files) in [
    ('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf']),
    ('Cairo', ['$r/Cairo-Regular.ttf', '$r/Cairo-Bold.ttf']),
    ('Amiri', ['$r/Amiri-Regular.ttf', '$r/Amiri-Bold.ttf']),
    ('Almarai', ['$r/Almarai-Regular.ttf', '$r/Almarai-Bold.ttf']),
    ('IBMPlexSansArabic', ['$r/IBMPlexSansArabic-Regular.ttf', '$r/IBMPlexSansArabic-Bold.ttf']),
    ('ReemKufi', ['$r/ReemKufi-Regular.ttf', '$r/ReemKufi-Bold.ttf']),
    ('Changa', ['$r/Changa-Regular.ttf', '$r/Changa-Bold.ttf']),
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
  if (save != null && dir != null) {
    File('$dir/$save.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(await r.pngBytes());
  }
  final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  return ('${r.height}:${sha1.convert(px)}', r);
}

int _pageH(ReceiptPaper p) => (p.dots * p.sheetHeightMm! / p.widthMm).floor();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await _loadFonts();
  });

  test('المعرض كامل: 142 قالباً بمعرّفات فريدة في ثماني عائلات', () {
    final all = ReceiptGallery.all;
    expect(all.length, 142);
    expect({for (final e in all) e.id}.length, all.length);
    for (final f in ReceiptGalleryFamily.values) {
      expect(ReceiptGallery.of(f), isNotEmpty, reason: f.name);
    }
    expect(ReceiptGallery.byId('sky_01')?.family, ReceiptGalleryFamily.sky);
    expect(ReceiptGallery.byId('غير موجود'), isNull);
  });

  test('كل هيكل من العشرين مستخدم', () {
    final used = {for (final e in ReceiptGallery.all) e.skeleton};
    expect(used, ReceiptSkeleton.values.toSet());
  });

  test('لا تحذير وضوح في أي قالب', () {
    final bad = {
      for (final e in ReceiptGallery.all)
        if (e.design.contrastWarnings().isNotEmpty) e.id: e.design.contrastWarnings(),
    };
    expect(bad, isEmpty);
  });

  test('القالب يُحفظ ويُسترجع كما هو، ويبقى قابلاً للتعديل', () {
    for (final e in ReceiptGallery.all) {
      final d = e.design;
      final back = ReceiptDesign.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back, d, reason: e.id);
      expect(d.preset, e.id);
      final edited = d.copyWith(font: ReceiptFont.amiri);
      expect(edited == d, d.font == ReceiptFont.amiri, reason: e.id);
    }
  });

  test('كل التصاميم مختلفة في القيم وفي الرسم', () async {
    final designs = <ReceiptDesign>{};
    final hashes = <String, String>{};
    for (final e in ReceiptGallery.all) {
      expect(designs.add(e.design.copyWith(preset: '')), isTrue, reason: e.id);
      final (h, _) = await _shot(e.design, save: 'gallery/${e.family.name}/${e.id}');
      expect(hashes[h], isNull, reason: '${e.id} يطابق ${hashes[h]}');
      hashes[h] = e.id;
    }
  });

  for (final paper in ReceiptPaper.values) {
    for (final mono in [false, true]) {
      test('كل القوالب تُرسم على ${paper.label}${mono ? ' أبيض وأسود' : ''}', () async {
        for (final e in ReceiptGallery.all) {
          final (_, r) = await _shot(
            e.design,
            paper: paper,
            mono: mono,
            save: const {'sky_09', 'dark_10', 'vintage_06', 'forest_03', 'vivid_14'}.contains(e.id)
                ? 'sizes/${e.id}_${paper.name}${mono ? '_mono' : ''}'
                : null,
          );
          expect(r.height, greaterThan(200), reason: e.id);
          expect(r.image.width, paper.dots, reason: e.id);
          // الصفحة الكبيرة تملأ ورقة كاملة والتذييل في أسفلها.
          if (!paper.isRoll) expect(r.height, _pageH(paper), reason: e.id);
        }
      });
    }
  }

  test('الأبيض والأسود لا يحمل إلا درجات الرمادي (عدا الشعار)', () async {
    for (final e in ReceiptGallery.all) {
      final (_, r) = await _shot(e.design, mono: true);
      final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final logo = r.logoRect?.inflate(2);
      for (var i = 0; i < px.length; i += 4 * 97) {
        final x = (i ~/ 4) % r.image.width, y = (i ~/ 4) ~/ r.image.width;
        // الشعار يُرسم كما هو والطابعة تحوّله؛ القياس لما يرسمه المحرّك.
        if (logo != null && logo.contains(Offset(x.toDouble(), y.toDouble()))) continue;
        expect(px[i] == px[i + 1] && px[i + 1] == px[i + 2], isTrue,
            reason: '${e.id} @$x,$y: ${px.sublist(i, i + 4)}');
      }
    }
  });

  test('كل خيار من الأجزاء الجديدة يغيّر الرسم', () async {
    const base = ReceiptDesign(
      palette: ReceiptPalette(accent: 0xFF1E3A5F, ink: 0xFF111827),
    );
    final (h0, _) = await _shot(base);
    final variants = <String, ReceiptDesign>{
      for (final v in ReceiptTopEdge.values.skip(1))
        'top-${v.name}': base.copyWith(
          topEdge: v,
          palette: base.palette.withSlot(ReceiptColorSlot.topBg, 0xFF1E3A5F),
        ),
      for (final v in ReceiptSectionTitles.values.skip(1))
        'titles-${v.name}': base.copyWith(sectionTitles: v),
      for (final v in ReceiptSectionBox.values.skip(1))
        'box-${v.name}': base.copyWith(sectionBox: v),
      for (final v in ReceiptItemMarker.values.skip(1))
        'marker-${v.name}': base.copyWith(itemMarker: v),
      for (final v in ReceiptTotalLayout.values.skip(1))
        'total-${v.name}': base.copyWith(totalLayout: v),
      for (final v in ReceiptEdges.values.skip(1))
        'edges-${v.name}': base.copyWith(edges: v),
      'side-strip': base.copyWith(sideStrip: true),
      'frame-double': base.copyWith(frame: ReceiptFrame.double),
      'frame-ornate': base.copyWith(frame: ReceiptFrame.ornate),
    };
    final seen = <String>{h0};
    for (final MapEntry(:key, :value) in variants.entries) {
      final (h, _) = await _shot(value, save: 'parts/$key');
      expect(seen.add(h), isTrue, reason: key);
    }
  });

  test('القوالب تعمل لكل أنواع الإيصالات', () async {
    final e = ReceiptGallery.all.first;
    for (final k in ReceiptKind.values) {
      final (_, r) = await _shot(e.design, kind: k);
      expect(r.height, greaterThan(200), reason: k.name);
    }
  });

  test('الصفحة الكبيرة: كل أنواع الإيصالات، والطويل يمتد لصفحات أخرى', () async {
    for (final paper in [ReceiptPaper.a5, ReceiptPaper.a4]) {
      for (final id in ['sky_01', 'dark_10', 'formal_05', 'vintage_06']) {
        final e = ReceiptGallery.byId(id)!;
        for (final k in ReceiptKind.values) {
          final (_, r) = await _shot(e.design, kind: k, paper: paper, save: 'kinds/${paper.name}_${id}_${k.name}');
          expect(r.height, greaterThanOrEqualTo(_pageH(paper)), reason: '$id ${k.name}');
        }
      }
    }
    // إيصال بأربعين صنفاً يتجاوز الصفحة ولا يُقصّ.
    final b = _doc(ReceiptKind.directSale);
    final long = ReceiptDocument(
      kind: b.kind,
      date: b.date,
      number: b.number,
      fields: b.fields,
      lines: [for (var i = 0; i < 40; i++) ...b.lines],
      totals: b.totals,
      qrData: b.qrData,
    );
    final r = await ReceiptRenderer.render(
      long,
      settings: _settings,
      template: ReceiptTemplate.defaultsFor(long.kind),
      paper: ReceiptPaper.a5,
      design: ReceiptGallery.byId('sky_04')!.design,
      monochrome: false,
    );
    expect(r.height, greaterThan(_pageH(ReceiptPaper.a5)));
  });
}
