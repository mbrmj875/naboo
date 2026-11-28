import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_renderer.dart';
import 'package:qr/qr.dart';

/// مزايا التصميم الجديدة: الجداول بخطوط كاملة، العلامة المائية المكررة،
/// ألوان الأجزاء الثلاثة وكل لون، وأشكال رمز QR مع الشعار.
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

Future<void> _save(String name, Uint8List png) async {
  final dir = Platform.environment['RECEIPT_SHOTS_DIR'];
  if (dir == null) return;
  File('$dir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png);
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
  if (save != null) await _save(save, await r.pngBytes());
  final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  return ('${r.height}:${sha1.convert(px)}', r);
}

const _navy = ReceiptPalette(accent: 0xFF1E3A5F, ink: 0xFF111827);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
    ReceiptRenderer.nabooLogoLoader = () async => _logo;
  });

  group('النموذج', () {
    test('الكلاسيكي لا يحفظ مفاتيح جديدة', () {
      final j = const ReceiptDesign().toJson();
      for (final k in ['watermarkPattern', 'watermarkSize', 'watermarkGap', 'qrStyle', 'qrLogo']) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
      expect((j['palette'] as Map).length, 4);
    });

    test('كل الخيارات الجديدة تُحفظ وتُقرأ كما هي', () {
      var pal = _navy;
      for (final s in ReceiptColorSlot.values.where((s) => !s.isCore)) {
        pal = pal.withSlot(s, 0xFF000000 + s.index * 0x101010);
      }
      final d = const ReceiptDesign().copyWith(
        palette: pal,
        items: ReceiptItemsStyle.grid,
        info: ReceiptInfoStyle.grid,
        watermark: ReceiptWatermark.storeLogo,
        watermarkPattern: ReceiptWatermarkPattern.diagonalLeft,
        watermarkSize: 0.3,
        watermarkGap: 1.2,
        qrStyle: ReceiptQrStyle.dotsLeaf,
        qrLogo: true,
      );
      final back = ReceiptDesign.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back, d);
      expect(back.palette.of(ReceiptColorSlot.qr), pal.of(ReceiptColorSlot.qr));
    });

    test('اللون الاختياري يرجع لقيمته التلقائية', () {
      final p = _navy.withSlot(ReceiptColorSlot.topBg, 0xFF123456);
      expect(p.of(ReceiptColorSlot.topBg), 0xFF123456);
      final back = p.withSlot(ReceiptColorSlot.topBg, null);
      expect(back.of(ReceiptColorSlot.topBg), back.paper);
      expect(back, _navy);
    });

    test('تغيير توزيع العلامة المائية يرجع الحجم المناسب له', () {
      const d = ReceiptDesign();
      expect(d.watermarkSize, 0.62);
      final tiled = d.copyWith(watermarkPattern: ReceiptWatermarkPattern.grid);
      expect(tiled.watermarkSize, ReceiptWatermarkPattern.grid.defaultSize);
      expect(tiled.copyWith(watermarkSize: 0.4).watermarkSize, 0.4);
    });

    test('عشرون شكلاً لرمز QR، كلها مختلفة', () {
      expect(ReceiptQrStyle.values.length, 20);
      expect(
        {for (final s in ReceiptQrStyle.values) (s.module, s.eye)}.length,
        20,
      );
    });

    test('تحذير عند نص غير واضح في الأجزاء ورأس الجدول وQR', () {
      final d = const ReceiptDesign().copyWith(
        items: ReceiptItemsStyle.grid,
        palette: _navy
            .withSlot(ReceiptColorSlot.topBg, 0xFF111111)
            .withSlot(ReceiptColorSlot.tableHead, 0xFF111111)
            .withSlot(ReceiptColorSlot.qr, 0xFFF5F5F5),
      );
      final w = d.contrastWarnings();
      expect(w, contains('نص الجزء العلوي غير واضح على خلفيته.'));
      expect(w, contains('نص رأس الجدول غير واضح على لونه.'));
      expect(w.any((e) => e.startsWith('رمز QR فاتح')), isTrue);
    });
  });

  group('الرسم', () {
    final base = const ReceiptDesign().copyWith(palette: _navy);
    final zones = _navy
        .withSlot(ReceiptColorSlot.topBg, 0xFF0F3D5E)
        .withSlot(ReceiptColorSlot.topInk, 0xFFFFFFFF)
        .withSlot(ReceiptColorSlot.bottomBg, 0xFFE0F2FE)
        .withSlot(ReceiptColorSlot.accent, 0xFF0E7490);
    final options = <String, ReceiptDesign>{
      'items-grid': base.copyWith(items: ReceiptItemsStyle.grid),
      'info-grid': base.copyWith(info: ReceiptInfoStyle.grid),
      'zones': base.copyWith(palette: zones),
      'table-colors': base.copyWith(
        items: ReceiptItemsStyle.grid,
        palette: _navy
            .withSlot(ReceiptColorSlot.tableHead, 0xFF0E7490)
            .withSlot(ReceiptColorSlot.tableHeadInk, 0xFFFFFFFF)
            .withSlot(ReceiptColorSlot.grid, 0xFF0E7490),
      ),
      'on-accent': base.copyWith(
        palette: _navy.withSlot(ReceiptColorSlot.onAccent, 0xFFFDE68A),
      ),
      for (final p in ReceiptWatermarkPattern.values.where((p) => p.tiled))
        'wm-${p.name}': base.copyWith(
          watermark: ReceiptWatermark.storeLogo,
          watermarkPattern: p,
        ),
      'qr-color': base.copyWith(
        palette: _navy.withSlot(ReceiptColorSlot.qr, 0xFF1E3A5F),
      ),
      'qr-dots-logo': base.copyWith(qrStyle: ReceiptQrStyle.dots, qrLogo: true),
    };

    test('كل خيار جديد يغيّر الورقة الملوّنة', () async {
      final (ref, r0) = await _shot(base);
      r0.dispose();
      for (final e in options.entries) {
        final (h, r) = await _shot(e.value, save: 'features/${e.key}');
        expect(h, isNot(ref), reason: e.key);
        r.dispose();
      }
    });

    test('العلامة المكررة تغطي طول الورقة، والحرارية نقاط سوداء فقط', () async {
      for (final p in ReceiptWatermarkPattern.values.where((p) => p.tiled)) {
        final d = base.copyWith(
          watermark: ReceiptWatermark.storeLogo,
          watermarkPattern: p,
          watermarkOpacity: 0.3,
        );
        final (_, r) = await _shot(
          d,
          mono: true,
          kind: ReceiptKind.directSale,
          save: 'features/mono-wm-${p.name}',
        );
        final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        // أبيض أو أسود فقط عدا أطراف الحروف والشعار.
        var grey = 0;
        for (var i = 0; i < px.length; i += 4) {
          if (px[i] > 40 && px[i] < 215) grey++;
        }
        expect(grey / (px.length / 4), lessThan(0.08), reason: p.name);
        // نقاط على طول الورقة: أكثر سواداً من الورقة نفسها بلا علامة، ولكل
        // ربع من الورقة نصيبه.
        final (_, plain) = await _shot(
          base.copyWith(watermarkOpacity: 0.3),
          mono: true,
          kind: ReceiptKind.directSale,
        );
        final pp = (await plain.image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        int dark(Uint8List b, int w, int from, int to) {
          var n = 0;
          for (var i = from * w * 4; i < to * w * 4; i += 4) {
            if (b[i] < 60) n++;
          }
          return n;
        }

        expect(plain.height, r.height, reason: p.name);
        // (العمود الواحد قد يقع شعاره الأول خلف شعار المحل الأسود.)
        final h = r.height;
        var covered = 0;
        for (var q = 0; q < 4; q++) {
          final from = h * q ~/ 4, to = h * (q + 1) ~/ 4;
          if (dark(px, r.width, from, to) > dark(pp, r.width, from, to) + 100) {
            covered++;
          }
        }
        expect(covered, greaterThanOrEqualTo(p == ReceiptWatermarkPattern.vertical ? 3 : 4), reason: p.name);
        plain.dispose();
        r.dispose();
      }
    });

    test('ألوان الأجزاء: أعلى الورقة وأسفلها بلونيهما، والوسط بلون الورقة', () async {
      final (_, r) = await _shot(base.copyWith(palette: zones), save: 'features/zones-check');
      final px = (await r.image.toByteData(format: ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      int at(int x, int y) {
        final i = (y * r.width + x) * 4;
        return 0xFF000000 | (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
      }

      expect(at(2, 2), 0xFF0F3D5E);
      expect(at(2, r.height - 3), 0xFFE0F2FE);
      expect(at(2, r.height ~/ 2), 0xFFFFFFFF);
      r.dispose();
    });

    test('الجداول على كل المقاسات والأنواع، حراري وملوّن', () async {
      final all = base.copyWith(
        items: ReceiptItemsStyle.grid,
        info: ReceiptInfoStyle.grid,
        watermark: ReceiptWatermark.storeLogo,
        watermarkPattern: ReceiptWatermarkPattern.diagonalRight,
        palette: zones,
        qrStyle: ReceiptQrStyle.softCircle,
        qrLogo: true,
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
                  ? 'features/all-${paper.name}-${mono ? 'mono' : 'color'}'
                  : null,
            );
            expect(r.width, paper.dots);
            r.dispose();
          }
        }
      }
    });
  });

  group('رمز QR', () {
    const data = 'basrainvoice://invoice/1024?g=3f2a1c9e-7b4d-4e8a-9c1f-0a2b3c4d5e6f';

    /// كل نقطة في الرمز تُقرأ في مكانها: وسط كل وحدة داكن إن كانت داكنة
    /// وفاتح إن كانت فاتحة (عدا منطقة الشعار التي يغطيها تصحيح الأخطاء).
    for (final style in ReceiptQrStyle.values) {
      for (final withLogo in [false, true]) {
        test('${style.label}${withLogo ? ' مع الشعار' : ''}: الوحدات في مكانها', () async {
          final code = QrCode.fromData(
            data: data,
            errorCorrectLevel: withLogo ? QrErrorCorrectLevel.H : QrErrorCorrectLevel.L,
          );
          final qi = QrImage(code);
          final n = code.moduleCount;
          const m = 12;
          final d = const ReceiptDesign().copyWith(
            qrStyle: style,
            qrLogo: withLogo,
            palette: const ReceiptPalette().withSlot(ReceiptColorSlot.qr, 0xFF1E3A5F),
          );
          final img = await ReceiptRenderer.qrImage(
            data,
            design: d,
            side: (n * m).toDouble(),
            logoBytes: _logo,
          );
          final png = (await img.toByteData(format: ImageByteFormat.png))!
              .buffer
              .asUint8List();
          if (!withLogo || style.index % 5 == 0) {
            await _save('qr/${style.index.toString().padLeft(2, '0')}-${style.name}${withLogo ? '-logo' : ''}', png);
          }
          final px = (await img.toByteData(format: ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
          var lm = (n * 0.22).ceil();
          if ((n - lm).isOdd) lm++;
          final l0 = (n - lm) ~/ 2;
          var wrong = 0;
          var logoCells = 0;
          for (var r = 0; r < n; r++) {
            for (var c = 0; c < n; c++) {
              if (withLogo && r >= l0 && r < l0 + lm && c >= l0 && c < l0 + lm) {
                logoCells++;
                continue;
              }
              final eye = (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
              // مربعات الزوايا بأشكالها (دائرية/ورقة): تُفحص منتصفات أضلاعها
              // ووسطها فقط، فأطرافها مدوّرة عمداً.
              if (eye) {
                final lr = r < 7 ? r : r - (n - 7);
                final lc = c < 7 ? c : c - (n - 7);
                final mid = (lr == 3 || lc == 3) || (lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4);
                if (!mid) continue;
              }
              final x = c * m + m ~/ 2;
              final y = r * m + m ~/ 2;
              final dark = px[(y * n * m + x) * 4] < 128;
              if (dark != qi.isDark(r, c)) wrong++;
            }
          }
          expect(wrong, 0);
          // الشعار يغطي أقل من ربع قدرة التصحيح العالي (30%).
          expect(logoCells / (n * n), lessThan(0.075));
          img.dispose();
        });
      }
    }
  });
}
