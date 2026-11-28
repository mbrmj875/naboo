import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/arabic_amount_words.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';

/// المرحلة 5: الفاتورة الرسمية على A5/A4 — المبلغ كتابةً، الختم والتوقيع،
/// وخيار «فاتورة رسمية / إيصال مكبَّر».
///
/// لحفظ صور المراجعة: `RECEIPT_SHOTS_DIR=/path flutter test <file>`.
Future<void> _loadFonts() async {
  final loader = FontLoader('Tajawal');
  for (final f in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf']) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
      ),
    );
  }
  await loader.load();
}

final _settings = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر',
  storePhones: ['0780 000 0000'],
);

Future<(String, RenderedReceipt)> _shot(
  ReceiptDocument doc, {
  ReceiptTemplate? template,
  ReceiptPaper paper = ReceiptPaper.a5,
  ReceiptDesign design = const ReceiptDesign(),
  bool mono = false,
  String? save,
}) async {
  final r = await ReceiptRenderer.render(
    doc,
    settings: _settings,
    template: template ?? ReceiptTemplate.defaultsFor(doc.kind),
    paper: paper,
    design: design,
    monochrome: mono,
  );
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (save != null && dir != null) {
    File('$dir/phase5/$save.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(await r.pngBytes());
  }
  final px = (await r.image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  return ('${r.height}:${sha1.convert(px)}', r);
}

ReceiptTemplate _hide(ReceiptKind k, Set<ReceiptSection> s) =>
    ReceiptTemplate.defaultsFor(k).copyWith(hidden: s);

double _pageH(ReceiptPaper p) =>
    (p.dots * p.sheetHeightMm! / p.widthMm).floorToDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await _loadFonts();
  });

  group('المبلغ كتابةً', () {
    test('أعداد شائعة', () {
      final cases = {
        1: 'واحد',
        2: 'اثنان',
        10: 'عشرة',
        11: 'أحد عشر',
        12: 'اثنا عشر',
        21: 'واحد وعشرون',
        100: 'مائة',
        250: 'مائتان وخمسون',
        1000: 'ألف',
        2000: 'ألفان',
        3000: 'ثلاثة آلاف',
        10000: 'عشرة آلاف',
        11000: 'أحد عشر ألف',
        43000: 'ثلاثة وأربعون ألف',
        125500: 'مائة وخمسة وعشرون ألف وخمسمائة',
        1000000: 'مليون',
        2500000: 'مليونان وخمسمائة ألف',
        7000000: 'سبعة ملايين',
        1000000000: 'مليار',
      };
      cases.forEach(
        (n, w) => expect(ArabicAmountWords.number(n), w, reason: '$n'),
      );
      expect(ArabicAmountWords.number(0), 'صفر');
    });

    test('صيغة الفاتورة بالدينار من الفلس', () {
      expect(
        ArabicAmountWords.iqd(43000 * 1000),
        'فقط ثلاثة وأربعون ألف دينار عراقي لا غير',
      );
      expect(
        ArabicAmountWords.iqd(-5000 * 1000),
        'فقط خمسة آلاف دينار عراقي لا غير',
      );
    });
  });

  test('القسمان الجديدان في كل الأنواع، والمبلغ كتابةً ليس في الكشوف', () {
    for (final k in ReceiptKind.values) {
      expect(k.sections, contains(ReceiptSection.signature), reason: k.name);
      final statement =
          k == ReceiptKind.customerStatement ||
          k == ReceiptKind.supplierStatement;
      expect(
        k.sections.contains(ReceiptSection.amountWords),
        !statement,
        reason: k.name,
      );
    }
  });

  test('شكل الورق الكبير يُحفظ، والرسمي افتراضي ولا يُكتب', () {
    final d = ReceiptTemplate.defaultsFor(ReceiptKind.sale);
    expect(d.sheetStyle, ReceiptSheetStyle.formal);
    expect(d.toJson().containsKey('sheetStyle'), isFalse);
    final e = d.copyWith(sheetStyle: ReceiptSheetStyle.enlarged);
    expect(e.toJson()['sheetStyle'], 'enlarged');
    expect(ReceiptTemplate.fromJson(ReceiptKind.sale, e.toJson()), e);
    expect(e == d, isFalse);
  });

  test('المبلغ كتابةً والختم يرسمان على الصفحة ويُخفيان بالمفتاح', () async {
    for (final k in [
      ReceiptKind.sale,
      ReceiptKind.oilChange,
      ReceiptKind.expense,
    ]) {
      final doc = ReceiptBuilders.sample(k);
      final (all, _) = await _shot(doc, save: 'formal_${k.name}');
      final (noWords, _) = await _shot(
        doc,
        template: _hide(k, {ReceiptSection.amountWords}),
      );
      final (noSign, _) = await _shot(
        doc,
        template: _hide(k, {ReceiptSection.signature}),
      );
      expect(noWords, isNot(all), reason: k.name);
      expect(noSign, isNot(all), reason: k.name);
    }
  });

  test('اللفافة لا تتغيّر بالقسمين الجديدين', () async {
    for (final p in ReceiptPaper.rolls) {
      final doc = ReceiptBuilders.sample(ReceiptKind.sale);
      final (a, _) = await _shot(doc, paper: p);
      final (b, _) = await _shot(
        doc,
        paper: p,
        template: _hide(ReceiptKind.sale, {
          ReceiptSection.amountWords,
          ReceiptSection.signature,
        }),
      );
      expect(a, b, reason: p.name);
    }
  });

  test('الفاتورة الرسمية صفحة واحدة بالضبط على A5 وA4 لكل الأنواع', () async {
    for (final p in [ReceiptPaper.a5, ReceiptPaper.a4]) {
      for (final k in ReceiptKind.values) {
        final (_, r) = await _shot(
          ReceiptBuilders.sample(k),
          paper: p,
          mono: true,
        );
        expect(r.height.toDouble(), _pageH(p), reason: '${k.name}/${p.name}');
      }
    }
  });

  test('الإيصال المكبَّر: شكل اللفافة على عرض الصفحة', () async {
    final doc = ReceiptBuilders.sample(ReceiptKind.oilChange);
    final big = ReceiptTemplate.defaultsFor(
      ReceiptKind.oilChange,
    ).copyWith(sheetStyle: ReceiptSheetStyle.enlarged);
    for (final p in [ReceiptPaper.a5, ReceiptPaper.a4]) {
      final (f, _) = await _shot(doc, paper: p);
      final (e, r) = await _shot(
        doc,
        paper: p,
        template: big,
        save: 'enlarged_${p.name}',
      );
      expect(e, isNot(f));
      expect(r.width, p.dots);
      // المكبَّر لا يُرسم بالمبلغ كتابةً ولا بالختم (هما للرسمية).
      final (e2, _) = await _shot(
        doc,
        paper: p,
        template: big.copyWith(
          hidden: {ReceiptSection.amountWords, ReceiptSection.signature},
        ),
      );
      expect(e2, e);
    }
  });

  test('سطر التوقيع النصي لا يتكرّر مع مربّع التوقيع', () async {
    final doc = ReceiptBuilders.sample(ReceiptKind.expense);
    expect(doc.notes.any((n) => n.contains('التوقيع')), isTrue);
    final bare = ReceiptDocument(
      kind: doc.kind,
      date: doc.date,
      number: doc.number,
      fields: doc.fields,
      totals: doc.totals,
    );
    final (a, _) = await _shot(doc);
    final (b, _) = await _shot(bare);
    expect(a, b);
  });
}
