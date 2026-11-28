import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr/qr.dart';

import '../models/print_settings_data.dart';
import '../utils/iraqi_currency_format.dart';
import 'arabic_amount_words.dart';
import 'receipt_design.dart';
import 'receipt_model.dart';

/// مقاس الورق. الحراري بالنقاط عند 203 نقطة/بوصة، والأوراق الكبيرة عند 150.
enum ReceiptPaper {
  mm58(384, '58 مم', 58, null),
  mm80(576, '80 مم', 80, null),
  a5(874, 'A5', 148, 210),
  a4(1240, 'A4', 210, 297);

  const ReceiptPaper(this.dots, this.label, this.widthMm, this.sheetHeightMm);
  final int dots;
  final String label;
  final double widthMm;

  /// ارتفاع الورقة للمقاسات الكبيرة، و`null` للفافة الحرارية.
  final double? sheetHeightMm;

  /// لفافة حرارية صغيرة (58/80 مم).
  bool get isRoll => sheetHeightMm == null;

  static const rolls = [mm58, mm80];

  /// وصف للمستخدم.
  String get hint => switch (this) {
    mm58 => 'الطابعة الحرارية الصغيرة (الأشيع، محمولة أو بلوتوث)',
    mm80 => 'الطابعة الحرارية العريضة (كاشير)',
    a5 => 'نصف ورقة A4 — طابعات المكتب',
    a4 => 'ورقة كاملة — طابعات المكتب (ليزر / حبر)',
  };

  static ReceiptPaper fromSettings(PrintPaperFormat f) =>
      f == PrintPaperFormat.thermal58 ? mm58 : mm80;
}

/// صورة الإيصال المرسومة.
class RenderedReceipt {
  RenderedReceipt(this.image, this.logoRect);

  final ui.Image image;

  /// موضع الشعار، لتطبيق التنقيط (dithering) عليه وحده عند التحويل لأبيض/أسود.
  final ui.Rect? logoRect;

  int get width => image.width;
  int get height => image.height;

  Future<Uint8List> pngBytes() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void dispose() => image.dispose();
}

/// يرسم [ReceiptDocument] صورةً بعرض الورق الحراري بالضبط.
///
/// الرسم بمحرك نصوص Flutter يعني أن العربي يتشكّل ويُقلب اتجاهه كما على
/// الشاشة، ثم تُرسل الصورة للطابعة نقطياً فلا يهم هل تدعم العربي أم لا.
///
/// الشكل من [ReceiptDesign]. الطابعة الحرارية ([monochrome]) تطبع بالأسود
/// على أبيض دائماً: الألوان أسود، الورقة بيضاء، والعلامة المائية نقاط خفيفة.
class ReceiptRenderer {
  ReceiptRenderer._(
    this.width,
    this.base, {
    required this.family,
    required this.ink,
    required this.accent,
    required this.paper,
    required this.muted,
    required this.design,
    required this.mono,
    required bool sheet,
    bool bigPaper = false,
  }) : _ink = ink,
       isSheet = sheet,
       pad =
           (width *
                   (sheet || bigPaper
                       ? 0.06
                       : design.density == ReceiptDensity.compact
                       ? 0.02
                       : 0.03))
               .roundToDouble();

  static const _black = ui.Color(0xFF000000);
  static const _white = ui.Color(0xFFFFFFFF);

  /// شعار نابو للعلامة المائية (قابل للاستبدال في الاختبارات).
  static Future<Uint8List?> Function() nabooLogoLoader = () async {
    final d = await rootBundle.load('assets/images/logo.png');
    return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  };

  /// عرض منطقة الرسم؛ يضيق مؤقتاً داخل أعمدة الصفحة الكبيرة.
  double width;
  final double base;
  final String family;
  final ui.Color ink;
  final ui.Color accent;
  final ui.Color paper;
  final ui.Color muted;
  final ReceiptDesign design;
  final bool mono;
  double pad;
  final bool isSheet;

  /// ارتفاع الصفحة بالنقاط للورق الكبير (A5/A4)، و`null` للفافة.
  double? _pageH;

  /// داخل الجزء العلوي الملوّن.
  bool _inTop = false;

  /// لون العنوان للنص والخطوط؛ في الجزء العلوي يصير لون نصه إن لم يُقرأ
  /// على خلفيته (عنوان كحلي على رأس كحلي مثلاً).
  ui.Color get _accentInk => _readableInTop(accent, 3);

  /// لون عناوين الأسطر بالقاعدة نفسها.
  ui.Color get _mutedInk => _readableInTop(muted, 3);

  ui.Color _readableInTop(ui.Color c, double need) {
    if (mono || !_inTop || !design.palette.isSet(ReceiptColorSlot.topBg))
      return c;
    final ok =
        ReceiptDesign.contrast(
          c.toARGB32(),
          design.palette.of(ReceiptColorSlot.topBg),
        ) >=
        need;
    return ok ? c : _ink;
  }

  /// لون النص في الجزء الذي يُرسم الآن (العلوي/الأوسط/السفلي).
  ui.Color _ink;

  /// حدود الأجزاء الثلاثة، تُقاس في المرور الأول.
  double? _topEnd;
  double? _bottomStart;

  /// مقدار ما تنزله حافة الجزء العلوي المشكّلة تحت حدّه.
  double get _edgeDepth => base * 0.8;

  /// مواضع الفواصل بين الأقسام (للثقوب الجانبية).
  final List<double> _dividers = [];

  bool get _hasTopShape =>
      !mono &&
      design.topEdge != ReceiptTopEdge.straight &&
      design.palette.isSet(ReceiptColorSlot.topBg);

  /// لون من لوحة التصميم؛ الحرارية بالأسود على أبيض دائماً.
  ui.Color _c(ReceiptColorSlot s, {bool light = false}) {
    if (mono) return light ? _white : _black;
    return ui.Color(design.palette.of(s));
  }

  bool get _zones =>
      !mono &&
      (design.palette.isSet(ReceiptColorSlot.topBg) ||
          design.palette.isSet(ReceiptColorSlot.bottomBg) ||
          design.palette.isSet(ReceiptColorSlot.topInk) ||
          design.palette.isSet(ReceiptColorSlot.bottomInk));

  /// إزاحة داخلية مؤقتة (المعلومات داخل إطار، رأس المحل داخل إطار).
  double _inset = 0;

  double get inner => width - pad * 2;
  double get _w => inner - _inset * 2;

