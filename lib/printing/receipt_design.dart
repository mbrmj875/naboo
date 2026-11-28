/// تصميم الإيصال: شكل كل جزء وألوانه. يحل محل [ReceiptStyle] ويقرأه.
///
/// يُحفظ قيماً صغيرة فقط (لا صور) في `receiptTemplates._design` للمحل، و
/// `receiptTemplates.{kind}.design` للنوع الذي أخذ تصميماً خاصاً به.
library;

import 'dart:math' as math;

import 'receipt_model.dart';

/// رأس الإيصال (الشعار واسم المحل وعنوانه).
enum ReceiptHeaderLayout {
  center('في الوسط'),
  boxed('بيانات المحل داخل إطار'),
  banner('شريط ممتلئ');

  const ReceiptHeaderLayout(this.label);
  final String label;
}

/// أسطر المعلومات (اللوحة، العميل، الفني…).
enum ReceiptInfoStyle {
  rows('أسطر'),
  zebra('أسطر متناوبة'),
  boxed('داخل إطار'),
  grid('جدول بخطوط كاملة'),
  tiles('مربعات');

  const ReceiptInfoStyle(this.label);
  final String label;
}

/// جدول الأصناف.
enum ReceiptItemsStyle {
  simple('بسيط'),
  table('جدول بأعمدة'),
  zebra('أسطر متناوبة'),
  grid('جدول بخطوط كاملة');

  const ReceiptItemsStyle(this.label);
  final String label;
}

/// الصناديق البارزة («الغيار القادم عند»).
enum ReceiptHighlightStyle {
  box('إطار'),
  filled('ممتلئ');

  const ReceiptHighlightStyle(this.label);
  final String label;
}

/// العلامة المائية في خلفية الورقة.
enum ReceiptWatermark {
  none('بلا'),
  storeLogo('شعار المحل'),
  nabooLogo('شعار نابو');

  const ReceiptWatermark(this.label);
  final String label;
}

/// توزيع العلامة المائية على الورقة.
enum ReceiptWatermarkPattern {
  single('واحدة في الوسط', 0),
  diagonalRight('مكررة مائلة لليمين', -30),
  diagonalLeft('مكررة مائلة لليسار', 30),
  vertical('مكررة بعمود في الوسط', 0),
  grid('مكررة شبكة مستقيمة', 0);

  const ReceiptWatermarkPattern(this.label, this.degrees);
  final String label;

  /// ميل كل شعار بالدرجات (السالب يرتفع نحو اليمين).
  final double degrees;

  bool get tiled => this != single;

  /// الحجم الافتراضي (نسبة من عرض الورقة).
  double get defaultSize => tiled ? 0.26 : 0.62;
}

/// شكل نقاط رمز QR.
enum ReceiptQrModule { square, dot, rounded, diamond, vbar, hbar, tiny, plus }

/// شكل مربعات الزوايا الثلاث في رمز QR.
enum ReceiptQrEye { square, rounded, circle, leaf }

