/// معرض القوالب الجاهزة: عشرون هيكلاً وعائلات ألوان، كلها مبنية من أجزاء
/// محرّك التصميم فتعمل على كل طابعة ومقاس وتبقى قابلة للتعديل كاملاً.
library;

import 'receipt_design.dart';
import 'receipt_gallery_data.dart';
import 'receipt_model.dart';

/// الهياكل العشرون: شكل الإيصال وهندسته (الألوان والخط من العائلة).
enum ReceiptSkeleton {
  ticketStub('تذكرة بقسيمة'),
  sideStrip('شريط جانبي'),
  cards('بطاقات'),
  fullGrid('جدول كامل'),
  twoColumns('عمودان'),
  diagonalBanner('رأس مائل'),
  classicCentred('كلاسيكي في الوسط'),
  timeline('خط زمني للخدمات'),
  sealTotal('ختم الإجمالي'),
  boardingPass('بطاقة صعود'),
  minimal('بسيط بأرقام كبيرة'),
  framedOrnate('إطار مزخرف'),
  tabbed('أقسام بألسنة'),
  waveHeader('رأس موجي'),
  checklist('قائمة فحص'),
  dashboard('لوحة مربعات'),
  ribbonTitles('عناوين بشرائط'),
  invertedBody('وسط داكن'),
  magazine('مجلة'),
  certificate('شهادة');

  const ReceiptSkeleton(this.label);
  final String label;

  /// هل يحتاج جزءاً علوياً ملوّناً (حافته المشكّلة هي الشكل)؟
  bool get needsTopColor =>
      this == diagonalBanner || this == waveHeader || this == magazine;

  /// أجزاء هذا الهيكل فوق التصميم [d] (الألوان والخط كما هي).
  ReceiptDesign apply(ReceiptDesign d) {
    const base = ReceiptDesign();
    final b = d.copyWith(
      header: base.header,
      title: base.title,
      info: base.info,
      items: base.items,
      totals: base.totals,
      highlight: base.highlight,
      frame: base.frame,
      topEdge: base.topEdge,
      sectionTitles: base.sectionTitles,
      sectionBox: base.sectionBox,
      itemMarker: base.itemMarker,
      totalLayout: base.totalLayout,
      edges: base.edges,
      sideStrip: false,
    );
    return switch (this) {
      ticketStub => b.copyWith(
        edges: ReceiptEdges.stub,
        items: ReceiptItemsStyle.table,
        highlight: ReceiptHighlightStyle.filled,
      ),
      sideStrip => b.copyWith(
        sideStrip: true,
        title: ReceiptHeaderShape.plain,
        totals: ReceiptHeaderShape.outlined,
        itemMarker: ReceiptItemMarker.dot,
      ),
      cards => b.copyWith(
        sectionBox: ReceiptSectionBox.card,
        sectionTitles: ReceiptSectionTitles.pill,
        items: ReceiptItemsStyle.zebra,
      ),
      fullGrid => b.copyWith(
        header: ReceiptHeaderLayout.boxed,
        info: ReceiptInfoStyle.grid,
        items: ReceiptItemsStyle.grid,
      ),
      twoColumns => b.copyWith(
        header: ReceiptHeaderLayout.boxed,
        title: ReceiptHeaderShape.outlined,
        info: ReceiptInfoStyle.grid,
        items: ReceiptItemsStyle.table,
        sectionTitles: ReceiptSectionTitles.line,
      ),
      diagonalBanner => b.copyWith(
        topEdge: ReceiptTopEdge.diagonal,
        items: ReceiptItemsStyle.table,
        highlight: ReceiptHighlightStyle.filled,
      ),
      classicCentred => b.copyWith(
        title: ReceiptHeaderShape.ribbon,
        totals: ReceiptHeaderShape.plain,
        frame: ReceiptFrame.corners,
      ),
      timeline => b.copyWith(
        title: ReceiptHeaderShape.plain,
        itemMarker: ReceiptItemMarker.timeline,
        sectionTitles: ReceiptSectionTitles.line,
      ),
      sealTotal => b.copyWith(
        totalLayout: ReceiptTotalLayout.seal,
        info: ReceiptInfoStyle.zebra,
        highlight: ReceiptHighlightStyle.filled,
      ),
      boardingPass => b.copyWith(
        header: ReceiptHeaderLayout.banner,
        title: ReceiptHeaderShape.outlined,
        info: ReceiptInfoStyle.boxed,
        totals: ReceiptHeaderShape.outlined,
        edges: ReceiptEdges.notches,
      ),
      minimal => b.copyWith(
        title: ReceiptHeaderShape.plain,
        totalLayout: ReceiptTotalLayout.big,
      ),
      framedOrnate => b.copyWith(
        frame: ReceiptFrame.ornate,
        title: ReceiptHeaderShape.ribbon,
        totals: ReceiptHeaderShape.outlined,
        sectionTitles: ReceiptSectionTitles.line,
      ),
      tabbed => b.copyWith(
        title: ReceiptHeaderShape.plain,
        sectionBox: ReceiptSectionBox.outline,
        sectionTitles: ReceiptSectionTitles.tab,
      ),
      waveHeader => b.copyWith(
        topEdge: ReceiptTopEdge.wave,
        items: ReceiptItemsStyle.zebra,
        totals: ReceiptHeaderShape.ribbon,
      ),
      checklist => b.copyWith(
        itemMarker: ReceiptItemMarker.check,
        sectionTitles: ReceiptSectionTitles.pill,
        edges: ReceiptEdges.zigzag,
      ),
      dashboard => b.copyWith(
        info: ReceiptInfoStyle.tiles,
        highlight: ReceiptHighlightStyle.filled,
        items: ReceiptItemsStyle.grid,
      ),
      ribbonTitles => b.copyWith(
        title: ReceiptHeaderShape.ribbon,
        totals: ReceiptHeaderShape.ribbon,
        sectionTitles: ReceiptSectionTitles.ribbon,
      ),
      invertedBody => b.copyWith(
        header: ReceiptHeaderLayout.banner,
        info: ReceiptInfoStyle.zebra,
        items: ReceiptItemsStyle.zebra,
        frame: ReceiptFrame.border,
      ),
      magazine => b.copyWith(
        topEdge: ReceiptTopEdge.arc,
        title: ReceiptHeaderShape.plain,
        totalLayout: ReceiptTotalLayout.big,
        itemMarker: ReceiptItemMarker.number,
      ),
      certificate => b.copyWith(
        frame: ReceiptFrame.double,
        title: ReceiptHeaderShape.outlined,
        totalLayout: ReceiptTotalLayout.seal,
        sectionTitles: ReceiptSectionTitles.line,
      ),
    };
  }
}