  static Future<RenderedReceipt> render(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptTemplate template,
    ReceiptPaper paper = ReceiptPaper.mm80,
    ReceiptStyle style = const ReceiptStyle(),
    ReceiptDesign? design,
    bool monochrome = true,
  }) async {
    final d = design ?? ReceiptDesign.fromStyle(style);
    final w = paper.dots.toDouble();
    final baseSize = switch (paper) {
      ReceiptPaper.mm58 => 22.0,
      ReceiptPaper.mm80 => 26.0,
      ReceiptPaper.a5 => 26.0,
      ReceiptPaper.a4 => 30.0,
    };
    // الورق الكبير: فاتورة رسمية بتخطيط صفحة، أو الإيصال نفسه مكبَّراً.
    final formal =
        !paper.isRoll && template.sheetStyle == ReceiptSheetStyle.formal;
    final enlarged = !paper.isRoll && !formal;
    final pal = d.palette;
    // الشريط الجانبي يأخذ حافة الورقة اليمنى والمحتوى بجانبه.
    final strip = d.sideStrip ? (w * 0.08).roundToDouble() : 0.0;
    final cw = w - strip;
    var fit = 1.0;
    ReceiptRenderer make() =>
        ReceiptRenderer._(
            cw,
            (baseSize *
                    (enlarged ? 1.25 : 1.0) *
                    d.size.scale *
                    d.density.scale *
                    fit)
                .roundToDouble(),
            family: d.font.family,
            // الطابعة الحرارية لا تطبع إلا الأسود.
            ink: monochrome ? _black : ui.Color(pal.ink),
            accent: monochrome ? _black : ui.Color(pal.accent),
            paper: monochrome ? _white : ui.Color(pal.paper),
            muted: monochrome ? _black : ui.Color(pal.muted),
            design: d,
            mono: monochrome,
            sheet: formal,
            bigPaper: enlarged,
          )
          .._pageH = !formal
              ? null
              : (w * paper.sheetHeightMm! / paper.widthMm).floorToDouble();
    final logo = template.showLogo
        ? await _decode(settings.storeLogoBytes)
        : null;
    final watermark = await _watermarkImage(d, settings, w);
    final qrLogo = d.qrLogo && template.showQr && (doc.qrData ?? '').isNotEmpty
        ? await _decode(settings.storeLogoBytes, targetWidth: 256)
        : null;
    try {
      // الصفحة الكبيرة: إن زاد المحتوى قليلاً عن الورقة نصغّر الخط قليلاً
      // حتى لا تخرج صفحة ثانية للتذييل وحده. الطويل فعلاً يمتد لصفحات.
      final pageH = make()._pageH;
      if (pageH != null) {
        for (var i = 0; i < 4; i++) {
          final rec = ui.PictureRecorder();
          final m = make().._qrLogo = qrLogo;
          final (h, _) = m._paint(
            ui.Canvas(rec),
            doc,
            settings,
            template,
            logo,
          );
          rec.endRecording().dispose();
          if (h <= pageH || h > pageH * 1.3 || fit <= 0.8) break;
          fit = math.max(0.8, fit * pageH / h * 0.99);
        }
      }
      final r = make().._qrLogo = qrLogo;
      // العلامة المائية وألوان الأجزاء تحتاج الطول وحدود الأجزاء: نقيسها
      // بمرور أول ثم نرسم الخلفية قبل النص.
      ui.Rect? wmRect;
      double? probeH;
      if (watermark != null ||
          r._zones ||
          d.topEdge != ReceiptTopEdge.straight) {
        final probe = ui.PictureRecorder();
        final p = make().._qrLogo = qrLogo;
        final (h, _) = p._paint(
          ui.Canvas(probe),
          doc,
          settings,
          template,
          logo,
        );
        probe.endRecording().dispose();
        probeH = h;
        r
          .._topEnd = p._topEnd
          .._bottomStart = p._bottomStart;
        if (watermark != null && !d.watermarkPattern.tiled) {
          final side = math.min(cw * d.watermarkSize, h * 0.8);
          final scale = math.min(
            side / watermark.width,
            side / watermark.height,
          );
          final ww = watermark.width * scale;
          final wh = watermark.height * scale;
          wmRect = ui.Rect.fromLTWH((cw - ww) / 2, (h - wh) / 2, ww, wh);
        }
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (watermark != null) await r._prepareWatermark(watermark);
      final (height, logoRect) = r._paint(
        canvas,
        doc,
        settings,
        template,
        logo,
        background: probeH == null
            ? null
            : (c) {
                r._zoneBackgrounds(c, probeH!);
                if (watermark == null) return;
                if (d.watermarkPattern.tiled) {
                  r._tiledWatermark(
                    c,
                    probeH,
                    watermark.width / watermark.height,
                  );
                } else if (wmRect != null) {
                  r._watermark(c, wmRect);
                }
              },
      );
      r._frame(canvas, height);
      r._edgeDecor(canvas, height);
      if (strip > 0) r._sideStrip(canvas, cw, strip, height, settings);
      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), height.ceil());
      picture.dispose();
      r._wmTint?.dispose();
      return RenderedReceipt(image, logoRect);
    } finally {
      logo?.dispose();
      watermark?.dispose();
      qrLogo?.dispose();
    }
  }

  /// رمز QR وحده بالشكل واللون المختارين (لمعاينة الأشكال في الشاشة
  /// وللاختبار). [side] بالنقاط.
  static Future<ui.Image> qrImage(
    String data, {
    required ReceiptDesign design,
    double side = 240,
    bool monochrome = false,
    Uint8List? logoBytes,
  }) async {
    final pal = design.palette;
    final r = ReceiptRenderer._(
      side,
      20,
      family: design.font.family,
      ink: monochrome ? _black : ui.Color(pal.ink),
      accent: monochrome ? _black : ui.Color(pal.accent),
      paper: monochrome ? _white : ui.Color(pal.paper),
      muted: monochrome ? _black : ui.Color(pal.muted),
      design: design,
      mono: monochrome,
      sheet: false,
    );
    final logo = design.qrLogo
        ? await _decode(logoBytes, targetWidth: 256)
        : null;
    r._qrLogo = logo;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(ui.Rect.fromLTWH(0, 0, side, side), ui.Paint()..color = r.paper);
    if (design.qrStyle == ReceiptQrStyle.classic &&
        !pal.isSet(ReceiptColorSlot.qr) &&
        logo == null) {
      r._qr(c, data, 0, 0, side);
    } else {
      r._qrStyled(c, data, 0, 0, side);
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(side.ceil(), side.ceil());
    pic.dispose();
    logo?.dispose();
    return img;
  }

  static Future<ui.Image?> _decode(Uint8List? bytes, {int? targetWidth}) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  /// صورة الشعار المختار للعلامة المائية، مصغّرة لعرضها على الورقة.
  static Future<ui.Image?> _watermarkImage(
    ReceiptDesign d,
    PrintSettingsData settings,
    double width,
  ) async {
    final Uint8List? bytes;
    switch (d.watermark) {
      case ReceiptWatermark.none:
        return null;
      case ReceiptWatermark.storeLogo:
        bytes = settings.storeLogoBytes;
      case ReceiptWatermark.nabooLogo:
        try {
          bytes = await nabooLogoLoader();
        } catch (_) {
          return null;
        }
    }
    final target = (width * d.watermarkSize).round().clamp(32, 2000);
    return _decode(bytes, targetWidth: target);
  }

  /// قوة كل نقطة في الشعار (0 إلى 1): بُعد لونها عن لون خلفية الشعار نفسه
  /// (الزاوية)، فالشعار بخلفية بيضاء أو سوداء أو شفافة يظهر شكله فقط لا
  /// مستطيله.
  Float32List? _wmMask;
  int _wmW = 0;
  int _wmH = 0;

  /// قناع الشعار للطابعة الملوّنة، يُرسم بلون العنوان وشفافية التصميم.
  ui.Image? _wmTint;

  Future<void> _prepareWatermark(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    final px = data.buffer.asUint8List();
    final w = img.width;
    final h = img.height;
    final mask = Float32List(w * h);
    final bgTransparent = px[3] < 16;
    final br = px[0], bgG = px[1], bb = px[2];
    for (var i = 0, p = 0; i < mask.length; i++, p += 4) {
      final a = px[p + 3] / 255.0;
      double v;
      if (bgTransparent) {
        v = a;
      } else {
        final dr = px[p] - br, dg = px[p + 1] - bgG, db = px[p + 2] - bb;
        final dist = math.sqrt(dr * dr + dg * dg + db * db);
        v = (dist / 160).clamp(0.0, 1.0) * a;
      }
      mask[i] = v;
    }
    _wmMask = mask;
    _wmW = w;
    _wmH = h;
    if (mono) return;
    // قناع بالشفافية فقط؛ اللون والشفافية العامة يُضافان عند الرسم.
    final out = Uint8List(w * h * 4);
    for (var i = 0, p = 0; i < mask.length; i++, p += 4) {
      out[p + 3] = (mask[i] * 255).round().clamp(0, 255);
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(out, w, h, ui.PixelFormat.rgba8888, done.complete);
    _wmTint = await done.future;
  }

  void _watermark(ui.Canvas c, ui.Rect dst) {
    final tint = _wmTint;
    if (!mono) {
      if (tint == null) return;
      c.drawImageRect(
        tint,
        ui.Rect.fromLTWH(0, 0, tint.width.toDouble(), tint.height.toDouble()),
        dst,
        ui.Paint()
          ..filterQuality = ui.FilterQuality.high
          ..colorFilter = ui.ColorFilter.mode(
            accent.withValues(
              alpha: design.watermarkOpacityFor(monochrome: false),
            ),
            ui.BlendMode.srcIn,
          ),
      );
      return;
    }
    // الحرارية: نقاط سوداء صرفة بعتبة Bayer، فيبقى النص فوقها حاداً.
    _monoDots(c, dst, design.watermarkOpacityFor(monochrome: true));
  }

  /// مصفوفة Bayer 4×4.
  static const _bayer = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ];

  void _monoDots(ui.Canvas c, ui.Rect dst, double op) {
    final mask = _wmMask;
    if (mask == null) return;
    final sx = _wmW / dst.width;
    final sy = _wmH / dst.height;
    final points = <ui.Offset>[];
    for (var y = 0; y < dst.height.floor(); y++) {
      final iy = (y * sy).floor().clamp(0, _wmH - 1);
      for (var x = 0; x < dst.width.floor(); x++) {
        final ix = (x * sx).floor().clamp(0, _wmW - 1);
        final dark = mask[iy * _wmW + ix] * op;
        final ox = (dst.left + x).round();
        final oy = (dst.top + y).round();
        if (dark * 16 > _bayer[oy & 3][ox & 3] + 0.5) {
          points.add(ui.Offset(ox + 0.5, oy + 0.5));
        }
      }
    }
    c.drawPoints(
      ui.PointMode.points,
      points,
      ui.Paint()
        ..color = _black
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  /// خلفيات الجزء العلوي والسفلي (الأوسط بلون الورقة).
  void _zoneBackgrounds(ui.Canvas c, double h) {
    if (mono) return;
    final pal = design.palette;
    final top = _topEnd;
    if (top != null && pal.isSet(ReceiptColorSlot.topBg)) {
      c.drawPath(
        _topShape(top),
        ui.Paint()..color = _c(ReceiptColorSlot.topBg),
      );
    }
    final bottom = _bottomStart;
    if (bottom != null && pal.isSet(ReceiptColorSlot.bottomBg)) {
      c.drawRect(
        ui.Rect.fromLTWH(0, bottom, width, h - bottom),
        ui.Paint()..color = _c(ReceiptColorSlot.bottomBg),
      );
    }
  }

  /// شكل الجزء العلوي: مستطيل وحافته السفلى حسب [ReceiptDesign.topEdge].
  ui.Path _topShape(double top) {
    final d = _edgeDepth;
    final p = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(width, 0);
    switch (design.topEdge) {
      case ReceiptTopEdge.straight:
        p
          ..lineTo(width, top)
          ..lineTo(0, top);
      case ReceiptTopEdge.diagonal:
        p
          ..lineTo(width, top + d)
          ..lineTo(0, top);
      case ReceiptTopEdge.wave:
        p.lineTo(width, top + d * 0.5);
        const n = 48;
        for (var i = n; i >= 0; i--) {
          final x = width * i / n;
          p.lineTo(x, top + d * 0.5 + math.sin(i / n * math.pi * 3) * d * 0.45);
        }
      case ReceiptTopEdge.arc:
        p
          ..lineTo(width, top)
          ..quadraticBezierTo(width / 2, top + d * 2, 0, top);
      case ReceiptTopEdge.zigzag:
        p.lineTo(width, top);
        final tooth = base * 0.7;
        final n = math.max(4, (width / tooth).round());
        for (var i = n; i > 0; i--) {
          final x1 = width * i / n;
          final x0 = width * (i - 1) / n;
          p
            ..lineTo((x0 + x1) / 2, top + d * 0.7)
            ..lineTo(x0, top);
        }
    }
    return p..close();
  }

  /// مراكز الشعارات المكررة على طول الورقة.
  List<ui.Offset> _tileCenters(double h, double side) {
    final step = side * (1 + design.watermarkGap);
    final out = <ui.Offset>[];
    switch (design.watermarkPattern) {
      case ReceiptWatermarkPattern.single:
        return out;
      case ReceiptWatermarkPattern.vertical:
        for (var y = step / 2; y < h + side / 2; y += step) {
          out.add(ui.Offset(width / 2, y));
        }
      case ReceiptWatermarkPattern.grid:
      case ReceiptWatermarkPattern.diagonalRight:
      case ReceiptWatermarkPattern.diagonalLeft:
        final cols = math.max(1, (width / step).floor());
        final x0 = (width - (cols - 1) * step) / 2;
        final stagger = design.watermarkPattern != ReceiptWatermarkPattern.grid;
        var row = 0;
        for (var y = step / 2; y < h + side / 2; y += step, row++) {
          // الصفوف المائلة تُزاح نصف خطوة فتصطف الشعارات على خطوط مائلة.
          final shift = stagger && row.isOdd
              ? (design.watermarkPattern ==
                            ReceiptWatermarkPattern.diagonalRight
                        ? 1
                        : -1) *
                    step /
                    2
              : 0.0;
          for (var i = -1; i <= cols; i++) {
            final x = x0 + i * step + shift;
            if (x < -side / 2 || x > width + side / 2) continue;
            out.add(ui.Offset(x, y));
          }
        }
    }
    return out;
  }

  /// العلامة المائية مكررة: ملوّنة بلون العنوان، أو نقاط على الحرارية.
  void _tiledWatermark(ui.Canvas c, double h, double aspect) {
    final side = width * design.watermarkSize;
    final tw = aspect >= 1 ? side : side * aspect;
    final th = aspect >= 1 ? side / aspect : side;
    final angle = design.watermarkPattern.degrees * math.pi / 180;
    final centers = _tileCenters(h, side);
    if (!mono) {
      final tint = _wmTint;
      if (tint == null) return;
      final paint = ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..colorFilter = ui.ColorFilter.mode(
          accent.withValues(
            alpha: design.watermarkOpacityFor(monochrome: false),
          ),
          ui.BlendMode.srcIn,
        );
      final src = ui.Rect.fromLTWH(
        0,
        0,
        tint.width.toDouble(),
        tint.height.toDouble(),
      );
      for (final o in centers) {
        c
          ..save()
          ..translate(o.dx, o.dy)
          ..rotate(angle);
        c.drawImageRect(
          tint,
          src,
          ui.Rect.fromCenter(center: ui.Offset.zero, width: tw, height: th),
          paint,
        );
        c.restore();
      }
      return;
    }
    // الحرارية: قناع بطول الورقة ثم نقاط Bayer سوداء صرفة.
    final mask = _wmMask;
    if (mask == null) return;
    final pw = width.toInt();
    final ph = h.ceil();
    final page = Float32List(pw * ph);
    final cosA = math.cos(-angle), sinA = math.sin(-angle);
    final half = math.sqrt(tw * tw + th * th) / 2;
    for (final o in centers) {
      final x0 = math.max(0, (o.dx - half).floor());
      final x1 = math.min(pw - 1, (o.dx + half).ceil());
      final y0 = math.max(0, (o.dy - half).floor());
      final y1 = math.min(ph - 1, (o.dy + half).ceil());
      for (var y = y0; y <= y1; y++) {
        final dy = y + 0.5 - o.dy;
        for (var x = x0; x <= x1; x++) {
          final dx = x + 0.5 - o.dx;
          final lx = dx * cosA - dy * sinA + tw / 2;
          final ly = dx * sinA + dy * cosA + th / 2;
          if (lx < 0 || ly < 0 || lx >= tw || ly >= th) continue;
          final ix = (lx / tw * _wmW).floor().clamp(0, _wmW - 1);
          final iy = (ly / th * _wmH).floor().clamp(0, _wmH - 1);
          final v = mask[iy * _wmW + ix];
          final i = y * pw + x;
          if (v > page[i]) page[i] = v;
        }
      }
    }
    final op = design.watermarkOpacityFor(monochrome: true);
    final points = <ui.Offset>[];
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < pw; x++) {
        final dark = page[y * pw + x] * op;
        if (dark > 0 && dark * 16 > _bayer[y & 3][x & 3] + 0.5) {
          points.add(ui.Offset(x + 0.5, y + 0.5));
        }
      }
    }
    c.drawPoints(
      ui.PointMode.points,
      points,
      ui.Paint()
        ..color = _black
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  // ---------------------------------------------------------------- الرسم

  (double, ui.Rect?) _paint(
    ui.Canvas c,
    ReceiptDocument doc,
    PrintSettingsData settings,
    ReceiptTemplate t,
    ui.Image? logo, {
    void Function(ui.Canvas c)? background,
  }) {
    if (isSheet)
      return _paintSheet(c, doc, settings, t, logo, background: background);
    c.drawRect(
      ui.Rect.fromLTWH(0, 0, width, 100000),
      ui.Paint()..color = paper,
    );
    background?.call(c);
    _ink = mono ? ink : _c(ReceiptColorSlot.topInk);
    _inTop = true;
    _dividers.clear();
    var y = pad + (design.edges == ReceiptEdges.zigzag ? base * 0.4 : 0);
    ui.Rect? logoRect;

    // الشعار.
    if (logo != null) {
      final maxW = width * 0.55;
      final maxH = base * 4.5;
      final scale = math.min(maxW / logo.width, maxH / logo.height);
      final lw = logo.width * scale;
      final lh = logo.height * scale;
      final top = design.header == ReceiptHeaderLayout.boxed
          ? y + base * 0.5
          : y;
      logoRect = ui.Rect.fromLTWH((width - lw) / 2, top, lw, lh);
      if (design.header == ReceiptHeaderLayout.boxed) y += base * 0.5;
      c.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        logoRect,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      y += lh + base * 0.4;
    }

    // اسم المحل وعنوانه.
    y = _header(c, settings, t, y, boxTop: logoRect == null ? null : pad);
    y += base * 0.4;

    // شريط العنوان.
    y += _inverted(c, doc.title, y, size: base * 1.25);
    y += base * 0.35;
    _topEnd = y - base * 0.15;
    if (_hasTopShape) y += _edgeDepth;
    _ink = ink;
    _inTop = false;

    // الرقم والتاريخ.
    final number = doc.number == null ? '' : 'رقم ${doc.number}';
    final status = doc.status ?? '';
    y += _row(
      c,
      [number, status].where((e) => e.isNotEmpty).join(' · '),
      DateFormat('yyyy/MM/dd  HH:mm', 'en').format(doc.date),
      y,
      size: base * 0.9,
      boldStart: true,
    );
    y += _dashed(c, y);

    // حقول الرأس.
    final fields = [
      for (final f in doc.fields)
        if (f.section == null || t.shows(f.section!)) f,
    ];
    final highlights = [
      for (final h in doc.highlights)
        if (h.section == null || t.shows(h.section!)) h,
    ];
    if (fields.isNotEmpty || highlights.isNotEmpty) {
      y = _section(c, 'التفاصيل', y, (y) {
        y = _fields(c, fields, y);
        // الصناديق البارزة.
        for (final h in highlights) {
          y += base * 0.3;
          y += _boxed(c, h.label, h.value, y);
        }
        return _loyalty(c, doc, t, y);
      });
      if (!_sectioned) y += _dashed(c, y);
    }

    // الأصناف.
    if (doc.lines.isNotEmpty) {
      y = _section(
        c,
        'الأصناف والخدمات',
        y,
        (y) => switch (design.items) {
          ReceiptItemsStyle.table => _table(c, doc.lines, y),
          ReceiptItemsStyle.grid => _gridTable(c, doc.lines, y),
          _ => _simpleLines(c, doc.lines, y),
        },
      );
    }

    // المجاميع.
    final totals = [
      for (final tot in doc.totals)
        if (tot.section == null || t.shows(tot.section!)) tot,
    ];
    if (totals.isNotEmpty) {
      y = _section(c, 'الحساب', y, (y) => _totalsBody(c, totals, y));
    }

    // الجزء السفلي: الملاحظات وQR والتذييل.
    // المسافة الإضافية مع ألوان الأجزاء فقط حتى يبقى الكلاسيكي كما هو.
    if (_zones) y += base * 0.2;
    _bottomStart = y;
    _ink = mono ? ink : _c(ReceiptColorSlot.bottomInk);
    if (_zones) y += base * 0.2;

    // ملاحظات.
    if (doc.notes.isNotEmpty) {
      y += base * 0.5;
      for (final n in doc.notes) {
        y += _text(c, n, y, size: base * 0.9, align: TextAlign.start);
      }
    }

    // QR.
    final qr = doc.qrData;
    if (t.showQr && qr != null && qr.isNotEmpty) {
      y += base * 0.6;
      final side = math.min(width * 0.38, 200.0).roundToDouble();
      final qrBg = mono
          ? _white
          : (design.palette.isSet(ReceiptColorSlot.bottomBg)
                ? _c(ReceiptColorSlot.bottomBg)
                : paper);
      _qrAt(c, qr, (width - side) / 2, y, side, qrBg);
      y += side + base * 0.2;
    }

    // التذييل.
    final footer = [
      settings.footerExtra.trim(),
      t.footer.trim(),
    ].where((e) => e.isNotEmpty).toList();
    // أوقات الدوام وحسابات التواصل: لا تُعدّ نص تذييل يُخفي سطر الشكر.
    final footerExtras = t.shows(ReceiptSection.storeExtras)
        ? settings.receiptStoreFooterExtras
        : const <String>[];
    y += base * 0.3;
    y += _dashed(c, y);
    if (t.thanksShown(hasFooterText: footer.isNotEmpty)) {
      y += _text(
        c,
        'شكراً لزيارتكم',
        y,
        size: base,
        bold: true,
        align: TextAlign.center,
      );
    }
    for (final f in [...footer, ...footerExtras]) {
      y += _text(c, f, y, size: base * 0.9, align: TextAlign.center);
    }
    if (design.edges == ReceiptEdges.stub)
      y = _stub(c, doc, totals, highlights, y);
    y += pad * 2;
    if (design.edges == ReceiptEdges.zigzag) y += base * 0.4;
    return (y, logoRect);
  }

  /// رمز QR في [x],[y] مع بطاقته: فاتحة على الخلفية الداكنة، وخلفية نظيفة
  /// فوق العلامة المائية، حتى تقرؤه الكاميرا.
  void _qrAt(
    ui.Canvas c,
    String qr,
    double x,
    double y,
    double side,
    ui.Color qrBg,
  ) {
    if (!mono && qrBg.computeLuminance() < 0.35) {
      // خلفية داكنة: الكاميرات تقرأ الرمز الداكن على فاتح، فنضع له بطاقة فاتحة.
      c.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(x, y, side, side).inflate(base * 0.5),
          ui.Radius.circular(base * 0.4),
        ),
        ui.Paint()..color = _white,
      );
    } else if (design.watermark != ReceiptWatermark.none) {
      // بلا علامة مائية تحت الرمز حتى تقرؤه الكاميرا.
      c.drawRect(
        ui.Rect.fromLTWH(x, y, side, side).inflate(base * 0.3),
        ui.Paint()..color = qrBg,
      );
    }
    if (design.qrStyle == ReceiptQrStyle.classic &&
        !design.palette.isSet(ReceiptColorSlot.qr) &&
        _qrLogo == null) {
      _qr(c, qr, x, y, side);
    } else {
      _qrStyled(c, qr, x, y, side);
    }
  }

  /// صندوق العروض والزيارات: سطر العرض بنقاط تقدّمه (●●○)، ورقم زيارة
  /// السيارة، وتاريخ الغيار القادم التقريبي إن حدّد المالك مدته.
  double _loyalty(
    ui.Canvas c,
    ReceiptDocument doc,
    ReceiptTemplate t,
    double y,
  ) {
    if (!t.shows(ReceiptSection.loyalty)) return y;
    final l = doc.loyalty;
    final months = doc.kind == ReceiptKind.oilChange ? t.nextServiceMonths : 0;
    final visit = l?.visit;
    final lines = <String>[
      if ((l?.line ?? '').trim().isNotEmpty) l!.line!.trim(),
      if (visit != null)
        visit <= 1
            ? 'أول زيارة لسيارتك — أهلاً بك'
            : 'زيارتك رقم $visit — شكراً لثقتك',
      if (months > 0)
        'الغيار القادم تقريباً: ${DateFormat('yyyy/MM/dd', 'en').format(DateTime(doc.date.year, doc.date.month + months, doc.date.day))}',
    ];
    final dots = l != null && l.hasProgress;
    if (lines.isEmpty && !dots) return y;
    y += base * 0.4;
    final top = y;
    final ip = base * 0.4;
    y += ip;
    _inset = ip;
    for (var i = 0; i < lines.length; i++) {
      y += _text(
        c,
        lines[i],
        y,
        size: i == 0 ? base * 0.95 : base * 0.85,
        bold: i == 0,
        align: TextAlign.center,
      );
    }
    if (dots) {
      final n = l.total!;
      final done = l.done!.clamp(0, n);
      final gap = base * 0.35;
      var r = base * 0.42;
      final maxW = _w;
      if (n * r * 2 + (n - 1) * gap > maxW)
        r = (maxW - (n - 1) * gap) / (n * 2);
      final rowW = n * r * 2 + (n - 1) * gap;
      y += base * 0.25;
      final cy = y + r;
      // التقدّم يبدأ من اليمين (بداية السطر العربي).
      for (var i = 0; i < n; i++) {
        final cx = width / 2 + rowW / 2 - r - i * (r * 2 + gap);
        final o = ui.Offset(cx, cy);
        if (i < done) {
          c.drawCircle(o, r, ui.Paint()..color = _accentInk);
        } else {
          c.drawCircle(
            o,
            r - _stroke / 2,
            ui.Paint()
              ..color = _accentInk
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = _stroke,
          );
        }
      }
      y += r * 2 + base * 0.15;
    }
    _inset = 0;
    y += ip;
    final box = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(pad, top, inner, y - top),
      ui.Radius.circular(base * 0.4),
    );
    if (!mono) {
      c.drawRRect(
        box,
        ui.Paint()
          ..color = _tint(0.08)
          ..blendMode = ui.BlendMode.multiply,
      );
    }
    c.drawRRect(
      box,
      ui.Paint()
        ..color = mono ? _black : _mix(paper, accent, 0.5)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = mono ? 1.5 : math.max(1.2, base / 16),
    );
    return y;
  }

  /// أسطر الحساب والإجمالي البارز. يُرجع y بعدها.
  double _totalsBody(ui.Canvas c, List<ReceiptTotal> totals, double y) {
    for (final tot in totals) {
      if (tot.emphasis) {
        y += base * 0.2;
        y += switch (design.totalLayout) {
          ReceiptTotalLayout.bar => _invertedRow(
            c,
            tot.label,
            _money(tot.fils),
            y,
          ),
          ReceiptTotalLayout.seal => _seal(c, tot.label, _money(tot.fils), y),
          ReceiptTotalLayout.big => _bigTotal(
            c,
            tot.label,
            _money(tot.fils),
            y,
          ),
        };
        y += base * 0.2;
      } else {
        y += _row(c, tot.label, _money(tot.fils), y, boldEnd: true);
      }
    }
    return y;
  }

  // ------------------------------------------------------- الصفحة الكبيرة

  /// يرسم [body] داخل عمود يبدأ عند [x] بعرض [w]: كل الأجزاء ترسم بين
  /// pad وwidth−pad، فنجعل العمود ورقة صغيرة مؤقتاً.
  double _inColumn(ui.Canvas c, double x, double w, double Function() body) {
    final (ow, op) = (width, pad);
    c
      ..save()
      ..translate(x, 0);
    width = w;
    pad = 0;
    try {
      return body();
    } finally {
      width = ow;
      pad = op;
      c.restore();
    }
  }

  /// فاتورة الصفحة الكبيرة (A5/A4): رأس بعمودين، التفاصيل بعمودين، جدول
  /// كامل بعمود السعر، الحساب بجانب QR، والتذييل في أسفل الصفحة. الألوان
  /// والأشكال من التصميم نفسه.
  /// المبلغ الرئيسي كتابةً تحت الحساب في الفاتورة الرسمية.
  double _amountWords(
    ui.Canvas c,
    ReceiptDocument doc,
    ReceiptTemplate t,
    List<ReceiptTotal> totals,
    double y,
  ) {
    if (!t.shows(ReceiptSection.amountWords) ||
        !doc.kind.sections.contains(ReceiptSection.amountWords)) {
      return y;
    }
    final main =
        totals.where((e) => e.emphasis).firstOrNull ?? totals.lastOrNull;
    if (main == null || main.fils == 0) return y;
    y += base * 0.3;
    return y +
        _text(
          c,
          ArabicAmountWords.iqd(main.fils),
          y,
          size: base * 0.82,
          bold: true,
          color: _mutedInk,
        );
  }

  static bool _isSignatureNote(String n) =>
      n.contains('توقيع') && (n.contains('___') || n.contains('....'));

  /// عنوانا مربّعي الختم والتوقيع، أو `null` إن أُخفيا.
  (String, String)? _signatures(ReceiptDocument doc, ReceiptTemplate t) {
    if (!t.shows(ReceiptSection.signature)) return null;
    final other = switch (doc.kind) {
      ReceiptKind.expense => 'توقيع المستلم',
      ReceiptKind.supplierStatement => 'توقيع المورد',
      ReceiptKind.debtPayment => 'توقيع المسدِّد',
      _ => 'توقيع الزبون',
    };
    return ('ختم المحل وتوقيعه', other);
  }

  /// مربّعا الختم والتوقيع أسفل الفاتورة الرسمية.
  double _signatureBoxes(
    ui.Canvas c,
    ReceiptDocument doc,
    ReceiptTemplate t,
    double y,
  ) {
    final labels = _signatures(doc, t);
    if (labels == null) return y;
    final gap = (base * 1.2).roundToDouble();
    final bw = (inner - gap) / 2;
    final bh = (base * 4.2).roundToDouble();
    y += base * 0.9;
    final line = mono ? _black : _mix(paper, accent, 0.55);
    for (final (i, label) in [labels.$1, labels.$2].indexed) {
      final x = width - pad - bw - i * (bw + gap);
      final r = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, y, bw, bh),
        ui.Radius.circular(base * 0.35),
      );
      c.drawRRect(
        r,
        ui.Paint()
          ..color = line
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, _stroke * 0.75),
      );
      final p = _tp(label, size: base * 0.8, color: _mutedInk);
      p.paint(c, ui.Offset(x + bw - p.width - base * 0.5, y + base * 0.35));
    }
    return y + bh;
  }

  (double, ui.Rect?) _paintSheet(
    ui.Canvas c,
    ReceiptDocument doc,
    PrintSettingsData settings,
    ReceiptTemplate t,
    ui.Image? logo, {
    void Function(ui.Canvas c)? background,
  }) {
    c.drawRect(
      ui.Rect.fromLTWH(0, 0, width, 100000),
      ui.Paint()..color = paper,
    );
    background?.call(c);
    _ink = mono ? ink : _c(ReceiptColorSlot.topInk);
    _inTop = true;
    _dividers.clear();
    final zig = design.edges == ReceiptEdges.zigzag ? base * 0.4 : 0.0;
    final gap = (base * 1.2).roundToDouble();
    var y = pad * 0.8 + zig;
    ui.Rect? logoRect;

    // الرأس: المحل يميناً، والعنوان والرقم والتاريخ يساراً.
    final storeW = (inner * 0.56).roundToDouble();
    final titleW = inner - storeW - gap;
    final storeX = width - pad - storeW;
    final store = settings.storeTitleLine.trim();
    final contact = [
      if (t.shows(ReceiptSection.storeExtras))
        ...settings.receiptStoreHeaderExtras,
      if (t.showStoreContact) ...settings.receiptStoreContactLines,
    ];
    final yStore = _inColumn(c, storeX, storeW, () {
      var sy = y;
      if (logo != null) {
        final scale = math.min(
          storeW * 0.5 / logo.width,
          base * 3.4 / logo.height,
        );
        final lw = logo.width * scale, lh = logo.height * scale;
        final r = ui.Rect.fromLTWH(width - lw, sy, lw, lh);
        logoRect = r.shift(ui.Offset(storeX, 0));
        c.drawImageRect(
          logo,
          ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          r,
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        sy += lh + base * 0.3;
      }
      final banner = design.header == ReceiptHeaderLayout.banner;
      final boxed = design.header == ReceiptHeaderLayout.boxed;
      final ip = banner || boxed ? base * 0.45 : 0.0;
      final painters = [
        if (store.isNotEmpty)
          _tp(
            store,
            size: base * 1.5,
            bold: true,
            color: banner ? _onAccent : (boxed ? _accentInk : null),
            maxWidth: width - ip * 2,
          ),
        for (final line in contact)
          _tp(
            line,
            size: base * 0.85,
            color: banner ? _onAccent : null,
            maxWidth: width - ip * 2,
          ),
      ];
      if (painters.isEmpty) return sy;
      final h = painters.fold<double>(0, (a, p) => a + p.height) + ip * 2;
      final box = ui.Rect.fromLTWH(0, sy, width, h);
      if (banner) c.drawRect(box, ui.Paint()..color = accent);
      if (boxed) _strokeRect(c, box);
      var ty = sy + ip;
      for (final p in painters) {
        p.paint(c, ui.Offset(width - ip - p.width, ty));
        ty += p.height;
      }
      return sy + h;
    });
    final yTitle = _inColumn(c, pad, titleW, () {
      var ty = y + base * 0.2;
      ty += _inverted(c, doc.title, ty, size: base * 1.2);
      ty += base * 0.35;
      final rows = [
        if (doc.number != null) ('الرقم', '${doc.number}'),
        ('التاريخ', DateFormat('yyyy/MM/dd  HH:mm', 'en').format(doc.date)),
        if ((doc.status ?? '').isNotEmpty) ('الحالة', doc.status!),
      ];
      for (final (l, v) in rows) {
        ty += _row(
          c,
          l,
          v,
          ty,
          size: base * 0.9,
          boldEnd: true,
          startColor: _mutedInk,
        );
      }
      return ty;
    });
    y = math.max(yStore, yTitle) + base * 0.5;
    _topEnd = y - base * 0.15;
    if (_hasTopShape) y += _edgeDepth;
    _ink = ink;
    _inTop = false;
    y += _dashed(c, y);

    // التفاصيل بعمودين، والصناديق البارزة في صف.
    final fields = [
      for (final f in doc.fields)
        if (f.section == null || t.shows(f.section!)) f,
    ];
    final highlights = [
      for (final h in doc.highlights)
        if (h.section == null || t.shows(h.section!)) h,
    ];
    if (fields.isNotEmpty || highlights.isNotEmpty) {
      y = _section(c, 'التفاصيل', y, (y) {
        if (design.info == ReceiptInfoStyle.grid ||
            design.info == ReceiptInfoStyle.tiles) {
          y = _fields(c, fields, y);
        } else if (fields.isNotEmpty) {
          final half = (fields.length + 1) ~/ 2;
          final colW = (inner - gap) / 2;
          final top = y;
          final a = _inColumn(
            c,
            width - pad - colW,
            colW,
            () => _fields(c, fields.sublist(0, half), top),
          );
          final b = _inColumn(
            c,
            pad,
            colW,
            () => _fields(c, fields.sublist(half), top),
          );
          y = math.max(a, b);
        }
        for (var i = 0; i < highlights.length; i += 3) {
          final row = highlights.skip(i).take(3).toList();
          final bw = (inner - gap * (row.length - 1)) / row.length;
          final top = y + base * 0.4;
          var bottom = top;
          for (var j = 0; j < row.length; j++) {
            final h = row[j];
            final x = width - pad - (j + 1) * bw - j * gap;
            bottom = math.max(
              bottom,
              _inColumn(c, x, bw, () => top + _boxed(c, h.label, h.value, top)),
            );
          }
          y = bottom;
        }
        return _loyalty(c, doc, t, y);
      });
      if (!_sectioned) y += _dashed(c, y);
    }

    // الأصناف بعرض الصفحة.
    if (doc.lines.isNotEmpty) {
      y = _section(
        c,
        'الأصناف والخدمات',
        y,
        (y) => switch (design.items) {
          ReceiptItemsStyle.table => _table(c, doc.lines, y),
          ReceiptItemsStyle.grid => _gridTable(c, doc.lines, y),
          _ => _simpleLines(c, doc.lines, y),
        },
      );
    }

    // الحساب يساراً، والملاحظات وQR يميناً.
    final totals = [
      for (final tot in doc.totals)
        if (tot.section == null || t.shows(tot.section!)) tot,
    ];
    final qr = doc.qrData;
    final showQr = t.showQr && qr != null && qr.isNotEmpty;
    y += base * 0.5;
    final totW = (inner * 0.5).roundToDouble();
    final sideW = inner - totW - gap;
    final top = y;
    final yTot = totals.isEmpty
        ? top
        : _inColumn(
            c,
            pad,
            totW,
            () => _section(
              c,
              'الحساب',
              top,
              (y) => _amountWords(c, doc, t, totals, _totalsBody(c, totals, y)),
            ),
          );
    final ySide = _inColumn(c, width - pad - sideW, sideW, () {
      var sy = top;
      for (final n in doc.notes) {
        // سطر التوقيع النصي يحلّ محله مربّع التوقيع أسفل الصفحة.
        if (_signatures(doc, t) != null && _isSignatureNote(n)) continue;
        sy += _text(c, n, sy, size: base * 0.9, align: TextAlign.start);
      }
      if (showQr) {
        if (doc.notes.isNotEmpty) sy += base * 0.4;
        final side = math.min(sideW * 0.55, base * 7).roundToDouble();
        sy += base * 0.3;
        _qrAt(
          c,
          qr,
          width - side - base * 0.3,
          sy,
          side,
          mono ? _white : paper,
        );
        sy += side + base * 0.3;
      }
      return sy;
    });
    y = math.max(yTot, ySide);
    y = _signatureBoxes(c, doc, t, y);

    // التذييل في أسفل الصفحة إن اتسعت.
    final footer = [
      settings.footerExtra.trim(),
      t.footer.trim(),
    ].where((e) => e.isNotEmpty).toList();
    // أوقات الدوام وحسابات التواصل: لا تُعدّ نص تذييل يُخفي سطر الشكر.
    final footerExtras = t.shows(ReceiptSection.storeExtras)
        ? settings.receiptStoreFooterExtras
        : const <String>[];
    double drawFooter(ui.Canvas cc, double fy) {
      fy += _dashed(cc, fy);
      if (t.thanksShown(hasFooterText: footer.isNotEmpty)) {
        fy += _text(
          cc,
          'شكراً لزيارتكم',
          fy,
          size: base,
          bold: true,
          align: TextAlign.center,
        );
      }
      for (final f in [...footer, ...footerExtras]) {
        fy += _text(cc, f, fy, size: base * 0.9, align: TextAlign.center);
      }
      return fy;
    }

    final rec = ui.PictureRecorder();
    final marks = _dividers.length;
    final footerH = drawFooter(ui.Canvas(rec), 0);
    rec.endRecording().dispose();
    _dividers.removeRange(marks, _dividers.length);
    var fy = y + base * 0.6;
    final pageH = _pageH;
    if (pageH != null) fy = math.max(fy, pageH - pad * 0.8 - zig - footerH);
    if (_zones) {
      _bottomStart = fy - base * 0.3;
      _ink = mono ? ink : _c(ReceiptColorSlot.bottomInk);
    }
    y = drawFooter(c, fy) + pad * 0.8 + zig;
    if (pageH != null && y < pageH) y = pageH;
    return (y, logoRect);
  }

  // ------------------------------------------------------------- الأجزاء

  /// اسم المحل وعنوانه حسب شكل الرأس. يُرجع y بعده.
  double _header(
    ui.Canvas c,
    PrintSettingsData settings,
    ReceiptTemplate t,
    double y, {
    double? boxTop,
  }) {
    final store = settings.storeTitleLine.trim();
    final contact = [
      if (t.shows(ReceiptSection.storeExtras))
        ...settings.receiptStoreHeaderExtras,
      if (t.showStoreContact) ...settings.receiptStoreContactLines,
    ];
    switch (design.header) {
      case ReceiptHeaderLayout.center:
        if (store.isNotEmpty) {
          y += _text(
            c,
            store,
            y,
            size: base * 1.4,
            bold: true,
            align: TextAlign.center,
          );
        }
        for (final line in contact) {
          y += _text(c, line, y, size: base * 0.85, align: TextAlign.center);
        }
        return y;
      case ReceiptHeaderLayout.boxed:
        final top = boxTop ?? y;
        if (boxTop == null) y += base * 0.5;
        _inset = base * 0.5;
        if (store.isNotEmpty) {
          y += _text(
            c,
            store,
            y,
            size: base * 1.45,
            bold: true,
            align: TextAlign.center,
            color: _accentInk,
          );
        }
        for (final line in contact) {
          y += _text(c, line, y, size: base * 0.85, align: TextAlign.center);
        }
        _inset = 0;
        y += base * 0.45;
        _strokeRect(c, ui.Rect.fromLTWH(pad, top, inner, y - top));
        return y;
      case ReceiptHeaderLayout.banner:
        _inset = base * 0.4;
        final painters = [
          if (store.isNotEmpty)
            _tp(
              store,
              size: base * 1.4,
              bold: true,
              color: _onAccent,
              align: TextAlign.center,
            ),
          for (final line in contact)
            _tp(
              line,
              size: base * 0.85,
              color: _onAccent,
              align: TextAlign.center,
            ),
        ];
        if (painters.isEmpty) {
          _inset = 0;
          return y;
        }
        final innerPad = base * 0.35;
        final h =
            painters.fold<double>(0, (a, p) => a + p.height) + innerPad * 2;
        c.drawRect(
          ui.Rect.fromLTWH(pad, y, inner, h),
          ui.Paint()..color = accent,
        );
        var ty = y + innerPad;
        for (final p in painters) {
          p.layout(minWidth: _w, maxWidth: _w);
          p.paint(c, ui.Offset(pad + _inset, ty));
          ty += p.height;
        }
        _inset = 0;
        return y + h;
    }
  }

  /// حقول الرأس حسب شكل المعلومات. يُرجع y بعدها.
  double _fields(ui.Canvas c, List<ReceiptField> fields, double y) {
    if (fields.isEmpty) return y;
    if (design.info == ReceiptInfoStyle.grid) return _gridFields(c, fields, y);
    if (design.info == ReceiptInfoStyle.tiles) return _tileFields(c, fields, y);
    final boxed = design.info == ReceiptInfoStyle.boxed;
    final top = y;
    if (boxed) {
      _inset = base * 0.45;
      y += base * 0.3;
    }
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final h = _row(
        c,
        f.label,
        f.value,
        y,
        boldEnd: f.bold,
        wrapEnd: true,
        startColor: muted,
      );
      if (design.info == ReceiptInfoStyle.zebra && i.isOdd) _shade(c, y, h);
      y += h;
    }
    if (boxed) {
      _inset = 0;
      y += base * 0.3;
      _strokeRect(c, ui.Rect.fromLTWH(pad, top, inner, y - top));
      y += base * 0.2;
    }
    return y;
  }

  /// الأصناف بالشكل البسيط (والمتناوب). يُرجع y بعدها.
  double _simpleLines(ui.Canvas c, List<ReceiptLine> lines, double y) {
    y += _row(
      c,
      'الصنف',
      'المبلغ',
      y,
      size: base * 0.85,
      boldStart: true,
      boldEnd: true,
    );
    y += _solid(c, y, 1.5);
    final marks = <ui.Offset>[];
    for (var i = 0; i < lines.length; i++) {
      final h = _line(c, lines[i], y);
      if (design.items == ReceiptItemsStyle.zebra && i.isOdd) _shade(c, y, h);
      if (_markerW > 0)
        marks.add(ui.Offset(width - pad - _markerW / 2, y + base * 0.68));
      y += h;
    }
    _markers(c, marks);
    y += _solid(c, y, 1.5);
    return y;
  }

  /// الأصناف جدولاً بثلاثة أعمدة: الصنف، الكمية، المبلغ. يُرجع y بعدها.
  double _table(ui.Canvas c, List<ReceiptLine> lines, double y) {
    // الورق الكبير يضيف عمود السعر.
    final wide = isSheet;
    final totalW = inner * (wide ? 0.22 : 0.30);
    final qtyW = inner * (wide ? 0.12 : 0.17);
    final priceW = wide ? inner * 0.18 : 0.0;
    final gap = base * 0.3;
    final nameW = inner - totalW - qtyW - priceW - gap * (wide ? 3 : 2);
    final right = width - pad;
    double row(
      String name,
      String qty,
      String total,
      double y, {
      bool head = false,
      String? price,
    }) {
      final sz = head ? base * 0.85 : base;
      final n = _tp(name, size: sz, bold: head, maxWidth: nameW);
      final q = _tp(
        qty,
        size: sz * 0.92,
        bold: head,
        maxWidth: qtyW,
        align: TextAlign.center,
      );
      final t = _tp(
        total,
        size: sz,
        bold: true,
        maxWidth: totalW,
        align: TextAlign.left,
      );
      q.layout(minWidth: qtyW, maxWidth: qtyW);
      final pr = wide
          ? _tp(
              price ?? '',
              size: sz * 0.92,
              bold: head,
              maxWidth: priceW,
              align: TextAlign.center,
            )
          : null;
      pr?.layout(minWidth: priceW, maxWidth: priceW);
      final h =
          [n.height, q.height, t.height, pr?.height ?? 0].reduce(math.max) +
          base * 0.2;
      if (head) {
        if (mono) {
          // الحرارية: بلا تظليل، والخط تحت الرأس يكفي.
        } else {
          c.drawRect(
            ui.Rect.fromLTWH(pad, y, inner, h),
            ui.Paint()
              ..color = _tint(0.16)
              ..blendMode = ui.BlendMode.multiply,
          );
        }
      }
      n.paint(c, ui.Offset(right - n.width, y + base * 0.1));
      q.paint(c, ui.Offset(right - nameW - gap - qtyW, y + base * 0.1));
      pr?.paint(
        c,
        ui.Offset(right - nameW - qtyW - gap * 2 - priceW, y + base * 0.1),
      );
      t.paint(c, ui.Offset(pad, y + base * 0.1));
      return h;
    }

    y += row('الصنف', 'الكمية', 'المبلغ', y, head: true, price: 'السعر');
    y += _solid(c, y, 1.5);
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final q = l.quantity ?? 1;
      final qty =
          '${_num(q)}${l.unit == null || l.unit!.isEmpty ? '' : ' ${l.unit}'}';
      final h = row(
        l.name,
        qty,
        _money(l.totalFils),
        y,
        price: l.unitPriceFils == null ? '' : _money(l.unitPriceFils!),
      );
      if (i < lines.length - 1) {
        c.drawRect(
          ui.Rect.fromLTWH(pad, y + h - 0.5, inner, 1),
          ui.Paint()..color = mono ? _black : _mix(paper, ink, 0.22),
        );
      }
      y += h;
    }
    y += _solid(c, y, 1.5);
    return y;
  }

  /// إطار حول الورقة أو زوايا.
  void _frame(ui.Canvas c, double height) {
    final inset = (pad * 0.35).roundToDouble();
    final r = ui.Rect.fromLTWH(
      inset,
      inset,
      width - inset * 2,
      height - inset * 2,
    );
    final paint = ui.Paint()
      ..color = accent
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = _stroke;
    switch (design.frame) {
      case ReceiptFrame.none:
        return;
      case ReceiptFrame.border:
        c.drawRect(r.deflate(_stroke / 2), paint);
      case ReceiptFrame.double:
        c
          ..drawRect(r.deflate(_stroke / 2), paint)
          ..drawRect(
            r.deflate(_stroke * 2.5),
            paint..strokeWidth = math.max(1.2, _stroke / 2),
          );
      case ReceiptFrame.ornate:
        c
          ..drawRect(r.deflate(_stroke / 2), paint)
          ..drawRect(
            r.deflate(_stroke * 2.5),
            ui.Paint()
              ..color = accent
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = math.max(1.2, _stroke / 2),
          );
        final k = base * 0.55;
        final fill = ui.Paint()..color = accent;
        for (final o in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          final cx = o.dx + (o.dx < width / 2 ? _stroke * 1.5 : -_stroke * 1.5);
          final cy =
              o.dy + (o.dy < height / 2 ? _stroke * 1.5 : -_stroke * 1.5);
          c.drawPath(
            ui.Path()
              ..moveTo(cx, cy - k)
              ..lineTo(cx + k, cy)
              ..lineTo(cx, cy + k)
              ..lineTo(cx - k, cy)
              ..close(),
            fill,
          );
        }
      case ReceiptFrame.corners:
        final l = base * 1.6;
        final p = ui.Path();
        final rr = r.deflate(_stroke / 2);
        p
          ..moveTo(rr.left, rr.top + l)
          ..lineTo(rr.left, rr.top)
          ..lineTo(rr.left + l, rr.top)
          ..moveTo(rr.right - l, rr.top)
          ..lineTo(rr.right, rr.top)
          ..lineTo(rr.right, rr.top + l)
          ..moveTo(rr.right, rr.bottom - l)
          ..lineTo(rr.right, rr.bottom)
          ..lineTo(rr.right - l, rr.bottom)
          ..moveTo(rr.left + l, rr.bottom)
          ..lineTo(rr.left, rr.bottom)
          ..lineTo(rr.left, rr.bottom - l);
        c.drawPath(p, paint);
    }
  }

  // ------------------------------------------------------------- عناصر

  /// لون العنوان مخففاً على الورقة (للتظليل).
  ui.Color _tint(double t) => _mix(_white, accent, t);

  static ui.Color _mix(ui.Color a, ui.Color b, double t) =>
      ui.Color.lerp(a, b, t)!;

  /// تظليل خلف سطر مرسوم: الضرب (multiply) يُبقي النص الأسود أسود. لا شيء
  /// على الحرارية (الرمادي الفاتح يصير أبيض أصلاً).
  void _shade(ui.Canvas c, double y, double h) {
    if (mono) return;
    c.drawRect(
      ui.Rect.fromLTWH(pad, y - base * 0.04, inner, h + base * 0.02),
      ui.Paint()
        ..color = _tint(0.09)
        ..blendMode = ui.BlendMode.multiply,
    );
  }

  void _strokeRect(ui.Canvas c, ui.Rect r) {
    c.drawRect(
      r.deflate(_stroke / 2),
      ui.Paint()
        ..color = accent
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
  }

  TextPainter _tp(
    String s, {
    required double size,
    bool bold = false,
    ui.Color? color,
    TextAlign align = TextAlign.start,
    double? maxWidth,
  }) {
    color ??= _ink;
    final tp = TextPainter(
      text: TextSpan(
        text: isolateNumbers(s),
        style: TextStyle(
          fontFamily: family,
          // بعض الخطوط المضمّنة بلا أرقام لاتينية أو رموز؛ تجوال يكملها.
          fontFamilyFallback: const ['Tajawal'],
          fontSize: size,
          height: 1.35,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: color,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: align,
    );
    tp.layout(maxWidth: maxWidth ?? _w);
    return tp;
  }

  /// فقرة بعرض الإيصال. يُرجع الارتفاع.
  double _text(
    ui.Canvas c,
    String s,
    double y, {
    required double size,
    bool bold = false,
    TextAlign align = TextAlign.start,
    ui.Color? color,
  }) {
    final tp = _tp(s, size: size, bold: bold, align: align, color: color);
    // تمدد إلى كامل العرض ليصح المحاذاة في المنتصف/البداية.
    tp.layout(minWidth: _w, maxWidth: _w);
    tp.paint(c, ui.Offset(pad + _inset, y));
    return tp.height;
  }

  /// صف: نص في البداية (يمين) ونص في النهاية (يسار).
  double _row(
    ui.Canvas c,
    String start,
    String end,
    double y, {
    double? size,
    bool boldStart = false,
    bool boldEnd = false,
    bool wrapEnd = false,
    ui.Color? startColor,
  }) {
    final sz = size ?? base;
    final w = _w;
    final right = width - pad - _inset;
    final left = pad + _inset;
    final a = _tp(
      start,
      size: sz,
      bold: boldStart,
      maxWidth: w * 0.5,
      color: startColor,
    );
    final gap = base * 0.6;
    final b = _tp(
      end,
      size: sz,
      bold: boldEnd,
      maxWidth: w - a.width - gap,
      align: TextAlign.left,
    );
    if (!wrapEnd && b.width + a.width + gap > w) {
      // لا يتسع: القيمة تحت العنوان.
      a.paint(c, ui.Offset(right - a.width, y));
      final b2 = _tp(end, size: sz, bold: boldEnd, align: TextAlign.left);
      b2.paint(c, ui.Offset(left, y + a.height));
      return a.height + b2.height;
    }
    a.paint(c, ui.Offset(right - a.width, y));
    b.paint(c, ui.Offset(left, y));
    return math.max(a.height, b.height);
  }

  double _line(ui.Canvas c, ReceiptLine l, double y) {
    final q = l.quantity ?? 1;
    final simple = (q - 1).abs() < 1e-9 && l.unit == null;
    final total = _money(l.totalFils);
    final mw = _markerW;
    if (simple) {
      final t = _tp(total, size: base, bold: true);
      final name = _tp(
        l.name,
        size: base,
        maxWidth: inner - t.width - base * 0.6 - mw,
      );
      name.paint(c, ui.Offset(width - pad - mw - name.width, y));
      t.paint(c, ui.Offset(pad, y));
      return math.max(name.height, t.height) + base * 0.15;
    }
    final name = _tp(l.name, size: base, maxWidth: inner - mw);
    name.paint(c, ui.Offset(width - pad - mw - name.width, y));
    var h = name.height;
    final qty =
        '${_num(q)}${l.unit == null || l.unit!.isEmpty ? '' : ' ${l.unit}'}'
        '${l.unitPriceFils == null ? '' : ' × ${_money(l.unitPriceFils!)}'}';
    h += _row(c, qty, total, y + h, size: base * 0.9, boldEnd: true);
    return h + base * 0.15;
  }

  double get _stroke => math.max(2.0, base / 9);

  ui.Color get _onAccent => _c(ReceiptColorSlot.onAccent, light: true);

  static bool _filled(ReceiptHeaderShape s) =>
      s == ReceiptHeaderShape.filled || s == ReceiptHeaderShape.ribbon;

  /// أطراف الشريطة: مثلثان بلون الورقة يُقصّان من طرفي الشريط.
  void _notches(ui.Canvas c, ui.Rect r) {
    final d = r.height * 0.32;
    final p = ui.Paint()..color = paper;
    c.drawPath(
      ui.Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left + d, r.center.dy)
        ..lineTo(r.left, r.bottom)
        ..close()
        ..moveTo(r.right, r.top)
        ..lineTo(r.right - d, r.center.dy)
        ..lineTo(r.right, r.bottom)
        ..close(),
      p,
    );
  }

  /// العنوان حسب الشكل المختار.
  double _inverted(ui.Canvas c, String s, double y, {required double size}) {
    final shape = design.title;
    final filled = _filled(shape);
    final tp = _tp(
      s,
      size: size,
      bold: true,
      color: filled ? _onAccent : _accentInk,
      align: TextAlign.center,
    );
    final h = tp.height + base * 0.4;
    switch (shape) {
      case ReceiptHeaderShape.filled:
        c.drawRect(
          ui.Rect.fromLTWH(pad, y, inner, h),
          ui.Paint()..color = accent,
        );
      case ReceiptHeaderShape.ribbon:
        final r = ui.Rect.fromLTWH(pad, y, inner, h);
        c.drawRect(r, ui.Paint()..color = accent);
        _notches(c, r);
      case ReceiptHeaderShape.outlined:
        c.drawRect(
          ui.Rect.fromLTWH(
            pad + _stroke / 2,
            y + _stroke / 2,
            inner - _stroke,
            h - _stroke,
          ),
          ui.Paint()
            ..color = _accentInk
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = _stroke,
        );
      case ReceiptHeaderShape.plain:
        c.drawRect(
          ui.Rect.fromLTWH(
            pad + inner * 0.2,
            y + h - _stroke,
            inner * 0.6,
            _stroke,
          ),
          ui.Paint()..color = _accentInk,
        );
    }
    tp.layout(minWidth: inner, maxWidth: inner);
    tp.paint(c, ui.Offset(pad, y + base * 0.2));
    return h;
  }

  /// الإجمالي حسب الشكل المختار.
  double _invertedRow(ui.Canvas c, String label, String value, double y) {
    final shape = design.totals;
    final filled = _filled(shape);
    final fg = filled ? _onAccent : accent;
    final innerPad = base * 0.4;
    var a = _tp(label, size: base * 1.1, bold: true, color: fg);
    var b = _tp(value, size: base * 1.5, bold: true, color: fg);
    // عمود ضيق (الصفحة الكبيرة): يصغر النص بدل أن يتراكب.
    final room =
        inner -
        innerPad * 2 -
        (shape == ReceiptHeaderShape.ribbon ? base * 1.2 : 0) -
        base * 0.6;
    if (a.width + b.width > room) {
      final f = room / (a.width + b.width);
      a = _tp(label, size: base * 1.1 * f, bold: true, color: fg);
      b = _tp(value, size: base * 1.5 * f, bold: true, color: fg);
    }
    final h = math.max(a.height, b.height) + innerPad;
    switch (shape) {
      case ReceiptHeaderShape.filled:
        c.drawRect(
          ui.Rect.fromLTWH(pad, y, inner, h),
          ui.Paint()..color = accent,
        );
      case ReceiptHeaderShape.ribbon:
        final r = ui.Rect.fromLTWH(pad, y, inner, h);
        c.drawRect(r, ui.Paint()..color = accent);
        _notches(c, r);
      case ReceiptHeaderShape.outlined:
        c.drawRect(
          ui.Rect.fromLTWH(
            pad + _stroke / 2,
            y + _stroke / 2,
            inner - _stroke,
            h - _stroke,
          ),
          ui.Paint()
            ..color = accent
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = _stroke,
        );
      case ReceiptHeaderShape.plain:
        final p = ui.Paint()..color = accent;
        c.drawRect(ui.Rect.fromLTWH(pad, y, inner, _stroke), p);
        c.drawRect(ui.Rect.fromLTWH(pad, y + h - _stroke, inner, _stroke), p);
    }
    final notch = shape == ReceiptHeaderShape.ribbon ? h * 0.32 : 0.0;
    a.paint(
      c,
      ui.Offset(
        width - pad - innerPad - notch - a.width,
        y + (h - a.height) / 2,
      ),
    );
    b.paint(c, ui.Offset(pad + innerPad + notch, y + (h - b.height) / 2));
    return h;
  }

  double _boxed(ui.Canvas c, String label, String value, double y) {
    final stroke = _stroke;
    final filled = design.highlight == ReceiptHighlightStyle.filled;
    final l = _tp(
      label,
      size: base * 0.9,
      align: TextAlign.center,
      color: filled ? _onAccent : null,
    );
    final v = _tp(
      value,
      size: base * 1.45,
      bold: true,
      align: TextAlign.center,
      color: filled ? _onAccent : accent,
    );
    final h = l.height + v.height + base * 0.5;
    if (filled) {
      c.drawRect(
        ui.Rect.fromLTWH(pad, y, inner, h),
        ui.Paint()..color = accent,
      );
    } else {
      c.drawRect(
        ui.Rect.fromLTWH(
          pad + stroke / 2,
          y + stroke / 2,
          inner - stroke,
          h - stroke,
        ),
        ui.Paint()
          ..color = accent
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
    l.layout(minWidth: inner, maxWidth: inner);
    v.layout(minWidth: inner, maxWidth: inner);
    l.paint(c, ui.Offset(pad, y + base * 0.25));
    v.paint(c, ui.Offset(pad, y + base * 0.25 + l.height));
    return h + base * 0.3;
  }

  double _dashed(ui.Canvas c, double y) {
    final p = ui.Paint()..color = _ink;
    final dash = base * 0.45;
    final my = y + base * 0.35;
    _dividers.add(my);
    for (var x = pad; x < width - pad; x += dash * 2) {
      c.drawRect(
        ui.Rect.fromLTWH(x, my, math.min(dash, width - pad - x), 2),
        p,
      );
    }
    return base * 0.8;
  }

  double _solid(ui.Canvas c, double y, double thickness) {
    c.drawRect(
      ui.Rect.fromLTWH(pad, y + base * 0.15, inner, thickness),
      ui.Paint()..color = accent,
    );
    return base * 0.35 + thickness;
  }

  void _qr(ui.Canvas c, String data, double x, double y, double side) {
    final p = ui.Paint()..color = _black;
    for (final e in Barcode.qrCode().make(data, width: side, height: side)) {
      if (e is BarcodeBar && e.black) {
        // تقريب لعدد صحيح من النقاط حتى تكون المربعات حادة.
        c.drawRect(
          ui.Rect.fromLTRB(
            (x + e.left).roundToDouble(),
            (y + e.top).roundToDouble(),
            (x + e.right).roundToDouble(),
            (y + e.bottom).roundToDouble(),
          ),
          p,
        );
      }
    }
  }

  // -------------------------------------------------------- أجزاء الهياكل

  /// هل للأقسام عناوين أو صناديق (فتُترك الفواصل المتقطعة)؟
  bool get _sectioned =>
      design.sectionBox != ReceiptSectionBox.none ||
      design.sectionTitles != ReceiptSectionTitles.none;

  /// قسم بعنوانه وصندوقه حسب التصميم. [body] يرسم المحتوى ويُرجع y بعده.
  double _section(
    ui.Canvas c,
    String title,
    double y,
    double Function(double) body,
  ) {
    if (!_sectioned) return body(y);
    final box = design.sectionBox;
    final titles = design.sectionTitles;
    y += base * 0.2;
    // اللسان يقف فوق الصندوق، والباقي عنوان ثم محتوى.
    if (titles != ReceiptSectionTitles.none) y += _sectionTitle(c, title, y);
    final top = y;
    if (box != ReceiptSectionBox.none) y += base * 0.3;
    y = body(y);
    if (box != ReceiptSectionBox.none) {
      y += base * 0.15;
      final r = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTRB(pad - base * 0.3, top, width - pad + base * 0.3, y),
        ui.Radius.circular(
          box == ReceiptSectionBox.card ? base * 0.5 : base * 0.15,
        ),
      );
      if (box == ReceiptSectionBox.card && !mono) {
        c.drawRRect(
          r,
          ui.Paint()
            ..color = _tint(0.07)
            ..blendMode = ui.BlendMode.multiply,
        );
      }
      c.drawRRect(
        r,
        ui.Paint()
          ..color = mono ? _black : _mix(paper, accent, 0.55)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = mono ? 2 : math.max(1.5, base / 14),
      );
      _dividers.add(y + base * 0.2);
      y += base * 0.2;
    }
    return y;
  }

  /// عنوان قسم. يُرجع ارتفاعه.
  double _sectionTitle(ui.Canvas c, String s, double y) {
    final right = width - pad;
    switch (design.sectionTitles) {
      case ReceiptSectionTitles.none:
        return 0;
      case ReceiptSectionTitles.line:
        final tp = _tp(s, size: base * 0.95, bold: true, color: accent);
        tp.paint(c, ui.Offset(right - tp.width, y));
        final ly = y + tp.height / 2;
        c.drawRect(
          ui.Rect.fromLTRB(
            pad,
            ly - 0.75,
            right - tp.width - base * 0.4,
            ly + 0.75,
          ),
          ui.Paint()..color = accent,
        );
        return tp.height + base * 0.15;
      case ReceiptSectionTitles.pill:
      case ReceiptSectionTitles.tab:
      case ReceiptSectionTitles.ribbon:
        final tp = _tp(s, size: base * 0.85, bold: true, color: _onAccent);
        final ph = tp.height + base * 0.2;
        final pw = tp.width + base * 1.2;
        final kind = design.sectionTitles;
        final dx = kind == ReceiptSectionTitles.tab ? base * 0.5 : 0.0;
        final r = ui.Rect.fromLTWH(right - pw - dx, y, pw, ph);
        final paint = ui.Paint()..color = accent;
        switch (kind) {
          case ReceiptSectionTitles.pill:
            c.drawRRect(
              ui.RRect.fromRectAndRadius(r, ui.Radius.circular(ph / 2)),
              paint,
            );
          case ReceiptSectionTitles.tab:
            c.drawRRect(
              ui.RRect.fromRectAndCorners(
                r,
                topLeft: ui.Radius.circular(base * 0.35),
                topRight: ui.Radius.circular(base * 0.35),
              ),
              paint,
            );
          default:
            // شريطة: تمتد لعرض الورقة بطرف مشقوق.
            final band = ui.Rect.fromLTRB(pad, y, right, y + ph);
            c.drawRect(band, ui.Paint()..color = _mix(paper, accent, 0.18));
            c.drawRect(r, paint);
            _notches(
              c,
              ui.Rect.fromLTRB(
                r.left - ph * 0.32,
                r.top,
                r.left + ph * 0.32,
                r.bottom,
              ),
            );
        }
        tp.paint(c, ui.Offset(r.right - base * 0.6 - tp.width, y + base * 0.1));
        return ph + (kind == ReceiptSectionTitles.tab ? 0 : base * 0.25);
    }
  }

  /// عرض عمود العلامات قبل الأصناف.
  double get _markerW =>
      design.itemMarker != ReceiptItemMarker.none &&
          (design.items == ReceiptItemsStyle.simple ||
              design.items == ReceiptItemsStyle.zebra)
      ? base * 1.3
      : 0;

  void _markers(ui.Canvas c, List<ui.Offset> at) {
    if (at.isEmpty) return;
    final paint = ui.Paint()..color = accent;
    final r = base * 0.32;
    switch (design.itemMarker) {
      case ReceiptItemMarker.none:
        return;
      case ReceiptItemMarker.timeline:
        c.drawRect(
          ui.Rect.fromLTRB(
            at.first.dx - 1,
            at.first.dy,
            at.first.dx + 1,
            at.last.dy,
          ),
          paint,
        );
        for (final o in at) {
          c
            ..drawCircle(o, r, ui.Paint()..color = paper)
            ..drawCircle(
              o,
              r,
              ui.Paint()
                ..color = accent
                ..style = ui.PaintingStyle.stroke
                ..strokeWidth = 2,
            )
            ..drawCircle(o, r * 0.45, paint);
        }
      case ReceiptItemMarker.dot:
        for (final o in at) {
          c.drawCircle(o, r * 0.6, paint);
        }
      case ReceiptItemMarker.number:
        for (var i = 0; i < at.length; i++) {
          c.drawCircle(at[i], r * 1.25, paint);
          final tp = _tp(
            '${i + 1}',
            size: base * 0.62,
            bold: true,
            color: _onAccent,
          );
          tp.paint(c, at[i] - ui.Offset(tp.width / 2, tp.height / 2));
        }
      case ReceiptItemMarker.check:
        for (final o in at) {
          final b = ui.Rect.fromCenter(
            center: o,
            width: r * 2.2,
            height: r * 2.2,
          );
          c.drawRRect(
            ui.RRect.fromRectAndRadius(b, ui.Radius.circular(r * 0.4)),
            paint,
          );
          c.drawPath(
            ui.Path()
              ..moveTo(b.left + b.width * 0.22, b.top + b.height * 0.52)
              ..lineTo(b.left + b.width * 0.42, b.top + b.height * 0.72)
              ..lineTo(b.left + b.width * 0.8, b.top + b.height * 0.3),
            ui.Paint()
              ..color = _onAccent
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = math.max(2, base / 10)
              ..strokeCap = ui.StrokeCap.round,
          );
        }
    }
  }

  /// الإجمالي داخل ختم دائري بحافة مسنّنة.
  double _seal(ui.Canvas c, String label, String value, double y) {
    final v = _tp(
      value,
      size: base * 1.35,
      bold: true,
      color: accent,
      align: TextAlign.center,
    );
    final l = _tp(
      label,
      size: base * 0.8,
      bold: true,
      color: accent,
      align: TextAlign.center,
    );
    final rad = math
        .max(math.max(v.width, l.width) / 2 + base * 0.9, base * 3.4)
        .clamp(0.0, inner / 2);
    final center = ui.Offset(width / 2, y + rad + base * 0.2);
    final teeth = 36;
    final path = ui.Path();
    for (var i = 0; i <= teeth * 2; i++) {
      final a = i / (teeth * 2) * math.pi * 2;
      final rr = i.isEven ? rad : rad - base * 0.28;
      final pt = center + ui.Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    if (!mono) {
      c.drawPath(path, ui.Paint()..color = _mix(paper, accent, 0.12));
    }
    c
      ..drawPath(
        path,
        ui.Paint()
          ..color = accent
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = _stroke,
      )
      ..drawCircle(
        center,
        rad - base * 0.55,
        ui.Paint()
          ..color = accent
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, _stroke * 0.6),
      );
    l.paint(
      c,
      ui.Offset(center.dx - l.width / 2, center.dy - (l.height + v.height) / 2),
    );
    v.paint(
      c,
      ui.Offset(
        center.dx - v.width / 2,
        center.dy - (l.height + v.height) / 2 + l.height,
      ),
    );
    return rad * 2 + base * 0.4;
  }

  /// الإجمالي برقم كبير وخطوط رفيعة.
  double _bigTotal(ui.Canvas c, String label, String value, double y) {
    final p = ui.Paint()..color = accent;
    c.drawRect(ui.Rect.fromLTWH(pad, y, inner, 1.5), p);
    final l = _tp(label, size: base * 0.9, bold: true, color: muted);
    l.paint(c, ui.Offset(width - pad - l.width, y + base * 0.3));
    final v = _tp(
      value,
      size: base * 2.5,
      bold: true,
      color: accent,
      maxWidth: inner,
    );
    v.paint(c, ui.Offset(pad, y + base * 0.3 + l.height));
    final h = base * 0.3 + l.height + v.height + base * 0.1;
    c.drawRect(ui.Rect.fromLTWH(pad, y + h, inner, 1.5), p);
    return h + base * 0.2;
  }

  /// الحقول مربعات: عنوان صغير وقيمة بارزة، عمودان (ثلاثة على الورق الكبير).
  double _tileFields(ui.Canvas c, List<ReceiptField> fields, double y) {
    final cols = isSheet ? 3 : 2;
    final gap = base * 0.35;
    final tw = (inner - gap * (cols - 1)) / cols;
    final cp = base * 0.3;
    for (var i = 0; i < fields.length; i += cols) {
      final row = fields.skip(i).take(cols).toList();
      final painted = [
        for (final f in row)
          (
            _tp(
              f.label,
              size: base * 0.75,
              color: muted,
              maxWidth: tw - cp * 2,
            ),
            _tp(f.value, size: base * 0.95, bold: true, maxWidth: tw - cp * 2),
          ),
      ];
      final h =
          painted.map((p) => p.$1.height + p.$2.height).reduce(math.max) +
          cp * 2;
      for (var j = 0; j < row.length; j++) {
        final x = width - pad - (j + 1) * tw - j * gap;
        final r = ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(x, y, tw, h),
          ui.Radius.circular(base * 0.35),
        );
        if (!mono) {
          c.drawRRect(
            r,
            ui.Paint()
              ..color = _tint(0.09)
              ..blendMode = ui.BlendMode.multiply,
          );
        }
        c.drawRRect(
          r,
          ui.Paint()
            ..color = mono ? _black : _mix(paper, accent, 0.45)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = mono ? 1.5 : 1.2,
        );
        final (l, v) = painted[j];
        l.paint(c, ui.Offset(x + tw - cp - l.width, y + cp));
        v.paint(c, ui.Offset(x + tw - cp - v.width, y + cp + l.height));
      }
      y += h + gap;
    }
    return y;
  }

  /// قسيمة قابلة للقطع: خط قطع ثم الرقم والإجمالي والموعد القادم.
  double _stub(
    ui.Canvas c,
    ReceiptDocument doc,
    List<ReceiptTotal> totals,
    List<ReceiptHighlight> highlights,
    double y,
  ) {
    y += base * 0.6;
    final cut = _tp('✂', size: base, color: _ink);
    final my = y + cut.height / 2;
    final dash = base * 0.35;
    final p = ui.Paint()..color = _ink;
    for (var x = pad; x < width - pad - cut.width - base * 0.3; x += dash * 2) {
      c.drawRect(ui.Rect.fromLTWH(x, my - 1, dash, 2), p);
    }
    cut.paint(c, ui.Offset(width - pad - cut.width, y));
    _dividers.add(my);
    y += cut.height + base * 0.3;
    final total =
        totals.where((t) => t.emphasis).firstOrNull ?? totals.lastOrNull;
    final rows = <(String, String)>[
      if (doc.number != null) ('رقم', '${doc.number}'),
      if (total != null) (total.label, _money(total.fils)),
      for (final h in highlights.take(1)) (h.label, h.value),
    ];
    if (rows.isEmpty) return y;
    final top = y;
    _inset = base * 0.4;
    y += base * 0.25;
    for (final (a, b) in rows) {
      y += _row(c, a, b, y, size: base * 0.9, boldEnd: true, startColor: muted);
    }
    _inset = 0;
    y += base * 0.25;
    c.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTRB(pad, top, width - pad, y),
        ui.Radius.circular(base * 0.3),
      ),
      ui.Paint()
        ..color = accent
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = _stroke * 0.8,
    );
    return y;
  }

  /// حواف الورقة: أسنان أعلى وأسفل، أو ثقوب جانبية عند الفواصل.
  void _edgeDecor(ui.Canvas c, double height) {
    switch (design.edges) {
      case ReceiptEdges.none:
      case ReceiptEdges.stub:
        return;
      case ReceiptEdges.zigzag:
        final tooth = base * 0.6;
        final n = math.max(6, (width / tooth).round());
        final p = ui.Paint()..color = accent;
        for (final top in [true, false]) {
          final path = ui.Path();
          final y0 = top ? 0.0 : height;
          final dy = top ? base * 0.3 : -base * 0.3;
          path.moveTo(0, y0);
          for (var i = 0; i < n; i++) {
            path
              ..lineTo(width * (i + 0.5) / n, y0 + dy)
              ..lineTo(width * (i + 1) / n, y0);
          }
          path.close();
          c.drawPath(path, p);
        }
      case ReceiptEdges.notches:
        final hole = mono ? _white : ui.Color.lerp(paper, _black, 0.12)!;
        final r = base * 0.45;
        final line = ui.Paint()
          ..color = mono ? _black : accent
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (final y in _dividers) {
          for (final x in [0.0, width]) {
            c
              ..drawCircle(ui.Offset(x, y), r, ui.Paint()..color = hole)
              ..drawCircle(ui.Offset(x, y), r, line);
          }
        }
    }
  }

  /// الشريط الجانبي على الحافة اليمنى، واسم المحل فيه عمودياً.
  void _sideStrip(
    ui.Canvas c,
    double x,
    double w,
    double h,
    PrintSettingsData settings,
  ) {
    c.drawRect(ui.Rect.fromLTWH(x, 0, w, h), ui.Paint()..color = accent);
    final name = settings.storeTitleLine.trim();
    if (name.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Tajawal'],
          fontSize: math.min(w * 0.55, base),
          fontWeight: FontWeight.w700,
          color: _onAccent,
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(10, h - base * 2));
    c
      ..save()
      ..translate(x + (w - tp.height) / 2 + tp.height, base)
      ..rotate(math.pi / 2);
    tp.paint(c, ui.Offset.zero);
    c.restore();
  }

  // ------------------------------------------------------------ الجداول

  double get _gridLine => mono ? 2.0 : math.max(1.2, base / 14);
  ui.Color get _gridColor => mono ? _black : _c(ReceiptColorSlot.grid);

  /// جدول بخطوط كاملة: [cols] نسب الأعمدة من اليمين، [rows] الخلايا.
  /// الصف الأول رأس إن كان [head]. يُرجع y بعده.
  double _grid(
    ui.Canvas c,
    double y, {
    required List<double> cols,
    required List<List<(String, TextAlign, bool, ui.Color?)>> rows,
    bool head = true,
    Set<int> shadedCols = const {},
  }) {
    final lw = _gridLine;
    final cp = base * 0.22;
    final widths = [for (final f in cols) inner * f];
    final right = width - pad;
    final top = y;
    final rowEdges = <double>[y];
    final headBg = mono ? _black : _c(ReceiptColorSlot.tableHead);
    final headInk = mono ? _white : _c(ReceiptColorSlot.tableHeadInk);
    for (var r = 0; r < rows.length; r++) {
      final isHead = head && r == 0;
      final painters = <TextPainter>[];
      for (var i = 0; i < widths.length; i++) {
        final (text, align, bold, color) = rows[r][i];
        final w = math.max(8.0, widths[i] - cp * 2);
        final tp = _tp(
          text,
          size: isHead ? base * 0.85 : base * 0.95,
          bold: bold || isHead,
          color: isHead ? headInk : color,
          align: align,
          maxWidth: w,
        );
        tp.layout(minWidth: w, maxWidth: w);
        painters.add(tp);
      }
      final h = painters.map((p) => p.height).reduce(math.max) + cp * 1.6;
      var x = right;
      for (var i = 0; i < widths.length; i++) {
        final cell = ui.Rect.fromLTWH(x - widths[i], y, widths[i], h);
        if (isHead) {
          c.drawRect(cell, ui.Paint()..color = headBg);
        } else if (shadedCols.contains(i) && !mono) {
          c.drawRect(
            cell,
            ui.Paint()
              ..color = _tint(0.08)
              ..blendMode = ui.BlendMode.multiply,
          );
        }
        painters[i].paint(c, ui.Offset(x - widths[i] + cp, y + cp * 0.8));
        x -= widths[i];
      }
      y += h;
      rowEdges.add(y);
    }
    final p = ui.Paint()..color = _gridColor;
    for (final e in rowEdges) {
      c.drawRect(ui.Rect.fromLTWH(pad, e - lw / 2, inner, lw), p);
    }
    var x = right;
    c.drawRect(ui.Rect.fromLTWH(x - lw / 2, top, lw, y - top), p);
    for (final w in widths) {
      x -= w;
      c.drawRect(ui.Rect.fromLTWH(x - lw / 2, top, lw, y - top), p);
    }
    return y + base * 0.35;
  }

  /// الأصناف جدولاً بخطوط بين كل صف وعمود. الورق الكبير يضيف عمود السعر.
  double _gridTable(ui.Canvas c, List<ReceiptLine> lines, double y) {
    final wide = isSheet;
    String qty(ReceiptLine l) {
      final q = l.quantity ?? 1;
      return '${_num(q)}${l.unit == null || l.unit!.isEmpty ? '' : ' ${l.unit}'}';
    }

    const s = TextAlign.start, m = TextAlign.center, e = TextAlign.left;
    return _grid(
      c,
      y,
      cols: wide ? const [0.46, 0.14, 0.2, 0.2] : const [0.48, 0.2, 0.32],
      rows: [
        [
          ('الصنف', s, true, null),
          ('الكمية', m, true, null),
          if (wide) ('السعر', m, true, null),
          ('المبلغ', m, true, null),
        ],
        for (final l in lines)
          [
            (l.name, s, false, null),
            (qty(l), m, false, null),
            if (wide)
              (
                l.unitPriceFils == null ? '' : _money(l.unitPriceFils!),
                m,
                false,
                null,
              ),
            (_money(l.totalFils), e, true, null),
          ],
      ],
    );
  }

  /// حقول الرأس جدولاً: عنوان وقيمة، وعلى الورق الكبير زوجان في الصف.
  double _gridFields(ui.Canvas c, List<ReceiptField> fields, double y) {
    final pairs = isSheet ? 2 : 1;
    final rows = <List<(String, TextAlign, bool, ui.Color?)>>[];
    for (var i = 0; i < fields.length; i += pairs) {
      final row = <(String, TextAlign, bool, ui.Color?)>[];
      for (var j = 0; j < pairs; j++) {
        final f = i + j < fields.length ? fields[i + j] : null;
        row
          ..add((f?.label ?? '', TextAlign.start, false, muted))
          ..add((f?.value ?? '', TextAlign.start, f?.bold ?? false, null));
      }
      rows.add(row);
    }
    final out = _grid(
      c,
      y,
      cols: pairs == 2 ? const [0.18, 0.32, 0.18, 0.32] : const [0.36, 0.64],
      rows: rows,
      head: false,
      shadedCols: pairs == 2 ? const {0, 2} : const {0},
    );
    return out;
  }

  // ---------------------------------------------------------------- QR

  /// شعار المحل لوسط رمز QR (إن طُلب).
  ui.Image? _qrLogo;

  /// رمز QR بالشكل واللون المختارين، والشعار في وسطه إن طُلب (بتصحيح
  /// أخطاء عالٍ حتى يبقى مقروءاً).
  void _qrStyled(ui.Canvas c, String data, double x, double y, double side) {
    final logo = _qrLogo;
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: logo != null
          ? QrErrorCorrectLevel.H
          : QrErrorCorrectLevel.L,
    );
    final img = QrImage(code);
    final n = code.moduleCount;
    final m = side / n;
    final color = mono ? _black : _c(ReceiptColorSlot.qr);
    final paint = ui.Paint()..color = color;
    // منطقة الشعار بوحدات كاملة في الوسط (نحو 22% من العرض).
    var lm = (n * 0.22).ceil();
    if ((n - lm).isOdd) lm++;
    final l0 = (n - lm) ~/ 2;
    bool inLogo(int r, int col) =>
        logo != null && r >= l0 && r < l0 + lm && col >= l0 && col < l0 + lm;
    bool inEye(int r, int col) =>
        (r < 7 && col < 7) ||
        (r < 7 && col >= n - 7) ||
        (r >= n - 7 && col < 7);
    bool dark(int r, int col) =>
        r >= 0 &&
        col >= 0 &&
        r < n &&
        col < n &&
        img.isDark(r, col) &&
        !inEye(r, col) &&
        !inLogo(r, col);

    ui.Rect cell(int r, int col) =>
        ui.Rect.fromLTWH(x + col * m, y + r * m, m, m);
    final module = design.qrStyle.module;
    if (module == ReceiptQrModule.vbar || module == ReceiptQrModule.hbar) {
      final vertical = module == ReceiptQrModule.vbar;
      for (var a = 0; a < n; a++) {
        var b = 0;
        while (b < n) {
          bool on(int k) => vertical ? dark(k, a) : dark(a, k);
          if (!on(b)) {
            b++;
            continue;
          }
          final start = b;
          while (b < n && on(b)) {
            b++;
          }
          final first = vertical ? cell(start, a) : cell(a, start);
          final last = vertical ? cell(b - 1, a) : cell(a, b - 1);
          final r = first.expandToInclude(last).deflate(m * 0.1);
          c.drawRRect(
            ui.RRect.fromRectAndRadius(r, ui.Radius.circular(m * 0.4)),
            paint,
          );
        }
      }
    } else {
      for (var r = 0; r < n; r++) {
        for (var col = 0; col < n; col++) {
          if (!dark(r, col)) continue;
          final b = cell(r, col);
          switch (module) {
            case ReceiptQrModule.square:
              c.drawRect(
                ui.Rect.fromLTRB(
                  b.left.roundToDouble(),
                  b.top.roundToDouble(),
                  b.right.roundToDouble(),
                  b.bottom.roundToDouble(),
                ),
                paint,
              );
            case ReceiptQrModule.dot:
              c.drawCircle(b.center, m * 0.47, paint);
            case ReceiptQrModule.rounded:
              c.drawRRect(
                ui.RRect.fromRectAndRadius(
                  b.deflate(m * 0.04),
                  ui.Radius.circular(m * 0.34),
                ),
                paint,
              );
            case ReceiptQrModule.diamond:
              final h = m * 0.6;
              c.drawPath(
                ui.Path()
                  ..moveTo(b.center.dx, b.center.dy - h)
                  ..lineTo(b.center.dx + h, b.center.dy)
                  ..lineTo(b.center.dx, b.center.dy + h)
                  ..lineTo(b.center.dx - h, b.center.dy)
                  ..close(),
                paint,
              );
            case ReceiptQrModule.tiny:
              c.drawRect(b.deflate(m * 0.14), paint);
            case ReceiptQrModule.plus:
              final t = m * 0.22;
              c
                ..drawRect(
                  ui.Rect.fromLTRB(
                    b.left,
                    b.center.dy - t,
                    b.right,
                    b.center.dy + t,
                  ),
                  paint,
                )
                ..drawRect(
                  ui.Rect.fromLTRB(
                    b.center.dx - t,
                    b.top,
                    b.center.dx + t,
                    b.bottom,
                  ),
                  paint,
                );
            case ReceiptQrModule.vbar:
            case ReceiptQrModule.hbar:
              break;
          }
        }
      }
    }
    // مربعات الزوايا الثلاث.
    for (final (r, col) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
      _qrEye(c, ui.Offset(x + col * m, y + r * m), m, paint);
    }
    if (logo != null) {
      final box = ui.Rect.fromLTWH(
        x + l0 * m,
        y + l0 * m,
        lm * m,
        lm * m,
      ).deflate(m * 0.3);
      final under = mono
          ? _white
          : (_bottomStart != null &&
                    design.palette.isSet(ReceiptColorSlot.bottomBg)
                ? _c(ReceiptColorSlot.bottomBg)
                : paper);
      final bg = under.computeLuminance() < 0.35 ? _white : under;
      c.drawRRect(
        ui.RRect.fromRectAndRadius(box, ui.Radius.circular(m)),
        ui.Paint()..color = bg,
      );
      final inner = box.deflate(m * 0.4);
      final sc = math.min(inner.width / logo.width, inner.height / logo.height);
      final dst = ui.Rect.fromCenter(
        center: inner.center,
        width: logo.width * sc,
        height: logo.height * sc,
      );
      c.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    }
  }

  void _qrEye(ui.Canvas c, ui.Offset o, double m, ui.Paint paint) {
    final outer = ui.Rect.fromLTWH(o.dx, o.dy, m * 7, m * 7);
    final hole = outer.deflate(m);
    final dot = outer.deflate(m * 2);
    ui.Path shape(ui.Rect r, double k) {
      final p = ui.Path();
      switch (design.qrStyle.eye) {
        case ReceiptQrEye.square:
          p.addRect(r);
        case ReceiptQrEye.rounded:
          p.addRRect(ui.RRect.fromRectAndRadius(r, ui.Radius.circular(m * k)));
        case ReceiptQrEye.circle:
          p.addOval(r);
        case ReceiptQrEye.leaf:
          final rad = ui.Radius.circular(m * k * 1.6);
          p.addRRect(
            ui.RRect.fromRectAndCorners(r, topLeft: rad, bottomRight: rad),
          );
      }
      return p;
    }

    c.drawPath(
      ui.Path.combine(
        ui.PathOperation.difference,
        shape(outer, 2),
        shape(hole, 1.4),
      ),
      paint,
    );
    c.drawPath(shape(dot, 0.9), paint);
  }

  /// أرقام مفصولة بمسافات (هاتف، تاريخ ووقت) داخل سطر عربي يقلبها اتجاه
  /// النص فتُطبع «0000 000 0780». نعزلها باتجاه يسار←يمين فتبقى كما كُتبت.
  static final _spacedNumber = RegExp(
    r'\d[\d/:.\-]*(?:[ \u00A0]+\d[\d/:.\-]*)+',
  );

  static String isolateNumbers(String s) =>
      s.replaceAllMapped(_spacedNumber, (m) => '\u2066${m[0]}\u2069');

  static String _money(int fils) => IraqiCurrencyFormat.formatIqd(fils / 1000);

  static String _num(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}