/// أشكال رمز QR الجاهزة. كلها تُقرأ بالكاميرا؛ الأول هو الشكل القديم.
enum ReceiptQrStyle {
  classic('مربعات (الأصلي)', ReceiptQrModule.square, ReceiptQrEye.square),
  squareRounded(
    'مربعات بزوايا ناعمة',
    ReceiptQrModule.square,
    ReceiptQrEye.rounded,
  ),
  squareCircle(
    'مربعات بزوايا دائرية',
    ReceiptQrModule.square,
    ReceiptQrEye.circle,
  ),
  squareLeaf('مربعات بزوايا ورقة', ReceiptQrModule.square, ReceiptQrEye.leaf),
  dots('نقاط', ReceiptQrModule.dot, ReceiptQrEye.square),
  dotsRounded('نقاط بزوايا ناعمة', ReceiptQrModule.dot, ReceiptQrEye.rounded),
  dotsCircle('نقاط بزوايا دائرية', ReceiptQrModule.dot, ReceiptQrEye.circle),
  dotsLeaf('نقاط بزوايا ورقة', ReceiptQrModule.dot, ReceiptQrEye.leaf),
  soft('ناعم', ReceiptQrModule.rounded, ReceiptQrEye.rounded),
  softCircle(
    'ناعم بزوايا دائرية',
    ReceiptQrModule.rounded,
    ReceiptQrEye.circle,
  ),
  softLeaf('ناعم بزوايا ورقة', ReceiptQrModule.rounded, ReceiptQrEye.leaf),
  diamond('معيّنات', ReceiptQrModule.diamond, ReceiptQrEye.square),
  diamondCircle(
    'معيّنات بزوايا دائرية',
    ReceiptQrModule.diamond,
    ReceiptQrEye.circle,
  ),
  vbars('أعمدة', ReceiptQrModule.vbar, ReceiptQrEye.rounded),
  vbarsSquare('أعمدة بزوايا مربعة', ReceiptQrModule.vbar, ReceiptQrEye.square),
  hbars('أشرطة أفقية', ReceiptQrModule.hbar, ReceiptQrEye.rounded),
  hbarsCircle('أشرطة بزوايا دائرية', ReceiptQrModule.hbar, ReceiptQrEye.circle),
  tiny('مربعات صغيرة', ReceiptQrModule.tiny, ReceiptQrEye.square),
  tinyLeaf('مربعات صغيرة بزوايا ورقة', ReceiptQrModule.tiny, ReceiptQrEye.leaf),
  plus('علامات زائد', ReceiptQrModule.plus, ReceiptQrEye.rounded);

  const ReceiptQrStyle(this.label, this.module, this.eye);
  final String label;
  final ReceiptQrModule module;
  final ReceiptQrEye eye;
}

/// كل لون يمكن تغييره في الإيصال. [ReceiptPalette.of] يعطي قيمته الفعلية.
enum ReceiptColorSlot {
  accent('العنوان والإجمالي والإطارات'),
  onAccent('النص فوق لون العنوان'),
  ink('النص'),
  muted('عناوين الأسطر'),
  paper('خلفية الورقة (الوسط)'),
  topBg('خلفية الجزء العلوي'),
  topInk('نص الجزء العلوي'),
  bottomBg('خلفية الجزء السفلي'),
  bottomInk('نص الجزء السفلي'),
  tableHead('رأس الجدول'),
  tableHeadInk('نص رأس الجدول'),
  grid('خطوط الجدول'),
  qr('رمز QR');

  const ReceiptColorSlot(this.label);
  final String label;

  /// الألوان الأربعة الأساسية محفوظة دائماً، والباقي اختياري.
  bool get isCore =>
      this == accent || this == ink || this == paper || this == muted;
}

/// شكل الحافة السفلى للجزء العلوي الملوّن.
enum ReceiptTopEdge {
  straight('مستقيمة'),
  diagonal('مائلة'),
  wave('موجة'),
  arc('قوس'),
  zigzag('مسنّنة');

  const ReceiptTopEdge(this.label);
  final String label;
}

/// عناوين الأقسام («التفاصيل»، «الأصناف والخدمات»، «الحساب»).
enum ReceiptSectionTitles {
  none('بلا عناوين'),
  line('عنوان بخط'),
  pill('كبسولة'),
  tab('لسان ملف'),
  ribbon('شريطة');

  const ReceiptSectionTitles(this.label);
  final String label;
}

/// صناديق حول الأقسام.
enum ReceiptSectionBox {
  none('بلا'),
  card('بطاقات'),
  outline('إطارات');

  const ReceiptSectionBox(this.label);
  final String label;
}

/// علامة قبل كل صنف (في الشكل البسيط والمتناوب).
enum ReceiptItemMarker {
  none('بلا'),
  number('أرقام'),
  dot('نقاط'),
  timeline('خط زمني'),
  check('علامة صح');

  const ReceiptItemMarker(this.label);
  final String label;
}

/// طريقة عرض الإجمالي.
enum ReceiptTotalLayout {
  bar('سطر'),
  seal('ختم دائري'),
  big('رقم كبير');

  const ReceiptTotalLayout(this.label);
  final String label;
}

/// حواف الورقة.
enum ReceiptEdges {
  none('عادية'),
  zigzag('مسنّنة'),
  notches('ثقوب جانبية بين الأقسام'),
  stub('قسيمة قابلة للقطع');