/// عائلات القوالب.
enum ReceiptGalleryFamily {
  sky('السماء'),
  sea('البحر'),
  forest('الغابة'),
  dark('الداكن'),
  vivid('الزاهي'),
  formal('الرسمي'),
  contemporary('العصري'),
  vintage('القديم');

  const ReceiptGalleryFamily(this.label);
  final String label;
}

/// قالب جاهز واحد: هيكل وخط وألوان مأخوذة من تصميمه الأصلي.
class ReceiptGalleryEntry {
  const ReceiptGalleryEntry(
    this.id,
    this.family,
    this.number,
    this.skeleton,
    this.font,
    this.palette, {
    this.qr = ReceiptQrStyle.classic,
    this.watermark = ReceiptWatermarkPattern.single,
    this.hasWatermark = false,
  });

  /// معرّف ثابت يُحفظ في التصميم (`preset`).
  final String id;
  final ReceiptGalleryFamily family;

  /// رقم التصميم داخل عائلته.
  final int number;
  final ReceiptSkeleton skeleton;
  final ReceiptFont font;

  /// الألوان بصيغة [ReceiptPalette.fromJson].
  final Map<String, String> palette;
  final ReceiptQrStyle qr;
  final ReceiptWatermarkPattern watermark;
  final bool hasWatermark;

  String get name => '${family.label} $number · ${skeleton.label}';

  /// التصميم الكامل لهذا القالب.
  ReceiptDesign get design => skeleton
      .apply(const ReceiptDesign())
      .copyWith(
        preset: id,
        font: font,
        palette: ReceiptPalette.fromJson(palette),
        qrStyle: qr,
        watermark: hasWatermark
            ? ReceiptWatermark.storeLogo
            : ReceiptWatermark.none,
        watermarkPattern: watermark,
        watermarkOpacity: 0.07,
      );
}

/// القوالب الجاهزة.
abstract final class ReceiptGallery {
  static List<ReceiptGalleryEntry> get all => receiptGalleryData;

  static List<ReceiptGalleryEntry> of(ReceiptGalleryFamily f) => [
    for (final e in all)
      if (e.family == f) e,
  ];

  static ReceiptGalleryEntry? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }
}
