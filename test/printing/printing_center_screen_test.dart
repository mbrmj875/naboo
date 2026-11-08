import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/printing_center_screen.dart';
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
  final loader = FontLoader('Tajawal');
  for (final f in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf']) {
    final bytes = File('assets/fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _host(_FakeSettings s) => ChangeNotifierProvider<PrintSettingsProvider>.value(
  value: s,
  child: MaterialApp(
    theme: ThemeData(fontFamily: 'Tajawal', useMaterial3: true),
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
      await tester.tap(find.text('طابعة شبكة (Wi-Fi / كابل)'));
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
}