  const ReceiptEdges(this.label);
  final String label;
}

/// زخرفة حول الورقة.
enum ReceiptFrame {
  none('بلا'),
  border('إطار حول الورقة'),
  corners('زوايا'),
  double('إطار مزدوج'),
  ornate('إطار مزخرف');

  const ReceiptFrame(this.label);
  final String label;
}

/// كثافة الإيصال.
enum ReceiptDensity {
  normal('عادي', 1.0),
  compact('موفّر للورق', 0.9);

  const ReceiptDensity(this.label, this.scale);
  final String label;

  /// معامل الحجم والمسافات.
  final double scale;
}

/// ألوان الإيصال (ARGB). الطابعة الحرارية تطبعها كلها بالأسود على أبيض.
class ReceiptPalette {
  const ReceiptPalette({
    this.accent = 0xFF000000,
    this.ink = 0xFF000000,
    this.paper = 0xFFFFFFFF,
    int? muted,
    this.extra = const {},
  }) : muted = muted ?? ink;

  /// الألوان الاختيارية التي غيّرها المستخدم؛ الغائب يأخذ قيمته من غيره.
  final Map<ReceiptColorSlot, int> extra;

  /// هل غيّر المستخدم هذا اللون بنفسه؟
  bool isSet(ReceiptColorSlot s) => s.isCore || extra.containsKey(s);

  static int _lerp(int a, int b, double t) {
    int ch(int c, int s) => (c >> s) & 0xFF;
    var out = 0xFF000000;
    for (final s in [16, 8, 0]) {
      final v = (ch(a, s) + (ch(b, s) - ch(a, s)) * t).round().clamp(0, 255);
      out |= v << s;
    }
    return out;
  }

  /// اللون الفعلي لهذا الموضع.
  int of(ReceiptColorSlot s) => switch (s) {
    ReceiptColorSlot.accent => accent,
    ReceiptColorSlot.ink => ink,
    ReceiptColorSlot.paper => paper,
    ReceiptColorSlot.muted => muted,
    ReceiptColorSlot.onAccent => extra[s] ?? 0xFFFFFFFF,
    ReceiptColorSlot.topBg || ReceiptColorSlot.bottomBg => extra[s] ?? paper,
    ReceiptColorSlot.topInk || ReceiptColorSlot.bottomInk => extra[s] ?? ink,
    ReceiptColorSlot.tableHead => extra[s] ?? _lerp(0xFFFFFFFF, accent, 0.16),
    ReceiptColorSlot.tableHeadInk => extra[s] ?? ink,
    ReceiptColorSlot.grid => extra[s] ?? _lerp(paper, ink, 0.22),
    ReceiptColorSlot.qr => extra[s] ?? 0xFF000000,
  };

  /// يغيّر لوناً واحداً؛ `null` يرجع الاختياري لقيمته التلقائية.
  ReceiptPalette withSlot(ReceiptColorSlot s, int? argb) {
    switch (s) {
      case ReceiptColorSlot.accent:
        return copyWith(accent: argb ?? 0xFF000000);
      case ReceiptColorSlot.ink:
        return copyWith(ink: argb ?? 0xFF000000);
      case ReceiptColorSlot.paper:
        return copyWith(paper: argb ?? 0xFFFFFFFF);
      case ReceiptColorSlot.muted:
        return copyWith(muted: argb ?? ink);
      default:
        final m = Map<ReceiptColorSlot, int>.from(extra);
        if (argb == null) {
          m.remove(s);
        } else {
          m[s] = argb | 0xFF000000;
        }
        return ReceiptPalette(
          accent: accent,
          ink: ink,
          paper: paper,
          muted: muted,
          extra: m,
        );
    }
  }

  /// العنوان والإجمالي والإطارات.
  final int accent;

  /// النص.
  final int ink;

  /// خلفية الورقة.
  final int paper;

  /// عناوين الأسطر («اللوحة:»، «العميل:»).
  final int muted;

  static int? _argb(Object? v) {
    if (v is int) return v | 0xFF000000;
    if (v is num) return v.toInt() | 0xFF000000;
    if (v is String) {
      var t = v.trim();
      if (t.startsWith('#')) t = t.substring(1);
      if (t.length == 6) t = 'FF$t';
      final n = int.tryParse(t, radix: 16);
      return n == null ? null : n | 0xFF000000;
    }
    return null;
  }

