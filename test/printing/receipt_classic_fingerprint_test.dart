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
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';

/// بصمة الإيصالات كما كانت قبل محرّك التصميم: من لم يغيّر تصميمه يطبع
/// الورقة نفسها نقطةً نقطة.
///
/// إعادة تسجيل البصمة (فقط عند تغيير مقصود في الشكل الكلاسيكي):
/// `RECEIPT_FINGERPRINT_WRITE=1 flutter test test/printing/receipt_classic_fingerprint_test.dart`
const _fixture = 'test/printing/fixtures/classic_receipt_fingerprints.json';

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

final _settings = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر، قرب الإشارة',
  storePhones: ['0780 000 0000'],
  storeLogoBase64: base64Encode(
    File('assets/images/splash_logo_mark.png').readAsBytesSync(),
  ),
);

/// أنواع محل الزيت كما كانت قبل إضافة كشفي الحساب (ثابتة حتى لا تتغيّر البصمة).
const _kinds = [
  ReceiptKind.oilChange,
  ReceiptKind.directSale,
  ReceiptKind.carWash,
  ReceiptKind.saleReturn,
  ReceiptKind.debtPayment,
  ReceiptKind.expense,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
  });

  test('التصميم الكلاسيكي يطابق الإيصال القديم نقطةً نقطة', () async {
    final got = <String, String>{};
    // تاريخ ثابت: النموذج يستعمل «الآن».
    for (final kind in _kinds) {
      final base = ReceiptBuilders.sample(kind);
      final doc = ReceiptDocument(
        kind: base.kind,
        date: DateTime(2026, 11, 27, 10, 30),
        number: base.number,
        status: base.status,
        fields: base.fields,
        lines: base.lines,
        totals: base.totals,
        highlights: base.highlights,
        notes: [
          for (final n in base.notes)
            if (!n.contains('/')) n,
        ],
        qrData: base.qrData,
        titleOverride: base.titleOverride,
      );
      for (final paper in ReceiptPaper.values) {
        for (final shape in const [ReceiptHeaderShape.filled, ReceiptHeaderShape.outlined, ReceiptHeaderShape.plain]) {
          for (final mono in [true, false]) {
            final style = ReceiptStyle(
              shape: shape,
              accent: mono ? ReceiptColor.black : ReceiptColor.navy,
              ink: mono ? ReceiptColor.black : ReceiptColor.charcoal,
              font: shape == ReceiptHeaderShape.plain
                  ? ReceiptFont.cairo
                  : ReceiptFont.tajawal,
            );
            final r = await ReceiptRenderer.render(
              doc,
              settings: _settings,
              template: ReceiptTemplate.defaultsFor(kind),
              paper: paper,
              style: style,
              monochrome: mono,
            );
            final rgba = (await r.image.toByteData(
              format: ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final key = '${kind.name}/${paper.name}/${shape.name}/${mono ? 'mono' : 'color'}';
            got[key] = '${r.width}x${r.height}:${sha1.convert(rgba)}';
            if (mono && paper.isRoll) {
              final bmp = await MonoBitmap.fromRendered(r);
              got['$key/bits'] = sha1.convert(bmp.bits).toString();
            }
            r.dispose();
          }
        }
      }
    }
    final file = File(_fixture);
    if (Platform.environment['RECEIPT_FINGERPRINT_WRITE'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(got));
      return;
    }
    final want = Map<String, String>.from(
      jsonDecode(file.readAsStringSync()) as Map,
    );
    final diff = [
      for (final k in want.keys)
        if (got[k] != want[k]) k,
    ];
    expect(diff, isEmpty, reason: 'إيصالات تغيّر شكلها');
    expect(got.length, want.length);
  });
}
