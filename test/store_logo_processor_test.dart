import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/services/store_logo_processor.dart';

/// صورة مصمتة بلا شفافية — تمثّل صورة واجهة محل.
Uint8List _opaquePng(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 160, 60));
  return Uint8List.fromList(img.encodePng(image));
}

/// شعار بخلفية شفافة — الحالة التي يجب ألّا تُفقد شفافيتها.
Uint8List _transparentPng(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillCircle(
    image,
    x: width ~/ 2,
    y: height ~/ 2,
    radius: width ~/ 4,
    color: img.ColorRgba8(200, 160, 60, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('معالجة شعار المتجر', () {
    test('الصور الكبيرة تُصغَّر إلى الحد الأقصى مع حفظ النِّسبة', () {
      final source = _opaquePng(2000, 1000);

      final out = encodeStoreLogo(StoreLogoInput(source, maxSide: 512));

      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 512);
      expect(decoded.height, 256);
    });

    test('الصور الصغيرة لا تُكبَّر', () {
      final source = _opaquePng(120, 80);

      final decoded = img.decodeImage(
        encodeStoreLogo(StoreLogoInput(source, maxSide: 512))!,
      )!;

      expect(decoded.width, 120);
      expect(decoded.height, 80);
    });

    test('الشفافية تبقى محفوظة (يُرمَّز PNG)', () {
      final source = _transparentPng(300, 300);

      final out = encodeStoreLogo(StoreLogoInput(source))!;

      final decoded = img.decodeImage(out)!;
      expect(decoded.hasAlpha, isTrue);
      expect(decoded.getPixel(0, 0).a, 0);
    });

    test('الصور المصمتة تُرمَّز JPEG لتصغير حجم السجلّ', () {
      // تدرّج لوني مع تشويش خفيف — يحاكي صورة واجهة محل حقيقية.
      final rnd = math.Random(42);
      final photo = img.Image(width: 400, height: 400);
      for (var y = 0; y < photo.height; y++) {
        for (var x = 0; x < photo.width; x++) {
          int jitter(int base) => (base + rnd.nextInt(41) - 20).clamp(0, 255);
          photo.setPixelRgb(
            x,
            y,
            jitter(x * 255 ~/ photo.width),
            jitter(y * 255 ~/ photo.height),
            jitter(128),
          );
        }
      }
      final source = Uint8List.fromList(img.encodePng(photo));

      final out = encodeStoreLogo(StoreLogoInput(source))!;

      // توقيع JPEG: FF D8 FF
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(out.length, lessThan(source.length));
    });

    test('صيغة أخرى (BMP) تُقبل وتُحوَّل', () {
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(10, 20, 30));
      final bmp = Uint8List.fromList(img.encodeBmp(image));

      final out = encodeStoreLogo(StoreLogoInput(bmp, maxSide: 200));

      expect(out, isNotNull);
      expect(img.decodeImage(out!)!.width, 200);
    });

    test('البايتات التالفة تعطي null بدل رمي استثناء', () {
      final junk = Uint8List.fromList(List<int>.filled(64, 7));

      expect(encodeStoreLogo(StoreLogoInput(junk)), isNull);
    });

    test('المدخل الفارغ يعطي null', () {
      expect(encodeStoreLogo(StoreLogoInput(Uint8List(0))), isNull);
    });
  });

  group('حفظ الشعار في الإعدادات', () {
    test('يُحفظ ويُقرأ كبايتات صالحة', () {
      final logo = encodeStoreLogo(StoreLogoInput(_opaquePng(300, 300)))!;

      final restored = PrintSettingsData.mergeFromJsonString(
        PrintSettingsData.defaults()
            .copyWith(storeLogoBase64: base64Encode(logo))
            .toJsonString(),
      );

      expect(restored.hasStoreLogo, isTrue);
      expect(restored.storeLogoBytes, logo);
    });

    test('غياب الشعار لا يكسر الإعدادات القديمة', () {
      final legacy = PrintSettingsData.mergeFromJsonString(
        jsonEncode({'storeTitleLine': 'محل قديم'}),
      );

      expect(legacy.hasStoreLogo, isFalse);
      expect(legacy.storeLogoBytes, isNull);
    });

    test('نص base64 تالف يعطي null بدل أن يُسقط الطباعة', () {
      final broken = PrintSettingsData.defaults().copyWith(
        storeLogoBase64: 'هذا ليس base64 %%%',
      );

      expect(broken.hasStoreLogo, isTrue);
      expect(broken.storeLogoBytes, isNull);
    });

    test('حذف الشعار يُفرّغ الحقل', () {
      final withLogo = PrintSettingsData.defaults().copyWith(
        storeLogoBase64: base64Encode(_opaquePng(50, 50)),
      );

      final cleared = withLogo.copyWith(storeLogoBase64: '');

      expect(cleared.hasStoreLogo, isFalse);
    });
  });
}
