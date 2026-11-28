import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/printing_center_screen.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_gallery.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/providers/print_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// شاشة «الطباعة» على كل المقاسات بلا فيضان، وحفظ القوالب.
///
/// للصور: `SHOTS_DIR=/path flutter test <file>`.
class _FakeSettings extends PrintSettingsProvider {
  PrintSettingsData _d = PrintSettingsData.defaults().copyWith(
    storeTitleLine: 'مركز البصرة لتبديل الزيوت',
    storeAddress: 'البصرة — الجزائر',
    storePhones: ['0780 000 0000'],
  );
  int saves = 0;

  @override
  PrintSettingsData get data => _d;
  @override
  bool get isReady => true;
  @override
  Future<void> load() async {}
  @override
  Future<void> save(PrintSettingsData d) async {
    _d = d;
    saves++;
    notifyListeners();
  }
}

Future<void> _loadFonts() async {
  const r = 'assets/fonts/restaurant';
  for (final (family, files) in [
    ('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf']),
    ('Cairo', ['$r/Cairo-Regular.ttf', '$r/Cairo-Bold.ttf']),
    ('Amiri', ['$r/Amiri-Regular.ttf', '$r/Amiri-Bold.ttf']),
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

Widget _host(_FakeSettings s, {bool dark = false}) => ChangeNotifierProvider<PrintSettingsProvider>.value(
  value: s,
  child: MaterialApp(
    theme: ThemeData(
      fontFamily: 'Tajawal',
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: const RepaintBoundary(
      key: ValueKey('shot'),
      child: PrintingCenterScreen(),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (label, size) in const [
    ('320', Size(320, 900)),
    ('412', Size(412, 915)),
    ('768', Size(768, 1024)),
    ('1280', Size(1280, 900)),
    ('1920', Size(1920, 1080)),
  ]) {
    testWidgets('بلا فيضان على $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = _FakeSettings();
      await tester.pumpWidget(_host(s));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      // اختيار طابعة شبكة يُظهر حقول العنوان.
      await tester.tap(find.byKey(const ValueKey('printer-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('طابعة شبكة (Wi-Fi / كابل)').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.text('عنوان الطابعة (IP)'), findsOneWidget);
      // انتظار رسم المعاينة.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final dir = Platform.environment['SHOTS_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final b = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shot')),
          );
          final im = await b.toImage();
          final png = await im.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/center_$label.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('إطفاء الطباعة التلقائية للغسيل يُحفظ في قوالب المحل', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = _FakeSettings();
    await tester.pumpWidget(_host(s));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    final tile = find.widgetWithText(ExpansionTile, 'غسيل السيارات');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final sw = find.descendant(
      of: tile,
      matching: find.byType(Switch),
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.saves, 1);
    expect(
      ReceiptTemplates(s.data.receiptTemplates).of(ReceiptKind.carWash).autoPrint,
      isFalse,
    );
    expect(
      ReceiptTemplates(s.data.receiptTemplates).of(ReceiptKind.oilChange).autoPrint,
      isTrue,
    );
  });

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Platform.environment['SHOTS_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      final im = await b.toImage();
      final png = await im.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    for (final (label, size) in const [
      ('360', Size(360, 7400)),
      ('412', Size(412, 7400)),
      ('768', Size(768, 5200)),
      ('1280', Size(1280, 3600)),
    ]) {
      testWidgets('كل الأقسام مفتوحة بلا فيضان على $label ${dark ? 'داكن' : 'فاتح'}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = _FakeSettings();
        await tester.pumpWidget(_host(s, dark: dark));
        await settle(tester);
        await shot(tester, 'v2_${dark ? 'dark' : 'light'}_${label}_closed');
        for (final k in [
          'receipt-fold-gallery',
          'receipt-fold-font',
          'receipt-design-parts',
          'receipt-fold-colors',
          'receipt-fold-watermark',
          'receipt-fold-qr',
        ]) {
          final f = find.byKey(ValueKey(k));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }
        await settle(tester, 800);
        expect(tester.takeException(), isNull);
        await shot(tester, 'v2_${dark ? 'dark' : 'light'}_${label}_open');
      });
    }
  }

  testWidgets('الصناديق تحفظ التصميم مرة واحدة، والمعاينة تتغيّر فوراً', (tester) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = _FakeSettings();
    await tester.pumpWidget(_host(s));
    await settle(tester);
    Future<void> pick(String key, String item) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    for (final k in ['receipt-design-parts', 'receipt-fold-watermark', 'receipt-fold-qr']) {
      final f = find.byKey(ValueKey(k));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
    await pick('receipt-items', ReceiptItemsStyle.grid.label);
    await pick('receipt-info', ReceiptInfoStyle.grid.label);
    await pick('receipt-wm', ReceiptWatermark.storeLogo.label);
    await pick('receipt-wm-pattern', ReceiptWatermarkPattern.diagonalRight.label);
    await pick('receipt-qr-style', ReceiptQrStyle.dotsCircle.label);
    final logo = find.byKey(const ValueKey('receipt-qr-logo'));
    await tester.ensureVisible(logo);
    await tester.pump(const Duration(seconds: 1));
    final before = s.saves;
    await tester.tap(logo);
    await tester.pump();
    // آخر تغيير لم يُحفظ بعد (الحفظ بعد توقف التغيير)، والمعاينة أخذته.
    expect(s.saves, before);
    expect(ReceiptTemplates(s.data.receiptTemplates).design.qrLogo, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.saves, before + 1);
    final d = ReceiptTemplates(s.data.receiptTemplates).design;
    expect(d.items, ReceiptItemsStyle.grid);
    expect(d.info, ReceiptInfoStyle.grid);
    expect(d.watermark, ReceiptWatermark.storeLogo);
    expect(d.watermarkPattern, ReceiptWatermarkPattern.diagonalRight);
    expect(d.qrStyle, ReceiptQrStyle.dotsCircle);
    expect(d.qrLogo, isTrue);
    await settle(tester, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الضغط على لون يفتح مربع الألوان المتدرج', (tester) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = _FakeSettings();
    await tester.pumpWidget(_host(s));
    await settle(tester);
    final fold = find.byKey(const ValueKey('receipt-fold-colors'));
    await tester.ensureVisible(fold);
    await tester.tap(fold);
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('receipt-color-topBg'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // عنوان الحوار هو اسم اللون.
    expect(find.text(ReceiptColorSlot.topBg.label), findsWidgets);
    await shot(tester, 'v2_color_picker');
    expect(tester.takeException(), isNull);
  });

  testWidgets('اختيار قالب جاهز يطبّقه ويبقى قابلاً للتعديل', (tester) async {
    tester.view.physicalSize = const Size(412, 7400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = _FakeSettings();
    await tester.pumpWidget(_host(s));
    await settle(tester);
    final fold = find.byKey(const ValueKey('receipt-fold-gallery'));
    await tester.ensureVisible(fold);
    await tester.tap(fold);
    await tester.pumpAndSettle();
    final fam = find.byKey(const ValueKey('receipt-gallery-family'));
    await tester.ensureVisible(fam);
    await tester.tap(fam);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(ReceiptGalleryFamily.dark.label).last);
    await tester.pumpAndSettle();
    await settle(tester, 1500);
    await shot(tester, 'v2_gallery_dark');
    final entry = ReceiptGallery.byId('dark_10')!;
    final tile = find.byKey(const ValueKey('gallery-dark_10'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 600));
    var d = ReceiptTemplates(s.data.receiptTemplates).design;
    expect(d.preset, 'dark_10');
    expect(d, entry.design);
    expect(find.textContaining('المختار: ${entry.name}'), findsOneWidget);
    // التعديل بعد الاختيار يبقى على القالب نفسه.
    final parts = find.byKey(const ValueKey('receipt-design-parts'));
    await tester.ensureVisible(parts);
    await tester.tap(parts);
    await tester.pumpAndSettle();
    final edge = find.byKey(const ValueKey('receipt-top-edge'));
    await tester.ensureVisible(edge);
    await tester.tap(edge);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReceiptTopEdge.wave.label).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    d = ReceiptTemplates(s.data.receiptTemplates).design;
    expect(d.topEdge, ReceiptTopEdge.wave);
    expect(d.palette, entry.design.palette);
    expect(d.font, entry.font);
    await settle(tester, 800);
    expect(tester.takeException(), isNull);
  });
}