  static String _hex(int c) =>
      '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  factory ReceiptPalette.fromJson(Object? raw) {
    if (raw is! Map) return const ReceiptPalette();
    final ink = _argb(raw['ink']) ?? 0xFF000000;
    return ReceiptPalette(
      accent: _argb(raw['accent']) ?? 0xFF000000,
      ink: ink,
      paper: _argb(raw['paper']) ?? 0xFFFFFFFF,
      muted: _argb(raw['muted']) ?? ink,
      extra: {
        for (final s in ReceiptColorSlot.values)
          if (!s.isCore && _argb(raw[s.name]) != null) s: _argb(raw[s.name])!,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'accent': _hex(accent),
    'ink': _hex(ink),
    'paper': _hex(paper),
    'muted': _hex(muted),
    for (final e in extra.entries) e.key.name: _hex(e.value),
  };

  ReceiptPalette copyWith({int? accent, int? ink, int? paper, int? muted}) =>
      ReceiptPalette(
        accent: accent ?? this.accent,
        ink: ink ?? this.ink,
        paper: paper ?? this.paper,
        // النص الثانوي يتبع النص إن كان مثله ولم يُغيَّر وحده.
        muted:
            muted ?? (this.muted == this.ink ? (ink ?? this.ink) : this.muted),
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is ReceiptPalette &&
      other.accent == accent &&
      other.ink == ink &&
      other.paper == paper &&
      other.muted == muted &&
      _sameExtra(other.extra, extra);

  static bool _sameExtra(
    Map<ReceiptColorSlot, int> a,
    Map<ReceiptColorSlot, int> b,
  ) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    accent,
    ink,
    paper,
    muted,
    Object.hashAllUnordered(
      extra.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// تصميم إيصال كامل.
class ReceiptDesign {
  const ReceiptDesign({
    this.preset = classicPreset,
    this.font = ReceiptFont.tajawal,
    this.size = ReceiptTextSize.medium,
    this.palette = const ReceiptPalette(),
    this.header = ReceiptHeaderLayout.center,
    this.title = ReceiptHeaderShape.filled,
    this.info = ReceiptInfoStyle.rows,
    this.items = ReceiptItemsStyle.simple,
    this.totals = ReceiptHeaderShape.filled,
    this.highlight = ReceiptHighlightStyle.box,
    this.watermark = ReceiptWatermark.none,
    this.watermarkOpacity = defaultWatermarkOpacity,
    this.frame = ReceiptFrame.none,
    this.density = ReceiptDensity.normal,
    this.watermarkPattern = ReceiptWatermarkPattern.single,
    double? watermarkSize,
    this.watermarkGap = defaultWatermarkGap,
    this.qrStyle = ReceiptQrStyle.classic,
    this.qrLogo = false,
    this.topEdge = ReceiptTopEdge.straight,
    this.sectionTitles = ReceiptSectionTitles.none,
    this.sectionBox = ReceiptSectionBox.none,
    this.itemMarker = ReceiptItemMarker.none,
    this.totalLayout = ReceiptTotalLayout.bar,
    this.edges = ReceiptEdges.none,
    this.sideStrip = false,
  }) : _watermarkSize = watermarkSize;

  static const defaultWatermarkGap = 0.6;

  static const schemaVersion = 1;
  static const classicPreset = 'classic';
  static const defaultWatermarkOpacity = 0.08;

  /// أعلى شفافية للعلامة المائية على الحرارية حتى يبقى النص مقروءاً.
  static const thermalWatermarkCap = 0.12;

  /// من مظهر المحل القديم: نفس الخط والحجم والشكل والألوان.
  factory ReceiptDesign.fromStyle(ReceiptStyle s) => ReceiptDesign(
    font: s.font,
    size: s.size,
    palette: ReceiptPalette(accent: s.accent.argb, ink: s.ink.argb),
    title: s.shape,
    totals: s.shape,
  );

  factory ReceiptDesign.fromJson(Object? raw) {
    if (raw is! Map) return const ReceiptDesign();
    T pick<T extends Enum>(List<T> values, Object? v, T d) =>
        values.firstWhere((e) => e.name == v, orElse: () => d);
    const d = ReceiptDesign();
    final op = raw['watermarkOpacity'];
    return ReceiptDesign(
      preset: raw['preset'] is String && (raw['preset'] as String).isNotEmpty
          ? raw['preset'] as String
          : d.preset,
      font: pick(ReceiptFont.values, raw['font'], d.font),
      size: pick(ReceiptTextSize.values, raw['size'], d.size),
      palette: ReceiptPalette.fromJson(raw['palette']),
      header: pick(ReceiptHeaderLayout.values, raw['header'], d.header),
      title: pick(ReceiptHeaderShape.values, raw['title'], d.title),
      info: pick(ReceiptInfoStyle.values, raw['info'], d.info),
      items: pick(ReceiptItemsStyle.values, raw['items'], d.items),
      totals: pick(ReceiptHeaderShape.values, raw['totals'], d.totals),
      highlight: pick(
        ReceiptHighlightStyle.values,
        raw['highlight'],
        d.highlight,
      ),
      watermark: pick(ReceiptWatermark.values, raw['watermark'], d.watermark),
      watermarkOpacity: op is num
          ? op.toDouble().clamp(0.02, 0.3)
          : d.watermarkOpacity,
      frame: pick(ReceiptFrame.values, raw['frame'], d.frame),
      density: pick(ReceiptDensity.values, raw['density'], d.density),
      watermarkPattern: pick(
        ReceiptWatermarkPattern.values,
        raw['watermarkPattern'],
        d.watermarkPattern,
      ),
      watermarkSize: raw['watermarkSize'] is num
          ? (raw['watermarkSize'] as num).toDouble().clamp(0.12, 0.8)
          : null,
      watermarkGap: raw['watermarkGap'] is num
          ? (raw['watermarkGap'] as num).toDouble().clamp(0.1, 2.0)
          : d.watermarkGap,
      qrStyle: pick(ReceiptQrStyle.values, raw['qrStyle'], d.qrStyle),
      qrLogo: raw['qrLogo'] == true,
      topEdge: pick(ReceiptTopEdge.values, raw['topEdge'], d.topEdge),
      sectionTitles: pick(
        ReceiptSectionTitles.values,
        raw['sectionTitles'],
        d.sectionTitles,
      ),
      sectionBox: pick(
        ReceiptSectionBox.values,
        raw['sectionBox'],
        d.sectionBox,
      ),
      itemMarker: pick(
        ReceiptItemMarker.values,
        raw['itemMarker'],
        d.itemMarker,
      ),
      totalLayout: pick(
        ReceiptTotalLayout.values,
        raw['totalLayout'],
        d.totalLayout,
      ),
      edges: pick(ReceiptEdges.values, raw['edges'], d.edges),
      sideStrip: raw['sideStrip'] == true,
    );
  }

  /// معرّف التصميم الجاهز الذي بُني عليه.
  final String preset;
  final ReceiptFont font;
  final ReceiptTextSize size;
  final ReceiptPalette palette;
  final ReceiptHeaderLayout header;

  /// شكل شريط العنوان.
  final ReceiptHeaderShape title;
  final ReceiptInfoStyle info;
  final ReceiptItemsStyle items;

  /// شكل سطر الإجمالي.
  final ReceiptHeaderShape totals;
  final ReceiptHighlightStyle highlight;
  final ReceiptWatermark watermark;

  /// 0.02 إلى 0.3.
  final double watermarkOpacity;
  final ReceiptFrame frame;
  final ReceiptDensity density;

  /// توزيع العلامة المائية: واحدة أو مكررة على طول الورقة.
  final ReceiptWatermarkPattern watermarkPattern;

  final double? _watermarkSize;

  /// حجم الشعار الواحد نسبةً من عرض الورقة (0.12 إلى 0.8).
  double get watermarkSize => _watermarkSize ?? watermarkPattern.defaultSize;

  /// المسافة بين الشعارات المكررة نسبةً من حجم الشعار (0.1 إلى 2).
  final double watermarkGap;

  final ReceiptQrStyle qrStyle;

  /// شعار المحل في وسط رمز QR.
  final bool qrLogo;

  final ReceiptTopEdge topEdge;
  final ReceiptSectionTitles sectionTitles;
  final ReceiptSectionBox sectionBox;
  final ReceiptItemMarker itemMarker;
  final ReceiptTotalLayout totalLayout;
  final ReceiptEdges edges;

  /// شريط بلون العنوان على طول الحافة اليمنى، فيه اسم المحل.
  final bool sideStrip;

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'preset': preset,
    'font': font.name,
    'size': size.name,
    'palette': palette.toJson(),
    'header': header.name,
    'title': title.name,
    'info': info.name,
    'items': items.name,
    'totals': totals.name,
    'highlight': highlight.name,
    'watermark': watermark.name,
    'watermarkOpacity': double.parse(watermarkOpacity.toStringAsFixed(3)),
    'frame': frame.name,
    'density': density.name,
    if (watermarkPattern != ReceiptWatermarkPattern.single)
      'watermarkPattern': watermarkPattern.name,
    if (_watermarkSize != null)
      'watermarkSize': double.parse(_watermarkSize.toStringAsFixed(3)),
    if (watermarkGap != defaultWatermarkGap)
      'watermarkGap': double.parse(watermarkGap.toStringAsFixed(3)),
    if (qrStyle != ReceiptQrStyle.classic) 'qrStyle': qrStyle.name,
    if (qrLogo) 'qrLogo': true,
    if (topEdge != ReceiptTopEdge.straight) 'topEdge': topEdge.name,
    if (sectionTitles != ReceiptSectionTitles.none)
      'sectionTitles': sectionTitles.name,
    if (sectionBox != ReceiptSectionBox.none) 'sectionBox': sectionBox.name,
    if (itemMarker != ReceiptItemMarker.none) 'itemMarker': itemMarker.name,
    if (totalLayout != ReceiptTotalLayout.bar) 'totalLayout': totalLayout.name,
    if (edges != ReceiptEdges.none) 'edges': edges.name,
    if (sideStrip) 'sideStrip': true,
  };

  /// أقرب مظهر قديم، يُحفظ بجانب التصميم حتى تبقى نسخ التطبيق الأقدم على
  /// أجهزة المحل الأخرى تطبع بألوان وخط قريبين.
  ReceiptStyle toLegacyStyle() {
    ReceiptColor near(int argb) => ReceiptColor.values.reduce(
      (a, b) => _distance(a.argb, argb) <= _distance(b.argb, argb) ? a : b,
    );
    return ReceiptStyle(
      font: font,
      size: size,
      shape: title == ReceiptHeaderShape.ribbon
          ? ReceiptHeaderShape.filled
          : title,
      accent: near(palette.accent),
      ink: near(palette.ink),
    );
  }

  static int _distance(int a, int b) {
    int ch(int c, int s) => (c >> s) & 0xFF;
    var d = 0;
    for (final s in [16, 8, 0]) {
      final x = ch(a, s) - ch(b, s);
      d += x * x;
    }
    return d;
  }

  ReceiptDesign copyWith({
    String? preset,
    ReceiptFont? font,
    ReceiptTextSize? size,
    ReceiptPalette? palette,
    ReceiptHeaderLayout? header,
    ReceiptHeaderShape? title,
    ReceiptInfoStyle? info,
    ReceiptItemsStyle? items,
    ReceiptHeaderShape? totals,
    ReceiptHighlightStyle? highlight,
    ReceiptWatermark? watermark,
    double? watermarkOpacity,
    ReceiptFrame? frame,
    ReceiptDensity? density,
    ReceiptWatermarkPattern? watermarkPattern,
    double? watermarkSize,
    double? watermarkGap,
    ReceiptQrStyle? qrStyle,
    bool? qrLogo,
    ReceiptTopEdge? topEdge,
    ReceiptSectionTitles? sectionTitles,
    ReceiptSectionBox? sectionBox,
    ReceiptItemMarker? itemMarker,
    ReceiptTotalLayout? totalLayout,
    ReceiptEdges? edges,
    bool? sideStrip,
  }) => ReceiptDesign(
    preset: preset ?? this.preset,
    font: font ?? this.font,
    size: size ?? this.size,
    palette: palette ?? this.palette,
    header: header ?? this.header,
    title: title ?? this.title,
    info: info ?? this.info,
    items: items ?? this.items,
    totals: totals ?? this.totals,
    highlight: highlight ?? this.highlight,
    watermark: watermark ?? this.watermark,
    watermarkOpacity: (watermarkOpacity ?? this.watermarkOpacity).clamp(
      0.02,
      0.3,
    ),
    frame: frame ?? this.frame,
    density: density ?? this.density,
    // تغيير التوزيع يرجع الحجم لقيمته المناسبة إن لم يُحدَّد حجم.
    watermarkPattern: watermarkPattern ?? this.watermarkPattern,
    watermarkSize:
        watermarkSize?.clamp(0.12, 0.8) ??
        (watermarkPattern != null && watermarkPattern != this.watermarkPattern
            ? null
            : _watermarkSize),
    watermarkGap: (watermarkGap ?? this.watermarkGap).clamp(0.1, 2.0),
    qrStyle: qrStyle ?? this.qrStyle,
    qrLogo: qrLogo ?? this.qrLogo,
    topEdge: topEdge ?? this.topEdge,
    sectionTitles: sectionTitles ?? this.sectionTitles,
    sectionBox: sectionBox ?? this.sectionBox,
    itemMarker: itemMarker ?? this.itemMarker,
    totalLayout: totalLayout ?? this.totalLayout,
    edges: edges ?? this.edges,
    sideStrip: sideStrip ?? this.sideStrip,
  );

  /// شفافية العلامة المائية الفعلية على هذه الطابعة.
  double watermarkOpacityFor({required bool monochrome}) => monochrome
      ? math.min(watermarkOpacity, thermalWatermarkCap)
      : watermarkOpacity;

  // ------------------------------------------------------------ التباين

  /// نسبة التباين (WCAG) بين لونين، من 1 إلى 21.
  static double contrast(int a, int b) {
    double lum(int c) {
      double ch(int s) {
        final v = ((c >> s) & 0xFF) / 255.0;
        return v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0);
    }

    final la = lum(a);
    final lb = lum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// ما يقع خلف رمز QR فعلاً: الخلفية الداكنة يوضع فوقها بطاقة بيضاء.
  static int _qrBackdrop(int bg) =>
      contrast(bg, 0xFF000000) < 8 ? 0xFFFFFFFF : bg;

  static bool _isFilled(ReceiptHeaderShape s) =>
      s == ReceiptHeaderShape.filled || s == ReceiptHeaderShape.ribbon;

  /// تحذيرات الألوان على الطابعة الملوّنة والصورة المرسلة (الحرارية بالأسود
  /// دائماً فلا تحذير لها). فارغة = الألوان واضحة.
  List<String> contrastWarnings() {
    final p = palette;
    return [
      if (contrast(p.ink, p.paper) < 4.5) 'لون النص غير واضح على لون الورقة.',
      if (contrast(p.muted, p.paper) < 3)
        'لون عناوين الأسطر غير واضح على لون الورقة.',
      if (contrast(p.accent, p.paper) < 3)
        'لون العنوان والإجمالي قريب من لون الورقة.',
      if ((_isFilled(title) ||
              _isFilled(totals) ||
              header == ReceiptHeaderLayout.banner ||
              highlight == ReceiptHighlightStyle.filled ||
              sideStrip ||
              sectionTitles == ReceiptSectionTitles.pill ||
              sectionTitles == ReceiptSectionTitles.tab ||
              sectionTitles == ReceiptSectionTitles.ribbon) &&
          contrast(p.of(ReceiptColorSlot.onAccent), p.accent) < 3)
        'النص فوق لون العنوان غير واضح؛ غيّر أحدهما.',
      if (contrast(
            p.of(ReceiptColorSlot.topInk),
            p.of(ReceiptColorSlot.topBg),
          ) <
          4.5)
        'نص الجزء العلوي غير واضح على خلفيته.',
      if (contrast(
            p.of(ReceiptColorSlot.bottomInk),
            p.of(ReceiptColorSlot.bottomBg),
          ) <
          4.5)
        'نص الجزء السفلي غير واضح على خلفيته.',
      if ((items == ReceiptItemsStyle.grid ||
              items == ReceiptItemsStyle.table) &&
          contrast(
                p.of(ReceiptColorSlot.tableHeadInk),
                p.of(ReceiptColorSlot.tableHead),
              ) <
              4.5)
        'نص رأس الجدول غير واضح على لونه.',
      if (qrStyle != ReceiptQrStyle.classic || p.isSet(ReceiptColorSlot.qr))
        if (contrast(
              p.of(ReceiptColorSlot.qr),
              _qrBackdrop(p.of(ReceiptColorSlot.bottomBg)),
            ) <
            4)
          'رمز QR فاتح على خلفيته وقد لا تقرؤه الكاميرا.',
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiptDesign &&
      other.preset == preset &&
      other.font == font &&
      other.size == size &&
      other.palette == palette &&
      other.header == header &&
      other.title == title &&
      other.info == info &&
      other.items == items &&
      other.totals == totals &&
      other.highlight == highlight &&
      other.watermark == watermark &&
      other.watermarkOpacity == watermarkOpacity &&
      other.frame == frame &&
      other.density == density &&
      other.watermarkPattern == watermarkPattern &&
      other._watermarkSize == _watermarkSize &&
      other.watermarkGap == watermarkGap &&
      other.qrStyle == qrStyle &&
      other.qrLogo == qrLogo &&
      other.topEdge == topEdge &&
      other.sectionTitles == sectionTitles &&
      other.sectionBox == sectionBox &&
      other.itemMarker == itemMarker &&
      other.totalLayout == totalLayout &&
      other.edges == edges &&
      other.sideStrip == sideStrip;

  @override
  int get hashCode => Object.hash(
    preset,
    font,
    size,
    palette,
    header,
    title,
    info,
    items,
    totals,
    highlight,
    watermark,
    watermarkOpacity,
    frame,
    density,
    Object.hash(
      watermarkPattern,
      _watermarkSize,
      watermarkGap,
      qrStyle,
      qrLogo,
    ),
    Object.hash(
      topEdge,
      sectionTitles,
      sectionBox,
      itemMarker,
      totalLayout,
      edges,
      sideStrip,
    ),
  );
}

/// قراءة التصميم وحفظه في قوالب المحل.
extension ReceiptTemplatesDesign on ReceiptTemplates {
  static const _key = '_design';
  static const _legacyKey = '_style';
  static const _kindKey = 'design';

  Map<String, dynamic> get _m => rawMap;

  /// تصميم المحل. إن لم يُحفظ بعد: من المظهر القديم (`_style`).
  ReceiptDesign get design {
    final raw = _m[_key];
    if (raw is Map) return ReceiptDesign.fromJson(raw);
    return ReceiptDesign.fromStyle(style);
  }

  /// هل لهذا النوع تصميم خاص به؟
  bool hasOwnDesign(ReceiptKind kind) {
    final k = _m[kind.name];
    return k is Map && k[_kindKey] is Map;
  }

  /// التصميم الذي يُطبع به هذا النوع: الخاص إن وُجد، وإلا تصميم المحل.
  ReceiptDesign designFor(ReceiptKind kind) {
    final k = _m[kind.name];
    if (k is Map && k[_kindKey] is Map) {
      return ReceiptDesign.fromJson(k[_kindKey]);
    }
    return design;
  }

  /// يحفظ تصميم المحل، ومعه المظهر القديم لنسخ التطبيق الأقدم.
  Map<String, dynamic> withDesign(ReceiptDesign d) => {
    ..._m,
    _key: d.toJson(),
    _legacyKey: d.toLegacyStyle().toJson(),
  };

  /// تصميم خاص لنوع واحد، و`null` يرجعه لتصميم المحل.
  Map<String, dynamic> withKindDesign(ReceiptKind kind, ReceiptDesign? d) {
    final current = _m[kind.name];
    final k = current is Map
        ? Map<String, dynamic>.from(current)
        : ReceiptTemplate.defaultsFor(kind).toJson();
    if (d == null) {
      k.remove(_kindKey);
    } else {
      k[_kindKey] = d.toJson();
    }
    return {..._m, kind.name: k};
  }
}
