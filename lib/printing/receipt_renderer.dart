import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/painting.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/print_settings_data.dart';
import '../utils/iraqi_currency_format.dart';
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
class ReceiptRenderer {
  ReceiptRenderer._(
    this.width,
    this.base, {
    required this.family,
    required this.ink,
    required this.accent,
    required this.shape,
    required bool sheet,
  }) : pad = (width * (sheet ? 0.06 : 0.03)).roundToDouble();

  static const _black = ui.Color(0xFF000000);
  static const _white = ui.Color(0xFFFFFFFF);

  final double width;
  final double base;
  final String family;
  final ui.Color ink;
  final ui.Color accent;
  final ReceiptHeaderShape shape;
  final double pad;
  double get inner => width - pad * 2;

  static Future<RenderedReceipt> render(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptTemplate template,
    ReceiptPaper paper = ReceiptPaper.mm80,
    ReceiptStyle style = const ReceiptStyle(),
    bool monochrome = true,
  }) async {
    final w = paper.dots.toDouble();
    final baseSize = switch (paper) {
      ReceiptPaper.mm58 => 22.0,
      ReceiptPaper.mm80 => 26.0,
      ReceiptPaper.a5 => 26.0,
      ReceiptPaper.a4 => 30.0,
    };
    final r = ReceiptRenderer._(
      w,
      (baseSize * style.size.scale).roundToDouble(),
      family: style.font.family,
      // الطابعة الحرارية لا تطبع إلا الأسود.
      ink: monochrome ? _black : ui.Color(style.ink.argb),
      accent: monochrome ? _black : ui.Color(style.accent.argb),
      shape: style.shape,
      sheet: !paper.isRoll,
    );
    ui.Image? logo;
    final logoBytes = template.showLogo ? settings.storeLogoBytes : null;
    if (logoBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(logoBytes);
        logo = (await codec.getNextFrame()).image;
      } catch (_) {
        logo = null;
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final (height, logoRect) = r._paint(canvas, doc, settings, template, logo);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), height.ceil());
    picture.dispose();
    logo?.dispose();
    return RenderedReceipt(image, logoRect);
  }

  // ---------------------------------------------------------------- الرسم

  (double, ui.Rect?) _paint(
    ui.Canvas c,
    ReceiptDocument doc,
    PrintSettingsData settings,
    ReceiptTemplate t,
    ui.Image? logo,
  ) {
    c.drawRect(ui.Rect.fromLTWH(0, 0, width, 100000), ui.Paint()..color = _white);
    var y = pad;
    ui.Rect? logoRect;

    // الشعار.
    if (logo != null) {
      final maxW = width * 0.55;
      final maxH = base * 4.5;
      final scale = math.min(maxW / logo.width, maxH / logo.height);
      final lw = logo.width * scale;
      final lh = logo.height * scale;
      logoRect = ui.Rect.fromLTWH((width - lw) / 2, y, lw, lh);
      c.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        logoRect,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      y += lh + base * 0.4;
    }

    // اسم المحل وعنوانه.
    final store = settings.storeTitleLine.trim();
    if (store.isNotEmpty) {
      y += _text(c, store, y, size: base * 1.4, bold: true, align: TextAlign.center);
    }
    if (t.showStoreContact) {
      for (final line in settings.receiptStoreContactLines) {
        y += _text(c, line, y, size: base * 0.85, align: TextAlign.center);
      }
    }
    y += base * 0.4;

    // شريط العنوان المعكوس.
    y += _inverted(c, doc.title, y, size: base * 1.25);
    y += base * 0.35;

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
    for (final f in fields) {
      y += _row(c, f.label, f.value, y, boldEnd: f.bold, wrapEnd: true);
    }

    // الصناديق البارزة.
    for (final h in doc.highlights) {
      if (h.section != null && !t.shows(h.section!)) continue;
      y += base * 0.3;
      y += _boxed(c, h.label, h.value, y);
    }
    if (fields.isNotEmpty || doc.highlights.isNotEmpty) y += _dashed(c, y);

    // الأصناف.
    if (doc.lines.isNotEmpty) {
      y += _row(c, 'الصنف', 'المبلغ', y, size: base * 0.85, boldStart: true, boldEnd: true);
      y += _solid(c, y, 1.5);
      for (final l in doc.lines) {
        y += _line(c, l, y);
      }
      y += _solid(c, y, 1.5);
    }

    // المجاميع.
    for (final tot in doc.totals) {
      if (tot.emphasis) {
        y += base * 0.2;
        y += _invertedRow(c, tot.label, _money(tot.fils), y);
        y += base * 0.2;
      } else {
        y += _row(c, tot.label, _money(tot.fils), y, boldEnd: true);
      }
    }

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
      _qr(c, qr, (width - side) / 2, y, side);
      y += side + base * 0.2;
    }

    // التذييل.
    final footer = [
      settings.footerExtra.trim(),
      t.footer.trim(),
    ].where((e) => e.isNotEmpty).toList();
    y += base * 0.3;
    y += _dashed(c, y);
    if (footer.isEmpty) {
      y += _text(c, 'شكراً لزيارتكم', y, size: base, bold: true, align: TextAlign.center);
    } else {
      for (final f in footer) {
        y += _text(c, f, y, size: base * 0.9, align: TextAlign.center);
      }
    }
    y += pad * 2;
    return (y, logoRect);
  }

  // ------------------------------------------------------------- عناصر

  TextPainter _tp(
    String s, {
    required double size,
    bool bold = false,
    ui.Color? color,
    TextAlign align = TextAlign.start,
    double? maxWidth,
  }) {
    color ??= ink;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
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
    tp.layout(maxWidth: maxWidth ?? inner);
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
  }) {
    final tp = _tp(s, size: size, bold: bold, align: align);
    // تمدد إلى كامل العرض ليصح المحاذاة في المنتصف/البداية.
    tp.layout(minWidth: inner, maxWidth: inner);
    tp.paint(c, ui.Offset(pad, y));
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
  }) {
    final sz = size ?? base;
    final a = _tp(start, size: sz, bold: boldStart, maxWidth: inner * 0.5);
    final gap = base * 0.6;
    final b = _tp(
      end,
      size: sz,
      bold: boldEnd,
      maxWidth: inner - a.width - gap,
      align: TextAlign.left,
    );
    if (!wrapEnd && b.width + a.width + gap > inner) {
      // لا يتسع: القيمة تحت العنوان.
      a.paint(c, ui.Offset(width - pad - a.width, y));
      final b2 = _tp(end, size: sz, bold: boldEnd, align: TextAlign.left);
      b2.paint(c, ui.Offset(pad, y + a.height));
      return a.height + b2.height;
    }
    a.paint(c, ui.Offset(width - pad - a.width, y));
    b.paint(c, ui.Offset(pad, y));
    return math.max(a.height, b.height);
  }

  double _line(ui.Canvas c, ReceiptLine l, double y) {
    final q = l.quantity ?? 1;
    final simple = (q - 1).abs() < 1e-9 && l.unit == null;
    final total = _money(l.totalFils);
    if (simple) {
      final t = _tp(total, size: base, bold: true);
      final name = _tp(l.name, size: base, maxWidth: inner - t.width - base * 0.6);
      name.paint(c, ui.Offset(width - pad - name.width, y));
      t.paint(c, ui.Offset(pad, y));
      return math.max(name.height, t.height) + base * 0.15;
    }
    final name = _tp(l.name, size: base);
    name.paint(c, ui.Offset(width - pad - name.width, y));
    var h = name.height;
    final qty = '${_num(q)}${l.unit == null || l.unit!.isEmpty ? '' : ' ${l.unit}'}'
        '${l.unitPriceFils == null ? '' : ' × ${_money(l.unitPriceFils!)}'}';
    h += _row(c, qty, total, y + h, size: base * 0.9, boldEnd: true);
    return h + base * 0.15;
  }

  double get _stroke => math.max(2.0, base / 9);

  /// العنوان حسب الشكل المختار.
  double _inverted(ui.Canvas c, String s, double y, {required double size}) {
    final filled = shape == ReceiptHeaderShape.filled;
    final tp = _tp(
      s,
      size: size,
      bold: true,
      color: filled ? _white : accent,
      align: TextAlign.center,
    );
    final h = tp.height + base * 0.4;
    switch (shape) {
      case ReceiptHeaderShape.filled:
        c.drawRect(ui.Rect.fromLTWH(pad, y, inner, h), ui.Paint()..color = accent);
      case ReceiptHeaderShape.outlined:
        c.drawRect(
          ui.Rect.fromLTWH(pad + _stroke / 2, y + _stroke / 2, inner - _stroke, h - _stroke),
          ui.Paint()
            ..color = accent
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = _stroke,
        );
      case ReceiptHeaderShape.plain:
        c.drawRect(
          ui.Rect.fromLTWH(pad + inner * 0.2, y + h - _stroke, inner * 0.6, _stroke),
          ui.Paint()..color = accent,
        );
    }
    tp.layout(minWidth: inner, maxWidth: inner);
    tp.paint(c, ui.Offset(pad, y + base * 0.2));
    return h;
  }

  /// الإجمالي حسب الشكل المختار.
  double _invertedRow(ui.Canvas c, String label, String value, double y) {
    final filled = shape == ReceiptHeaderShape.filled;
    final fg = filled ? _white : accent;
    final innerPad = base * 0.4;
    final a = _tp(label, size: base * 1.1, bold: true, color: fg);
    final b = _tp(value, size: base * 1.5, bold: true, color: fg);
    final h = math.max(a.height, b.height) + innerPad;
    switch (shape) {
      case ReceiptHeaderShape.filled:
        c.drawRect(ui.Rect.fromLTWH(pad, y, inner, h), ui.Paint()..color = accent);
      case ReceiptHeaderShape.outlined:
        c.drawRect(
          ui.Rect.fromLTWH(pad + _stroke / 2, y + _stroke / 2, inner - _stroke, h - _stroke),
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
    a.paint(c, ui.Offset(width - pad - innerPad - a.width, y + (h - a.height) / 2));
    b.paint(c, ui.Offset(pad + innerPad, y + (h - b.height) / 2));
    return h;
  }

  double _boxed(ui.Canvas c, String label, String value, double y) {
    final stroke = _stroke;
    final l = _tp(label, size: base * 0.9, align: TextAlign.center);
    final v = _tp(
      value,
      size: base * 1.45,
      bold: true,
      align: TextAlign.center,
      color: accent,
    );
    final h = l.height + v.height + base * 0.5;
    c.drawRect(
      ui.Rect.fromLTWH(pad + stroke / 2, y + stroke / 2, inner - stroke, h - stroke),
      ui.Paint()
        ..color = accent
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    l.layout(minWidth: inner, maxWidth: inner);
    v.layout(minWidth: inner, maxWidth: inner);
    l.paint(c, ui.Offset(pad, y + base * 0.25));
    v.paint(c, ui.Offset(pad, y + base * 0.25 + l.height));
    return h + base * 0.3;
  }

  double _dashed(ui.Canvas c, double y) {
    final p = ui.Paint()..color = ink;
    final dash = base * 0.45;
    final my = y + base * 0.35;
    for (var x = pad; x < width - pad; x += dash * 2) {
      c.drawRect(ui.Rect.fromLTWH(x, my, math.min(dash, width - pad - x), 2), p);
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

  static String _money(int fils) =>
      IraqiCurrencyFormat.formatIqd(fils / 1000);

  static String _num(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}
